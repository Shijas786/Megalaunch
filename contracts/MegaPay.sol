// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title MegaPay
 * @dev Multi-currency transaction fee payment system for MegaETH
 * Allows users to pay gas fees in different tokens
 */
contract MegaPay is Ownable, ReentrancyGuard {
    struct FeePayment {
        address token;
        uint256 amount;
        uint256 gasUsed;
        uint256 timestamp;
    }

    mapping(address => bool) public supportedTokens;
    mapping(address => uint256) public tokenGasPrice; // Gas price in token units per gas
    mapping(address => FeePayment[]) public userPayments;
    
    address public feeCollector;
    uint256 public baseGasPrice = 20 gwei;
    
    event TokenSupported(address indexed token, uint256 gasPrice);
    event TokenUnsupported(address indexed token);
    event FeePaid(address indexed user, address indexed token, uint256 amount, uint256 gasUsed);
    event GasPriceUpdated(address indexed token, uint256 newGasPrice);

    constructor(address _feeCollector) {
        feeCollector = _feeCollector;
    }

    /**
     * @dev Add support for a new token
     * @param token Token contract address
     * @param gasPrice Gas price in token units per gas
     */
    function addSupportedToken(address token, uint256 gasPrice) external onlyOwner {
        require(token != address(0), "Invalid token address");
        require(gasPrice > 0, "Gas price must be positive");
        
        supportedTokens[token] = true;
        tokenGasPrice[token] = gasPrice;
        
        emit TokenSupported(token, gasPrice);
    }

    /**
     * @dev Remove support for a token
     * @param token Token contract address
     */
    function removeSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = false;
        tokenGasPrice[token] = 0;
        
        emit TokenUnsupported(token);
    }

    /**
     * @dev Update gas price for a supported token
     * @param token Token contract address
     * @param newGasPrice New gas price in token units per gas
     */
    function updateTokenGasPrice(address token, uint256 newGasPrice) external onlyOwner {
        require(supportedTokens[token], "Token not supported");
        require(newGasPrice > 0, "Gas price must be positive");
        
        tokenGasPrice[token] = newGasPrice;
        
        emit GasPriceUpdated(token, newGasPrice);
    }

    /**
     * @dev Pay transaction fees using a supported token
     * @param token Token to pay fees with
     * @param gasUsed Amount of gas used in the transaction
     */
    function payFeesWithToken(address token, uint256 gasUsed) external nonReentrant {
        require(supportedTokens[token], "Token not supported");
        require(gasUsed > 0, "Gas used must be positive");
        
        uint256 feeAmount = calculateFeeAmount(token, gasUsed);
        
        IERC20(token).transferFrom(msg.sender, feeCollector, feeAmount);
        
        FeePayment memory payment = FeePayment({
            token: token,
            amount: feeAmount,
            gasUsed: gasUsed,
            timestamp: block.timestamp
        });
        
        userPayments[msg.sender].push(payment);
        
        emit FeePaid(msg.sender, token, feeAmount, gasUsed);
    }

    /**
     * @dev Calculate fee amount for a given token and gas usage
     * @param token Token contract address
     * @param gasUsed Amount of gas used
     * @return Fee amount in token units
     */
    function calculateFeeAmount(address token, uint256 gasUsed) public view returns (uint256) {
        require(supportedTokens[token], "Token not supported");
        
        uint256 gasPriceInToken = tokenGasPrice[token];
        return gasUsed * gasPriceInToken;
    }

    /**
     * @dev Get user's payment history
     * @param user User address
     * @return Array of fee payments
     */
    function getUserPayments(address user) external view returns (FeePayment[] memory) {
        return userPayments[user];
    }

    /**
     * @dev Get user's payment count
     * @param user User address
     * @return Number of payments made
     */
    function getUserPaymentCount(address user) external view returns (uint256) {
        return userPayments[user].length;
    }

    /**
     * @dev Update fee collector address
     * @param newFeeCollector New fee collector address
     */
    function updateFeeCollector(address newFeeCollector) external onlyOwner {
        require(newFeeCollector != address(0), "Invalid fee collector address");
        feeCollector = newFeeCollector;
    }

    /**
     * @dev Update base gas price
     * @param newBaseGasPrice New base gas price in wei
     */
    function updateBaseGasPrice(uint256 newBaseGasPrice) external onlyOwner {
        require(newBaseGasPrice > 0, "Base gas price must be positive");
        baseGasPrice = newBaseGasPrice;
    }
}
