// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPayrollDispatcher
 * @notice Interface for the PayrollDispatcher contract.
 */
interface IPayrollDispatcher {
    // ─── Structs ─────────────────────────────────────────────────────────────

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

    // ─── Custom Errors ───────────────────────────────────────────────────────

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

    // ─── Events ──────────────────────────────────────────────────────────────

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

    // ─── State Variable Getters ──────────────────────────────────────────────
    
    function SCALE() external view returns (uint256);
    function MAX_FEE_BPS() external view returns (uint256);
    function usdc() external view returns (address);
    function yieldRouter() external view returns (address);
    function payrollManager() external view returns (address);
    function payVault() external view returns (address);
    function feeRecipient() external view returns (address);
    function feeBps() external view returns (uint256);
    
    function disbursements(address employer, uint256 cycleId) external view returns (
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

    // ─── Core & View Functions ───────────────────────────────────────────────

    function disburse(address employer, uint256 cycleId, uint256 amount) external;
    
    function getDisbursement(address employer, uint256 cycleId) external view returns (DisbursementRecord memory);
    
    function isDisbursed(address employer, uint256 cycleId) external view returns (bool);

    // ─── Admin & Recovery Functions ──────────────────────────────────────────

    function setYieldRouter(address _router) external;
    function setPayrollManager(address _manager) external;
    function setPayVault(address _vault) external;
    function setFeeRecipient(address _feeRecipient) external;
    function setFeeBps(uint256 _feeBps) external;
    
    function pause() external;
    function unpause() external;
    function recoverDust() external;
}