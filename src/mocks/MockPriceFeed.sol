// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AggregatorV3Interface} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MockPriceFeed is AggregatorV3Interface {
    function decimals() external pure override returns (uint8) {
        return 18;
    }

    function description() external pure override returns (string memory) {
        return "Mock Price Feed";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80) external pure override returns (uint80, int256, uint256, uint256, uint80) {
        revert("Not implemented");
    }

    function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
        return (0, 1000 * 10 ** 18, 0, block.timestamp, 0); // Mock price: 1000 TOKEN_A/TOKEN_B
    }
}
