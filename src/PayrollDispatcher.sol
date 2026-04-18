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
 * @notice Handles payday settlement and yield distribution for Flowroll.
 */
contract PayrollDispatcher is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- STRUCTS ---

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

    // --- ERRORS ---

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

    // --- EVENTS ---

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
        uint256 cycleId,
        uint256 indexed groupId,
        address indexed employee,
        uint256 amount
    );

    event FeeCollected(address indexed recipient, uint256 amount);
    event YieldReturnedToEmployer(address indexed employer, uint256 amount);
    event YieldRouterSet(address indexed router);
    event PayrollManagerSet(address indexed manager);
    event PayVaultSet(address indexed vault);
    event FeeRecipientUpdated(address indexed previous, address indexed updated);
    event FeeBpsUpdated(uint256 previous, uint256 updated);

    // --- STATE VARIABLES ---

    uint256 public constant SCALE = 10_000;
    uint256 public constant MAX_FEE_BPS = 2_000;

    address public immutable usdc;
    address public yieldRouter;
    address public payrollManager;
    address public payVault;
    address public feeRecipient;
    uint256 public feeBps;

    mapping(address employer => mapping(uint256 cycleId => DisbursementRecord)) public disbursements;

    // --- MODIFIERS ---

    modifier onlyYieldRouter() {
        _onlyYieldRouter();
        _;
    }

    // --- CONSTRUCTOR ---

    /**
     * @param _usdc USDC token address.
     * @param _feeRecipient Address receiving protocol yield fees.
     * @param _feeBps Fee in basis points taken from yield.
     */
    constructor(
        address _usdc,
        address _feeRecipient,
        uint256 _feeBps
    ) Ownable(msg.sender) {
        if (_usdc == address(0) || _feeRecipient == address(0)) revert PayrollDispatcher__ZeroAddress();
        if (_feeBps > MAX_FEE_BPS) revert PayrollDispatcher__InvalidFeeBps();

        usdc = _usdc;
        feeRecipient = _feeRecipient;
        feeBps = _feeBps;
    }

    // --- EXTERNAL ---

    /**
     * @notice Settles a payroll cycle, distributing yield and principal.
     * @param employer The employer whose cycle is settling.
     * @param cycleId The ID of the maturing cycle.
     * @param amount Total USDC transferred (principal + yield).
     */
    function disburse(
        address employer,
        uint256 cycleId,
        uint256 amount
    ) external onlyYieldRouter whenNotPaused nonReentrant {
        if (yieldRouter == address(0)) revert PayrollDispatcher__RouterNotSet();
        if (payrollManager == address(0)) revert PayrollDispatcher__ManagerNotSet();
        if (payVault == address(0)) revert PayrollDispatcher__VaultNotSet();
        if (amount == 0) revert PayrollDispatcher__InvalidAmount();
        if (disbursements[employer][cycleId].executed) revert PayrollDispatcher__AlreadyDisbursed();

        if (IERC20(usdc).balanceOf(address(this)) < amount) revert PayrollDispatcher__InsufficientBalance();

        uint256 totalDeposited = IYieldRouter(yieldRouter).getCycle(employer, cycleId).totalDeposited;

        uint256 yieldEarned = amount > totalDeposited ? amount - totalDeposited : 0;
        uint256 fee = (yieldEarned * feeBps) / SCALE;
        uint256 employerReturn = yieldEarned - fee;
        uint256 employeeTotal = amount > totalDeposited ? totalDeposited : amount;

        if (fee > 0) {
            IERC20(usdc).safeTransfer(feeRecipient, fee);
            emit FeeCollected(feeRecipient, fee);
        }

        if (employerReturn > 0) {
            IERC20(usdc).safeTransfer(employer, employerReturn);
            emit YieldReturnedToEmployer(employer, employerReturn);
        }

        (uint256 groupId, uint256 employeeCount) = _disburseToEmployees(employer, cycleId, employeeTotal);

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
        if (_feeRecipient == address(0)) revert PayrollDispatcher__ZeroAddress();
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

    /**
     * @notice Recovers dust USDC left from division rounding.
     */
    function recoverDust() external onlyOwner {
        uint256 balance = IERC20(usdc).balanceOf(address(this));
        if (balance > 0) {
            IERC20(usdc).safeTransfer(feeRecipient, balance);
        }
    }

    // --- EXTERNAL VIEW ---

    function getDisbursement(address employer, uint256 cycleId) external view returns (DisbursementRecord memory) {
        return disbursements[employer][cycleId];
    }

    function isDisbursed(address employer, uint256 cycleId) external view returns (bool) {
        return disbursements[employer][cycleId].executed;
    }

    // --- INTERNAL ---

    function _disburseToEmployees(
        address employer,
        uint256 cycleId,
        uint256 employeeTotal
    ) internal returns (uint256 groupId, uint256 employeeCount) {
        groupId = IPayrollManager(payrollManager).cycleToGroup(employer, cycleId);
        address[] memory employees = IPayrollManager(payrollManager).getGroupEmployees(employer, groupId);
        uint256 totalPayroll = IPayrollManager(payrollManager).getTotalPayroll(employer, groupId);

        if (employees.length == 0) revert PayrollDispatcher__NoEmployees();
        if (totalPayroll == 0) revert PayrollDispatcher__ZeroTotalPayroll();

        IERC20(usdc).approve(payVault, employeeTotal);

        uint256 paid;

        for (uint256 i = 0; i < employees.length; i++) {
            address employee = employees[i];
            uint256 salary = IPayrollManager(payrollManager).getSalary(employer, groupId, employee);

            if (salary == 0) continue;

            uint256 share = (salary * employeeTotal) / totalPayroll;

            if (share == 0) continue;

            IPayVault(payVault).credit(employee, share);
            emit EmployeePaid(employer, cycleId, groupId, employee, share);

            paid++;
        }

        IERC20(usdc).approve(payVault, 0);

        return (groupId, paid);
    }

    // --- INTERNAL VIEW ---

    function _onlyYieldRouter() internal view {
        if (msg.sender != yieldRouter) revert PayrollDispatcher__NotYieldRouter();
    }
}