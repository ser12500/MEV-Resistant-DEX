// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "lib/forge-std/src/Script.sol";
import "../src/MEVResistantDEX.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract DeployMEVResistantDEX is Script {}
