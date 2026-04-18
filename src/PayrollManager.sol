// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IYieldRouter} from "./interfaces/IYieldRouter.sol";

/**
 * @title PayrollManager
 * @notice Employer-facing entry point for Flowroll.
 * @dev Manages employer registration, employee groups, and payroll cycle deposits.
 */
contract PayrollManager is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- STRUCTS ---

    struct EmployerProfile {
        bool isRegistered;
        uint256 groupCount;
        address employerAddress;
    }

    struct PayrollGroup {
        uint256 groupId;
        string name;
        uint256 totalPayroll;
        uint256 activeCycleId;
        uint256 cycleDuration;
        bool exists;
    }

    // --- ERRORS ---

    error PayrollManager__NotRegistered();
    error PayrollManager__AlreadyRegistered();
    error PayrollManager__ZeroAddress();
    error PayrollManager__ZeroSalary();
    error PayrollManager__ZeroDuration();
    error PayrollManager__GroupNotFound();
    error PayrollManager__GroupHasActiveCycle();
    error PayrollManager__NoActiveCycle();
    error PayrollManager__EmployeeAlreadyExists();
    error PayrollManager__EmployeeNotFound();
    error PayrollManager__InsufficientPayroll();
    error PayrollManager__CycleNotCancellable();
    error PayrollManager__InvalidFeeBps();
    error PayrollManager__RouterNotSet();
    error PayrollManager__InvalidFeeRecipient();
    error PayrollManager__EmptyArray();
    error PayrollManager__ArrayLengthMismatch();
    error PayrollManager__InsufficientPendingSalary();
    error PayrollManager__NotPayVault();

    // --- EVENTS ---

    event EmployerRegistered(address indexed employer);
    event GroupCreated(address indexed employer, uint256 indexed groupId, string name);
    event EmployeeAdded(address indexed employer, uint256 indexed groupId, address indexed employee, uint256 salary);
    event EmployeeRemoved(address indexed employer, uint256 indexed groupId, address indexed employee);
    event SalaryUpdated(address indexed employer, uint256 indexed groupId, address indexed employee, uint256 oldSalary, uint256 newSalary);
    event PayrollDeposited(address indexed employer, uint256 indexed groupId, uint256 indexed cycleId, uint256 amount, uint256 cycleDuration);
    event CycleCancelled(address indexed employer, uint256 indexed groupId, uint256 indexed cycleId, uint256 amountReturned);
    event FeeRecipientUpdated(address indexed previous, address indexed updated);
    event FeeBpsUpdated(uint256 previous, uint256 updated);
    event YieldRouterSet(address indexed router);
    event PayrollDispatcherSet(address indexed _dispatcher);
    event PayVaultSet(address indexed vault);
    event PayrollSetup(address indexed employer, uint256 indexed groupId, uint256 indexed cycleId);
    event TotalPendingSalaryRemoved(address indexed employee, uint256 indexed amount);

    // --- STATE VARIABLES ---

    uint256 public constant SCALE = 10_000;
    uint256 public constant MAX_FEE_BPS = 2_000;

    address public immutable USDC;
    address public yieldRouter;
    address public payrollDispatcher;
    address public feeRecipient;
    address public payVault;
    uint256 public feeBps;

    mapping(address => mapping(uint256 cycleId => uint256 groupId)) public cycleToGroup;
    mapping(address => EmployerProfile) private employers;
    mapping(address employer => mapping(uint256 groupId => PayrollGroup)) private groups;
    mapping(address employer => mapping(uint256 groupId => address[])) private groupEmployees;
    mapping(address employer => mapping(uint256 groupId => mapping(address employee => uint256 salary))) private groupSalaries;
    mapping(address employer => mapping(uint256 groupId => mapping(address employee => bool))) private isGroupEmployee;
    mapping(address employee => uint256 totalPendingSalary) private employeeTotalPendingSalary;

    // --- MODIFIERS ---

    modifier onlyRegistered() {
        _onlyRegistered();
        _;
    }

    modifier onlyPayVault() {
        _onlyPayVault();
        _;
    }

    modifier groupExists(uint256 groupId) {
        _groupExists(groupId);
        _;
    }

    modifier noActiveCycle(uint256 groupId) {
        _noActiveCycle(groupId);
        _;
    }

    // --- CONSTRUCTOR ---

    /**
     * @param _usdc USDC token address for this environment.
     * @param _feeRecipient Address that receives yield fees.
     * @param _feeBps Fee in basis points taken from yield earned.
     */
    constructor(
        address _usdc,
        address _feeRecipient,
        uint256 _feeBps
    ) Ownable(msg.sender) {
        if (_usdc == address(0) || _feeRecipient == address(0)) revert PayrollManager__ZeroAddress();
        if (_feeBps > MAX_FEE_BPS) revert PayrollManager__InvalidFeeBps();

        USDC = _usdc;
        feeRecipient = _feeRecipient;
        feeBps = _feeBps;
    }

    // --- EXTERNAL ---

    function setYieldRouter(address _router) external onlyOwner {
        if (_router == address(0)) revert PayrollManager__ZeroAddress();
        yieldRouter = _router;
        emit YieldRouterSet(_router);
    }

    function setPayrollDispatcher(address _dispatcher) external onlyOwner {
        if (_dispatcher == address(0)) revert PayrollManager__ZeroAddress();
        payrollDispatcher = _dispatcher;
        emit PayrollDispatcherSet(_dispatcher);
    }
    
    function setPayVault(address _payVault) external onlyOwner {
        if (_payVault == address(0)) revert PayrollManager__ZeroAddress();
        payVault = _payVault;
        emit PayVaultSet(_payVault);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) revert PayrollManager__ZeroAddress();
        emit FeeRecipientUpdated(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    function setFeeBps(uint256 _feeBps) external onlyOwner {
        if (_feeBps > MAX_FEE_BPS) revert PayrollManager__InvalidFeeBps();
        emit FeeBpsUpdated(feeBps, _feeBps);
        feeBps = _feeBps;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Register as an employer on Flowroll.
     */
    function registerEmployer() external whenNotPaused {
        if (employers[msg.sender].isRegistered) revert PayrollManager__AlreadyRegistered();

        employers[msg.sender] = EmployerProfile({
            isRegistered: true,
            groupCount: 0,
            employerAddress: msg.sender
        });

        emit EmployerRegistered(msg.sender);
    }

    /**
     * @notice Create a new payroll group.
     * @param name Human-readable group name.
     * @param cycleDuration Lock duration for the payroll cycle.
     * @return groupId The newly created group's ID.
     */
    function createGroup(
        string calldata name,
        uint256 cycleDuration
    ) external whenNotPaused returns (uint256 groupId) {
        groupId = _createGroup(name, cycleDuration);
    }

    /**
     * @notice Add a single employee to a payroll group.
     */
    function addEmployee(
        uint256 groupId,
        address employee,
        uint256 salary
    )
        external
        onlyRegistered
        groupExists(groupId)
        noActiveCycle(groupId)
        whenNotPaused
    {
        if (employee == address(0)) revert PayrollManager__ZeroAddress();
        if (salary == 0) revert PayrollManager__ZeroSalary();
        if (isGroupEmployee[msg.sender][groupId][employee]) revert PayrollManager__EmployeeAlreadyExists();

        isGroupEmployee[msg.sender][groupId][employee] = true;
        groupEmployees[msg.sender][groupId].push(employee);
        groupSalaries[msg.sender][groupId][employee] = salary;
        groups[msg.sender][groupId].totalPayroll += salary;

        emit EmployeeAdded(msg.sender, groupId, employee, salary);
    }

    /**
     * @notice Add multiple employees to a payroll group in one transaction.
     */
    function addEmployees(
        uint256 groupId,
        address[] calldata employees,
        uint256[] calldata salaries
    )
        external
        onlyRegistered
        groupExists(groupId)
        noActiveCycle(groupId)
        whenNotPaused
    {
        if (employees.length != salaries.length) revert PayrollManager__ArrayLengthMismatch();
        if (employees.length == 0) revert PayrollManager__EmptyArray();

        _addEmployees(groupId, employees, salaries);
    }

    /**
     * @notice Remove an employee from a payroll group.
     */
    function removeEmployee(
        uint256 groupId,
        address employee
    )
        external
        onlyRegistered
        groupExists(groupId)
        noActiveCycle(groupId)
        whenNotPaused
    {
        if (!isGroupEmployee[msg.sender][groupId][employee]) revert PayrollManager__EmployeeNotFound();

        uint256 salary = groupSalaries[msg.sender][groupId][employee];

        groups[msg.sender][groupId].totalPayroll -= salary;
        groupSalaries[msg.sender][groupId][employee] = 0;
        isGroupEmployee[msg.sender][groupId][employee] = false;

        address[] storage employees = groupEmployees[msg.sender][groupId];
        uint256 len = employees.length;
        for (uint256 i = 0; i < len; i++) {
            if (employees[i] == employee) {
                employees[i] = employees[len - 1];
                employees.pop();
                break;
            }
        }

        emit EmployeeRemoved(msg.sender, groupId, employee);
    }

    /**
     * @notice Remove multiple employees from a payroll group in one transaction.
     */
    function removeEmployees(
        uint256 groupId,
        address[] calldata employees
    )
        external
        onlyRegistered
        groupExists(groupId)
        noActiveCycle(groupId)
        whenNotPaused
    {
        if (employees.length == 0) revert PayrollManager__EmptyArray();

        address[] storage groupEmps = groupEmployees[msg.sender][groupId];

        for (uint256 i = 0; i < employees.length; i++) {
            address employee = employees[i];

            if (!isGroupEmployee[msg.sender][groupId][employee]) revert PayrollManager__EmployeeNotFound();

            uint256 salary = groupSalaries[msg.sender][groupId][employee];

            groups[msg.sender][groupId].totalPayroll -= salary;
            groupSalaries[msg.sender][groupId][employee] = 0;
            isGroupEmployee[msg.sender][groupId][employee] = false;

            uint256 len = groupEmps.length;
            for (uint256 j = 0; j < len; j++) {
                if (groupEmps[j] == employee) {
                    groupEmps[j] = groupEmps[len - 1];
                    groupEmps.pop();
                    len--;
                    break;
                }
            }

            emit EmployeeRemoved(msg.sender, groupId, employee);
        }
    }

    /**
     * @notice Update a single employee's salary.
     */
    function updateSalary(
        uint256 groupId,
        address employee,
        uint256 newSalary
    )
        external
        onlyRegistered
        groupExists(groupId)
        noActiveCycle(groupId)
        whenNotPaused
    {
        if (!isGroupEmployee[msg.sender][groupId][employee]) revert PayrollManager__EmployeeNotFound();
        if (newSalary == 0) revert PayrollManager__ZeroSalary();

        uint256 oldSalary = groupSalaries[msg.sender][groupId][employee];

        groupSalaries[msg.sender][groupId][employee] = newSalary;
        groups[msg.sender][groupId].totalPayroll -= oldSalary;
        groups[msg.sender][groupId].totalPayroll += newSalary;

        emit SalaryUpdated(msg.sender, groupId, employee, oldSalary, newSalary);
    }

    /**
     * @notice Update salaries for multiple employees in one transaction.
     */
    function updateSalaries(
        uint256 groupId,
        address[] calldata employees,
        uint256[] calldata newSalaries
    )
        external
        onlyRegistered
        groupExists(groupId)
        noActiveCycle(groupId)
        whenNotPaused
    {
        if (employees.length != newSalaries.length) revert PayrollManager__ArrayLengthMismatch();
        if (employees.length == 0) revert PayrollManager__EmptyArray();

        for (uint256 i = 0; i < employees.length; i++) {
            address employee = employees[i];
            uint256 newSalary = newSalaries[i];

            if (!isGroupEmployee[msg.sender][groupId][employee]) revert PayrollManager__EmployeeNotFound();
            if (newSalary == 0) revert PayrollManager__ZeroSalary();

            uint256 oldSalary = groupSalaries[msg.sender][groupId][employee];

            groupSalaries[msg.sender][groupId][employee] = newSalary;
            groups[msg.sender][groupId].totalPayroll -= oldSalary;
            groups[msg.sender][groupId].totalPayroll += newSalary;

            emit SalaryUpdated(msg.sender, groupId, employee, oldSalary, newSalary);
        }
    }

    /**
     * @notice Fund a payroll cycle for a group and start yield farming.
     */
    function depositPayroll(
        uint256 groupId
    )
        external
        onlyRegistered
        groupExists(groupId)
        noActiveCycle(groupId)
        whenNotPaused
        nonReentrant
    {
        _depositPayroll(groupId);
    }

    /**
     * @notice One-shot setup: create group, add employees, and start cycle.
     */
    function setUpPayroll(
        uint256 groupId,
        address[] calldata employees,
        uint256[] calldata salaries
    )
        external
        whenNotPaused
        nonReentrant
        returns (uint256 cycleId)
    {
        if (yieldRouter == address(0)) revert PayrollManager__RouterNotSet();
        if (employees.length == 0) revert PayrollManager__EmptyArray();
        if (employees.length != salaries.length) revert PayrollManager__ArrayLengthMismatch();

        _addEmployees(groupId, employees, salaries);
        _depositPayroll(groupId);

        emit PayrollSetup(msg.sender, groupId, groups[msg.sender][groupId].activeCycleId);

        return groups[msg.sender][groupId].activeCycleId;
    }

    /**
     * @notice Cancel an active cycle and recover funds before deployment.
     */
    function cancelCycle(
        uint256 groupId
    ) external onlyRegistered groupExists(groupId) whenNotPaused nonReentrant {
        if (!_isGroupActive(msg.sender, groupId)) revert PayrollManager__NoActiveCycle();

        uint256 cycleId = groups[msg.sender][groupId].activeCycleId;
        uint256 amountReturned = IYieldRouter(yieldRouter).cancelCycle(msg.sender, cycleId);

        groups[msg.sender][groupId].activeCycleId = 0;
        IERC20(USDC).safeTransfer(msg.sender, amountReturned);

        emit CycleCancelled(msg.sender, groupId, cycleId, amountReturned);
    }

    /**
     * @notice Adjusts the internal tracking of an employee's pending salary.
     * @dev Called by the credit module (via PayVault) when an advance is settled.
     */
    function removeFromTotalPendingSalary(address employee, uint256 amount) external onlyPayVault {
        if (employeeTotalPendingSalary[employee] < amount) revert PayrollManager__InsufficientPendingSalary();

        employeeTotalPendingSalary[employee] -= amount;

        emit TotalPendingSalaryRemoved(employee, amount);
    }

    // --- EXTERNAL VIEW ---

    function getEmployer(address employer) external view returns (EmployerProfile memory) {
        return employers[employer];
    }

    function getGroup(address employer, uint256 groupId) external view returns (PayrollGroup memory) {
        if (!groups[employer][groupId].exists) revert PayrollManager__GroupNotFound();
        return groups[employer][groupId];
    }

    function getGroupEmployees(address employer, uint256 groupId) external view returns (address[] memory) {
        if (!groups[employer][groupId].exists) revert PayrollManager__GroupNotFound();
        return groupEmployees[employer][groupId];
    }

    function getSalary(address employer, uint256 groupId, address employee) external view returns (uint256) {
        return groupSalaries[employer][groupId][employee];
    }

    function getEmployeeTotalPendingSalary(address employee) external view returns (uint256) {
        return employeeTotalPendingSalary[employee];
    }

    function getTotalPayroll(address employer, uint256 groupId) external view returns (uint256) {
        if (!groups[employer][groupId].exists) revert PayrollManager__GroupNotFound();
        return groups[employer][groupId].totalPayroll;
    }

    function isRegistered(address employer) external view returns (bool) {
        return employers[employer].isRegistered;
    }

    function hasActiveGroup(address employer, uint256 groupId) external view returns (bool) {
        if (!groups[employer][groupId].exists) return false;
        uint256 cycleId = groups[employer][groupId].activeCycleId;
        if (cycleId == 0) return false;
        
        return IYieldRouter(yieldRouter).getCycle(employer, cycleId).isActive;
    }

    // --- INTERNAL ---

    function _isGroupActive(address employer, uint256 groupId) internal returns (bool) {
        uint256 cycleId = groups[employer][groupId].activeCycleId;
        if (cycleId == 0) return false;

        bool stillActive = IYieldRouter(yieldRouter).getCycle(employer, cycleId).isActive;

        if (!stillActive) {
            groups[employer][groupId].activeCycleId = 0;
        }

        return stillActive;
    }

    function _createGroup(string calldata name, uint256 cycleDuration) internal returns (uint256 groupId) {
        if (!employers[msg.sender].isRegistered) {
            employers[msg.sender] = EmployerProfile({
                isRegistered: true,
                groupCount: 0,
                employerAddress: msg.sender
            });
            emit EmployerRegistered(msg.sender);
        }

        groupId = ++employers[msg.sender].groupCount;

        groups[msg.sender][groupId] = PayrollGroup({
            groupId: groupId,
            name: name,
            totalPayroll: 0,
            activeCycleId: 0,
            cycleDuration: cycleDuration,
            exists: true
        });

        emit GroupCreated(msg.sender, groupId, name);
    }

    function _addEmployees(
        uint256 groupId,
        address[] calldata employees,
        uint256[] calldata salaries
    ) internal {
        for (uint256 i = 0; i < employees.length; i++) {
            address employee = employees[i];
            uint256 salary = salaries[i];

            if (employee == address(0)) revert PayrollManager__ZeroAddress();
            if (salary == 0) revert PayrollManager__ZeroSalary();
            if (isGroupEmployee[msg.sender][groupId][employee]) revert PayrollManager__EmployeeAlreadyExists();

            isGroupEmployee[msg.sender][groupId][employee] = true;
            groupEmployees[msg.sender][groupId].push(employee);
            groupSalaries[msg.sender][groupId][employee] = salary;
            groups[msg.sender][groupId].totalPayroll += salary;
            employeeTotalPendingSalary[employee] += salary;

            emit EmployeeAdded(msg.sender, groupId, employee, salary);
        }
    }

    function _depositPayroll(uint256 groupId) internal {
        if (yieldRouter == address(0)) revert PayrollManager__RouterNotSet();

        uint256 cycleDuration = groups[msg.sender][groupId].cycleDuration;
        if (cycleDuration == 0) revert PayrollManager__ZeroDuration();

        uint256 totalPayroll = groups[msg.sender][groupId].totalPayroll;
        if (totalPayroll == 0) revert PayrollManager__InsufficientPayroll();

        IERC20(USDC).safeTransferFrom(msg.sender, address(this), totalPayroll);
        IERC20(USDC).approve(yieldRouter, totalPayroll);

        uint256 cycleId = IYieldRouter(yieldRouter).startCycle(
            msg.sender,
            totalPayroll,
            cycleDuration,
            payrollDispatcher
        );

        groups[msg.sender][groupId].activeCycleId = cycleId;
        cycleToGroup[msg.sender][cycleId] = groupId;

        emit PayrollDeposited(msg.sender, groupId, cycleId, totalPayroll, cycleDuration);
    }

    function _noActiveCycle(uint256 groupId) internal {
        if (_isGroupActive(msg.sender, groupId)) revert PayrollManager__GroupHasActiveCycle();
    }

    // --- INTERNAL VIEW ---

    function _onlyRegistered() internal view {
        if (!employers[msg.sender].isRegistered) revert PayrollManager__NotRegistered();
    }

    function _onlyPayVault() internal view {
        if (msg.sender != payVault) revert PayrollManager__NotPayVault();
    }

    function _groupExists(uint256 groupId) internal view {
        if (!groups[msg.sender][groupId].exists) revert PayrollManager__GroupNotFound();
    }
}