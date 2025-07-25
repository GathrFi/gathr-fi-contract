// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {GathrFi} from "../src/GathrFi.sol";

contract CounterScript is Script {
    GathrFi public gathrFi;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // gathrFi = new GathrFi();

        vm.stopBroadcast();
    }
}
