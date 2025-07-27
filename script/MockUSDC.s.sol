// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

contract CounterScript is Script {
    MockUSDC public usdc;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        usdc = new MockUSDC();
        vm.stopBroadcast();
    }
}
