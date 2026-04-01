// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPayrollManager
 * @notice Interface for the PayrollManager contract.
 */
interface IPayrollManager {
    // ─── Structs ─────────────────────────────────────────────────────────────

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

    // ─── Custom Errors ───────────────────────────────────────────────────────

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

    // ─── Events ──────────────────────────────────────────────────────────────

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

    // ─── State Variable Getters ──────────────────────────────────────────────

    function SCALE() external view returns (uint256);
    function MAX_FEE_BPS() external view returns (uint256);
    function usdc() external view returns (address);
    function yieldRouter() external view returns (address);
    function payrollDispatcher() external view returns (address);
    function feeRecipient() external view returns (address);
    function feeBps() external view returns (uint256);
    function cycleToGroup(address employer, uint256 cycleId) external view returns (uint256 groupId);

    // ─── Employer & Group Management ─────────────────────────────────────────

    function registerEmployer() external;
    function createGroup(string calldata name, uint256 cycleDuration) external returns (uint256 groupId);

    // ─── Payroll Schedule ─────────────────────────────────────────────────────

    function addEmployee(uint256 groupId, address employee, uint256 salary) external;
    function addEmployees(uint256 groupId, address[] calldata employees, uint256[] calldata salaries) external;
    function removeEmployee(uint256 groupId, address employee) external;
    function removeEmployees(uint256 groupId, address[] calldata employees) external;
    function updateSalary(uint256 groupId, address employee, uint256 newSalary) external;
    function updateSalaries(uint256 groupId, address[] calldata employees, uint256[] calldata newSalaries) external;

    // ─── Cycle Management ─────────────────────────────────────────────────────

    function depositPayroll(uint256 groupId) external;
    function cancelCycle(uint256 groupId) external;

    // ─── View Functions ───────────────────────────────────────────────────────

    function getEmployer(address employer) external view returns (EmployerProfile memory);
    function getGroup(address employer, uint256 groupId) external view returns (PayrollGroup memory);
    function getGroupEmployees(address employer, uint256 groupId) external view returns (address[] memory);
    function getSalary(address employer, uint256 groupId, address employee) external view returns (uint256);
    function getTotalPayroll(address employer, uint256 groupId) external view returns (uint256);
    function isRegistered(address employer) external view returns (bool);
    function hasActiveGroup(address employer, uint256 groupId) external view returns (bool);

    // ─── Admin Functions ──────────────────────────────────────────────────────

    function setYieldRouter(address _router) external;
    function setPayrollDispatcher(address _dispatcher) external;
    function setFeeRecipient(address _feeRecipient) external;
    function setFeeBps(uint256 _feeBps) external;
    function pause() external;
    function unpause() external;
}