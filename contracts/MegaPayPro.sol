// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title MegaPay Pro
 * @dev Professional multi-currency transaction fee payment system with advanced features
 */
contract MegaPayPro is AccessControl, Pausable, ReentrancyGuard {
    using Counters for Counters.Counter;
    using ECDSA for bytes32;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");

    struct FeePayment {
        uint256 id;
        address user;
        address token;
        uint256 amount;
        uint256 gasUsed;
        uint256 timestamp;
        bytes32 txHash;
        bool refunded;
    }

    struct TokenConfig {
        bool supported;
        uint256 gasPrice;
        uint256 minAmount;
        uint256 maxAmount;
        uint256 dailyLimit;
        bool whitelistOnly;
        uint256 feePercent;
        address feeCollector;
    }

    struct UserLimits {
        uint256 dailySpent;
        uint256 lastReset;
        uint256 maxDailyAmount;
        bool isWhitelisted;
    }

    struct BatchPayment {
        uint256 id;
        address[] users;
        address token;
        uint256[] amounts;
        uint256[] gasUsed;
        bytes32 merkleRoot;
        bool executed;
        uint256 timestamp;
    }

    Counters.Counter private _paymentIds;
    Counters.Counter private _batchIds;

    mapping(address => TokenConfig) public tokenConfigs;
    mapping(address => UserLimits) public userLimits;
    mapping(uint256 => FeePayment) public payments;
    mapping(uint256 => BatchPayment) public batchPayments;
    mapping(address => uint256[]) public userPayments;
    mapping(bytes32 => bool) public usedSignatures;
    mapping(address => bool) public emergencyStops;

    uint256 public globalDailyLimit = 1000000 ether;
    uint256 public maxBatchSize = 1000;
    uint256 public signatureValidityPeriod = 1 hours;
    address public treasury;
    address public emergencyAdmin;

    event PaymentProcessed(uint256 indexed paymentId, address indexed user, address indexed token, uint256 amount);
    event BatchPaymentExecuted(uint256 indexed batchId, uint256 totalAmount, uint256 userCount);
    event TokenConfigUpdated(address indexed token, TokenConfig config);
    event UserLimitsUpdated(address indexed user, UserLimits limits);
    event EmergencyStop(address indexed token, bool stopped);
    event RefundProcessed(uint256 indexed paymentId, address indexed user, uint256 amount);

    constructor(address _admin, address _treasury) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        treasury = _treasury;
        emergencyAdmin = _admin;
    }

    /**
     * @dev Add or update token configuration
     */
    function setTokenConfig(
        address token,
        uint256 gasPrice,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 dailyLimit,
        bool whitelistOnly,
        uint256 feePercent,
        address feeCollector
    ) external onlyRole(ADMIN_ROLE) {
        require(gasPrice > 0, "Invalid gas price");
        require(minAmount <= maxAmount, "Invalid amount range");
        require(feePercent <= 1000, "Fee too high"); // Max 10%

        tokenConfigs[token] = TokenConfig({
            supported: true,
            gasPrice: gasPrice,
            minAmount: minAmount,
            maxAmount: maxAmount,
            dailyLimit: dailyLimit,
            whitelistOnly: whitelistOnly,
            feePercent: feePercent,
            feeCollector: feeCollector
        });

        emit TokenConfigUpdated(token, tokenConfigs[token]);
    }

    /**
     * @dev Set user limits and whitelist status
     */
    function setUserLimits(
        address user,
        uint256 maxDailyAmount,
        bool isWhitelisted
    ) external onlyRole(ADMIN_ROLE) {
        userLimits[user] = UserLimits({
            dailySpent: userLimits[user].dailySpent,
            lastReset: userLimits[user].lastReset,
            maxDailyAmount: maxDailyAmount,
            isWhitelisted: isWhitelisted
        });

        emit UserLimitsUpdated(user, userLimits[user]);
    }

    /**
     * @dev Process fee payment with signature verification
     */
    function payFeesWithSignature(
        address token,
        uint256 gasUsed,
        uint256 nonce,
        bytes memory signature
    ) external whenNotPaused nonReentrant {
        require(tokenConfigs[token].supported, "Token not supported");
        require(!emergencyStops[token], "Token emergency stopped");

        bytes32 messageHash = keccak256(abi.encodePacked(
            msg.sender,
            token,
            gasUsed,
            nonce,
            block.timestamp,
            block.chainid
        ));

        require(!usedSignatures[messageHash], "Signature already used");
        require(block.timestamp <= nonce + signatureValidityPeriod, "Signature expired");

        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        address signer = ethSignedMessageHash.recover(signature);
        require(hasRole(OPERATOR_ROLE, signer), "Invalid signer");

        _processPayment(msg.sender, token, gasUsed);
        usedSignatures[messageHash] = true;
    }

    /**
     * @dev Process batch payments using Merkle proof
     */
    function processBatchPayment(
        uint256 batchId,
        uint256 userIndex,
        uint256 amount,
        uint256 gasUsed,
        bytes32[] memory merkleProof
    ) external whenNotPaused nonReentrant {
        BatchPayment storage batch = batchPayments[batchId];
        require(!batch.executed, "Batch already executed");
        require(userIndex < batch.users.length, "Invalid user index");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount, gasUsed));
        require(MerkleProof.verify(merkleProof, batch.merkleRoot, leaf), "Invalid proof");

        _processPayment(msg.sender, batch.token, gasUsed);
    }

    /**
     * @dev Execute batch payment (admin only)
     */
    function executeBatchPayment(
        address[] memory users,
        address token,
        uint256[] memory amounts,
        uint256[] memory gasUsed,
        bytes32 merkleRoot
    ) external onlyRole(ADMIN_ROLE) {
        require(users.length == amounts.length && amounts.length == gasUsed.length, "Array length mismatch");
        require(users.length <= maxBatchSize, "Batch too large");

        _batchIds.increment();
        uint256 batchId = _batchIds.current();

        batchPayments[batchId] = BatchPayment({
            id: batchId,
            users: users,
            token: token,
            amounts: amounts,
            gasUsed: gasUsed,
            merkleRoot: merkleRoot,
            executed: true,
            timestamp: block.timestamp
        });

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        emit BatchPaymentExecuted(batchId, totalAmount, users.length);
    }

    /**
     * @dev Emergency stop for a token
     */
    function emergencyStop(address token, bool stop) external {
        require(msg.sender == emergencyAdmin || hasRole(ADMIN_ROLE, msg.sender), "Not authorized");
        emergencyStops[token] = stop;
        emit EmergencyStop(token, stop);
    }

    /**
     * @dev Process refund for a payment
     */
    function processRefund(uint256 paymentId) external onlyRole(ADMIN_ROLE) {
        FeePayment storage payment = payments[paymentId];
        require(!payment.refunded, "Already refunded");

        // Transfer refund amount
        if (payment.token == address(0)) {
            payable(payment.user).transfer(payment.amount);
        } else {
            IERC20(payment.token).transfer(payment.user, payment.amount);
        }

        payment.refunded = true;
        emit RefundProcessed(paymentId, payment.user, payment.amount);
    }

    /**
     * @dev Internal payment processing
     */
    function _processPayment(address user, address token, uint256 gasUsed) internal {
        TokenConfig memory config = tokenConfigs[token];
        UserLimits storage limits = userLimits[user];

        // Reset daily limits if needed
        if (block.timestamp > limits.lastReset + 1 days) {
            limits.dailySpent = 0;
            limits.lastReset = block.timestamp;
        }

        uint256 feeAmount = gasUsed * config.gasPrice;
        require(feeAmount >= config.minAmount && feeAmount <= config.maxAmount, "Amount out of range");
        require(limits.dailySpent + feeAmount <= limits.maxDailyAmount, "Daily limit exceeded");
        require(limits.dailySpent + feeAmount <= globalDailyLimit, "Global limit exceeded");

        // Check whitelist requirement
        if (config.whitelistOnly) {
            require(limits.isWhitelisted, "User not whitelisted");
        }

        // Calculate fees
        uint256 platformFee = (feeAmount * config.feePercent) / 10000;
        uint256 netAmount = feeAmount - platformFee;

        // Process payment
        if (token == address(0)) {
            require(msg.value >= feeAmount, "Insufficient ETH");
            if (msg.value > feeAmount) {
                payable(user).transfer(msg.value - feeAmount);
            }
            payable(config.feeCollector).transfer(platformFee);
            payable(treasury).transfer(netAmount);
        } else {
            IERC20(token).transferFrom(user, config.feeCollector, platformFee);
            IERC20(token).transferFrom(user, treasury, netAmount);
        }

        // Record payment
        _paymentIds.increment();
        uint256 paymentId = _paymentIds.current();

        payments[paymentId] = FeePayment({
            id: paymentId,
            user: user,
            token: token,
            amount: feeAmount,
            gasUsed: gasUsed,
            timestamp: block.timestamp,
            txHash: keccak256(abi.encodePacked(block.timestamp, user, feeAmount)),
            refunded: false
        });

        userPayments[user].push(paymentId);
        limits.dailySpent += feeAmount;

        emit PaymentProcessed(paymentId, user, token, feeAmount);
    }

    /**
     * @dev Get user payment history with pagination
     */
    function getUserPaymentsPaginated(
        address user,
        uint256 offset,
        uint256 limit
    ) external view returns (FeePayment[] memory, uint256 total) {
        uint256[] memory userPaymentIds = userPayments[user];
        total = userPaymentIds.length;
        
        uint256 end = offset + limit;
        if (end > total) end = total;
        if (offset >= total) return (new FeePayment[](0), total);

        FeePayment[] memory result = new FeePayment[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = payments[userPaymentIds[i]];
        }

        return (result, total);
    }

    /**
     * @dev Get token statistics
     */
    function getTokenStats(address token) external view returns (
        uint256 totalPayments,
        uint256 totalVolume,
        uint256 activeUsers
    ) {
        // This would require additional storage for efficiency in production
        // For now, return basic config info
        TokenConfig memory config = tokenConfigs[token];
        return (0, 0, 0); // Placeholder - implement with proper tracking
    }

    /**
     * @dev Update global settings
     */
    function updateGlobalSettings(
        uint256 _globalDailyLimit,
        uint256 _maxBatchSize,
        uint256 _signatureValidityPeriod
    ) external onlyRole(ADMIN_ROLE) {
        globalDailyLimit = _globalDailyLimit;
        maxBatchSize = _maxBatchSize;
        signatureValidityPeriod = _signatureValidityPeriod;
    }

    /**
     * @dev Update treasury address
     */
    function updateTreasury(address _treasury) external onlyRole(ADMIN_ROLE) {
        require(_treasury != address(0), "Invalid address");
        treasury = _treasury;
    }

    /**
     * @dev Pause/unpause contract
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}
