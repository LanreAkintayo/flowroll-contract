// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IFlowrollCredit
 * @notice Interface for Flowroll's credit and salary advance module.
 * @dev Manages employee debt, salary advances, and liquidity for the protocol.
 */
interface IFlowrollCredit {
    error FlowrollCredit__ZeroAddress();
    error FlowrollCredit__NotPayVault();
    error FlowrollCredit__ZeroAmount();
    error FlowrollCredit__InsufficientLiquidity();
    error FlowrollCredit__ExceedsMaxAdvance();
    error FlowrollCredit__InvalidBps();
    error FlowrollCredit__PayrollManagerNotSet();

    event PayVaultSet(address indexed vault);
    event PayrollManagerSet(address indexed manager);
    event AdvanceRequested(address indexed employee, uint256 requestedAmount, uint256 fee, uint256 netAmount);
    event DebtRepaid(address indexed employee, uint256 amount);
    event FeeUpdated(uint256 newFeeBps);
    event MaxAdvanceUpdated(uint256 newMaxAdvanceBps);
    event FeesWithdrawn(address indexed owner, uint256 amount);
    event DebtUpdated(address indexed employee, uint256 amount);

    /**
     * @notice Allows an employee to request a salary advance.
     * @param amount The total amount of salary to advance.
     */
    function requestSalary(uint256 amount) external;

    /**
     * @notice Repays a specific employee's debt.
     * @param employee The address of the employee whose debt is being settled.
     * @param amount The amount to repay.
     */
    function repayDebt(address employee, uint256 amount) external;

    /**
     * @notice Updates the debt record for an employee.
     * @dev Restricted to the PayVault.
     * @param employee The address of the employee.
     * @param newDebt The updated debt balance.
     */
    function updateDebt(address employee, uint256 newDebt) external;

    /**
     * @notice Sets the address of the PayVault.
     * @param _payVault The new PayVault address.
     */
    function setPayVault(address _payVault) external;

    /**
     * @notice Sets the address of the PayrollManager.
     * @param _payrollManager The new PayrollManager address.
     */
    function setPayrollManager(address _payrollManager) external;

    /**
     * @notice Updates the transaction fee in basis points.
     * @param _feeBps The new fee value.
     */
    function updateFeeBps(uint256 _feeBps) external;

    /**
     * @notice Updates the maximum allowable advance percentage.
     * @param _maxAdvanceBps The new maximum advance in basis points.
     */
    function updateMaxAdvanceBps(uint256 _maxAdvanceBps) external;

    /**
     * @notice Withdraws accumulated protocol fees to the owner.
     */
    function withdrawFees() external;

    /**
     * @notice Withdraws protocol liquidity to the owner.
     * @param amount The amount of liquidity to withdraw.
     */
    function withdrawLiquidity(uint256 amount) external;

    /**
     * @notice Returns the current debt of an employee.
     * @param employee The address to query.
     */
    function getEmployeeDebt(address employee) external view returns (uint256);

    /**
     * @notice Returns comprehensive advance details for an employee.
     * @param employee The address to query.
     * @return pendingSalary Total salary not yet withdrawn.
     * @return currentDebt Current outstanding debt.
     * @return maxAvailableToDraw Remaining credit available for advance.
     * @return currentFeeBps The current fee applied to advances.
     */
    function getAdvanceInfo(address employee) external view returns (
        uint256 pendingSalary,
        uint256 currentDebt,
        uint256 maxAvailableToDraw,
        uint256 currentFeeBps
    );

    function pause() external;

    function unpause() external;

    function token() external view returns (address);

    function payrollManager() external view returns (address);

    function payVault() external view returns (address);

    function feeBps() external view returns (uint256);

    function maxAdvanceBps() external view returns (uint256);

    function totalCollectedFees() external view returns (uint256);
}