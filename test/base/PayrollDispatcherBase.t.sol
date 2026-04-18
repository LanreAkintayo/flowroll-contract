// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SharedBase} from "./SharedBase.t.sol";

/**
 * @title PayrollDispatcherBase
 * @dev Base test contract for PayrollDispatcher logic. Handles multi-employee cycle simulations.
 */
abstract contract PayrollDispatcherBase is SharedBase {
    uint256 internal constant SALARY_1 = 5_000e6;
    uint256 internal constant SALARY_2 = 2_500e6;
    uint256 internal constant SALARY_3 = 1_500e6;
    uint256 internal constant TOTAL_PAYROLL = SALARY_1 + SALARY_2 + SALARY_3;

    function setUp() public virtual override {
        super.setUp();
    }

    /// @dev Warps the virtual machine time to the payday of a specific cycle.
    function _warpToPayday(uint256 cycleId) internal {
        uint256 payday = router.getCycle(employer, cycleId).payDay;
        vm.warp(payday);
    }

    /// @dev Executes an agent rebalance for the specified cycle.
    function _rebalance(uint256 cycleId) internal {
        vm.prank(agentOperator);
        router.agentRebalance(employer, cycleId);
    }

    /// @dev Simulates a full payroll cycle including yield generation and disbursement.
    function _runFullCycle(uint256 yieldAmount) internal returns (uint256 cycleId) {
        address[] memory employees = new address[](3);
        employees[0] = employee;
        employees[1] = employee2;
        employees[2] = employee3;

        uint256[] memory salaries = new uint256[](3);
        salaries[0] = SALARY_1;
        salaries[1] = SALARY_2;
        salaries[2] = SALARY_3;

        vm.startPrank(employer);
        uint256 groupId = manager.createGroup("Tech Team", CYCLE_DURATION);
        usdc.approve(address(manager), DEPOSIT_AMOUNT);
        cycleId = manager.setUpPayroll(groupId, employees, salaries);
        vm.stopPrank();

        _rebalance(cycleId);
        _simulateYield(yieldAmount);
        _warpToPayday(cycleId);
        _rebalance(cycleId);
    }

    /// @dev Simulates a full payroll cycle with zero yield.
    function _runFullCycleNoYield() internal returns (uint256 cycleId) {
        address[] memory employees = new address[](3);
        employees[0] = employee;
        employees[1] = employee2;
        employees[2] = employee3;

        uint256[] memory salaries = new uint256[](3);
        salaries[0] = SALARY_1;
        salaries[1] = SALARY_2;
        salaries[2] = SALARY_3;

        vm.startPrank(employer);
        uint256 groupId = manager.createGroup("Tech Team", CYCLE_DURATION);
        usdc.approve(address(manager), TOTAL_PAYROLL);
        cycleId = manager.setUpPayroll(groupId, employees, salaries);
        vm.stopPrank();

        _warpToPayday(cycleId);
        _rebalance(cycleId);
    }

    /// @dev Calculates the expected protocol fee based on yield.
    function _expectedFee(uint256 yieldAmount) internal pure returns (uint256) {
        return (yieldAmount * CREDIT_FEE_BPS) / SCALE;
    }

    /// @dev Calculates the expected proportional share for an employee.
    function _expectedShare(uint256 salary, uint256 employeeTotal) internal pure returns (uint256) {
        return (salary * employeeTotal) / TOTAL_PAYROLL;
    }
}