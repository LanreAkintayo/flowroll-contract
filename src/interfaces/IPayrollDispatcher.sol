// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPayrollDispatcher
 * @notice Interface for handling the distribution of payroll assets and yield.
 * @dev Manages the logic for splitting funds between employees, protocol fees, and employer returns.
 */
interface IPayrollDispatcher {
    /**
     * @notice Record of a specific payroll disbursement cycle.
     * @param totalReceived Total assets returned from the yield router.
     * @param totalDeposited Original principal amount deposited.
     * @param yieldEarned Total profit generated during the cycle.
     * @param fee Protocol fee deducted from the yield.
     * @param employerReturn Assets returned to the employer (surplus yield).
     * @param employeeTotal Total principal distributed to employees.
     * @param employeeCount Number of employees paid in this cycle.
     * @param timestamp Block timestamp of the execution.
     * @param executed Whether the disbursement has been completed.
     */
    struct DisbursementRecord {
        uint256 totalReceived;
        uint256 totalDeposited;
        uint256 yieldEarned;
        uint256 fee;
        uint256 employerReturn;
        uint256 employeeTotal;
        uint256 employeeCount;
        uint256 timestamp;
        bool executed;
    }

    error PayrollDispatcher__NotYieldRouter();
    error PayrollDispatcher__ZeroAddress();
    error PayrollDispatcher__AlreadyDisbursed();
    error PayrollDispatcher__InvalidAmount();
    error PayrollDispatcher__RouterNotSet();
    error PayrollDispatcher__ManagerNotSet();
    error PayrollDispatcher__VaultNotSet();
    error PayrollDispatcher__InvalidFeeBps();
    error PayrollDispatcher__NoEmployees();
    error PayrollDispatcher__ZeroTotalPayroll();
    error PayrollDispatcher__InsufficientBalance();

    event Disbursed(
        address indexed employer,
        uint256 indexed cycleId,
        uint256 indexed groupId,
        uint256 totalReceived,
        uint256 yieldEarned,
        uint256 fee,
        uint256 employerReturn,
        uint256 employeeTotal,
        uint256 employeeCount
    );

    event EmployeePaid(
        address indexed employer,
        uint256 indexed cycleId,
        uint256 indexed groupId,
        address employee,
        uint256 amount
    );

    event FeeCollected(address indexed recipient, uint256 amount);
    event YieldReturnedToEmployer(address indexed employer, uint256 amount);
    event YieldRouterSet(address indexed router);
    event PayrollManagerSet(address indexed manager);
    event PayVaultSet(address indexed vault);
    event FeeRecipientUpdated(address indexed previous, address indexed updated);
    event FeeBpsUpdated(uint256 previous, uint256 updated);

    function SCALE() external view returns (uint256);

    function MAX_FEE_BPS() external view returns (uint256);

    function usdc() external view returns (address);

    function yieldRouter() external view returns (address);

    function payrollManager() external view returns (address);

    function payVault() external view returns (address);

    function feeRecipient() external view returns (address);

    function feeBps() external view returns (uint256);

    /**
     * @notice Returns the disbursement data for a specific employer and cycle.
     */
    function disbursements(address employer, uint256 cycleId)
        external
        view
        returns (
            uint256 totalReceived,
            uint256 totalDeposited,
            uint256 yieldEarned,
            uint256 fee,
            uint256 employerReturn,
            uint256 employeeTotal,
            uint256 employeeCount,
            uint256 timestamp,
            bool executed
        );

    /**
     * @notice Executes the distribution of funds for a completed payroll cycle.
     * @param employer The address of the employer.
     * @param cycleId The unique identifier of the payroll cycle.
     * @param amount The total amount of assets received from the pool.
     */
    function disburse(
        address employer,
        uint256 cycleId,
        uint256 amount
    ) external;

    /**
     * @notice Fetches the full record of a disbursement.
     */
    function getDisbursement(address employer, uint256 cycleId) external view returns (DisbursementRecord memory);

    /**
     * @notice Checks if a specific cycle has already been disbursed.
     */
    function isDisbursed(address employer, uint256 cycleId) external view returns (bool);

    /**
     * @notice Updates the Yield Router address.
     */
    function setYieldRouter(address _router) external;

    /**
     * @notice Updates the Payroll Manager address.
     */
    function setPayrollManager(address _manager) external;

    /**
     * @notice Updates the Pay Vault address.
     */
    function setPayVault(address _vault) external;

    /**
     * @notice Updates the fee recipient address.
     */
    function setFeeRecipient(address _feeRecipient) external;

    /**
     * @notice Updates the protocol fee in basis points.
     */
    function setFeeBps(uint256 _feeBps) external;

    function pause() external;

    function unpause() external;

    /**
     * @notice Recovers accidental token transfers to the contract.
     */
    function recoverDust() external;
}