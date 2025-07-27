// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {MockAavePool} from "../src/MockAavePool.sol";
import {GathrFi} from "../src/GathrFi.sol";

contract GathrFiScript is Script {
    MockUSDC public mockUSDCToken;
    MockAavePool public mockAavePool;
    GathrFi public gathrFi;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        mockUSDCToken = new MockUSDC();
        console.log("MockUSDC deployed at:", address(mockUSDCToken));

        mockAavePool = new MockAavePool(address(mockUSDCToken));
        console.log("MocMockAavePoolkUSDC deployed at:", address(mockAavePool));

        gathrFi = new GathrFi(address(mockUSDCToken), address(mockAavePool));
        console.log("GathrFi deployed at:", address(gathrFi));

        vm.stopBroadcast();
    }
}
