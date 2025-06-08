// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

contract MockERC20 is ERC20Upgradeable {
    function initialize(string memory name, string memory symbol) external initializer {
        __ERC20_init(name, symbol);
        _mint(msg.sender, 1_000_000 * 10 ** 18);
    }
}
