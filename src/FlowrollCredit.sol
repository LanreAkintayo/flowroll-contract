// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPayrollManager} from "./interfaces/IPayrollManager.sol";

/**
 * @title FlowrollCredit
 * @notice Manages salary advances and employee debt within the Flowroll protocol.
 */
contract FlowrollCredit is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- STATE VARIABLES ---

    IERC20 public immutable token;
    address public payrollManager;
    address public payVault;

    uint256 public feeBps; 
    uint256 public maxAdvanceBps; 
    uint256 public totalCollectedFees;
    
    uint256 private constant BPS_DENOMINATOR = 10000;
    uint256 private constant MAX_FEE_BPS = 1000;

    mapping(address => uint256) private employeeDebt;

    // --- EVENTS ---

    event PayVaultSet(address indexed vault);
    event PayrollManagerSet(address indexed manager);
    event AdvanceRequested(address indexed employee, uint256 requestedAmount, uint256 fee, uint256 netAmount);
    event DebtRepaid(address indexed employee, uint256 amount);
    event FeeUpdated(uint256 newFeeBps);
    event MaxAdvanceUpdated(uint256 newMaxAdvanceBps);
    event FeesWithdrawn(address indexed owner, uint256 amount);
    event DebtUpdated(address indexed employee, uint256 amount);

    // --- ERRORS ---

    error FlowrollCredit__ZeroAddress();
    error FlowrollCredit__NotPayVault();
    error FlowrollCredit__ZeroAmount();
    error FlowrollCredit__InsufficientLiquidity();
    error FlowrollCredit__ExceedsMaxAdvance();
    error FlowrollCredit__InvalidBps();
    error FlowrollCredit__PayrollManagerNotSet();

    // --- MODIFIERS ---

    modifier onlyPayVault() {
       _onlyPayVault();
       _;
    }

    // --- CONSTRUCTOR ---

    /**
     * @param _token USDC or underlying token address.
     * @param _feeBps Advance fee in basis points.
     * @param _maxAdvanceBps Maximum advance percentage in basis points.
     */
    constructor(
        address _token,
        uint256 _feeBps,
        uint256 _maxAdvanceBps
    ) Ownable(msg.sender) {
        if (_token == address(0)) revert FlowrollCredit__ZeroAddress();
        if (_feeBps > MAX_FEE_BPS || _maxAdvanceBps > BPS_DENOMINATOR) revert FlowrollCredit__InvalidBps();

        token = IERC20(_token);
        feeBps = _feeBps;
        maxAdvanceBps = _maxAdvanceBps;
    }

    // --- EXTERNAL ---

    /**
     * @notice Allows an employee to draw a salary advance against pending payroll.
     * @param amount The requested advance amount.
     */
    function requestSalary(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert FlowrollCredit__ZeroAmount();
        if (payrollManager == address(0)) revert FlowrollCredit__PayrollManagerNotSet();

        uint256 pendingSalary = IPayrollManager(payrollManager).getEmployeeTotalPendingSalary(msg.sender);
        uint256 currentDebt = employeeDebt[msg.sender];
        
        uint256 maxAllowed = (pendingSalary * maxAdvanceBps) / BPS_DENOMINATOR;
        if (currentDebt + amount > maxAllowed) revert FlowrollCredit__ExceedsMaxAdvance();

        if (token.balanceOf(address(this)) < amount) revert FlowrollCredit__InsufficientLiquidity();

        uint256 fee = (amount * feeBps) / BPS_DENOMINATOR;
        uint256 netAmount = amount - fee;

        employeeDebt[msg.sender] += amount;
        totalCollectedFees += fee;

        token.safeTransfer(msg.sender, netAmount);

        emit AdvanceRequested(msg.sender, amount, fee, netAmount);
    }

    /**
     * @notice Allows direct repayment of an employee's debt.
     * @param employee The address of the employee.
     * @param amount The amount to repay.
     */
    function repayDebt(address employee, uint256 amount) external nonReentrant {
        if (amount == 0) revert FlowrollCredit__ZeroAmount();
        
        employeeDebt[employee] -= amount;
        token.safeTransferFrom(msg.sender, address(this), amount);

        emit DebtRepaid(employee, amount);
    }

    /**
     * @notice Updates the debt balance for an employee.
     * @param employee The address of the employee.
     * @param newDebt The updated debt amount.
     */
    function updateDebt(address employee, uint256 newDebt) external onlyPayVault nonReentrant {
        employeeDebt[employee] = newDebt;
        emit DebtUpdated(employee, newDebt);
    }

    /**
     * @notice Sets the PayVault address.
     */
    function setPayVault(address _payVault) external onlyOwner {
        if (_payVault == address(0)) revert FlowrollCredit__ZeroAddress();
        payVault = _payVault;
        emit PayVaultSet(_payVault);
    }

    /**
     * @notice Sets the PayrollManager address.
     */
    function setPayrollManager(address _payrollManager) external onlyOwner {
        if (_payrollManager == address(0)) revert FlowrollCredit__ZeroAddress();
        payrollManager = _payrollManager;
        emit PayrollManagerSet(_payrollManager);
    }

    /**
     * @notice Updates the protocol fee.
     */
    function updateFeeBps(uint256 _feeBps) external onlyOwner {
        if (_feeBps > MAX_FEE_BPS) revert FlowrollCredit__InvalidBps();
        feeBps = _feeBps;
        emit FeeUpdated(_feeBps);
    }

    /**
     * @notice Updates the maximum allowed advance percentage.
     */
    function updateMaxAdvanceBps(uint256 _maxAdvanceBps) external onlyOwner {
        if (_maxAdvanceBps > BPS_DENOMINATOR) revert FlowrollCredit__InvalidBps();
        maxAdvanceBps = _maxAdvanceBps;
        emit MaxAdvanceUpdated(_maxAdvanceBps);
    }

    /**
     * @notice Withdraws accumulated protocol fees.
     */
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = totalCollectedFees;
        if (amount == 0) revert FlowrollCredit__ZeroAmount();

        totalCollectedFees = 0;
        token.safeTransfer(owner(), amount);

        emit FeesWithdrawn(owner(), amount);
    }

    /**
     * @notice Withdraws unused liquidity provided to the credit module.
     * @param amount The amount to withdraw.
     */
    function withdrawLiquidity(uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert FlowrollCredit__ZeroAmount();
        
        uint256 availableLiquidity = token.balanceOf(address(this)) - totalCollectedFees;
        if (amount > availableLiquidity) revert FlowrollCredit__InsufficientLiquidity();

        token.safeTransfer(owner(), amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // --- EXTERNAL VIEW ---

    /**
     * @notice Returns the outstanding debt of an employee.
     */
    function getEmployeeDebt(address employee) external view returns (uint256) {
        return employeeDebt[employee];
    }

    /**
     * @notice Returns the current advance status and availability for an employee.
     */
    function getAdvanceInfo(address employee) external view returns (
        uint256 pendingSalary,
        uint256 currentDebt,
        uint256 maxAvailableToDraw,
        uint256 currentFeeBps
    ) {
        if (payrollManager != address(0)) {
            pendingSalary = IPayrollManager(payrollManager).getEmployeeTotalPendingSalary(employee);
        }
        
        currentDebt = employeeDebt[employee];
        currentFeeBps = feeBps;

        uint256 maxAllowed = (pendingSalary * maxAdvanceBps) / BPS_DENOMINATOR;
        maxAvailableToDraw = currentDebt >= maxAllowed ? 0 : maxAllowed - currentDebt;
    }


    // --- INTERNAL ---

    function _onlyPayVault() internal view {
        if (msg.sender != payVault) revert FlowrollCredit__NotPayVault();
    }

}