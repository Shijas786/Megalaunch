// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title MegaPayments
 * @dev Standard protocol for decentralized payments on MegaETH with QR codes and transaction requests
 */
contract MegaPayments is Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    using ECDSA for bytes32;

    struct PaymentRequest {
        uint256 id;
        address merchant;
        address customer;
        uint256 amount;
        address token; // address(0) for ETH
        string description;
        string metadata; // JSON string for additional data
        bool fulfilled;
        uint256 createdAt;
        uint256 expiresAt;
        bytes32 requestHash;
    }

    struct PaymentIntent {
        uint256 requestId;
        address customer;
        uint256 amount;
        address token;
        bool completed;
        uint256 timestamp;
        bytes signature;
    }

    Counters.Counter private _requestIds;
    
    mapping(uint256 => PaymentRequest) public paymentRequests;
    mapping(bytes32 => bool) public usedSignatures;
    mapping(address => uint256[]) public merchantRequests;
    mapping(address => uint256[]) public customerPayments;
    mapping(address => bool) public supportedTokens;
    mapping(address => bool) public authorizedMerchants;

    uint256 public defaultExpiryTime = 24 hours;
    uint256 public platformFeePercent = 50; // 0.5%
    address public feeCollector;
    uint256 public constant FEE_DENOMINATOR = 10000;

    event PaymentRequestCreated(uint256 indexed requestId, address indexed merchant, address indexed customer, uint256 amount);
    event PaymentCompleted(uint256 indexed requestId, address indexed customer, uint256 amount);
    event PaymentCancelled(uint256 indexed requestId, address indexed merchant);
    event MerchantAuthorized(address indexed merchant);
    event MerchantDeauthorized(address indexed merchant);
    event TokenSupported(address indexed token);
    event TokenUnsupported(address indexed token);

    constructor(address _feeCollector) {
        feeCollector = _feeCollector;
    }

    /**
     * @dev Create a payment request
     * @param customer Customer address
     * @param amount Payment amount
     * @param token Token address (address(0) for ETH)
     * @param description Payment description
     * @param metadata Additional metadata (JSON string)
     * @param expiresAt Expiration timestamp (0 for default)
     */
    function createPaymentRequest(
        address customer,
        uint256 amount,
        address token,
        string memory description,
        string memory metadata,
        uint256 expiresAt
    ) external returns (uint256) {
        require(authorizedMerchants[msg.sender], "Not authorized merchant");
        require(customer != address(0), "Invalid customer address");
        require(amount > 0, "Amount must be positive");
        require(token == address(0) || supportedTokens[token], "Token not supported");

        if (expiresAt == 0) {
            expiresAt = block.timestamp + defaultExpiryTime;
        }

        _requestIds.increment();
        uint256 requestId = _requestIds.current();

        bytes32 requestHash = keccak256(abi.encodePacked(
            requestId,
            msg.sender,
            customer,
            amount,
            token,
            expiresAt
        ));

        paymentRequests[requestId] = PaymentRequest({
            id: requestId,
            merchant: msg.sender,
            customer: customer,
            amount: amount,
            token: token,
            description: description,
            metadata: metadata,
            fulfilled: false,
            createdAt: block.timestamp,
            expiresAt: expiresAt,
            requestHash: requestHash
        });

        merchantRequests[msg.sender].push(requestId);

        emit PaymentRequestCreated(requestId, msg.sender, customer, amount);
        return requestId;
    }

    /**
     * @dev Fulfill a payment request with ETH
     * @param requestId Payment request ID
     */
    function fulfillPaymentRequestETH(uint256 requestId) external payable nonReentrant {
        PaymentRequest storage request = paymentRequests[requestId];
        
        require(request.customer == msg.sender, "Not authorized customer");
        require(request.token == address(0), "Not ETH payment");
        require(!request.fulfilled, "Request already fulfilled");
        require(block.timestamp <= request.expiresAt, "Request expired");
        require(msg.value >= request.amount, "Insufficient payment");

        // Refund excess ETH
        if (msg.value > request.amount) {
            payable(msg.sender).transfer(msg.value - request.amount);
        }

        // Calculate fees
        uint256 platformFee = (request.amount * platformFeePercent) / FEE_DENOMINATOR;
        uint256 merchantAmount = request.amount - platformFee;

        // Transfer platform fee
        payable(feeCollector).transfer(platformFee);

        // Transfer to merchant
        payable(request.merchant).transfer(merchantAmount);

        // Mark as fulfilled
        request.fulfilled = true;
        customerPayments[msg.sender].push(requestId);

        emit PaymentCompleted(requestId, msg.sender, request.amount);
    }

    /**
     * @dev Fulfill a payment request with ERC20 token
     * @param requestId Payment request ID
     */
    function fulfillPaymentRequestToken(uint256 requestId) external nonReentrant {
        PaymentRequest storage request = paymentRequests[requestId];
        
        require(request.customer == msg.sender, "Not authorized customer");
        require(request.token != address(0), "Not token payment");
        require(!request.fulfilled, "Request already fulfilled");
        require(block.timestamp <= request.expiresAt, "Request expired");

        // Calculate fees
        uint256 platformFee = (request.amount * platformFeePercent) / FEE_DENOMINATOR;
        uint256 merchantAmount = request.amount - platformFee;

        // Transfer platform fee
        IERC20(request.token).transferFrom(msg.sender, feeCollector, platformFee);

        // Transfer to merchant
        IERC20(request.token).transferFrom(msg.sender, request.merchant, merchantAmount);

        // Mark as fulfilled
        request.fulfilled = true;
        customerPayments[msg.sender].push(requestId);

        emit PaymentCompleted(requestId, msg.sender, request.amount);
    }

    /**
     * @dev Cancel a payment request (merchant only)
     * @param requestId Payment request ID
     */
    function cancelPaymentRequest(uint256 requestId) external {
        PaymentRequest storage request = paymentRequests[requestId];
        
        require(request.merchant == msg.sender, "Not request merchant");
        require(!request.fulfilled, "Request already fulfilled");

        request.fulfilled = true; // Mark as fulfilled to prevent further processing

        emit PaymentCancelled(requestId, msg.sender);
    }

    /**
     * @dev Verify payment signature for off-chain verification
     * @param requestId Payment request ID
     * @param signature Customer signature
     * @return isValid Whether signature is valid
     */
    function verifyPaymentSignature(uint256 requestId, bytes memory signature) external view returns (bool isValid) {
        PaymentRequest storage request = paymentRequests[requestId];
        
        bytes32 messageHash = keccak256(abi.encodePacked(
            requestId,
            request.customer,
            request.amount,
            request.token,
            block.chainid
        ));
        
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        address signer = ethSignedMessageHash.recover(signature);
        
        return signer == request.customer;
    }

    /**
     * @dev Generate QR code data for payment request
     * @param requestId Payment request ID
     * @return QR code data string
     */
    function generateQRCodeData(uint256 requestId) external view returns (string memory) {
        PaymentRequest storage request = paymentRequests[requestId];
        
        return string(abi.encodePacked(
            "megapayments://pay?",
            "requestId=", uint2str(requestId),
            "&merchant=", addressToString(request.merchant),
            "&amount=", uint2str(request.amount),
            "&token=", addressToString(request.token),
            "&expires=", uint2str(request.expiresAt)
        ));
    }

    /**
     * @dev Get merchant's payment requests
     * @param merchant Merchant address
     * @return Array of request IDs
     */
    function getMerchantRequests(address merchant) external view returns (uint256[] memory) {
        return merchantRequests[merchant];
    }

    /**
     * @dev Get customer's payment history
     * @param customer Customer address
     * @return Array of request IDs
     */
    function getCustomerPayments(address customer) external view returns (uint256[] memory) {
        return customerPayments[customer];
    }

    /**
     * @dev Authorize a merchant
     * @param merchant Merchant address
     */
    function authorizeMerchant(address merchant) external onlyOwner {
        authorizedMerchants[merchant] = true;
        emit MerchantAuthorized(merchant);
    }

    /**
     * @dev Deauthorize a merchant
     * @param merchant Merchant address
     */
    function deauthorizeMerchant(address merchant) external onlyOwner {
        authorizedMerchants[merchant] = false;
        emit MerchantDeauthorized(merchant);
    }

    /**
     * @dev Add supported token
     * @param token Token address
     */
    function addSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = true;
        emit TokenSupported(token);
    }

    /**
     * @dev Remove supported token
     * @param token Token address
     */
    function removeSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = false;
        emit TokenUnsupported(token);
    }

    /**
     * @dev Update platform fee percentage
     * @param newFeePercent New fee percentage (in basis points)
     */
    function updatePlatformFee(uint256 newFeePercent) external onlyOwner {
        require(newFeePercent <= 500, "Fee too high"); // Max 5%
        platformFeePercent = newFeePercent;
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

    // Helper functions
    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }
}
