// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {MockAavePool} from "../src/MockAavePool.sol";
import {GathrFi} from "../src/GathrFi.sol";

contract GathrFiTest is Test {
    MockUSDC mockUSDCToken;
    MockAavePool mockAavePool;
    GathrFi gathrFi;

    address owner = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address user3 = address(0x4);

    uint256 constant INITIAL_USDC = 1000000 * 10 ** 6; // 1M USDC
    uint256 constant DEPOSIT_AMOUNT = 1000 * 10 ** 6; // 1000 USDC
    uint256 constant EXPENSE_AMOUNT = 300 * 10 ** 6; // 300 USDC

    function setUp() public {
        // Deploy mocked contracts
        mockUSDCToken = new MockUSDC();
        mockAavePool = new MockAavePool(address(mockUSDCToken));

        // Deploy GathrFi contract
        vm.startPrank(owner);
        gathrFi = new GathrFi(address(mockUSDCToken), address(mockAavePool));
        vm.stopPrank();

        // Mint USDC to test users
        mockUSDCToken.mint(user1, INITIAL_USDC);
        mockUSDCToken.mint(user2, INITIAL_USDC);
        mockUSDCToken.mint(user3, INITIAL_USDC);

        // Approve GathrFi contract to spend USDC
        vm.prank(user1);
        mockUSDCToken.approve(address(gathrFi), type(uint256).max);
        vm.prank(user2);
        mockUSDCToken.approve(address(gathrFi), type(uint256).max);
        vm.prank(user3);
        mockUSDCToken.approve(address(gathrFi), type(uint256).max);
    }

    function test_CreateGroup() public {
        address[] memory groupMembers = new address[](2);
        groupMembers[0] = user2;
        groupMembers[1] = user3;

        vm.prank(user1);
        gathrFi.createGroup("Test Group", groupMembers);

        (string memory name, address[] memory members) = gathrFi.getGroup(1);

        assertEq(name, "Test Group");
        assertEq(members.length, 3); // Includes admin
        assertEq(members[0], user1); // Admin
        assertEq(members[1], user2);
        assertEq(members[2], user3);
        assertEq(gathrFi.groupCount(), 1);
    }

    function test_DepositFunds() public {
        uint256 initialBalance = mockUSDCToken.balanceOf(user1);

        vm.prank(user1);
        gathrFi.depositFunds(DEPOSIT_AMOUNT);

        assertEq(gathrFi.userBalances(user1), DEPOSIT_AMOUNT);
        assertEq(
            mockUSDCToken.balanceOf(user1),
            initialBalance - DEPOSIT_AMOUNT
        );
        assertEq(mockUSDCToken.balanceOf(address(gathrFi)), 0);
        assertEq(
            mockUSDCToken.balanceOf(address(mockAavePool)),
            DEPOSIT_AMOUNT
        );
    }

    function test_RevertWhen_DepositFunds_ZeroAmount() public {
        vm.expectRevert();
        vm.prank(user1);
        gathrFi.depositFunds(0);
    }

    function test_AddExpense() public {
        // Create group
        address[] memory groupMembers = new address[](2);
        groupMembers[0] = user2;
        groupMembers[1] = user3;

        vm.prank(user1);
        gathrFi.createGroup("Test Group", groupMembers);

        // Add expense to group
        address[] memory splitMembers = new address[](3);
        splitMembers[0] = user1;
        splitMembers[1] = user2;
        splitMembers[2] = user3;
        uint256[] memory splitAmounts = new uint256[](3);
        splitAmounts[0] = EXPENSE_AMOUNT / 3;
        splitAmounts[1] = EXPENSE_AMOUNT / 3;
        splitAmounts[2] = EXPENSE_AMOUNT / 3;

        vm.prank(user1);
        gathrFi.addExpense(
            1,
            EXPENSE_AMOUNT,
            "Dinner",
            splitMembers,
            splitAmounts
        );

        (
            address payer,
            uint256 amount,
            uint256 amountSettled,
            string memory description,
            bool fullySettled
        ) = gathrFi.getExpense(1, 1);

        assertEq(payer, user1);
        assertEq(amount, EXPENSE_AMOUNT);
        assertEq(amountSettled, EXPENSE_AMOUNT / 3);
        assertEq(description, "Dinner");
        assertEq(fullySettled, false);
        assertEq(gathrFi.hasSettled(1, 1, user1), true);
        assertEq(gathrFi.getAmountOwed(1, 1, user1), 0);
        assertEq(gathrFi.getAmountOwed(1, 1, user2), EXPENSE_AMOUNT / 3);
        assertEq(gathrFi.getAmountOwed(1, 1, user3), EXPENSE_AMOUNT / 3);
    }

    function test_RevertWhen_AddExpense_InvalidGroup() public {
        // Add expense to group
        address[] memory splitMembers = new address[](3);
        splitMembers[0] = user1;
        splitMembers[1] = user2;
        splitMembers[2] = user3;
        uint256[] memory splitAmounts = new uint256[](3);
        splitAmounts[0] = EXPENSE_AMOUNT / 3;
        splitAmounts[1] = EXPENSE_AMOUNT / 3;
        splitAmounts[2] = EXPENSE_AMOUNT / 3;

        vm.expectRevert();
        vm.prank(user1);
        gathrFi.addExpense(
            1,
            EXPENSE_AMOUNT,
            "Dinner",
            splitMembers,
            splitAmounts
        );
    }

    function test_RevertWhen_AddExpense_MismatchedSplits() public {
        // Create group
        address[] memory groupMembers = new address[](3);
        groupMembers[0] = user2;
        groupMembers[1] = user3;

        vm.prank(user1);
        gathrFi.createGroup("Test Group", groupMembers);

        // Add expense to group
        address[] memory splitMembers = new address[](3);
        splitMembers[0] = user1;
        splitMembers[1] = user2;
        splitMembers[2] = user3;
        uint256[] memory splitAmounts = new uint256[](2);
        splitAmounts[0] = EXPENSE_AMOUNT / 3;
        splitAmounts[1] = EXPENSE_AMOUNT / 3;

        vm.expectRevert();
        vm.prank(user1);
        gathrFi.addExpense(
            1,
            EXPENSE_AMOUNT,
            "Dinner",
            splitMembers,
            splitAmounts
        );
    }

    function test_SettleExpense() public {
        // Create group and add expense to group
        address[] memory groupMembers = new address[](3);
        groupMembers[0] = user2;
        groupMembers[1] = user3;

        vm.prank(user1);
        gathrFi.createGroup("Test Group", groupMembers);

        address[] memory splitMembers = new address[](3);
        splitMembers[0] = user1;
        splitMembers[1] = user2;
        splitMembers[2] = user3;
        uint256[] memory splitAmounts = new uint256[](3);
        splitAmounts[0] = EXPENSE_AMOUNT / 3;
        splitAmounts[1] = EXPENSE_AMOUNT / 3;
        splitAmounts[2] = EXPENSE_AMOUNT / 3;

        vm.prank(user1);
        gathrFi.addExpense(
            1,
            EXPENSE_AMOUNT,
            "Dinner",
            splitMembers,
            splitAmounts
        );

        // Deposit funds (user2)
        vm.prank(user2);
        gathrFi.depositFunds(DEPOSIT_AMOUNT);

        // Settle expense (user2)
        vm.prank(user2);
        gathrFi.settleExpense(1, 1);

        assertEq(gathrFi.getAmountOwed(1, 1, user2), 0);
        assertEq(gathrFi.hasSettled(1, 1, user2), true);
        assertEq(
            gathrFi.userBalances(user2),
            DEPOSIT_AMOUNT - (EXPENSE_AMOUNT / 3)
        );
        assertEq(gathrFi.userBalances(user1), EXPENSE_AMOUNT / 3);
    }

    function test_SettleExpense_InsufficientBalance() public {
        // Create group and add expense to group
        address[] memory groupMembers = new address[](3);
        groupMembers[0] = user2;
        groupMembers[1] = user3;

        vm.prank(user1);
        gathrFi.createGroup("Test Group", groupMembers);

        address[] memory splitMembers = new address[](3);
        splitMembers[0] = user1;
        splitMembers[1] = user2;
        splitMembers[2] = user3;
        uint256[] memory splitAmounts = new uint256[](3);
        splitAmounts[0] = EXPENSE_AMOUNT / 3;
        splitAmounts[1] = EXPENSE_AMOUNT / 3;
        splitAmounts[2] = EXPENSE_AMOUNT / 3;

        vm.prank(user1);
        gathrFi.addExpense(
            1,
            EXPENSE_AMOUNT,
            "Dinner",
            splitMembers,
            splitAmounts
        );

        // Settle expense (user2)
        vm.expectRevert();
        vm.prank(user2);
        gathrFi.settleExpense(1, 1);
    }

    function test_WithdrawFunds() public {
        // Deposit funds
        vm.prank(user1);
        gathrFi.depositFunds(DEPOSIT_AMOUNT);

        // Fast forward time to accrue yield
        vm.warp(block.timestamp + 7 days);

        uint256 expectedYield = mockAavePool.calculateYield(
            DEPOSIT_AMOUNT,
            block.timestamp - 7 days
        );

        uint256 balanceBefore = mockUSDCToken.balanceOf(user1);

        vm.prank(user1);
        gathrFi.withdrawFunds(DEPOSIT_AMOUNT);

        assertEq(gathrFi.userBalances(user1), 0);
        assertEq(
            mockUSDCToken.balanceOf(user1),
            balanceBefore + DEPOSIT_AMOUNT + expectedYield
        );
        assertEq(mockUSDCToken.balanceOf(address(mockAavePool)), 0);
    }

    function test_RevertWhen_WithdrawFunds_InsufficientBalance() public {
        vm.expectRevert();
        vm.prank(user1);
        gathrFi.withdrawFunds(DEPOSIT_AMOUNT);
    }
}
