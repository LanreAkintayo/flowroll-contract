// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPayrollManager} from "./interfaces/IPayrollManager.sol";
import {IYieldRouter} from "./interfaces/IYieldRouter.sol";
import {IPayVault} from "./interfaces/IPayVault.sol";

/**
 * @title PayrollDispatcher
 * @notice Payday settlement contract for Flowroll.
 *
 * @dev Key architectural decisions:
 *
 *   SINGLE ENTRY POINT: Only YieldRouter can call disburse(). Called
 *   automatically on payday after YieldRouter withdraws all pool positions
 *   and transfers the full amount (principal + yield) to this contract.
 *
 *   YIELD SPLIT: Employees receive exactly their assigned salaries from
 *   totalDeposited. Protocol fee is taken from yield only. Remaining
 *   yield returns to employer. Principal always fully covers salaries.
 *
 *     totalReceived  = totalDeposited + yieldEarned
 *     fee            = yieldEarned * feeBps / SCALE  → feeRecipient
 *     employerReturn = yieldEarned - fee              → employer wallet
 *     employeeTotal  = totalDeposited                 → split among employees
 *
 *   STATELESS READS: Employee list, salaries, and totalPayroll are read
 *   from PayrollManager at disbursement time. Dispatcher stores only
 *   disbursement records for auditing and double-disbursement protection.
 *
 *   NO CROSS-CHAIN LOGIC: Dispatcher only credits PayVault on the same
 *   chain. Cross-chain bridging is handled by the frontend using Initia's
 *   native bridge SDK after employees claim from PayVault.
 *
 *   PROPORTIONAL SPLIT: Each employee's share is calculated as:
 *     share = (salary * employeeTotal) / totalPayroll
 *   Multiply before divide to preserve precision. Any dust from rounding
 *   stays in the contract and is recoverable by owner.
 *
 *   BALANCE ASSERTION: disburse() verifies that the contract's actual
 *   USDC balance matches the amount parameter before proceeding. This
 *   ensures YieldRouter cannot claim to have sent more than it actually
 *   transferred.
 *
 *   PAID COUNT: employeeCount in DisbursementRecord reflects the number
 *   of employees actually credited — not headcount. Matches the number
 *   of EmployeePaid events emitted exactly.
 */
contract PayrollDispatcher is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Structs ─────────────────────────────────────────────────────────────

    struct DisbursementRecord {
        uint256 totalReceived;
        uint256 totalDeposited;
        uint256 yieldEarned;
        uint256 fee;
        uint256 employerReturn;
        uint256 employeeTotal;
        uint256 employeeCount; // number of employees actually credited
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

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 public constant SCALE = 10_000;
    uint256 public constant MAX_FEE_BPS = 2_000; // 20% max fee on yield

    // ─── State ───────────────────────────────────────────────────────────────

    address public immutable usdc;
    address public yieldRouter;
    address public payrollManager;
    address public payVault;
    address public feeRecipient;
    uint256 public feeBps;

    // employer → cycleId → DisbursementRecord
    mapping(address employer => mapping(uint256 cycleId => DisbursementRecord))
        public disbursements;

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
        uint256  cycleId,
        uint256 indexed groupId,
        address indexed employee,
        uint256 amount
    );

    event FeeCollected(address indexed recipient, uint256 amount);

    event YieldReturnedToEmployer(address indexed employer, uint256 amount);

    event YieldRouterSet(address indexed router);
    event PayrollManagerSet(address indexed manager);
    event PayVaultSet(address indexed vault);
    event FeeRecipientUpdated(
        address indexed previous,
        address indexed updated
    );
    event FeeBpsUpdated(uint256 previous, uint256 updated);

    // ─── Modifiers ───────────────────────────────────────────────────────────

    modifier onlyYieldRouter() {
        if (msg.sender != yieldRouter)
            revert PayrollDispatcher__NotYieldRouter();
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────────

    /**
     * @param _usdc         USDC token address on evm-1
     * @param _feeRecipient Address that receives protocol fee from yield
     * @param _feeBps       Fee in basis points taken from yield earned
     */
    constructor(
        address _usdc,
        address _feeRecipient,
        uint256 _feeBps
    ) Ownable(msg.sender) {
        if (_usdc == address(0)) revert PayrollDispatcher__ZeroAddress();
        if (_feeRecipient == address(0))
            revert PayrollDispatcher__ZeroAddress();
        if (_feeBps > MAX_FEE_BPS) revert PayrollDispatcher__InvalidFeeBps();

        usdc = _usdc;
        feeRecipient = _feeRecipient;
        feeBps = _feeBps;
    }

    // ─── Admin ───────────────────────────────────────────────────────────────

    function setYieldRouter(address _router) external onlyOwner {
        if (_router == address(0)) revert PayrollDispatcher__ZeroAddress();
        yieldRouter = _router;
        emit YieldRouterSet(_router);
    }

    function setPayrollManager(address _manager) external onlyOwner {
        if (_manager == address(0)) revert PayrollDispatcher__ZeroAddress();
        payrollManager = _manager;
        emit PayrollManagerSet(_manager);
    }

    function setPayVault(address _vault) external onlyOwner {
        if (_vault == address(0)) revert PayrollDispatcher__ZeroAddress();
        payVault = _vault;
        emit PayVaultSet(_vault);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0))
            revert PayrollDispatcher__ZeroAddress();
        emit FeeRecipientUpdated(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    function setFeeBps(uint256 _feeBps) external onlyOwner {
        if (_feeBps > MAX_FEE_BPS) revert PayrollDispatcher__InvalidFeeBps();
        emit FeeBpsUpdated(feeBps, _feeBps);
        feeBps = _feeBps;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ─── Core: Disburse ──────────────────────────────────────────────────────

    /**
     * @notice Settle a payroll cycle. Called by YieldRouter on payday.
     * @dev YieldRouter transfers USDC to this contract before calling.
     *      Balance is verified against the amount parameter before proceeding.
     *
     * @param employer  Employer whose cycle is settling
     * @param cycleId   YieldRouter cycle ID
     * @param amount    Total USDC transferred — principal + yield
     */
    function disburse(
        address employer,
        uint256 cycleId,
        uint256 amount
    ) external onlyYieldRouter whenNotPaused nonReentrant {
        // ── Guard checks ──────────────────────────────────────────────────────
        if (yieldRouter == address(0)) revert PayrollDispatcher__RouterNotSet();
        if (payrollManager == address(0))
            revert PayrollDispatcher__ManagerNotSet();
        if (payVault == address(0)) revert PayrollDispatcher__VaultNotSet();
        if (amount == 0) revert PayrollDispatcher__InvalidAmount();
        if (disbursements[employer][cycleId].executed)
            revert PayrollDispatcher__AlreadyDisbursed();

        // ── Verify actual balance matches claimed amount ────────────────
        if (IERC20(usdc).balanceOf(address(this)) < amount)
            revert PayrollDispatcher__InsufficientBalance();

        // ── Read cycle data ───────────────────────────────────────────────────
        uint256 totalDeposited = IYieldRouter(yieldRouter)
            .getCycle(employer, cycleId)
            .totalDeposited;

        // ── Calculate yield split ─────────────────────────────────────────────
        uint256 yieldEarned = amount > totalDeposited
            ? amount - totalDeposited
            : 0;

        uint256 fee = (yieldEarned * feeBps) / SCALE;
        uint256 employerReturn = yieldEarned - fee;
        uint256 employeeTotal = totalDeposited;

        // ── Collect protocol fee ──────────────────────────────────────────────
        if (fee > 0) {
            IERC20(usdc).safeTransfer(feeRecipient, fee);
            emit FeeCollected(feeRecipient, fee);
        }

        // ── Return yield to employer ──────────────────────────────────────────
        if (employerReturn > 0) {
            IERC20(usdc).safeTransfer(employer, employerReturn);
            emit YieldReturnedToEmployer(employer, employerReturn);
        }

        // ── Disburse to employees — extracted to free stack slots ─────────────
        (uint256 groupId, uint256 employeeCount) = _disburseToEmployees(
            employer,
            cycleId,
            employeeTotal
        );

        // ── Record disbursement ───────────────────────────────────────────────
        disbursements[employer][cycleId] = DisbursementRecord({
            totalReceived: amount,
            totalDeposited: totalDeposited,
            yieldEarned: yieldEarned,
            fee: fee,
            employerReturn: employerReturn,
            employeeTotal: employeeTotal,
            employeeCount: employeeCount,
            timestamp: block.timestamp,
            executed: true
        });

        emit Disbursed(
            employer,
            cycleId,
            groupId,
            amount,
            yieldEarned,
            fee,
            employerReturn,
            employeeTotal,
            employeeCount
        );
    }

    /**
     * @notice Credit each employee's share via PayVault.
     * @dev Extracted from disburse() to reduce stack depth.
     *      Returns groupId (for events) and paid count (for record).
     *      employeeCount is the number of employees actually credited —
     *      zero-salary entries are skipped and not counted.
     */
    function _disburseToEmployees(
        address employer,
        uint256 cycleId,
        uint256 employeeTotal
    ) internal returns (uint256 groupId, uint256 employeeCount) {
        groupId = IPayrollManager(payrollManager).cycleToGroup(
            employer,
            cycleId
        );

        address[] memory employees = IPayrollManager(payrollManager)
            .getGroupEmployees(employer, groupId);

        uint256 totalPayroll = IPayrollManager(payrollManager).getTotalPayroll(
            employer,
            groupId
        );

        if (employees.length == 0) revert PayrollDispatcher__NoEmployees();
        if (totalPayroll == 0) revert PayrollDispatcher__ZeroTotalPayroll();

        IERC20(usdc).approve(payVault, employeeTotal);

        // ── Track paid count, not headcount ────────────────────────────
        uint256 paid;

        for (uint256 i = 0; i < employees.length; i++) {
            address employee = employees[i];

            uint256 salary = IPayrollManager(payrollManager).getSalary(
                employer,
                groupId,
                employee
            );

            if (salary == 0) continue;

            uint256 share = (salary * employeeTotal) / totalPayroll;

            if (share == 0) continue;

            IPayVault(payVault).credit(employee, share);

            // ── groupId on EmployeePaid ────────────────────────────────
            emit EmployeePaid(employer, cycleId, groupId, employee, share);

            paid++;
        }

        IERC20(usdc).approve(payVault, 0);

        return (groupId, paid);
    }

    // ─── View Functions ───────────────────────────────────────────────────────

    function getDisbursement(
        address employer,
        uint256 cycleId
    ) external view returns (DisbursementRecord memory) {
        return disbursements[employer][cycleId];
    }

    function isDisbursed(
        address employer,
        uint256 cycleId
    ) external view returns (bool) {
        return disbursements[employer][cycleId].executed;
    }

    // ─── Recovery ────────────────────────────────────────────────────────────

    /**
     * @notice Recover dust USDC left from rounding.
     * @dev Rounding in proportional splits can leave tiny amounts.
     *      Only owner can recover — funds go to feeRecipient.
     */
    function recoverDust() external onlyOwner {
        uint256 balance = IERC20(usdc).balanceOf(address(this));
        if (balance > 0) {
            IERC20(usdc).safeTransfer(feeRecipient, balance);
        }
    }
}
