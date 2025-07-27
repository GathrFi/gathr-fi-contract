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
        address admin;
        address[] members;
        bool exists;
    }

    struct Expense {
        address payer;
        uint256 amount;
        uint256 settledAmount;
        string description;
        mapping(address => uint256) splits;
        mapping(address => bool) hasSettled;
        bool fullySettled;
    }

    struct ExpenseInfo {
        uint256 expenseId;
        address payer;
        uint256 amount;
        uint256 settledAmount;
        string description;
        bool fullySettled;
    }

    mapping(uint256 => Group) public groups;
    mapping(uint256 => mapping(uint256 => Expense)) public expenses;
    mapping(uint256 => uint256) public groupExpenseCount;
    mapping(address => uint256) public userBalances;
    mapping(address => uint256[]) public userGroups;
    uint256 public groupCount;

    using SafeERC20 for IERC20;
    IERC20 public immutable usdcToken;
    IAavePool public immutable aavePool;

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
    event ExpenseSplit(
        uint256 indexed groupId,
        uint256 indexed expenseId,
        address[] splitMembers,
        uint256[] splitAmounts
    );
    event ExpenseSettled(
        uint256 indexed groupId,
        uint256 indexed expenseId,
        address indexed member,
        uint256 amount
    );

    constructor(address _usdcToken, address _aavePool) Ownable(msg.sender) {
        usdcToken = IERC20(_usdcToken);
        aavePool = IAavePool(_aavePool);
    }

    function createGroup(
        string memory _name,
        address[] memory _members
    ) external {
        groupCount++;

        Group storage newGroup = groups[groupCount];
        newGroup.name = _name;
        newGroup.admin = msg.sender;
        newGroup.exists = true;

        address[] memory members = new address[](_members.length + 1);
        members[0] = msg.sender;
        for (uint256 i = 0; i < _members.length; i++) {
            members[i + 1] = _members[i];
        }

        newGroup.members = members;
        userGroups[msg.sender].push(groupCount);
        for (uint256 i = 0; i < _members.length; i++) {
            userGroups[_members[i]].push(groupCount);
        }

        emit GroupCreated(groupCount, _name, members);
    }

    function addExpense(
        uint256 _groupId,
        uint256 _amount,
        string memory _description,
        address[] memory _splitMembers,
        uint256[] memory _splitAmounts
    ) external {
        require(groups[_groupId].exists, "Group does not exist");
        require(
            _splitMembers.length == _splitAmounts.length,
            "Mismatched splits"
        );

        groupExpenseCount[_groupId]++;
        uint256 expenseId = groupExpenseCount[_groupId];
        Expense storage newExpense = expenses[_groupId][expenseId];

        newExpense.payer = msg.sender;
        newExpense.amount = _amount;
        newExpense.settledAmount = 0;
        newExpense.description = _description;
        newExpense.fullySettled = false;

        uint256 totalSplit = 0;
        for (uint256 i = 0; i < _splitMembers.length; i++) {
            if (_splitMembers[i] == msg.sender) {
                newExpense.splits[_splitMembers[i]] = 0;
                newExpense.hasSettled[_splitMembers[i]] = true;
                newExpense.settledAmount += _splitAmounts[i];
            } else {
                newExpense.splits[_splitMembers[i]] = _splitAmounts[i];
                newExpense.hasSettled[_splitMembers[i]] = false;
            }

            totalSplit += _splitAmounts[i];
        }

        require(totalSplit == _amount, "Split amounts must be equal total");

        if (newExpense.settledAmount == _amount) {
            newExpense.fullySettled = true;
        }

        emit ExpenseAdded(
            _groupId,
            expenseId,
            msg.sender,
            _amount,
            _description
        );

        emit ExpenseSplit(_groupId, expenseId, _splitMembers, _splitAmounts);
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

        aavePool.supply(address(usdcToken), _amount, address(this));
        userBalances[msg.sender] += _amount;

        emit FundsDeposited(msg.sender, _amount);
    }

    function settleExpense(uint256 _groupId, uint256 _expenseId) external {
        require(groups[_groupId].exists, "Group does not exist");

        Expense storage expense = expenses[_groupId][_expenseId];
        require(!expense.fullySettled, "Expense already fully settled");
        require(!expense.hasSettled[msg.sender], "Member already settled");

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

        aavePool.supply(address(usdcToken), amountOwed, address(this));
        expense.splits[msg.sender] = 0;
        expense.hasSettled[msg.sender] = true;
        expense.settledAmount += amountOwed;

        if (expense.settledAmount == expense.amount) {
            expense.fullySettled = true;
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
        require(groups[_groupId].exists, "Group does not exist");
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
            uint256 settledAmount,
            string memory description,
            bool fullySettled
        )
    {
        require(groups[_groupId].exists, "Group does not exist");

        Expense storage expense = expenses[_groupId][_expenseId];
        return (
            expense.payer,
            expense.amount,
            expense.settledAmount,
            expense.description,
            expense.fullySettled
        );
    }

    function getAmountOwed(
        uint256 _groupId,
        uint256 _expenseId,
        address _member
    ) external view returns (uint256) {
        require(groups[_groupId].exists, "Group does not exist");
        return expenses[_groupId][_expenseId].splits[_member];
    }

    function hasSettled(
        uint256 _groupId,
        uint256 _expenseId,
        address _member
    ) external view returns (bool) {
        require(groups[_groupId].exists, "Group does not exist");
        return expenses[_groupId][_expenseId].hasSettled[_member];
    }

    function getUserYield(address _user) external view returns (uint256) {
        return aavePool.getUserYield(_user);
    }

    /**
     * @dev Calling this function will requires high gas fees.
     * This function is keep as the on-chain fallback options besides indexer.
     */
    function getUserGroups(
        address _user
    ) external view returns (Group[] memory items) {
        uint256[] memory groupIds = userGroups[_user];

        items = new Group[](groupIds.length);
        for (uint256 i = 0; i < groupIds.length; i++) {
            Group storage group = groups[groupIds[i]];
            items[i] = Group({
                name: group.name,
                admin: group.admin,
                members: group.members,
                exists: group.exists
            });
        }

        return items;
    }

    /**
     * @dev Calling this function will requires high gas fees.
     * This function is keep as the on-chain fallback options besides indexer.
     */
    function getGroupExpenses(
        uint256 _groupId,
        uint256 _startIndex,
        uint256 _maxCount
    ) external view returns (ExpenseInfo[] memory items) {
        require(groups[_groupId].exists, "Group does not exist");

        uint256 expenseCount = groupExpenseCount[_groupId];
        require(_startIndex <= expenseCount, "Invalid start index");

        uint256 endIndex = _startIndex + _maxCount;
        if (endIndex > expenseCount) {
            endIndex = expenseCount;
        }

        uint256 returnCount = endIndex >= _startIndex
            ? endIndex - _startIndex
            : 0;

        items = new ExpenseInfo[](returnCount);
        for (uint256 i = 0; i < returnCount; i++) {
            uint256 expenseId = _startIndex + i;
            Expense storage expense = expenses[_groupId][expenseId];
            items[i] = ExpenseInfo({
                expenseId: expenseId,
                payer: expense.payer,
                amount: expense.amount,
                settledAmount: expense.settledAmount,
                description: expense.description,
                fullySettled: expense.fullySettled
            });
        }

        return items;
    }
}
