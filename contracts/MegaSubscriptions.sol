// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title MegaSubscriptions
 * @dev Professional subscription and recurring payment system
 */
contract MegaSubscriptions is AccessControl, ReentrancyGuard, Pausable {
    using Counters for Counters.Counter;
    using ECDSA for bytes32;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    enum SubscriptionStatus { Active, Paused, Cancelled, Expired, Failed }
    enum BillingCycle { Daily, Weekly, Monthly, Quarterly, Yearly }
    enum PaymentStatus { Pending, Paid, Failed, Refunded }

    struct SubscriptionPlan {
        uint256 id;
        string name;
        string description;
        uint256 price;
        address priceToken; // address(0) for ETH
        BillingCycle cycle;
        uint256 cycleDuration; // in seconds
        uint256 maxSubscribers;
        uint256 currentSubscribers;
        bool active;
        uint256 createdAt;
    }

    struct Subscription {
        uint256 id;
        address subscriber;
        uint256 planId;
        uint256 startTime;
        uint256 nextBillingTime;
        uint256 endTime;
        SubscriptionStatus status;
        uint256 totalPaid;
        uint256 failedPayments;
        uint256 maxFailedPayments;
        bool autoRenew;
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct PaymentRecord {
        uint256 id;
        uint256 subscriptionId;
        uint256 amount;
        address token;
        PaymentStatus status;
        uint256 timestamp;
        bytes32 txHash;
        string failureReason;
    }

    struct UsageMetrics {
        uint256 subscriptionId;
        uint256 usageCount;
        uint256 lastUsage;
        uint256 totalUsage;
        mapping(string => uint256) customMetrics;
    }

    Counters.Counter private _planIds;
    Counters.Counter private _subscriptionIds;
    Counters.Counter private _paymentIds;

    mapping(uint256 => SubscriptionPlan) public plans;
    mapping(uint256 => Subscription) public subscriptions;
    mapping(uint256 => PaymentRecord) public payments;
    mapping(address => uint256[]) public userSubscriptions;
    mapping(uint256 => uint256[]) public planSubscriptions;
    mapping(uint256 => UsageMetrics) public usageMetrics;
    mapping(address => bool) public supportedTokens;
    mapping(address => bool) public authorizedOperators;

    uint256 public platformFeePercent = 250; // 2.5%
    uint256 public maxFailedPayments = 3;
    uint256 public gracePeriod = 7 days;
    address public feeCollector;
    address public treasury;

    event PlanCreated(uint256 indexed planId, string name, uint256 price);
    event SubscriptionCreated(uint256 indexed subscriptionId, address indexed subscriber, uint256 planId);
    event PaymentProcessed(uint256 indexed paymentId, uint256 subscriptionId, uint256 amount);
    event PaymentFailed(uint256 indexed paymentId, uint256 subscriptionId, string reason);
    event SubscriptionCancelled(uint256 indexed subscriptionId, address indexed subscriber);
    event SubscriptionPaused(uint256 indexed subscriptionId, address indexed subscriber);
    event SubscriptionResumed(uint256 indexed subscriptionId, address indexed subscriber);

    constructor(address _admin, address _feeCollector, address _treasury) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        feeCollector = _feeCollector;
        treasury = _treasury;
    }

    /**
     * @dev Create a new subscription plan
     */
    function createPlan(
        string memory name,
        string memory description,
        uint256 price,
        address priceToken,
        BillingCycle cycle,
        uint256 maxSubscribers
    ) external onlyRole(ADMIN_ROLE) returns (uint256) {
        require(bytes(name).length > 0, "Name required");
        require(price > 0, "Price must be positive");
        require(priceToken == address(0) || supportedTokens[priceToken], "Token not supported");

        _planIds.increment();
        uint256 planId = _planIds.current();

        uint256 cycleDuration = _getCycleDuration(cycle);

        plans[planId] = SubscriptionPlan({
            id: planId,
            name: name,
            description: description,
            price: price,
            priceToken: priceToken,
            cycle: cycle,
            cycleDuration: cycleDuration,
            maxSubscribers: maxSubscribers,
            currentSubscribers: 0,
            active: true,
            createdAt: block.timestamp
        });

        emit PlanCreated(planId, name, price);
        return planId;
    }

    /**
     * @dev Subscribe to a plan
     */
    function subscribe(
        uint256 planId,
        bool autoRenew
    ) external payable whenNotPaused nonReentrant returns (uint256) {
        SubscriptionPlan storage plan = plans[planId];
        require(plan.active, "Plan not active");
        require(plan.currentSubscribers < plan.maxSubscribers, "Plan full");
        require(plan.priceToken == address(0) || supportedTokens[plan.priceToken], "Token not supported");

        // Check if user already has active subscription to this plan
        uint256[] memory userSubs = userSubscriptions[msg.sender];
        for (uint256 i = 0; i < userSubs.length; i++) {
            Subscription storage existingSub = subscriptions[userSubs[i]];
            if (existingSub.planId == planId && existingSub.status == SubscriptionStatus.Active) {
                revert("Already subscribed to this plan");
            }
        }

        _subscriptionIds.increment();
        uint256 subscriptionId = _subscriptionIds.current();

        uint256 startTime = block.timestamp;
        uint256 nextBillingTime = startTime + plan.cycleDuration;

        subscriptions[subscriptionId] = Subscription({
            id: subscriptionId,
            subscriber: msg.sender,
            planId: planId,
            startTime: startTime,
            nextBillingTime: nextBillingTime,
            endTime: 0, // No end time for auto-renewing subscriptions
            status: SubscriptionStatus.Active,
            totalPaid: 0,
            failedPayments: 0,
            maxFailedPayments: maxFailedPayments,
            autoRenew: autoRenew,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        userSubscriptions[msg.sender].push(subscriptionId);
        planSubscriptions[planId].push(subscriptionId);
        plan.currentSubscribers++;

        // Process initial payment
        _processPayment(subscriptionId, plan.price, plan.priceToken);

        emit SubscriptionCreated(subscriptionId, msg.sender, planId);
        return subscriptionId;
    }

    /**
     * @dev Process recurring payments (called by operator or automated system)
     */
    function processRecurringPayments(uint256[] memory subscriptionIds) external onlyRole(OPERATOR_ROLE) {
        for (uint256 i = 0; i < subscriptionIds.length; i++) {
            _processRecurringPayment(subscriptionIds[i]);
        }
    }

    /**
     * @dev Cancel subscription
     */
    function cancelSubscription(uint256 subscriptionId) external {
        Subscription storage subscription = subscriptions[subscriptionId];
        require(subscription.subscriber == msg.sender, "Not subscriber");
        require(subscription.status == SubscriptionStatus.Active, "Not active");

        subscription.status = SubscriptionStatus.Cancelled;
        subscription.endTime = block.timestamp;
        subscription.updatedAt = block.timestamp;

        // Update plan subscriber count
        SubscriptionPlan storage plan = plans[subscription.planId];
        plan.currentSubscribers--;

        emit SubscriptionCancelled(subscriptionId, msg.sender);
    }

    /**
     * @dev Pause subscription
     */
    function pauseSubscription(uint256 subscriptionId) external {
        Subscription storage subscription = subscriptions[subscriptionId];
        require(subscription.subscriber == msg.sender, "Not subscriber");
        require(subscription.status == SubscriptionStatus.Active, "Not active");

        subscription.status = SubscriptionStatus.Paused;
        subscription.updatedAt = block.timestamp;

        emit SubscriptionPaused(subscriptionId, msg.sender);
    }

    /**
     * @dev Resume subscription
     */
    function resumeSubscription(uint256 subscriptionId) external {
        Subscription storage subscription = subscriptions[subscriptionId];
        require(subscription.subscriber == msg.sender, "Not subscriber");
        require(subscription.status == SubscriptionStatus.Paused, "Not paused");

        subscription.status = SubscriptionStatus.Active;
        subscription.nextBillingTime = block.timestamp + plans[subscription.planId].cycleDuration;
        subscription.updatedAt = block.timestamp;

        emit SubscriptionResumed(subscriptionId, msg.sender);
    }

    /**
     * @dev Record usage for a subscription
     */
    function recordUsage(uint256 subscriptionId, string memory metric, uint256 value) external {
        Subscription storage subscription = subscriptions[subscriptionId];
        require(subscription.subscriber == msg.sender, "Not subscriber");
        require(subscription.status == SubscriptionStatus.Active, "Not active");

        UsageMetrics storage metrics = usageMetrics[subscriptionId];
        metrics.usageCount++;
        metrics.lastUsage = block.timestamp;
        metrics.totalUsage += value;
        metrics.customMetrics[metric] += value;
    }

    /**
     * @dev Get subscription details
     */
    function getSubscriptionDetails(uint256 subscriptionId) external view returns (
        Subscription memory subscription,
        SubscriptionPlan memory plan,
        PaymentRecord[] memory recentPayments
    ) {
        subscription = subscriptions[subscriptionId];
        plan = plans[subscription.planId];
        
        // Get recent payments (simplified - in production, use proper indexing)
        recentPayments = new PaymentRecord[](0);
    }

    /**
     * @dev Get user's subscriptions
     */
    function getUserSubscriptions(address user) external view returns (uint256[] memory) {
        return userSubscriptions[user];
    }

    /**
     * @dev Get plan subscribers
     */
    function getPlanSubscribers(uint256 planId) external view returns (uint256[] memory) {
        return planSubscriptions[planId];
    }

    /**
     * @dev Get usage metrics for subscription
     */
    function getUsageMetrics(uint256 subscriptionId) external view returns (
        uint256 usageCount,
        uint256 lastUsage,
        uint256 totalUsage
    ) {
        UsageMetrics storage metrics = usageMetrics[subscriptionId];
        return (metrics.usageCount, metrics.lastUsage, metrics.totalUsage);
    }

    /**
     * @dev Internal payment processing
     */
    function _processPayment(uint256 subscriptionId, uint256 amount, address token) internal {
        Subscription storage subscription = subscriptions[subscriptionId];
        
        uint256 platformFee = (amount * platformFeePercent) / 10000;
        uint256 netAmount = amount - platformFee;

        bool success = false;
        string memory failureReason = "";

        if (token == address(0)) {
            // ETH payment
            if (msg.value >= amount) {
                if (msg.value > amount) {
                    payable(msg.sender).transfer(msg.value - amount);
                }
                payable(feeCollector).transfer(platformFee);
                payable(treasury).transfer(netAmount);
                success = true;
            } else {
                failureReason = "Insufficient ETH";
            }
        } else {
            // ERC20 payment
            try IERC20(token).transferFrom(msg.sender, feeCollector, platformFee) {
                try IERC20(token).transferFrom(msg.sender, treasury, netAmount) {
                    success = true;
                } catch {
                    failureReason = "ERC20 transfer failed";
                }
            } catch {
                failureReason = "ERC20 approval failed";
            }
        }

        _recordPayment(subscriptionId, amount, token, success, failureReason);

        if (success) {
            subscription.totalPaid += amount;
            subscription.failedPayments = 0;
        } else {
            subscription.failedPayments++;
            if (subscription.failedPayments >= subscription.maxFailedPayments) {
                subscription.status = SubscriptionStatus.Failed;
            }
        }
    }

    /**
     * @dev Process recurring payment
     */
    function _processRecurringPayment(uint256 subscriptionId) internal {
        Subscription storage subscription = subscriptions[subscriptionId];
        require(subscription.status == SubscriptionStatus.Active, "Not active");
        require(block.timestamp >= subscription.nextBillingTime, "Not time for billing");

        SubscriptionPlan storage plan = plans[subscription.planId];
        
        // Attempt payment (simplified - in production, implement proper payment processing)
        _recordPayment(subscriptionId, plan.price, plan.priceToken, true, "");

        if (subscription.autoRenew) {
            subscription.nextBillingTime += plan.cycleDuration;
        } else {
            subscription.status = SubscriptionStatus.Expired;
            subscription.endTime = block.timestamp;
        }

        subscription.updatedAt = block.timestamp;
    }

    /**
     * @dev Record payment
     */
    function _recordPayment(
        uint256 subscriptionId,
        uint256 amount,
        address token,
        bool success,
        string memory failureReason
    ) internal {
        _paymentIds.increment();
        uint256 paymentId = _paymentIds.current();

        payments[paymentId] = PaymentRecord({
            id: paymentId,
            subscriptionId: subscriptionId,
            amount: amount,
            token: token,
            status: success ? PaymentStatus.Paid : PaymentStatus.Failed,
            timestamp: block.timestamp,
            txHash: keccak256(abi.encodePacked(block.timestamp, subscriptionId, amount)),
            failureReason: failureReason
        });

        if (success) {
            emit PaymentProcessed(paymentId, subscriptionId, amount);
        } else {
            emit PaymentFailed(paymentId, subscriptionId, failureReason);
        }
    }

    /**
     * @dev Get cycle duration in seconds
     */
    function _getCycleDuration(BillingCycle cycle) internal pure returns (uint256) {
        if (cycle == BillingCycle.Daily) return 1 days;
        if (cycle == BillingCycle.Weekly) return 1 weeks;
        if (cycle == BillingCycle.Monthly) return 30 days;
        if (cycle == BillingCycle.Quarterly) return 90 days;
        if (cycle == BillingCycle.Yearly) return 365 days;
        return 30 days; // Default to monthly
    }

    /**
     * @dev Add supported token
     */
    function addSupportedToken(address token) external onlyRole(ADMIN_ROLE) {
        supportedTokens[token] = true;
    }

    /**
     * @dev Update platform fee
     */
    function updatePlatformFee(uint256 newFeePercent) external onlyRole(ADMIN_ROLE) {
        require(newFeePercent <= 1000, "Fee too high");
        platformFeePercent = newFeePercent;
    }

    /**
     * @dev Update max failed payments
     */
    function updateMaxFailedPayments(uint256 newMax) external onlyRole(ADMIN_ROLE) {
        maxFailedPayments = newMax;
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
