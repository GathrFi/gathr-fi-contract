// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// Aave V3 interfaces - Official implementation
// https://aave.com/docs/developers/smart-contracts/pool

interface IAavePool {
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);
}
