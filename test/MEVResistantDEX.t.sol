// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "lib/forge-std/src/Test.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../src/MEVResistantDEX.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {MockV3Aggregator} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/tests/MockV3Aggregator.sol";

/// @title MEVResistantDEXTest
/// @notice Test suite for MEVResistantDEX to verify MEV protection mechanisms
/// @title MEVResistantDEXTest
/// @notice Test suite for MEVResistantDEX to verify MEV protection mechanisms
contract MEVResistantDEXTest is Test {
    MEVResistantDEX _dex;
    MockERC20 _tokenA;
    MockERC20 _tokenB;
    MockV3Aggregator _priceFeed;
    address _user1 = address(0x1);
    address _user2 = address(0x2);
    address _attacker = address(0x3);
    address _owner = address(0x4);

    function setUp() public {
        // Deploy mock tokens
        _tokenA = new MockERC20();
        _tokenB = new MockERC20();
        _tokenA.initialize("Token A", "TKNA");
        _tokenB.initialize("Token B", "TKNB");

        // Deploy Chainlink mock
        _priceFeed = new MockV3Aggregator(8, 1000 * 10 ** 8); // 1000 TOKEN_A/TOKEN_B

        // Deploy DEX implementation (no constructor args)
        MEVResistantDEX dexImpl = new MEVResistantDEX();

        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            MEVResistantDEX.initialize.selector, address(_tokenA), address(_tokenB), address(_priceFeed)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(dexImpl), initData);
        _dex = MEVResistantDEX(address(proxy));

        vm.store(address(_dex), bytes32(uint256(1)), bytes32(uint256(uint160(address(_tokenA))))); // TOKEN_A
        vm.store(address(_dex), bytes32(uint256(2)), bytes32(uint256(uint160(address(_tokenB))))); // TOKEN_B
        vm.store(address(_dex), bytes32(uint256(3)), bytes32(uint256(uint160(address(_priceFeed))))); // priceFeed

        // Fund users and attacker
        _tokenA.transfer(_user1, 1000 * 10 ** 18);
        _tokenB.transfer(_user1, 1000 * 10 ** 18);
        _tokenA.transfer(_user2, 1000 * 10 ** 18);
        _tokenB.transfer(_user2, 1000 * 10 ** 18);
        _tokenA.transfer(_attacker, 1000 * 10 ** 18);
        _tokenB.transfer(_attacker, 1000 * 10 ** 18);

        // Approve DEX for token transfers
        vm.startPrank(_user1);
        _tokenA.approve(address(_dex), type(uint256).max);
        _tokenB.approve(address(_dex), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(_user2);
        _tokenA.approve(address(_dex), type(uint256).max);
        _tokenB.approve(address(_dex), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(_attacker);
        _tokenA.approve(address(_dex), type(uint256).max);
        _tokenB.approve(address(_dex), type(uint256).max);
        vm.stopPrank();
    }

    function testCommitReveal() public {
        vm.startPrank(_user1);
        bytes32 commitment = keccak256(abi.encodePacked(uint256(100), uint256(1000), true, bytes32(uint256(123))));
        _dex.commitOrder(commitment);
        vm.roll(block.number + 10); // Simulate delay (~5s on zkSync)
        _dex.revealOrder(0, 100, 1000, true, bytes32(uint256(123)));
        vm.stopPrank();
    }

    function testFrontRunningAttackFails() public {
        vm.startPrank(_attacker);
        bytes32 commitment = keccak256(abi.encodePacked(uint256(100), uint256(1000), true, bytes32(uint256(123))));
        _dex.commitOrder(commitment);
        vm.roll(block.number + 10); // Ensure delay
        vm.expectRevert("Invalid commitment");
        _dex.revealOrder(0, 100, 1000, true, bytes32(uint256(456))); // Wrong nonce
        vm.stopPrank();
    }

    function testUpgrade() public {
        // Deploy new implementation
        MEVResistantDEX newImpl = new MEVResistantDEX();

        // Upgrade proxy

        _dex.upgradeTo(address(newImpl));

        // Verify functionality after upgrade
        vm.startPrank(_user1);
        bytes32 commitment = keccak256(abi.encodePacked(uint256(100), uint256(1000), true, bytes32(uint256(123))));
        _dex.commitOrder(commitment);
        vm.roll(block.number + 10);
        _dex.revealOrder(0, 100, 1000, true, bytes32(uint256(123)));
        vm.stopPrank();
    }
}
