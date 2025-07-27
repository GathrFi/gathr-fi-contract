// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IAavePool.sol";

/**
 * @title GathrFi Contract
 * @dev Smart contract for decentralized bill splitting with DeFi yield earning
 * @notice This contract manages groups, expenses, settlements,
 * and earns yield via Aave Protocol.
 */
contract GathrFi is ReentrancyGuard, Ownable, Pausable {
    struct Group {
        string name;
        address[] members;
        bool exists;
    }

    struct Expense {
        address payer;
        uint256 amount;
        string description;
        mapping(address => uint256) splits;
        bool settled;
    }

    mapping(uint256 => Group) public groups;
    mapping(uint256 => mapping(uint256 => Expense)) public expenses;
    mapping(uint256 => uint256) public groupExpenseCount;
    mapping(address => uint256) public userBalances;
    uint256 public groupCount;

    using SafeERC20 for IERC20;
    IAavePool public immutable aavePool;
    IERC20 public immutable usdcToken;
    uint16 public constant REFERRAL_CODE = 0;

    event FundsDeposited(address indexed user, uint256 amount);
    event FundsWithdrawn(address indexed user, uint256 amount);
    event GroupCreated(uint256 indexed groupId, string name, address[] members);
    event ExpenseAdded(
        uint256 indexed groupId,
        uint256 indexed expenseId,
        address indexed payer,
        uint256 amount,
        string description
    );
    event ExpenseSettled(
        uint256 indexed groupId,
        uint256 indexed expenseId,
        address indexed member,
        uint256 amount
    );

    constructor(address _aavePool, address _usdcToken) Ownable(msg.sender) {
        aavePool = IAavePool(_aavePool);
        usdcToken = IERC20(_usdcToken);
    }

    function createGroup(
        string memory _name,
        address[] memory _members
    ) external {
        groupCount++;

        Group storage newGroup = groups[groupCount];
        newGroup.name = _name;
        newGroup.members = _members;
        newGroup.exists = true;

        emit GroupCreated(groupCount, _name, _members);
    }

    function addExpense(
        uint256 _groupId,
        uint256 _amount,
        string memory _description,
        address[] memory _splitMembers,
        uint256[] memory _splitAmounts
    ) external {
        require(groups[_groupId].exists, "Group does not exists");
        require(
            _splitMembers.length == _splitAmounts.length,
            "Mismatched splits"
        );

        groupExpenseCount[_groupId]++;
        uint256 expenseId = groupExpenseCount[_groupId];
        Expense storage newExpense = expenses[_groupId][expenseId];

        newExpense.payer = msg.sender;
        newExpense.amount = _amount;
        newExpense.description = _description;
        newExpense.settled = false;

        uint256 totalSplit = 0;
        for (uint256 i = 0; i < _splitMembers.length; i++) {
            newExpense.splits[_splitMembers[i]] = _splitAmounts[i];
            totalSplit += _splitAmounts[i];
        }

        require(totalSplit == _amount, "Split amounts must be equal total");

        emit ExpenseAdded(
            _groupId,
            expenseId,
            msg.sender,
            _amount,
            _description
        );
    }

    function depositFunds(uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than 0");
        require(
            usdcToken.transferFrom(msg.sender, address(this), _amount),
            "USDC transfer failed"
        );
        require(
            usdcToken.approve(address(aavePool), _amount),
            "USDC approval failed"
        );

        aavePool.supply(
            address(usdcToken),
            _amount,
            address(this),
            REFERRAL_CODE
        );

        userBalances[msg.sender] += _amount;
        emit FundsDeposited(msg.sender, _amount);
    }

    function settleExpense(uint256 _groupId, uint256 _expenseId) external {
        require(groups[_groupId].exists, "Group does not exists");

        Expense storage expense = expenses[_groupId][_expenseId];
        require(!expense.settled, "Expense already settled");

        uint256 amountOwed = expense.splits[msg.sender];
        require(amountOwed > 0, "No amount owed by caller");
        require(userBalances[msg.sender] >= amountOwed, "Insufficient balance");

        if (userBalances[msg.sender] > 0) {
            aavePool.withdraw(address(usdcToken), amountOwed, address(this));
        }

        userBalances[msg.sender] -= amountOwed;
        userBalances[expense.payer] += amountOwed;

        require(
            usdcToken.approve(address(aavePool), amountOwed),
            "USDC approval failed"
        );

        aavePool.supply(
            address(usdcToken),
            amountOwed,
            address(this),
            REFERRAL_CODE
        );

        expense.splits[msg.sender] = 0;

        bool allSettled = true;
        for (uint256 i = 0; i < groups[_groupId].members.length; i++) {
            if (expense.splits[groups[_groupId].members[i]] > 0) {
                allSettled = false;
                break;
            }
        }

        if (allSettled) {
            expense.settled = true;
        }

        emit ExpenseSettled(_groupId, _expenseId, msg.sender, amountOwed);
    }

    function withdrawFunds(uint256 _amount) external {
        require(userBalances[msg.sender] >= _amount, "Insufficient balance");

        uint256 amountWithYiled = aavePool.withdraw(
            address(usdcToken),
            _amount,
            address(this)
        );

        userBalances[msg.sender] -= _amount;

        require(
            usdcToken.transfer(msg.sender, amountWithYiled),
            "USDC transfer failed"
        );

        emit FundsWithdrawn(msg.sender, amountWithYiled);
    }

    function getGroup(
        uint256 _groupId
    ) external view returns (string memory name, address[] memory members) {
        require(groups[_groupId].exists, "Group does not exists");
        return (groups[_groupId].name, groups[_groupId].members);
    }

    function getExpense(
        uint256 _groupId,
        uint256 _expenseId
    )
        external
        view
        returns (
            address payer,
            uint256 amount,
            string memory description,
            bool settled
        )
    {
        require(groups[_groupId].exists, "Group does not exists");

        Expense storage expense = expenses[_groupId][_expenseId];
        return (
            expense.payer,
            expense.amount,
            expense.description,
            expense.settled
        );
    }

    function getAmountOwed(
        uint256 _groupId,
        uint256 _expenseId,
        address _member
    ) external view returns (uint256) {
        require(groups[_groupId].exists, "Group does not exists");
        return expenses[_groupId][_expenseId].splits[_member];
    }

    function getUserYield(address user) external view returns (uint256) {
        return aavePool.getUserYield(user);
    }
}
