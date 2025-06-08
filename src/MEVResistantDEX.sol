// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import {AggregatorV3Interface} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

/// @title MEVResistantDEX
/// @notice A decentralized exchange with MEV protection and UUPS upgradability for zkSync
/// @dev Implements limit-order trading for an ERC20 token pair with commit-reveal, time-delay, and batch execution
contract MEVResistantDEX is UUPSUpgradeable, OwnableUpgradeable {
    /// @notice Structure to store order details
    /// @dev Includes commitment for MEV protection and partial fill tracking
    struct Order {
        address user; // Order creator
        uint256 amount; // Token amount (in TOKEN_B for buy, TOKEN_A for sell)
        uint256 price; // Price in TOKEN_A per TOKEN_B
        bool isBuy; // True for buy orders, false for sell orders
        uint256 blockNumber; // Block when order was committed
        bytes32 commitment; // Hash of order details
        bool revealed; // Whether order details are revealed
        uint256 filledAmount; // Amount already filled
        bool cancelled; // Whether order is cancelled
    }

    /// @notice Mapping of order ID to order details
    mapping(uint256 => Order) public orders;
    /// @notice Incremental order counter
    uint256 public orderCount;
    /// @notice Minimum blocks to wait before revealing/executing orders
    uint256 public constant DELAY_BLOCKS = 10; // Adjusted for zkSync (~0.25s block time)
    /// @notice Maximum orders per batch to limit gas
    uint256 public constant BATCH_SIZE = 10;
    /// @notice First token in the trading pair (e.g., WETH)
    IERC20Upgradeable public TOKEN_A;
    /// @notice Second token in the trading pair (e.g., DAI)
    IERC20Upgradeable public TOKEN_B;
    /// @notice Chainlink price feed for TOKEN_A/TOKEN_B
    AggregatorV3Interface public priceFeed;

    /// @notice Emitted when an order is committed
    event OrderCommitted(uint256 indexed orderId, bytes32 commitment);
    /// @notice Emitted when an order is revealed
    event OrderRevealed(uint256 indexed orderId, address user, uint256 amount, uint256 price, bool isBuy);
    /// @notice Emitted when an order is cancelled
    event OrderCancelled(uint256 indexed orderId);
    /// @notice Emitted when a batch is executed
    event BatchExecuted(uint256 indexed batchId, uint256 clearingPrice);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers(); // Prevent initialization in implementation contract
    }

    /// @notice Initializes the contract with token pair and price feed
    /// @dev Sets up UUPS and Ownable, only callable once
    /// @param _tokenA Address of the first token (e.g., WETH)
    /// @param _tokenB Address of the second token (e.g., DAI)
    /// @param _priceFeed Address of Chainlink price feed for TOKEN_A/TOKEN_B
    function initialize(address _tokenA, address _tokenB, address _priceFeed) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        TOKEN_A = IERC20Upgradeable(_tokenA);
        TOKEN_B = IERC20Upgradeable(_tokenB);
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    /// @notice Authorizes contract upgrades
    /// @dev Required by UUPS, only owner can upgrade
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Commits an order with a cryptographic hash
    /// @dev Users submit a hash of order details to hide them from miners
    /// @param _commitment Hash of (amount, price, isBuy, nonce)
    function commitOrder(bytes32 _commitment) external {
        orders[orderCount] = Order({
            user: msg.sender,
            amount: 0,
            price: 0,
            isBuy: false,
            blockNumber: block.number,
            commitment: _commitment,
            revealed: false,
            filledAmount: 0,
            cancelled: false
        });
        emit OrderCommitted(orderCount, _commitment);
        orderCount++;
    }

    /// @notice Reveals order details after delay
    /// @dev Verifies commitment and updates order details, transfers tokens to contract
    /// @param _orderId ID of the order to reveal
    /// @param _amount Amount of tokens to trade
    /// @param _price Price in TOKEN_A per TOKEN_B
    /// @param _isBuy True if buy order, false if sell order
    /// @param _nonce Random nonce for commitment
    function revealOrder(uint256 _orderId, uint256 _amount, uint256 _price, bool _isBuy, bytes32 _nonce) external {
        Order storage order = orders[_orderId];
        require(order.user == msg.sender, "Not order owner");
        require(!order.revealed, "Order already revealed");
        require(!order.cancelled, "Order cancelled");
        require(block.number >= order.blockNumber + DELAY_BLOCKS, "Delay not met");
        require(keccak256(abi.encodePacked(_amount, _price, _isBuy, _nonce)) == order.commitment, "Invalid commitment");

        order.amount = _amount;
        order.price = _price;
        order.isBuy = _isBuy;
        order.revealed = true;

        // Transfer tokens to contract
        if (_isBuy) {
            require(TOKEN_A.transferFrom(msg.sender, address(this), _amount * _price), "Token A transfer failed");
        } else {
            require(TOKEN_B.transferFrom(msg.sender, address(this), _amount), "Token B transfer failed");
        }

        emit OrderRevealed(_orderId, msg.sender, _amount, _price, _isBuy);
    }

    /// @notice Cancels an order before execution
    /// @dev Refunds deposited tokens and marks order as cancelled
    /// @param _orderId ID of the order to cancel
    function cancelOrder(uint256 _orderId) external {
        Order storage order = orders[_orderId];
        require(order.user == msg.sender, "Not order owner");
        require(!order.cancelled, "Order already cancelled");
        require(order.filledAmount == 0, "Order partially filled");

        order.cancelled = true;

        // Refund deposited tokens
        if (order.revealed) {
            if (order.isBuy) {
                require(TOKEN_A.transfer(msg.sender, order.amount * order.price), "Refund failed");
            } else {
                require(TOKEN_B.transfer(msg.sender, order.amount), "Refund failed");
            }
        }

        emit OrderCancelled(_orderId);
    }

    /// @notice Executes a batch of orders at a fair clearing price
    /// @dev Uses Chainlink oracle to validate price, supports partial fills
    /// @param _orderIds Array of order IDs to include in the batch
    function executeBatch(uint256[] calldata _orderIds) external {
        require(_orderIds.length <= BATCH_SIZE, "Batch too large");

        // Get Chainlink price for validation
        (, int256 chainlinkPrice,,,) = priceFeed.latestRoundData();
        require(chainlinkPrice > 0, "Invalid Chainlink price");

        // Gas optimization: Use memory arrays
        uint256[] memory buyAmounts = new uint256[](_orderIds.length);
        uint256[] memory sellAmounts = new uint256[](_orderIds.length);
        uint256[] memory buyValues = new uint256[](_orderIds.length);
        uint256[] memory sellValues = new uint256[](_orderIds.length);
        uint256 buyCount;
        uint256 sellCount;

        // Aggregate buy and sell orders
        for (uint256 i = 0; i < _orderIds.length; i++) {
            Order storage order = orders[_orderIds[i]];
            require(order.revealed, "Order not revealed");
            require(!order.cancelled, "Order cancelled");
            require(block.number >= order.blockNumber + DELAY_BLOCKS, "Delay not met");

            uint256 remainingAmount = order.amount - order.filledAmount;
            if (remainingAmount == 0) continue;

            if (order.isBuy) {
                buyAmounts[buyCount] = remainingAmount;
                buyValues[buyCount] = remainingAmount * order.price;
                buyCount++;
            } else {
                sellAmounts[sellCount] = remainingAmount;
                sellValues[sellCount] = remainingAmount * order.price;
                sellCount++;
            }
        }

        // Calculate total amounts and values
        uint256 totalBuyAmount;
        uint256 totalSellAmount;
        uint256 totalBuyValue;
        uint256 totalSellValue;

        for (uint256 i = 0; i < buyCount; i++) {
            totalBuyAmount += buyAmounts[i];
            totalBuyValue += buyValues[i];
        }
        for (uint256 i = 0; i < sellCount; i++) {
            totalSellAmount += sellAmounts[i];
            totalSellValue += sellValues[i];
        }

        // Calculate fair clearing price (VWAP)
        uint256 clearingPrice;
        if (totalBuyAmount > 0 && totalSellAmount > 0) {
            clearingPrice = (totalBuyValue + totalSellValue) / (totalBuyAmount + totalSellAmount);
            require(
                clearingPrice >= uint256(chainlinkPrice) * 95 / 100
                    && clearingPrice <= uint256(chainlinkPrice) * 105 / 100,
                "Price deviates from oracle"
            );
        } else {
            revert("No valid orders");
        }

        // Determine matched volume
        uint256 matchedVolume = totalBuyAmount < totalSellAmount ? totalBuyAmount : totalSellAmount;

        // Execute trades with partial fills
        for (uint256 i = 0; i < _orderIds.length; i++) {
            Order storage order = orders[_orderIds[i]];
            uint256 remainingAmount = order.amount - order.filledAmount;
            if (remainingAmount == 0) continue;

            // Calculate fill amount
            uint256 fillAmount = remainingAmount;
            if (matchedVolume < remainingAmount) {
                fillAmount = matchedVolume;
            }

            if (order.isBuy) {
                // Transfer TOKEN_B to user, deduct TOKEN_A
                uint256 tokenAAmount = fillAmount * clearingPrice;
                require(TOKEN_B.transfer(order.user, fillAmount), "Token B transfer failed");
                require(TOKEN_A.transferFrom(order.user, address(this), tokenAAmount), "Token A transfer failed");
            } else {
                // Transfer TOKEN_A to user, deduct TOKEN_B
                uint256 tokenAAmount = fillAmount * clearingPrice;
                require(TOKEN_A.transfer(order.user, tokenAAmount), "Token A transfer failed");
                require(TOKEN_B.transferFrom(order.user, address(this), fillAmount), "Token B transfer failed");
            }

            order.filledAmount += fillAmount;
            matchedVolume -= fillAmount;

            // Clean up fully filled orders
            if (order.filledAmount == order.amount) {
                delete orders[_orderIds[i]];
            }
        }

        emit BatchExecuted(block.number, clearingPrice);
    }

    /// @notice Gets the latest Chainlink price
    /// @return Current price from the Chainlink oracle
    function getLatestPrice() public view returns (int256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        return price;
    }
}
