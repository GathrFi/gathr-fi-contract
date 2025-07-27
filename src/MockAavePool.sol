// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockUSDC} from "./MockUSDC.sol";

contract MockAavePool {
    IERC20 public token;
    MockUSDC public usdcToken;

    uint256 public constant APY = 5;
    uint256 public constant SECONDS_PER_YEAR = 365 * 24 * 60 * 60;

    struct Supply {
        uint256 amount;
        uint256 timestamp;
    }

    mapping(address => Supply[]) public supplies;

    constructor(address _token) {
        token = IERC20(_token);
        usdcToken = MockUSDC(_token);
    }

    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external {
        require(asset == address(token), "Invalid asset");
        token.transferFrom(msg.sender, address(this), amount);
        supplies[onBehalfOf].push(Supply(amount, block.timestamp));
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256) {
        require(asset == address(token), "Invalid asset");
        uint256 totalWithdrawn = 0;
        uint256 remaining = amount;

        uint256 i = 0;
        while (i < supplies[msg.sender].length) {
            Supply storage supp = supplies[msg.sender][i];
            if (supp.amount == 0) {
                i++;
                continue;
            }

            uint256 withdrawAmount = remaining >= supp.amount
                ? supp.amount
                : remaining;
            uint256 yield = calculateYield(supp.amount, supp.timestamp);
            usdcToken.mint(address(this), yield); // Simulate yiled-earnings
            totalWithdrawn += withdrawAmount + yield;
            supp.amount -= withdrawAmount;
            remaining -= withdrawAmount;

            if (supp.amount == 0) {
                if (i < supplies[msg.sender].length - 1) {
                    supplies[msg.sender][i] = supplies[msg.sender][
                        supplies[msg.sender].length - 1
                    ];
                }
                supplies[msg.sender].pop();
            } else {
                i++;
            }
        }

        require(totalWithdrawn >= amount, "Insufficient balance");
        token.transfer(to, totalWithdrawn);
        return totalWithdrawn;
    }

    function calculateYield(
        uint256 amount,
        uint256 startTime
    ) public view returns (uint256) {
        uint256 timeElapsed = block.timestamp - startTime;
        return (amount * APY * timeElapsed) / (100 * SECONDS_PER_YEAR);
    }

    function getUserYield(address user) external view returns (uint256) {
        uint256 totalYield = 0;
        for (uint256 i = 0; i < supplies[user].length; i++) {
            if (supplies[user][i].amount > 0) {
                totalYield += calculateYield(
                    supplies[user][i].amount,
                    supplies[user][i].timestamp
                );
            }
        }

        return totalYield;
    }
}
