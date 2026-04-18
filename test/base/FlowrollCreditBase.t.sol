// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SharedBase} from "./SharedBase.t.sol";

/**
 * @title FlowrollCreditBase
 * @notice Base test contract for FlowrollCredit unit tests.
 * @dev Provides internal helper logic for payroll and environment setup.
 */
abstract contract FlowrollCreditBase is SharedBase {

    // --- INTERNAL ---

    /**
     * @notice Sets up a standard payroll group and triggers the initial agent rebalance.
     * @return groupId The identifier for the newly created payroll group.
     */
    function _setupStandardPayroll() internal returns (uint256 groupId) {
        address[] memory employees = new address[](1);
        employees[0] = employee;

        uint256[] memory salaries = new uint256[](1);
        salaries[0] = EMPLOYEE_SALARY;

        vm.startPrank(employer);
        groupId = manager.createGroup("Tech Team", CYCLE_DURATION);

        usdc.approve(address(manager), type(uint256).max);
        manager.setUpPayroll(groupId, employees, salaries);
        vm.stopPrank();

        vm.prank(agentOperator);
        router.agentRebalance(employer, 1);
    }
}