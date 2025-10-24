// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title MegaCommerce
 * @dev Complete e-commerce toolkit for building MegaETH-powered online stores
 */
contract MegaCommerce is Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;

    enum OrderStatus { Pending, Paid, Shipped, Delivered, Cancelled, Refunded }
    enum PaymentMethod { ETH, ERC20, MegaPayments }

    struct Product {
        uint256 id;
        address seller;
        string name;
        string description;
        uint256 price;
        address priceToken; // Address(0) for ETH
        uint256 stock;
        bool active;
        string imageUrl;
        uint256 createdAt;
    }

    struct Order {
        uint256 id;
        address buyer;
        uint256 productId;
        uint256 quantity;
        uint256 totalAmount;
        address paymentToken;
        PaymentMethod paymentMethod;
        OrderStatus status;
        uint256 createdAt;
        uint256 updatedAt;
        string shippingAddress;
        string trackingNumber;
    }

    struct Store {
        address owner;
        string name;
        string description;
        string logoUrl;
        bool active;
        uint256 createdAt;
    }

    Counters.Counter private _productIds;
    Counters.Counter private _orderIds;
    Counters.Counter private _storeIds;

    mapping(uint256 => Product) public products;
    mapping(uint256 => Order) public orders;
    mapping(uint256 => Store) public stores;
    mapping(address => uint256[]) public userOrders;
    mapping(address => uint256[]) public sellerProducts;
    mapping(address => uint256) public userStore;
    mapping(address => bool) public supportedTokens;

    uint256 public platformFeePercent = 250; // 2.5%
    address public feeCollector;
    uint256 public constant FEE_DENOMINATOR = 10000;

    event ProductCreated(uint256 indexed productId, address indexed seller, string name, uint256 price);
    event ProductUpdated(uint256 indexed productId, uint256 newPrice, uint256 newStock);
    event OrderCreated(uint256 indexed orderId, address indexed buyer, uint256 indexed productId, uint256 quantity);
    event OrderStatusUpdated(uint256 indexed orderId, OrderStatus newStatus);
    event StoreCreated(uint256 indexed storeId, address indexed owner, string name);
    event PaymentProcessed(uint256 indexed orderId, address indexed buyer, uint256 amount);
    event RefundProcessed(uint256 indexed orderId, address indexed buyer, uint256 amount);

    constructor(address _feeCollector) {
        feeCollector = _feeCollector;
    }

    /**
     * @dev Create a new store
     * @param name Store name
     * @param description Store description
     * @param logoUrl Store logo URL
     */
    function createStore(string memory name, string memory description, string memory logoUrl) external {
        require(bytes(name).length > 0, "Store name required");
        require(userStore[msg.sender] == 0, "Store already exists");

        _storeIds.increment();
        uint256 storeId = _storeIds.current();

        stores[storeId] = Store({
            owner: msg.sender,
            name: name,
            description: description,
            logoUrl: logoUrl,
            active: true,
            createdAt: block.timestamp
        });

        userStore[msg.sender] = storeId;

        emit StoreCreated(storeId, msg.sender, name);
    }

    /**
     * @dev Create a new product
     * @param name Product name
     * @param description Product description
     * @param price Product price
     * @param priceToken Token address (address(0) for ETH)
     * @param stock Initial stock
     * @param imageUrl Product image URL
     */
    function createProduct(
        string memory name,
        string memory description,
        uint256 price,
        address priceToken,
        uint256 stock,
        string memory imageUrl
    ) external {
        require(userStore[msg.sender] > 0, "Store required");
        require(bytes(name).length > 0, "Product name required");
        require(price > 0, "Price must be positive");
        require(stock > 0, "Stock must be positive");
        require(priceToken == address(0) || supportedTokens[priceToken], "Token not supported");

        _productIds.increment();
        uint256 productId = _productIds.current();

        products[productId] = Product({
            id: productId,
            seller: msg.sender,
            name: name,
            description: description,
            price: price,
            priceToken: priceToken,
            stock: stock,
            active: true,
            imageUrl: imageUrl,
            createdAt: block.timestamp
        });

        sellerProducts[msg.sender].push(productId);

        emit ProductCreated(productId, msg.sender, name, price);
    }

    /**
     * @dev Update product details
     * @param productId Product ID
     * @param newPrice New price
     * @param newStock New stock
     */
    function updateProduct(uint256 productId, uint256 newPrice, uint256 newStock) external {
        Product storage product = products[productId];
        require(product.seller == msg.sender, "Not product owner");
        require(product.active, "Product not active");

        product.price = newPrice;
        product.stock = newStock;

        emit ProductUpdated(productId, newPrice, newStock);
    }

    /**
     * @dev Create an order
     * @param productId Product ID
     * @param quantity Quantity to order
     * @param shippingAddress Shipping address
     */
    function createOrder(uint256 productId, uint256 quantity, string memory shippingAddress) external payable nonReentrant {
        Product storage product = products[productId];
        require(product.active, "Product not active");
        require(product.stock >= quantity, "Insufficient stock");
        require(quantity > 0, "Quantity must be positive");

        uint256 totalAmount = product.price * quantity;
        uint256 platformFee = (totalAmount * platformFeePercent) / FEE_DENOMINATOR;
        uint256 sellerAmount = totalAmount - platformFee;

        // Process payment
        if (product.priceToken == address(0)) {
            // ETH payment
            require(msg.value >= totalAmount, "Insufficient ETH payment");
            
            // Refund excess ETH
            if (msg.value > totalAmount) {
                payable(msg.sender).transfer(msg.value - totalAmount);
            }
            
            // Transfer platform fee
            payable(feeCollector).transfer(platformFee);
            
            // Transfer to seller
            payable(product.seller).transfer(sellerAmount);
        } else {
            // ERC20 payment
            IERC20(product.priceToken).transferFrom(msg.sender, feeCollector, platformFee);
            IERC20(product.priceToken).transferFrom(msg.sender, product.seller, sellerAmount);
        }

        // Update product stock
        product.stock -= quantity;

        // Create order
        _orderIds.increment();
        uint256 orderId = _orderIds.current();

        orders[orderId] = Order({
            id: orderId,
            buyer: msg.sender,
            productId: productId,
            quantity: quantity,
            totalAmount: totalAmount,
            paymentToken: product.priceToken,
            paymentMethod: product.priceToken == address(0) ? PaymentMethod.ETH : PaymentMethod.ERC20,
            status: OrderStatus.Paid,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            shippingAddress: shippingAddress,
            trackingNumber: ""
        });

        userOrders[msg.sender].push(orderId);

        emit OrderCreated(orderId, msg.sender, productId, quantity);
        emit PaymentProcessed(orderId, msg.sender, totalAmount);
    }

    /**
     * @dev Update order status (seller only)
     * @param orderId Order ID
     * @param newStatus New order status
     * @param trackingNumber Optional tracking number
     */
    function updateOrderStatus(uint256 orderId, OrderStatus newStatus, string memory trackingNumber) external {
        Order storage order = orders[orderId];
        Product storage product = products[order.productId];
        
        require(product.seller == msg.sender, "Not order seller");
        require(order.status != OrderStatus.Cancelled, "Order cancelled");

        order.status = newStatus;
        order.updatedAt = block.timestamp;
        
        if (bytes(trackingNumber).length > 0) {
            order.trackingNumber = trackingNumber;
        }

        emit OrderStatusUpdated(orderId, newStatus);
    }

    /**
     * @dev Process refund
     * @param orderId Order ID
     */
    function processRefund(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];
        Product storage product = products[order.productId];
        
        require(product.seller == msg.sender || msg.sender == owner(), "Not authorized");
        require(order.status == OrderStatus.Cancelled, "Order not cancelled");

        uint256 refundAmount = order.totalAmount;

        if (order.paymentToken == address(0)) {
            // ETH refund
            payable(order.buyer).transfer(refundAmount);
        } else {
            // ERC20 refund
            IERC20(order.paymentToken).transfer(order.buyer, refundAmount);
        }

        // Restore product stock
        product.stock += order.quantity;

        order.status = OrderStatus.Refunded;
        order.updatedAt = block.timestamp;

        emit RefundProcessed(orderId, order.buyer, refundAmount);
    }

    /**
     * @dev Get user's orders
     * @param user User address
     * @return Array of order IDs
     */
    function getUserOrders(address user) external view returns (uint256[] memory) {
        return userOrders[user];
    }

    /**
     * @dev Get seller's products
     * @param seller Seller address
     * @return Array of product IDs
     */
    function getSellerProducts(address seller) external view returns (uint256[] memory) {
        return sellerProducts[seller];
    }

    /**
     * @dev Add supported token
     * @param token Token address
     */
    function addSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = true;
    }

    /**
     * @dev Remove supported token
     * @param token Token address
     */
    function removeSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = false;
    }

    /**
     * @dev Update platform fee percentage
     * @param newFeePercent New fee percentage (in basis points)
     */
    function updatePlatformFee(uint256 newFeePercent) external onlyOwner {
        require(newFeePercent <= 1000, "Fee too high"); // Max 10%
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
}
