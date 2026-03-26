// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPayrollDispatcher
 * @notice Standard interface for triggering salary disbursements from the YieldRouter.
 * @dev Handles the downstream routing of settled cycle funds to employee addresses.
 */
interface IPayrollDispatcher {
    /**
     * @notice Executes salary disbursement for a settled payroll cycle.
     * @param caller The employer address that owns the cycle.
     * @param cycleId The unique identifier of the settled cycle.
     * @param amount The total USDC amount transferred for disbursement (6 decimals).
     */
    function disburse(address caller, uint256 cycleId, uint256 amount) external;
}