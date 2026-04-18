// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IYieldRouter} from "./interfaces/IYieldRouter.sol";

/**
 * @title PayrollManager
 * @notice Employer-facing entry point for Flowroll.
 */

contract PayrollManager is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ---- Structs --------------------------------------------------------------------------------─

    struct EmployerProfile {
        bool isRegistered;
        uint256 groupCount;
        address employerAddress;
    }


    struct PayrollGroup {
        uint256 groupId;
        string name;
        uint256 totalPayroll;
        uint256 activeCycleId; // 0 = no active cycle, >0 = cycleId in YieldRouter
        uint256 cycleDuration;
        bool exists;
    }

    // ---- Custom Errors ------------------------------------------------------------------------─

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

    // ---- Constants ----------------------------------------------------------------------------──

    uint256 public constant SCALE = 10_000;
    uint256 public constant MAX_FEE_BPS = 2_000; // 20% max fee — protect employers

    // ---- State ------------------------------------------------------------------------------------

    address public immutable usdc;
    address public yieldRouter;
    address public payrollDispatcher;
    address public feeRecipient;
    address public payVault;
    uint256 public feeBps;

    mapping(address => mapping(uint256 cycleId => uint256 groupId))
        public cycleToGroup;
    mapping(address => EmployerProfile) private employers;
    mapping(address employer => mapping(uint256 groupId => PayrollGroup)) private groups;
    mapping(address employer => mapping(uint256 groupId => address[])) private groupEmployees;
    mapping(address employer => mapping(uint256 groupId => mapping(address employee => uint256 salary)))
        private groupSalaries;
    mapping(address employer => mapping(uint256 groupId => mapping(address employee => bool)))
        private isGroupEmployee;
    // mapping(address employee => uint256[] employeeGroup) private employeeGroups;
    mapping(address employee => uint256 totalPendingSalary) private employeeTotalPendingSalary;

    // ---- Events --------------------------------------------------------------------------------──

    event EmployerRegistered(address indexed employer);
    event GroupCreated(
        address indexed employer,
        uint256 indexed groupId,
        string name
    );
    event EmployeeAdded(
        address indexed employer,
        uint256 indexed groupId,
        address indexed employee,
        uint256 salary
    );
    event EmployeeRemoved(
        address indexed employer,
        uint256 indexed groupId,
        address indexed employee
    );
    event SalaryUpdated(
        address indexed employer,
        uint256 indexed groupId,
        address indexed employee,
        uint256 oldSalary,
        uint256 newSalary
    );
    event PayrollDeposited(
        address indexed employer,
        uint256 indexed groupId,
        uint256 indexed cycleId,
        uint256 amount,
        uint256 cycleDuration
    );
    event CycleCancelled(
        address indexed employer,
        uint256 indexed groupId,
        uint256 indexed cycleId,
        uint256 amountReturned
    );
    event FeeRecipientUpdated(
        address indexed previous,
        address indexed updated
    );
    event FeeBpsUpdated(uint256 previous, uint256 updated);
    event YieldRouterSet(address indexed router);
    event PayrollDispatcherSet(address indexed _dispatcher);
    event PayVaultSet(
        address indexed vault
    );

    event PayrollSetup(
        address indexed employer,
        uint256 indexed groupId,
        uint256 indexed cycleId
    );
    
    
    event TotalPendingSalaryRemoved(address indexed employee, uint256 indexed amount);


    // ---- Modifiers ----------------------------------------------------------------------------──

    modifier onlyRegistered() {
        if (!employers[msg.sender].isRegistered)
            revert PayrollManager__NotRegistered();
        _;
    }

    modifier onlyPayVault() {
        if (msg.sender != payVault){
            revert PayrollManager__NotPayVault();
        }
        _;
    }

    modifier groupExists(uint256 groupId) {
        if (!groups[msg.sender][groupId].exists)
            revert PayrollManager__GroupNotFound();
        _;
    }

    modifier noActiveCycle(uint256 groupId) {
        if (_isGroupActive(msg.sender, groupId))
            revert PayrollManager__GroupHasActiveCycle();
        _;
    }

    // ---- Constructor ----------------------------------------------------------------------------

    /**
     * @param _usdc          USDC token address for this environment
     * @param _feeRecipient  Address that receives yield fees
     * @param _feeBps        Fee in basis points taken from yield earned
     */
    constructor(
        address _usdc,
        address _feeRecipient,
        uint256 _feeBps
    ) Ownable(msg.sender) {
        if (_usdc == address(0)) revert PayrollManager__ZeroAddress();
        if (_feeRecipient == address(0)) revert PayrollManager__ZeroAddress();
        if (_feeBps > MAX_FEE_BPS) revert PayrollManager__InvalidFeeBps();

        usdc = _usdc;
        feeRecipient = _feeRecipient;
        feeBps = _feeBps;
    }

    // ---- Admin ------------------------------------------------------------------------------------

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
     * @dev Self-registration — anyone can register. No approval needed.
     *      Must create at least one group before depositing payroll.
     */
    function registerEmployer() external whenNotPaused {
        if (employers[msg.sender].isRegistered)
            revert PayrollManager__AlreadyRegistered();

        employers[msg.sender] = EmployerProfile({
            isRegistered: true,
            groupCount: 0,
            employerAddress: msg.sender
        });

        emit EmployerRegistered(msg.sender);
    }

    // ---- Group Management --------------------------------------------------------------------──

    /**
     * @notice Create a new payroll group.
     * @dev Each group is independent — separate employees, salaries, and cycle.
     *      groupId is 1-indexed per employer, increments with each createGroup().
     *
     * @param name Human-readable group name (e.g. "Engineering", "Sales")
     * @return groupId The newly created group's ID
     */
    function createGroup(
        string calldata name,
        uint256 cycleDuration
    ) external whenNotPaused returns (uint256 groupId) {
        groupId = _createGroup(name, cycleDuration);
    }

    // ---- Payroll Schedule --------------------------------------------------------------------──

    /**
     * @notice Add an employee to a payroll group.
     * @dev Blocked if group has an active cycle — schedule is locked during farming.
     *      Updates totalPayroll immediately.
     *
     * @param groupId  Target group
     * @param employee Employee wallet address
     * @param salary   Monthly salary in USDC (6 decimals)
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
        if (isGroupEmployee[msg.sender][groupId][employee])
            revert PayrollManager__EmployeeAlreadyExists();

        isGroupEmployee[msg.sender][groupId][employee] = true;
        groupEmployees[msg.sender][groupId].push(employee);
        groupSalaries[msg.sender][groupId][employee] = salary;
        groups[msg.sender][groupId].totalPayroll += salary;

        emit EmployeeAdded(msg.sender, groupId, employee, salary);
    }

    /**
     * @notice Add multiple employees to a payroll group in one transaction.
     * @dev Blocked if group has an active cycle.
     *      employees and salaries arrays must be the same length.
     *
     * @param groupId   Target group
     * @param employees Array of employee wallet addresses
     * @param salaries  Array of salaries in USDC (6 decimals), index-aligned with employees
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
        if (employees.length != salaries.length)
            revert PayrollManager__ArrayLengthMismatch();
        if (employees.length == 0) revert PayrollManager__EmptyArray();

        _addEmployees(groupId, employees, salaries);
    }

    /**
     * @notice Remove an employee from a payroll group.
     * @dev Blocked if group has an active cycle.
     *      Updates totalPayroll immediately.
     *      Removes employee from array by swap-and-pop.
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
        if (!isGroupEmployee[msg.sender][groupId][employee])
            revert PayrollManager__EmployeeNotFound();

        uint256 salary = groupSalaries[msg.sender][groupId][employee];

        // Update salary cache and mappings
        groups[msg.sender][groupId].totalPayroll -= salary;
        groupSalaries[msg.sender][groupId][employee] = 0;
        isGroupEmployee[msg.sender][groupId][employee] = false;

        // Swap-and-pop to remove from array
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
     * @dev Blocked if group has an active cycle.
     *
     * @param groupId   Target group
     * @param employees Array of employee wallet addresses to remove
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

            if (!isGroupEmployee[msg.sender][groupId][employee])
                revert PayrollManager__EmployeeNotFound();

            uint256 salary = groupSalaries[msg.sender][groupId][employee];

            groups[msg.sender][groupId].totalPayroll -= salary;
            groupSalaries[msg.sender][groupId][employee] = 0;
            isGroupEmployee[msg.sender][groupId][employee] = false;

            // Swap-and-pop
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
     * @notice Update an employee's salary.
     * @dev Blocked if group has an active cycle.
     *      Updates totalPayroll delta immediately.
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
        if (!isGroupEmployee[msg.sender][groupId][employee])
            revert PayrollManager__EmployeeNotFound();
        if (newSalary == 0) revert PayrollManager__ZeroSalary();

        uint256 oldSalary = groupSalaries[msg.sender][groupId][employee];

        groupSalaries[msg.sender][groupId][employee] = newSalary;
        groups[msg.sender][groupId].totalPayroll -= oldSalary;
        groups[msg.sender][groupId].totalPayroll += newSalary;

        emit SalaryUpdated(msg.sender, groupId, employee, oldSalary, newSalary);
    }

    /**
     * @notice Update salaries for multiple employees in one transaction.
     * @dev Blocked if group has an active cycle.
     *      employees and newSalaries arrays must be the same length.
     *
     * @param groupId     Target group
     * @param employees   Array of employee wallet addresses
     * @param newSalaries Array of new salaries, index-aligned with employees
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
        if (employees.length != newSalaries.length)
            revert PayrollManager__ArrayLengthMismatch();
        if (employees.length == 0) revert PayrollManager__EmptyArray();

        for (uint256 i = 0; i < employees.length; i++) {
            address employee = employees[i];
            uint256 newSalary = newSalaries[i];

            if (!isGroupEmployee[msg.sender][groupId][employee])
                revert PayrollManager__EmployeeNotFound();
            if (newSalary == 0) revert PayrollManager__ZeroSalary();

            uint256 oldSalary = groupSalaries[msg.sender][groupId][employee];

            groupSalaries[msg.sender][groupId][employee] = newSalary;
            groups[msg.sender][groupId].totalPayroll -= oldSalary;
            groups[msg.sender][groupId].totalPayroll += newSalary;

            emit SalaryUpdated(
                msg.sender,
                groupId,
                employee,
                oldSalary,
                newSalary
            );
        }
    }

    // ---- Cycle Management --------------------------------------------------------------------──

    /**
     * @notice Fund a payroll cycle for a group and start yield farming.
     * @dev Pass-through funding — USDC pulled from employer and immediately
     *      passed to YieldRouter.startCycle() in the same transaction.
     *      Amount is read from group.totalPayroll — employer cannot override.
     *      Blocked if group already has an active cycle.
     *
     * @param groupId       Target group
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
     * @notice One-shot employer setup: create group, add employees, and start cycle.
     * @dev Combines createGroup + addEmployees + depositPayroll into a single call.
     *      Employer is auto-registered if not already registered.
     *      USDC approval for totalPayroll must be granted to this contract before calling.
     *
     * @param groupId   The ID of the group to set up
     * @param employees   Array of employee wallet addresses
     * @param salaries    Array of salaries in USDC (6 decimals), index-aligned with employees
     * @return cycleId    The cycle ID returned from YieldRouter
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
        if (employees.length != salaries.length)
            revert PayrollManager__ArrayLengthMismatch();

        // ── Add employees ------------------------------------------------------------
        _addEmployees(groupId, employees, salaries);

        // ── Deposit payroll and start cycle ------------------------------------
        _depositPayroll(groupId);

        emit PayrollSetup(
            msg.sender,
            groupId,
            groups[msg.sender][groupId].activeCycleId
        );

        return (groups[msg.sender][groupId].activeCycleId);
    }

    /**
     * @notice Cancel an active cycle and recover funds.
     * @dev Only possible if YieldRouter has not yet deployed funds to any pool.
     *      Once the agent has rebalanced, cancellation is blocked.
     *      Full refund — no penalty.
     *
     * @param groupId Target group
     */
    function cancelCycle(
        uint256 groupId
    ) external onlyRegistered groupExists(groupId) whenNotPaused nonReentrant {
        if (!_isGroupActive(msg.sender, groupId))
            revert PayrollManager__NoActiveCycle();

        uint256 cycleId = groups[msg.sender][groupId].activeCycleId;

        // cancelCycle in YieldRouter reverts if currentAllocation > 0
        uint256 amountReturned = IYieldRouter(yieldRouter).cancelCycle(
            msg.sender,
            cycleId
        );

        // Reset group state
        groups[msg.sender][groupId].activeCycleId = 0;

        // Return funds to employer
        IERC20(usdc).safeTransfer(msg.sender, amountReturned);

        emit CycleCancelled(msg.sender, groupId, cycleId, amountReturned);
    }

    // ---- View Functions ------------------------------------------------------------------------─

    function getEmployer(
        address employer
    ) external view returns (EmployerProfile memory) {
        return employers[employer];
    }

    function getGroup(
        address employer,
        uint256 groupId
    ) external view returns (PayrollGroup memory) {
        if (!groups[employer][groupId].exists)
            revert PayrollManager__GroupNotFound();
        return groups[employer][groupId];
    }

    function getGroupEmployees(
        address employer,
        uint256 groupId
    ) external view returns (address[] memory) {
        if (!groups[employer][groupId].exists)
            revert PayrollManager__GroupNotFound();
        return groupEmployees[employer][groupId];
    }

    function getSalary(
        address employer,
        uint256 groupId,
        address employee
    ) external view returns (uint256) {
        return groupSalaries[employer][groupId][employee];
    }

    function getEmployeeTotalPendingSalary(
        address employee
    ) external view returns (uint256) {
        return employeeTotalPendingSalary[employee];
    }

    function getTotalPayroll(
        address employer,
        uint256 groupId
    ) external view returns (uint256) {
        if (!groups[employer][groupId].exists)
            revert PayrollManager__GroupNotFound();
        return groups[employer][groupId].totalPayroll;
    }

    function isRegistered(address employer) external view returns (bool) {
        return employers[employer].isRegistered;
    }

    function hasActiveGroup(
        address employer,
        uint256 groupId
    ) external view returns (bool) {
        if (!groups[employer][groupId].exists) return false;
        uint256 cycleId = groups[employer][groupId].activeCycleId;
        if (cycleId == 0) return false;
        return IYieldRouter(yieldRouter).getCycle(employer, cycleId).isActive;
    }

    // ---- Internal Helpers --------------------------------------------------------------------──

    /**
     * @notice Check if a group has an active cycle in YieldRouter.
     * @dev Lazy evaluation — resets stale activeCycleId if cycle has closed.
     *      This avoids needing callbacks from YieldRouter or Dispatcher.
     */
    function _isGroupActive(
        address employer,
        uint256 groupId
    ) internal returns (bool) {
        uint256 cycleId = groups[employer][groupId].activeCycleId;
        if (cycleId == 0) return false;

        bool stillActive = IYieldRouter(yieldRouter)
            .getCycle(employer, cycleId)
            .isActive;

        if (!stillActive) {
            // Lazily reset stale state
            groups[employer][groupId].activeCycleId = 0;
        }

        return stillActive;
    }

    function _createGroup(
        string calldata name,
        uint256 cycleDuration
    ) internal returns (uint256 groupId) {
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
            if (isGroupEmployee[msg.sender][groupId][employee])
                revert PayrollManager__EmployeeAlreadyExists();

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

        // Pull USDC from employer into PayrollManager
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), totalPayroll);

        // Approve YieldRouter to pull from PayrollManager
        IERC20(usdc).approve(yieldRouter, totalPayroll);

        // Start cycle — YieldRouter pulls USDC and returns cycleId
        uint256 cycleId = IYieldRouter(yieldRouter).startCycle(
            msg.sender,
            totalPayroll,
            cycleDuration,
            payrollDispatcher
        );

        // Store cycleId — links this group to its YieldRouter cycle
        groups[msg.sender][groupId].activeCycleId = cycleId;

        cycleToGroup[msg.sender][cycleId] = groupId;

        emit PayrollDeposited(
            msg.sender,
            groupId,
            cycleId,
            totalPayroll,
            cycleDuration
        );
    }

    function removeFromTotalPendingSalary(address employee, uint256 amount) external onlyPayVault{
        if (employeeTotalPendingSalary[employee] < amount){
            revert PayrollManager__InsufficientPendingSalary();
        }

        employeeTotalPendingSalary[employee] -= amount;

        emit TotalPendingSalaryRemoved(employee, amount);
    }
}
