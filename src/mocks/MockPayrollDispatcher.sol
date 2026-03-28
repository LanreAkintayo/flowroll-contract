// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MockPayrollDispatcher
 * @notice Stub implementation of IPayrollDispatcher for testing.
 * @dev Accepts disburse() calls without reverting. Replace with real
 *      PayrollDispatcher in integration tests.
 */
contract MockPayrollDispatcher {

    // ─── Events ──────────────────────────────────────────────────────────────

    event Disbursed(
        address indexed caller,
        uint256 indexed cycleId,
        uint256 amount
    );

    // ─── State ───────────────────────────────────────────────────────────────

    mapping(address => mapping(uint256 => uint256)) public disbursements;
    uint256 public totalDisbursed;

    // ─── Interface ───────────────────────────────────────────────────────────

    function disburse(
        address caller,
        uint256 cycleId,
        uint256 amount
    ) external {
        disbursements[caller][cycleId] = amount;
        totalDisbursed += amount;
        emit Disbursed(caller, cycleId, amount);
    }
}