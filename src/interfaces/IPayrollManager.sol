// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPayrollManager
 * @notice Interface for managing employer registrations, employee groups, and payroll cycles.
 * @dev Core state manager for the Flowroll protocol's organizational logic.
 */
interface IPayrollManager {
    /**
     * @notice Profile data for a registered employer.
     * @param isRegistered Boolean indicating if the employer is in the system.
     * @param groupCount Total number of payroll groups created by this employer.
     * @param employerAddress The primary wallet address of the employer.
     */
    struct EmployerProfile {
        bool isRegistered;
        uint256 groupCount;
        address employerAddress;
    }

    /**
     * @notice Configuration and state of a specific payroll group.
     * @param groupId Unique identifier for the group within an employer's profile.
     * @param name Descriptive name for the group.
     * @param totalPayroll Cumulative salary amount required for the entire group.
     * @param activeCycleId The ID of the currently running payroll cycle, if any.
     * @param cycleDuration The time lock duration for deposits in this group.
     * @param exists Boolean indicating if the group has been initialized.
     */
    struct PayrollGroup {
        uint256 groupId;
        string name;
        uint256 totalPayroll;
        uint256 activeCycleId;
        uint256 cycleDuration;
        bool exists;
    }

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

    function SCALE() external view returns (uint256);

    function MAX_FEE_BPS() external view returns (uint256);

    function usdc() external view returns (address);

    function yieldRouter() external view returns (address);

    function payrollDispatcher() external view returns (address);

    function feeRecipient() external view returns (address);

    function feeBps() external view returns (uint256);

    /**
     * @notice Maps a specific cycle ID back to its parent group ID.
     */
    function cycleToGroup(address employer, uint256 cycleId) external view returns (uint256 groupId);

    /**
     * @notice Initializes an employer profile in the system.
     */
    function registerEmployer() external;

    /**
     * @notice Creates a new payroll group with a specific lock duration.
     * @param name The name of the department or group.
     * @param cycleDuration Duration in seconds that funds are locked to earn yield.
     * @return groupId The auto-incremented ID of the new group.
     */
    function createGroup(string calldata name, uint256 cycleDuration) external returns (uint256 groupId);

    /**
     * @notice Adds a single employee to a payroll group.
     */
    function addEmployee(uint256 groupId, address employee, uint256 salary) external;

    /**
     * @notice Batch adds multiple employees to a payroll group.
     */
    function addEmployees(uint256 groupId, address[] calldata employees, uint256[] calldata salaries) external;

    /**
     * @notice Removes a single employee from a payroll group.
     */
    function removeEmployee(uint256 groupId, address employee) external;

    /**
     * @notice Batch removes multiple employees from a payroll group.
     */
    function removeEmployees(uint256 groupId, address[] calldata employees) external;

    /**
     * @notice Updates the salary for a specific employee in a group.
     */
    function updateSalary(uint256 groupId, address employee, uint256 newSalary) external;

    /**
     * @notice Batch updates salaries for multiple employees.
     */
    function updateSalaries(uint256 groupId, address[] calldata employees, uint256[] calldata newSalaries) external;

    /**
     * @notice Decrements the total pending salary record for an employee.
     * @dev Used by the credit module to settle advances.
     */
    function removeFromTotalPendingSalary(address employee, uint256 amount) external;

    /**
     * @notice Initiates a payroll cycle by depositing the total group salary into the yield router.
     * @param groupId The ID of the group to fund.
     */
    function depositPayroll(uint256 groupId) external;

    /**
     * @notice Cancels an active payroll cycle and returns funds to the employer.
     * @dev Only possible if the cycle has not yet reached maturity.
     */
    function cancelCycle(uint256 groupId) external;

    /**
     * @notice Fetches the profile of a registered employer.
     */
    function getEmployer(address employer) external view returns (EmployerProfile memory);

    /**
     * @notice Fetches group details for a specific employer.
     */
    function getGroup(address employer, uint256 groupId) external view returns (PayrollGroup memory);

    /**
     * @notice Returns the list of employee addresses assigned to a group.
     */
    function getGroupEmployees(address employer, uint256 groupId) external view returns (address[] memory);

    /**
     * @notice Returns the salary of a specific employee within a group.
     */
    function getSalary(address employer, uint256 groupId, address employee) external view returns (uint256);

    /**
     * @notice Returns total pending salary across all groups for an employee.
     */
    function getEmployeeTotalPendingSalary(address employee) external view returns (uint256);

    /**
     * @notice Returns the total payroll amount required for a group.
     */
    function getTotalPayroll(address employer, uint256 groupId) external view returns (uint256);

    function isRegistered(address employer) external view returns (bool);

    function hasActiveGroup(address employer, uint256 groupId) external view returns (bool);

    function setYieldRouter(address _router) external;

    function setPayrollDispatcher(address _dispatcher) external;

    function setFeeRecipient(address _feeRecipient) external;

    function setFeeBps(uint256 _feeBps) external;

    function pause() external;

    function unpause() external;
}