// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title MegaAttest
 * @dev A public good program for associating offchain data with onchain accounts
 * Used for KYC, Reputation and other trust-based applications
 */
contract MegaAttest is Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    using ECDSA for bytes32;

    enum AttestationType { KYC, Reputation, Identity, Credential, Custom }
    enum AttestationStatus { Pending, Approved, Rejected, Revoked }

    struct Attestation {
        uint256 id;
        address attester; // Who created the attestation
        address subject; // Who the attestation is about
        AttestationType attestationType;
        AttestationStatus status;
        string dataHash; // Hash of off-chain data
        string dataUri; // URI to off-chain data
        uint256 createdAt;
        uint256 updatedAt;
        uint256 expiresAt;
        bool revocable;
        bytes32 attestationHash;
    }

    struct AttestationSchema {
        uint256 id;
        string name;
        string description;
        string schema; // JSON schema definition
        address creator;
        bool active;
        uint256 createdAt;
    }

    Counters.Counter private _attestationIds;
    Counters.Counter private _schemaIds;

    mapping(uint256 => Attestation) public attestations;
    mapping(uint256 => AttestationSchema) public schemas;
    mapping(address => uint256[]) public subjectAttestations;
    mapping(address => uint256[]) public attesterAttestations;
    mapping(address => bool) public authorizedAttesters;
    mapping(bytes32 => bool) public usedAttestationHashes;
    mapping(string => bool) public usedDataHashes;

    uint256 public attestationFee = 0.001 ether;
    address public feeCollector;
    uint256 public defaultExpiryTime = 365 days;

    event AttestationCreated(uint256 indexed attestationId, address indexed attester, address indexed subject, AttestationType attestationType);
    event AttestationUpdated(uint256 indexed attestationId, AttestationStatus newStatus);
    event AttestationRevoked(uint256 indexed attestationId, address indexed revoker);
    event SchemaCreated(uint256 indexed schemaId, address indexed creator, string name);
    event AttesterAuthorized(address indexed attester);
    event AttesterDeauthorized(address indexed attester);

    constructor(address _feeCollector) {
        feeCollector = _feeCollector;
    }

    /**
     * @dev Create a new attestation schema
     * @param name Schema name
     * @param description Schema description
     * @param schema JSON schema definition
     */
    function createSchema(
        string memory name,
        string memory description,
        string memory schema
    ) external returns (uint256) {
        require(bytes(name).length > 0, "Schema name required");
        require(bytes(schema).length > 0, "Schema definition required");

        _schemaIds.increment();
        uint256 schemaId = _schemaIds.current();

        schemas[schemaId] = AttestationSchema({
            id: schemaId,
            name: name,
            description: description,
            schema: schema,
            creator: msg.sender,
            active: true,
            createdAt: block.timestamp
        });

        emit SchemaCreated(schemaId, msg.sender, name);
        return schemaId;
    }

    /**
     * @dev Create a new attestation
     * @param subject Subject address
     * @param attestationType Type of attestation
     * @param dataHash Hash of off-chain data
     * @param dataUri URI to off-chain data
     * @param expiresAt Expiration timestamp (0 for default)
     * @param revocable Whether attestation can be revoked
     */
    function createAttestation(
        address subject,
        AttestationType attestationType,
        string memory dataHash,
        string memory dataUri,
        uint256 expiresAt,
        bool revocable
    ) external payable nonReentrant returns (uint256) {
        require(authorizedAttesters[msg.sender], "Not authorized attester");
        require(subject != address(0), "Invalid subject address");
        require(bytes(dataHash).length > 0, "Data hash required");
        require(!usedDataHashes[dataHash], "Data hash already used");
        require(msg.value >= attestationFee, "Insufficient fee");

        if (expiresAt == 0) {
            expiresAt = block.timestamp + defaultExpiryTime;
        }

        _attestationIds.increment();
        uint256 attestationId = _attestationIds.current();

        bytes32 attestationHash = keccak256(abi.encodePacked(
            attestationId,
            msg.sender,
            subject,
            attestationType,
            dataHash,
            expiresAt
        ));

        require(!usedAttestationHashes[attestationHash], "Attestation hash collision");

        attestations[attestationId] = Attestation({
            id: attestationId,
            attester: msg.sender,
            subject: subject,
            attestationType: attestationType,
            status: AttestationStatus.Pending,
            dataHash: dataHash,
            dataUri: dataUri,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            expiresAt: expiresAt,
            revocable: revocable,
            attestationHash: attestationHash
        });

        subjectAttestations[subject].push(attestationId);
        attesterAttestations[msg.sender].push(attestationId);
        usedDataHashes[dataHash] = true;
        usedAttestationHashes[attestationHash] = true;

        // Transfer fee
        if (msg.value > 0) {
            payable(feeCollector).transfer(msg.value);
        }

        emit AttestationCreated(attestationId, msg.sender, subject, attestationType);
        return attestationId;
    }

    /**
     * @dev Update attestation status
     * @param attestationId Attestation ID
     * @param newStatus New status
     */
    function updateAttestationStatus(uint256 attestationId, AttestationStatus newStatus) external {
        Attestation storage attestation = attestations[attestationId];
        
        require(attestation.attester == msg.sender || msg.sender == owner(), "Not authorized");
        require(attestation.status != AttestationStatus.Revoked, "Attestation revoked");
        require(block.timestamp <= attestation.expiresAt, "Attestation expired");

        attestation.status = newStatus;
        attestation.updatedAt = block.timestamp;

        emit AttestationUpdated(attestationId, newStatus);
    }

    /**
     * @dev Revoke an attestation
     * @param attestationId Attestation ID
     */
    function revokeAttestation(uint256 attestationId) external {
        Attestation storage attestation = attestations[attestationId];
        
        require(
            attestation.attester == msg.sender || 
            msg.sender == owner() || 
            attestation.subject == msg.sender,
            "Not authorized to revoke"
        );
        require(attestation.revocable, "Attestation not revocable");
        require(attestation.status != AttestationStatus.Revoked, "Already revoked");

        attestation.status = AttestationStatus.Revoked;
        attestation.updatedAt = block.timestamp;

        emit AttestationRevoked(attestationId, msg.sender);
    }

    /**
     * @dev Verify attestation signature
     * @param attestationId Attestation ID
     * @param signature Attester signature
     * @return isValid Whether signature is valid
     */
    function verifyAttestationSignature(uint256 attestationId, bytes memory signature) external view returns (bool isValid) {
        Attestation storage attestation = attestations[attestationId];
        
        bytes32 messageHash = keccak256(abi.encodePacked(
            attestationId,
            attestation.subject,
            attestation.attestationType,
            attestation.dataHash,
            block.chainid
        ));
        
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        address signer = ethSignedMessageHash.recover(signature);
        
        return signer == attestation.attester;
    }

    /**
     * @dev Get attestations for a subject
     * @param subject Subject address
     * @param attestationType Optional filter by type
     * @return Array of attestation IDs
     */
    function getSubjectAttestations(address subject, AttestationType attestationType) external view returns (uint256[] memory) {
        uint256[] memory allAttestations = subjectAttestations[subject];
        uint256 count = 0;
        
        // Count matching attestations
        for (uint256 i = 0; i < allAttestations.length; i++) {
            if (attestations[allAttestations[i]].attestationType == attestationType) {
                count++;
            }
        }
        
        // Create result array
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < allAttestations.length; i++) {
            if (attestations[allAttestations[i]].attestationType == attestationType) {
                result[index] = allAttestations[i];
                index++;
            }
        }
        
        return result;
    }

    /**
     * @dev Get attestations created by an attester
     * @param attester Attester address
     * @return Array of attestation IDs
     */
    function getAttesterAttestations(address attester) external view returns (uint256[] memory) {
        return attesterAttestations[attester];
    }

    /**
     * @dev Check if subject has valid attestation of specific type
     * @param subject Subject address
     * @param attestationType Type of attestation
     * @return hasValidAttestation Whether subject has valid attestation
     */
    function hasValidAttestation(address subject, AttestationType attestationType) external view returns (bool hasValidAttestation) {
        uint256[] memory attestationIds = subjectAttestations[subject];
        
        for (uint256 i = 0; i < attestationIds.length; i++) {
            Attestation storage attestation = attestations[attestationIds[i]];
            if (attestation.attestationType == attestationType &&
                attestation.status == AttestationStatus.Approved &&
                block.timestamp <= attestation.expiresAt) {
                return true;
            }
        }
        
        return false;
    }

    /**
     * @dev Authorize an attester
     * @param attester Attester address
     */
    function authorizeAttester(address attester) external onlyOwner {
        authorizedAttesters[attester] = true;
        emit AttesterAuthorized(attester);
    }

    /**
     * @dev Deauthorize an attester
     * @param attester Attester address
     */
    function deauthorizeAttester(address attester) external onlyOwner {
        authorizedAttesters[attester] = false;
        emit AttesterDeauthorized(attester);
    }

    /**
     * @dev Update attestation fee
     * @param newFee New fee in wei
     */
    function updateAttestationFee(uint256 newFee) external onlyOwner {
        attestationFee = newFee;
    }

    /**
     * @dev Update fee collector
     * @param newFeeCollector New fee collector address
     */
    function updateFeeCollector(address newFeeCollector) external onlyOwner {
        require(newFeeCollector != address(0), "Invalid address");
        feeCollector = newFeeCollector;
    }

    /**
     * @dev Update default expiry time
     * @param newExpiryTime New expiry time in seconds
     */
    function updateDefaultExpiryTime(uint256 newExpiryTime) external onlyOwner {
        require(newExpiryTime > 0, "Invalid expiry time");
        defaultExpiryTime = newExpiryTime;
    }

    /**
     * @dev Get attestation count for a subject
     * @param subject Subject address
     * @return Count of attestations
     */
    function getSubjectAttestationCount(address subject) external view returns (uint256) {
        return subjectAttestations[subject].length;
    }

    /**
     * @dev Get attestation count for an attester
     * @param attester Attester address
     * @return Count of attestations
     */
    function getAttesterAttestationCount(address attester) external view returns (uint256) {
        return attesterAttestations[attester].length;
    }
}
