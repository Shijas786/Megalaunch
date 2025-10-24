// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title MegaSDK
 * @dev Comprehensive SDK and API system for MegaETH Launch Kit
 */
contract MegaSDK is AccessControl, ReentrancyGuard, Pausable {
    using ECDSA for bytes32;

    bytes32 public constant SDK_ADMIN_ROLE = keccak256("SDK_ADMIN_ROLE");
    bytes32 public constant API_KEY_ROLE = keccak256("API_KEY_ROLE");
    bytes32 public constant DEVELOPER_ROLE = keccak256("DEVELOPER_ROLE");

    struct APIKey {
        string keyId;
        address owner;
        string name;
        string description;
        uint256 rateLimit; // requests per minute
        uint256 currentUsage;
        uint256 lastReset;
        bool active;
        uint256 createdAt;
        uint256 expiresAt;
        string[] permissions;
    }

    struct SDKIntegration {
        uint256 id;
        address developer;
        string appName;
        string appDescription;
        string version;
        string[] contractAddresses;
        bool verified;
        uint256 createdAt;
        uint256 lastUsed;
    }

    struct RateLimit {
        uint256 requestsPerMinute;
        uint256 requestsPerHour;
        uint256 requestsPerDay;
        uint256 currentMinuteUsage;
        uint256 currentHourUsage;
        uint256 currentDayUsage;
        uint256 lastMinuteReset;
        uint256 lastHourReset;
        uint256 lastDayReset;
    }

    struct SDKCall {
        uint256 id;
        string apiKeyId;
        address caller;
        string functionName;
        bytes parameters;
        bool success;
        uint256 gasUsed;
        uint256 timestamp;
        string errorMessage;
    }

    mapping(string => APIKey) public apiKeys;
    mapping(address => string[]) public userApiKeys;
    mapping(uint256 => SDKIntegration) public integrations;
    mapping(address => uint256[]) public developerIntegrations;
    mapping(string => RateLimit) public rateLimits;
    mapping(uint256 => SDKCall) public sdkCalls;
    mapping(address => bool) public verifiedDevelopers;

    uint256 private _integrationIds;
    uint256 private _callIds;
    uint256 public defaultRateLimit = 1000; // requests per minute
    uint256 public maxApiKeysPerUser = 10;
    address public feeCollector;

    event APIKeyCreated(string indexed keyId, address indexed owner, string name);
    event APIKeyRevoked(string indexed keyId, address indexed owner);
    event IntegrationRegistered(uint256 indexed integrationId, address indexed developer);
    event SDKCallExecuted(uint256 indexed callId, string apiKeyId, bool success);
    event RateLimitExceeded(string indexed apiKeyId, address indexed caller);
    event DeveloperVerified(address indexed developer, bool verified);

    constructor(address _admin, address _feeCollector) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(SDK_ADMIN_ROLE, _admin);
        _grantRole(DEVELOPER_ROLE, _admin);
        feeCollector = _feeCollector;
    }

    /**
     * @dev Create API key
     */
    function createAPIKey(
        string memory keyId,
        string memory name,
        string memory description,
        uint256 rateLimit,
        uint256 expiresAt,
        string[] memory permissions
    ) external returns (string memory) {
        require(bytes(keyId).length > 0, "Key ID required");
        require(bytes(name).length > 0, "Name required");
        require(apiKeys[keyId].owner == address(0), "Key ID already exists");
        require(userApiKeys[msg.sender].length < maxApiKeysPerUser, "Too many API keys");

        apiKeys[keyId] = APIKey({
            keyId: keyId,
            owner: msg.sender,
            name: name,
            description: description,
            rateLimit: rateLimit > 0 ? rateLimit : defaultRateLimit,
            currentUsage: 0,
            lastReset: block.timestamp,
            active: true,
            createdAt: block.timestamp,
            expiresAt: expiresAt,
            permissions: permissions
        });

        userApiKeys[msg.sender].push(keyId);
        rateLimits[keyId] = RateLimit({
            requestsPerMinute: rateLimit > 0 ? rateLimit : defaultRateLimit,
            requestsPerHour: (rateLimit > 0 ? rateLimit : defaultRateLimit) * 60,
            requestsPerDay: (rateLimit > 0 ? rateLimit : defaultRateLimit) * 60 * 24,
            currentMinuteUsage: 0,
            currentHourUsage: 0,
            currentDayUsage: 0,
            lastMinuteReset: block.timestamp,
            lastHourReset: block.timestamp,
            lastDayReset: block.timestamp
        });

        emit APIKeyCreated(keyId, msg.sender, name);
        return keyId;
    }

    /**
     * @dev Register SDK integration
     */
    function registerIntegration(
        string memory appName,
        string memory appDescription,
        string memory version,
        string[] memory contractAddresses
    ) external returns (uint256) {
        require(bytes(appName).length > 0, "App name required");
        require(contractAddresses.length > 0, "Contract addresses required");

        _integrationIds++;
        uint256 integrationId = _integrationIds;

        integrations[integrationId] = SDKIntegration({
            id: integrationId,
            developer: msg.sender,
            appName: appName,
            appDescription: appDescription,
            version: version,
            contractAddresses: contractAddresses,
            verified: verifiedDevelopers[msg.sender],
            createdAt: block.timestamp,
            lastUsed: block.timestamp
        });

        developerIntegrations[msg.sender].push(integrationId);

        emit IntegrationRegistered(integrationId, msg.sender);
        return integrationId;
    }

    /**
     * @dev Execute SDK call with rate limiting
     */
    function executeSDKCall(
        string memory apiKeyId,
        string memory functionName,
        bytes memory parameters,
        bytes memory signature
    ) external whenNotPaused nonReentrant returns (bool success, bytes memory result) {
        APIKey storage apiKey = apiKeys[apiKeyId];
        require(apiKey.owner != address(0), "Invalid API key");
        require(apiKey.active, "API key inactive");
        require(apiKey.expiresAt == 0 || block.timestamp <= apiKey.expiresAt, "API key expired");

        // Verify signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            apiKeyId,
            functionName,
            parameters,
            block.timestamp,
            block.chainid
        ));
        require(messageHash.recover(signature) == apiKey.owner, "Invalid signature");

        // Check rate limits
        if (!_checkRateLimit(apiKeyId)) {
            emit RateLimitExceeded(apiKeyId, msg.sender);
            return (false, abi.encode("Rate limit exceeded"));
        }

        // Record call
        _callIds++;
        uint256 callId = _callIds;

        sdkCalls[callId] = SDKCall({
            id: callId,
            apiKeyId: apiKeyId,
            caller: msg.sender,
            functionName: functionName,
            parameters: parameters,
            success: false,
            gasUsed: 0,
            timestamp: block.timestamp,
            errorMessage: ""
        });

        // Execute function (simplified - in production, implement proper function routing)
        try this._executeFunction(functionName, parameters) returns (bytes memory callResult) {
            sdkCalls[callId].success = true;
            sdkCalls[callId].gasUsed = gasleft(); // Simplified gas tracking
            emit SDKCallExecuted(callId, apiKeyId, true);
            return (true, callResult);
        } catch Error(string memory reason) {
            sdkCalls[callId].success = false;
            sdkCalls[callId].errorMessage = reason;
            emit SDKCallExecuted(callId, apiKeyId, false);
            return (false, abi.encode(reason));
        }
    }

    /**
     * @dev Internal function execution
     */
    function _executeFunction(string memory functionName, bytes memory parameters) external view returns (bytes memory) {
        // In production, implement proper function routing based on functionName
        // This is a simplified example
        if (keccak256(bytes(functionName)) == keccak256(bytes("getBalance"))) {
            address account = abi.decode(parameters, (address));
            return abi.encode(account.balance);
        }
        
        revert("Function not found");
    }

    /**
     * @dev Check rate limit
     */
    function _checkRateLimit(string memory apiKeyId) internal returns (bool) {
        RateLimit storage limit = rateLimits[apiKeyId];
        uint256 currentTime = block.timestamp;

        // Reset counters if needed
        if (currentTime > limit.lastMinuteReset + 1 minutes) {
            limit.currentMinuteUsage = 0;
            limit.lastMinuteReset = currentTime;
        }
        if (currentTime > limit.lastHourReset + 1 hours) {
            limit.currentHourUsage = 0;
            limit.lastHourReset = currentTime;
        }
        if (currentTime > limit.lastDayReset + 1 days) {
            limit.currentDayUsage = 0;
            limit.lastDayReset = currentTime;
        }

        // Check limits
        if (limit.currentMinuteUsage >= limit.requestsPerMinute ||
            limit.currentHourUsage >= limit.requestsPerHour ||
            limit.currentDayUsage >= limit.requestsPerDay) {
            return false;
        }

        // Increment counters
        limit.currentMinuteUsage++;
        limit.currentHourUsage++;
        limit.currentDayUsage++;

        return true;
    }

    /**
     * @dev Revoke API key
     */
    function revokeAPIKey(string memory keyId) external {
        APIKey storage apiKey = apiKeys[keyId];
        require(apiKey.owner == msg.sender || hasRole(SDK_ADMIN_ROLE, msg.sender), "Not authorized");
        
        apiKey.active = false;
        emit APIKeyRevoked(keyId, apiKey.owner);
    }

    /**
     * @dev Verify developer
     */
    function verifyDeveloper(address developer, bool verified) external onlyRole(SDK_ADMIN_ROLE) {
        verifiedDevelopers[developer] = verified;
        
        // Update all integrations by this developer
        uint256[] memory integrationIds = developerIntegrations[developer];
        for (uint256 i = 0; i < integrationIds.length; i++) {
            integrations[integrationIds[i]].verified = verified;
        }

        emit DeveloperVerified(developer, verified);
    }

    /**
     * @dev Get API key details
     */
    function getAPIKeyDetails(string memory keyId) external view returns (
        APIKey memory apiKey,
        RateLimit memory rateLimit
    ) {
        apiKey = apiKeys[keyId];
        rateLimit = rateLimits[keyId];
    }

    /**
     * @dev Get user's API keys
     */
    function getUserAPIKeys(address user) external view returns (string[] memory) {
        return userApiKeys[user];
    }

    /**
     * @dev Get integration details
     */
    function getIntegrationDetails(uint256 integrationId) external view returns (SDKIntegration memory) {
        return integrations[integrationId];
    }

    /**
     * @dev Get developer's integrations
     */
    function getDeveloperIntegrations(address developer) external view returns (uint256[] memory) {
        return developerIntegrations[developer];
    }

    /**
     * @dev Get SDK call history
     */
    function getSDKCallHistory(
        string memory apiKeyId,
        uint256 offset,
        uint256 limit
    ) external view returns (SDKCall[] memory, uint256 total) {
        // In production, implement proper pagination with indexed storage
        SDKCall[] memory calls = new SDKCall[](0);
        return (calls, 0);
    }

    /**
     * @dev Update API key settings
     */
    function updateAPIKeySettings(
        string memory keyId,
        uint256 newRateLimit,
        uint256 newExpiresAt,
        string[] memory newPermissions
    ) external {
        APIKey storage apiKey = apiKeys[keyId];
        require(apiKey.owner == msg.sender, "Not owner");

        apiKey.rateLimit = newRateLimit;
        apiKey.expiresAt = newExpiresAt;
        apiKey.permissions = newPermissions;

        // Update rate limits
        RateLimit storage limit = rateLimits[keyId];
        limit.requestsPerMinute = newRateLimit;
        limit.requestsPerHour = newRateLimit * 60;
        limit.requestsPerDay = newRateLimit * 60 * 24;
    }

    /**
     * @dev Update integration
     */
    function updateIntegration(
        uint256 integrationId,
        string memory appName,
        string memory appDescription,
        string memory version,
        string[] memory contractAddresses
    ) external {
        SDKIntegration storage integration = integrations[integrationId];
        require(integration.developer == msg.sender, "Not developer");

        integration.appName = appName;
        integration.appDescription = appDescription;
        integration.version = version;
        integration.contractAddresses = contractAddresses;
        integration.lastUsed = block.timestamp;
    }

    /**
     * @dev Update global settings
     */
    function updateGlobalSettings(
        uint256 newDefaultRateLimit,
        uint256 newMaxApiKeysPerUser
    ) external onlyRole(SDK_ADMIN_ROLE) {
        defaultRateLimit = newDefaultRateLimit;
        maxApiKeysPerUser = newMaxApiKeysPerUser;
    }

    /**
     * @dev Emergency pause
     */
    function emergencyPause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function emergencyUnpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
