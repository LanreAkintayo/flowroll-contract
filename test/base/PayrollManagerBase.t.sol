// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SharedBase} from "./SharedBase.t.sol";

/**
 * @title PayrollManagerBase
 * @dev Deploys the full stack — PayrollManager wired to a real YieldRouter.
 * Real YieldRouter is used to exercise actual integration paths.
 */
abstract contract PayrollManagerBase is SharedBase {
    uint256 internal constant EMPLOYEE_SALARY2 = 3_000e6;

    function setUp() public virtual override {
        super.setUp();
    }

    /// @dev Register employer and create a group with one employee.
    function _setupGroup() internal returns (uint256 groupId) {
        vm.startPrank(employer);
        manager.registerEmployer();
        groupId = manager.createGroup("Engineering", CYCLE_DURATION);
        manager.addEmployee(groupId, employee, EMPLOYEE_SALARY);
        vm.stopPrank();
    }

    /// @dev Full setup + deposit payroll — group has active cycle after this.
    function _setupGroupWithActiveCycle() internal returns (uint256 groupId) {
        groupId = _setupGroup();
        vm.prank(employer);
        manager.depositPayroll(groupId);
    }
}