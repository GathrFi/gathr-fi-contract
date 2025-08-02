// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title GathrFi Contract
 * @dev Smart contract for decentralized bill splitting with direct P2P settlement
 * @notice This contract manages groups, expenses, and direct peer-to-peer settlements.
 *
 * - 1st stage: Only instant peer-to-peer settlements.
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
        uint256 amountSettled;
        string description;
        mapping(address => uint256) splits;
        mapping(address => bool) hasSettled;
        bool fullySettled;
    }

    struct ExpenseInfo {
        uint256 expenseId;
        address payer;
        uint256 amount;
        uint256 amountSettled;
        string description;
        bool fullySettled;
    }

    struct InstantExpense {
        address payer;
        uint256 amount;
        uint256 amountSettled;
        string description;
        mapping(address => uint256) splits;
        mapping(address => bool) hasSettled;
        bool fullySettled;
        uint256 timestamp;
    }

    struct InstantExpenseInfo {
        uint256 expenseId;
        address payer;
        uint256 amount;
        uint256 amountSettled;
        string description;
        bool fullySettled;
        uint256 timestamp;
    }

    mapping(uint256 => Group) public groups;
    mapping(uint256 => mapping(uint256 => Expense)) public groupExpenses;
    mapping(uint256 => uint256) public groupExpenseCount;
    mapping(address => uint256[]) public userGroups;
    uint256 public groupCount;

    mapping(uint256 => InstantExpense) public instantExpenses;
    mapping(address => uint256[]) public userInstantExpenses;
    uint256 public instantExpenseCount;

    using SafeERC20 for IERC20;
    IERC20 public immutable usdcToken;

    event GroupCreated(
        uint256 indexed groupId,
        string name,
        address indexed admin,
        address[] members
    );

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

    event InstantExpenseAdded(
        uint256 indexed expenseId,
        address indexed payer,
        uint256 amount,
        string description,
        address[] splitMembers,
        uint256[] splitAmounts
    );
    event InstantExpenseSettled(
        uint256 indexed expenseId,
        address indexed member,
        uint256 amount
    );

    constructor(address _usdcToken) Ownable(msg.sender) {
        usdcToken = IERC20(_usdcToken);
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

        emit GroupCreated(groupCount, _name, msg.sender, members);
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
        Expense storage newExpense = groupExpenses[_groupId][expenseId];

        newExpense.payer = msg.sender;
        newExpense.amount = _amount;
        newExpense.amountSettled = 0;
        newExpense.description = _description;
        newExpense.fullySettled = false;

        uint256 totalSplit = 0;
        for (uint256 i = 0; i < _splitMembers.length; i++) {
            if (_splitMembers[i] == msg.sender) {
                newExpense.splits[_splitMembers[i]] = 0;
                newExpense.hasSettled[_splitMembers[i]] = true;
                newExpense.amountSettled += _splitAmounts[i];
            } else {
                newExpense.splits[_splitMembers[i]] = _splitAmounts[i];
                newExpense.hasSettled[_splitMembers[i]] = false;
            }

            totalSplit += _splitAmounts[i];
        }

        require(totalSplit == _amount, "Split amounts must be equal total");

        if (newExpense.amountSettled == _amount) {
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

    function addInstantExpense(
        uint256 _amount,
        string memory _description,
        address[] memory _splitMembers,
        uint256[] memory _splitAmounts
    ) external {
        require(
            _splitMembers.length == _splitAmounts.length,
            "Mismatched splits"
        );

        instantExpenseCount++;
        uint256 expenseId = instantExpenseCount;
        InstantExpense storage newExpense = instantExpenses[expenseId];

        newExpense.payer = msg.sender;
        newExpense.amount = _amount;
        newExpense.amountSettled = 0;
        newExpense.description = _description;
        newExpense.fullySettled = false;
        newExpense.timestamp = block.timestamp;

        uint256 totalSplit = 0;
        for (uint256 i = 0; i < _splitMembers.length; i++) {
            if (_splitMembers[i] == msg.sender) {
                newExpense.splits[_splitMembers[i]] = 0;
                newExpense.hasSettled[_splitMembers[i]] = true;
                newExpense.amountSettled += _splitAmounts[i];
            } else {
                newExpense.splits[_splitMembers[i]] = _splitAmounts[i];
                newExpense.hasSettled[_splitMembers[i]] = false;
                userInstantExpenses[_splitMembers[i]].push(expenseId);
            }

            totalSplit += _splitAmounts[i];
        }

        require(totalSplit == _amount, "Split amounts must equal total");

        userInstantExpenses[msg.sender].push(expenseId);

        if (newExpense.amountSettled == _amount) {
            newExpense.fullySettled = true;
        }

        emit InstantExpenseAdded(
            expenseId,
            msg.sender,
            _amount,
            _description,
            _splitMembers,
            _splitAmounts
        );
    }

    function settleExpense(uint256 _groupId, uint256 _expenseId) external {
        require(groups[_groupId].exists, "Group does not exist");

        Expense storage expense = groupExpenses[_groupId][_expenseId];
        require(!expense.fullySettled, "Expense already fully settled");
        require(!expense.hasSettled[msg.sender], "Member already settled");

        uint256 amountOwed = expense.splits[msg.sender];
        require(amountOwed > 0, "No amount owed by caller");

        require(
            usdcToken.transferFrom(msg.sender, expense.payer, amountOwed),
            "USDC transfer failed"
        );

        expense.splits[msg.sender] = 0;
        expense.hasSettled[msg.sender] = true;
        expense.amountSettled += amountOwed;

        if (expense.amountSettled == expense.amount) {
            expense.fullySettled = true;
        }

        emit ExpenseSettled(_groupId, _expenseId, msg.sender, amountOwed);
    }

    function settleInstantExpense(uint256 _expenseId) external {
        InstantExpense storage expense = instantExpenses[_expenseId];
        require(expense.payer != address(0), "Expense does not exist");
        require(!expense.fullySettled, "Expense already fully settled");
        require(!expense.hasSettled[msg.sender], "Member already settled");

        uint256 amountOwed = expense.splits[msg.sender];
        require(amountOwed > 0, "No amount owed by caller");

        require(
            usdcToken.transferFrom(msg.sender, expense.payer, amountOwed),
            "USDC transfer failed"
        );

        expense.splits[msg.sender] = 0;
        expense.hasSettled[msg.sender] = true;
        expense.amountSettled += amountOwed;

        if (expense.amountSettled == expense.amount) {
            expense.fullySettled = true;
        }

        emit InstantExpenseSettled(_expenseId, msg.sender, amountOwed);
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

        Expense storage expense = groupExpenses[_groupId][_expenseId];
        return (
            expense.payer,
            expense.amount,
            expense.amountSettled,
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
        return groupExpenses[_groupId][_expenseId].splits[_member];
    }

    function hasSettled(
        uint256 _groupId,
        uint256 _expenseId,
        address _member
    ) external view returns (bool) {
        require(groups[_groupId].exists, "Group does not exist");
        return groupExpenses[_groupId][_expenseId].hasSettled[_member];
    }

    function getInstantExpense(
        uint256 _expenseId
    )
        external
        view
        returns (
            address payer,
            uint256 amount,
            uint256 settledAmount,
            string memory description,
            bool fullySettled,
            uint256 timestamp
        )
    {
        InstantExpense storage expense = instantExpenses[_expenseId];
        require(expense.payer != address(0), "Expense does not exist");

        return (
            expense.payer,
            expense.amount,
            expense.amountSettled,
            expense.description,
            expense.fullySettled,
            expense.timestamp
        );
    }

    function getInstantAmountOwed(
        uint256 _expenseId,
        address _member
    ) external view returns (uint256) {
        require(
            instantExpenses[_expenseId].payer != address(0),
            "Expense does not exist"
        );

        return instantExpenses[_expenseId].splits[_member];
    }

    function hasSettledInstant(
        uint256 _expenseId,
        address _member
    ) external view returns (bool) {
        require(
            instantExpenses[_expenseId].payer != address(0),
            "Expense does not exist"
        );

        return instantExpenses[_expenseId].hasSettled[_member];
    }
}
