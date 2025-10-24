// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title MegaBridge
 * @dev Cross-chain bridge integration for MegaETH Launch Kit
 */
contract MegaBridge is AccessControl, ReentrancyGuard, Pausable {
    using Counters for Counters.Counter;
    using ECDSA for bytes32;

    bytes32 public constant BRIDGE_OPERATOR_ROLE = keccak256("BRIDGE_OPERATOR_ROLE");
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    enum BridgeStatus { Pending, Confirmed, Failed, Refunded }
    enum ChainType { Ethereum, Polygon, Arbitrum, Optimism, Base, MegaETH }

    struct ChainConfig {
        uint256 chainId;
        string name;
        ChainType chainType;
        address bridgeContract;
        bool active;
        uint256 minTransferAmount;
        uint256 maxTransferAmount;
        uint256 dailyLimit;
        uint256 currentDailyVolume;
        uint256 lastResetTime;
    }

    struct BridgeTransaction {
        uint256 id;
        address user;
        address token;
        uint256 amount;
        uint256 sourceChainId;
        uint256 destinationChainId;
        address destinationAddress;
        BridgeStatus status;
        uint256 timestamp;
        bytes32 txHash;
        bytes32 merkleRoot;
        uint256 nonce;
        bool isRefundable;
    }

    struct CrossChainPayment {
        uint256 bridgeTxId;
        address merchant;
        uint256 amount;
        address token;
        string paymentId;
        bool completed;
        uint256 timestamp;
    }

    Counters.Counter private _bridgeTxIds;
    Counters.Counter private _paymentIds;

    mapping(uint256 => ChainConfig) public supportedChains;
    mapping(uint256 => BridgeTransaction) public bridgeTransactions;
    mapping(uint256 => CrossChainPayment) public crossChainPayments;
    mapping(address => uint256[]) public userBridgeTransactions;
    mapping(bytes32 => bool) public processedTransactions;
    mapping(address => bool) public supportedTokens;
    mapping(uint256 => uint256) public chainDailyVolumes;

    uint256 public bridgeFeePercent = 50; // 0.5%
    uint256 public confirmationThreshold = 2; // Number of relayers needed for confirmation
    uint256 public maxDailyBridgeVolume = 10000000 ether; // 10M ETH equivalent
    address public feeCollector;
    address public treasury;

    event ChainAdded(uint256 indexed chainId, string name);
    event BridgeTransactionInitiated(uint256 indexed txId, address indexed user, uint256 amount);
    event BridgeTransactionConfirmed(uint256 indexed txId, bytes32 merkleRoot);
    event CrossChainPaymentCompleted(uint256 indexed paymentId, address indexed merchant);
    event BridgeFeeUpdated(uint256 newFeePercent);
    event DailyLimitUpdated(uint256 newLimit);

    constructor(address _admin, address _feeCollector, address _treasury) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(BRIDGE_OPERATOR_ROLE, _admin);
        _grantRole(RELAYER_ROLE, _admin);
        feeCollector = _feeCollector;
        treasury = _treasury;
    }

    /**
     * @dev Add supported chain
     */
    function addSupportedChain(
        uint256 chainId,
        string memory name,
        ChainType chainType,
        address bridgeContract,
        uint256 minTransferAmount,
        uint256 maxTransferAmount,
        uint256 dailyLimit
    ) external onlyRole(BRIDGE_OPERATOR_ROLE) {
        require(supportedChains[chainId].chainId == 0, "Chain already supported");
        require(bridgeContract != address(0), "Invalid bridge contract");

        supportedChains[chainId] = ChainConfig({
            chainId: chainId,
            name: name,
            chainType: chainType,
            bridgeContract: bridgeContract,
            active: true,
            minTransferAmount: minTransferAmount,
            maxTransferAmount: maxTransferAmount,
            dailyLimit: dailyLimit,
            currentDailyVolume: 0,
            lastResetTime: block.timestamp
        });

        emit ChainAdded(chainId, name);
    }

    /**
     * @dev Initiate cross-chain bridge transaction
     */
    function initiateBridge(
        address token,
        uint256 amount,
        uint256 destinationChainId,
        address destinationAddress
    ) external payable whenNotPaused nonReentrant returns (uint256) {
        ChainConfig storage destChain = supportedChains[destinationChainId];
        require(destChain.active, "Destination chain not supported");
        require(amount >= destChain.minTransferAmount, "Amount too small");
        require(amount <= destChain.maxTransferAmount, "Amount too large");
        require(supportedTokens[token], "Token not supported");

        // Check daily limits
        _checkDailyLimits(destinationChainId, amount);

        _bridgeTxIds.increment();
        uint256 txId = _bridgeTxIds.current();

        bytes32 txHash = keccak256(abi.encodePacked(
            txId,
            msg.sender,
            token,
            amount,
            destinationChainId,
            destinationAddress,
            block.timestamp,
            block.chainid
        ));

        bridgeTransactions[txId] = BridgeTransaction({
            id: txId,
            user: msg.sender,
            token: token,
            amount: amount,
            sourceChainId: block.chainid,
            destinationChainId: destinationChainId,
            destinationAddress: destinationAddress,
            status: BridgeStatus.Pending,
            timestamp: block.timestamp,
            txHash: txHash,
            merkleRoot: bytes32(0),
            nonce: txId,
            isRefundable: true
        });

        userBridgeTransactions[msg.sender].push(txId);

        // Process payment
        _processBridgePayment(token, amount);

        // Update daily volume
        destChain.currentDailyVolume += amount;
        chainDailyVolumes[destinationChainId] += amount;

        emit BridgeTransactionInitiated(txId, msg.sender, amount);
        return txId;
    }

    /**
     * @dev Confirm bridge transaction (relayers only)
     */
    function confirmBridgeTransaction(
        uint256 txId,
        bytes32 merkleRoot,
        bytes[] memory signatures
    ) external onlyRole(RELAYER_ROLE) {
        BridgeTransaction storage bridgeTx = bridgeTransactions[txId];
        require(bridgeTx.status == BridgeStatus.Pending, "Transaction not pending");
        require(signatures.length >= confirmationThreshold, "Insufficient signatures");

        // Verify signatures
        bytes32 messageHash = keccak256(abi.encodePacked(txId, merkleRoot, block.chainid));
        uint256 validSignatures = 0;

        for (uint256 i = 0; i < signatures.length; i++) {
            bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
            address signer = ethSignedMessageHash.recover(signatures[i]);
            if (hasRole(RELAYER_ROLE, signer)) {
                validSignatures++;
            }
        }

        require(validSignatures >= confirmationThreshold, "Invalid signatures");

        bridgeTx.status = BridgeStatus.Confirmed;
        bridgeTx.merkleRoot = merkleRoot;

        emit BridgeTransactionConfirmed(txId, merkleRoot);
    }

    /**
     * @dev Complete cross-chain payment
     */
    function completeCrossChainPayment(
        uint256 bridgeTxId,
        address merchant,
        string memory paymentId,
        bytes32[] memory merkleProof
    ) external onlyRole(BRIDGE_OPERATOR_ROLE) returns (uint256) {
        BridgeTransaction storage bridgeTx = bridgeTransactions[bridgeTxId];
        require(bridgeTx.status == BridgeStatus.Confirmed, "Bridge transaction not confirmed");

        // Verify merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(merchant, bridgeTx.amount, paymentId));
        require(MerkleProof.verify(merkleProof, bridgeTx.merkleRoot, leaf), "Invalid proof");

        _paymentIds.increment();
        uint256 paymentId_num = _paymentIds.current();

        crossChainPayments[paymentId_num] = CrossChainPayment({
            bridgeTxId: bridgeTxId,
            merchant: merchant,
            amount: bridgeTx.amount,
            token: bridgeTx.token,
            paymentId: paymentId,
            completed: true,
            timestamp: block.timestamp
        });

        emit CrossChainPaymentCompleted(paymentId_num, merchant);
        return paymentId_num;
    }

    /**
     * @dev Process refund for failed bridge transaction
     */
    function processRefund(uint256 txId) external onlyRole(BRIDGE_OPERATOR_ROLE) {
        BridgeTransaction storage bridgeTx = bridgeTransactions[txId];
        require(bridgeTx.status == BridgeStatus.Failed, "Transaction not failed");
        require(bridgeTx.isRefundable, "Not refundable");

        // Transfer back to user
        if (bridgeTx.token == address(0)) {
            payable(bridgeTx.user).transfer(bridgeTx.amount);
        } else {
            IERC20(bridgeTx.token).transfer(bridgeTx.user, bridgeTx.amount);
        }

        bridgeTx.status = BridgeStatus.Refunded;
    }

    /**
     * @dev Get bridge transaction status
     */
    function getBridgeTransactionStatus(uint256 txId) external view returns (
        BridgeTransaction memory bridgeTx,
        ChainConfig memory destChain
    ) {
        bridgeTx = bridgeTransactions[txId];
        destChain = supportedChains[bridgeTx.destinationChainId];
    }

    /**
     * @dev Get user's bridge transactions
     */
    function getUserBridgeTransactions(address user) external view returns (uint256[] memory) {
        return userBridgeTransactions[user];
    }

    /**
     * @dev Get supported chains
     */
    function getSupportedChains() external view returns (ChainConfig[] memory) {
        // In production, implement proper array management
        ChainConfig[] memory chains = new ChainConfig[](10); // Placeholder
        return chains;
    }

    /**
     * @dev Check daily limits
     */
    function _checkDailyLimits(uint256 chainId, uint256 amount) internal view {
        ChainConfig storage chain = supportedChains[chainId];
        
        // Reset daily volume if needed
        if (block.timestamp > chain.lastResetTime + 1 days) {
            // Daily limit resets - this would be handled in a separate function
        }

        require(chain.currentDailyVolume + amount <= chain.dailyLimit, "Daily limit exceeded");
        require(chainDailyVolumes[chainId] + amount <= maxDailyBridgeVolume, "Global daily limit exceeded");
    }

    /**
     * @dev Process bridge payment
     */
    function _processBridgePayment(address token, uint256 amount) internal {
        uint256 bridgeFee = (amount * bridgeFeePercent) / 10000;
        uint256 netAmount = amount - bridgeFee;

        if (token == address(0)) {
            require(msg.value >= amount, "Insufficient ETH");
            if (msg.value > amount) {
                payable(msg.sender).transfer(msg.value - amount);
            }
            payable(feeCollector).transfer(bridgeFee);
            payable(treasury).transfer(netAmount);
        } else {
            IERC20(token).transferFrom(msg.sender, feeCollector, bridgeFee);
            IERC20(token).transferFrom(msg.sender, treasury, netAmount);
        }
    }

    /**
     * @dev Add supported token
     */
    function addSupportedToken(address token) external onlyRole(BRIDGE_OPERATOR_ROLE) {
        supportedTokens[token] = true;
    }

    /**
     * @dev Update bridge fee
     */
    function updateBridgeFee(uint256 newFeePercent) external onlyRole(BRIDGE_OPERATOR_ROLE) {
        require(newFeePercent <= 500, "Fee too high"); // Max 5%
        bridgeFeePercent = newFeePercent;
        emit BridgeFeeUpdated(newFeePercent);
    }

    /**
     * @dev Update daily limits
     */
    function updateDailyLimits(uint256 chainId, uint256 newDailyLimit) external onlyRole(BRIDGE_OPERATOR_ROLE) {
        ChainConfig storage chain = supportedChains[chainId];
        require(chain.chainId != 0, "Chain not supported");
        chain.dailyLimit = newDailyLimit;
        emit DailyLimitUpdated(newDailyLimit);
    }

    /**
     * @dev Update confirmation threshold
     */
    function updateConfirmationThreshold(uint256 newThreshold) external onlyRole(BRIDGE_OPERATOR_ROLE) {
        require(newThreshold > 0, "Threshold must be positive");
        confirmationThreshold = newThreshold;
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

    /**
     * @dev Reset daily volumes (call daily)
     */
    function resetDailyVolumes() external onlyRole(BRIDGE_OPERATOR_ROLE) {
        // Reset all chain daily volumes
        // In production, implement proper iteration over supported chains
    }
}
