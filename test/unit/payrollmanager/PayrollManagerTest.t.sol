// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PayrollManagerBase} from "../../base/PayrollManagerBase.t.sol";
import {PayrollManager} from "../../../src/PayrollManager.sol";
import {YieldRouter} from "../../../src/YieldRouter.sol";

contract PayrollManagerTest is PayrollManagerBase {
    // =========================================================================
    // REGISTRATION
    // =========================================================================

    function test_register_succeeds() public {
        vm.prank(employer);
        manager.registerEmployer();
        assertTrue(manager.isRegistered(employer));
    }

    function test_register_revertsIfAlreadyRegistered() public {
        vm.startPrank(employer);
        manager.registerEmployer();
        vm.expectRevert(
            PayrollManager.PayrollManager__AlreadyRegistered.selector
        );
        manager.registerEmployer();
        vm.stopPrank();
    }

    function test_unregistered_cannotCreateGroup() public {
        vm.prank(employer);
        vm.expectRevert(PayrollManager.PayrollManager__NotRegistered.selector);
        manager.createGroup("Engineering", CYCLE_DURATION);
    }

    // =========================================================================
    // GROUP MANAGEMENT
    // =========================================================================

    function test_createGroup_storesCorrectly() public {
        vm.startPrank(employer);
        manager.registerEmployer();
        uint256 groupId = manager.createGroup("Engineering", CYCLE_DURATION);
        vm.stopPrank();

        PayrollManager.PayrollGroup memory group = manager.getGroup(
            employer,
            groupId
        );

        assertEq(groupId, 1);
        assertEq(group.groupId, 1);
        assertEq(group.name, "Engineering");
        assertEq(group.totalPayroll, 0);
        assertEq(group.activeCycleId, 0);
        assertEq(group.cycleDuration, CYCLE_DURATION);
        assertTrue(group.exists);
    }

    function test_createGroup_incrementsGroupIdPerEmployer() public {
        vm.startPrank(employer);
        manager.registerEmployer();
        uint256 id1 = manager.createGroup("Engineering", CYCLE_DURATION);
        uint256 id2 = manager.createGroup("Sales", CYCLE_DURATION);
        uint256 id3 = manager.createGroup("Marketing", CYCLE_DURATION);
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(id3, 3);
    }

    function test_createGroup_twoEmployersHaveIndependentCounters() public {
        address employerB = makeAddr("employerB");

        vm.prank(employer);
        manager.registerEmployer();

        vm.prank(employerB);
        manager.registerEmployer();

        vm.prank(employer);
        uint256 idA = manager.createGroup("Engineering", CYCLE_DURATION);

        vm.startPrank(employerB);
        manager.createGroup("Sales", CYCLE_DURATION);
        uint256 idB = manager.createGroup("Marketing", CYCLE_DURATION);
        vm.stopPrank();

        assertEq(idA, 1);
        assertEq(idB, 2); // employerB's second group
    }

    function test_setupPayroll() public {
        address employerB = makeAddr("employerB");

        address[] memory employees = new address[](2);
        employees[0] = employee;
        employees[1] = employee2;

        uint256[] memory salaries = new uint256[](2);
        salaries[0] = EMPLOYEE_SALARY;
        salaries[1] = EMPLOYEE_SALARY2;

        vm.startPrank(employer);
        uint256 groupId = manager.createGroup("Engineering", CYCLE_DURATION);

        // Then approve payrollmanager to spend your stuff on your behalf
        usdc.approve(address(manager), type(uint256).max);

        manager.setUpPayroll(groupId, employees, salaries);

        vm.stopPrank();

        vm.prank(agentOperator);
        router.agentRebalance(employer, 1);

        PayrollManager.PayrollGroup memory group = manager.getGroup(
            employer,
            groupId
        );
        YieldRouter.PayrollCycle memory cycle = router.getCycle(
            employer,
            group.activeCycleId
        );

        // Wrap to the end of pyday
        vm.warp(router.getCycle(employer, 1).payDay - 2000 seconds);
        vm.prank(agentOperator);
        router.agentRebalance(employer, 1);
        
        
        vm.warp(router.getCycle(employer, 1).payDay + 20 seconds);
        vm.prank(agentOperator);
        router.agentRebalance(employer, 1);

    }

    // =========================================================================
    // EMPLOYEE MANAGEMENT
    // =========================================================================

    function test_addEmployee_updatesTotalPayroll() public {
        uint256 groupId = _setupGroup();

        assertEq(manager.getTotalPayroll(employer, groupId), EMPLOYEE_SALARY);
    }

    function test_addEmployee_revertsOnZeroAddress() public {
        vm.startPrank(employer);
        manager.registerEmployer();
        uint256 groupId = manager.createGroup("Engineering", CYCLE_DURATION);

        vm.expectRevert(PayrollManager.PayrollManager__ZeroAddress.selector);
        manager.addEmployee(groupId, address(0), EMPLOYEE_SALARY);
        vm.stopPrank();
    }

    function test_addEmployee_revertsOnZeroSalary() public {
        vm.startPrank(employer);
        manager.registerEmployer();
        uint256 groupId = manager.createGroup("Engineering", CYCLE_DURATION);

        vm.expectRevert(PayrollManager.PayrollManager__ZeroSalary.selector);
        manager.addEmployee(groupId, employee, 0);
        vm.stopPrank();
    }

    function test_addEmployee_revertsOnDuplicate() public {
        uint256 groupId = _setupGroup();

        vm.prank(employer);
        vm.expectRevert(
            PayrollManager.PayrollManager__EmployeeAlreadyExists.selector
        );
        manager.addEmployee(groupId, employee, EMPLOYEE_SALARY);
    }

    function test_addEmployee_revertsWhenCycleActive() public {
        uint256 groupId = _setupGroupWithActiveCycle();

        vm.prank(employer);
        vm.expectRevert(
            PayrollManager.PayrollManager__GroupHasActiveCycle.selector
        );
        manager.addEmployee(groupId, employee2, EMPLOYEE_SALARY2);
    }

    function test_removeEmployee_updatesTotalPayroll() public {
        uint256 groupId = _setupGroup();

        vm.prank(employer);
        manager.removeEmployee(groupId, employee);

        assertEq(manager.getTotalPayroll(employer, groupId), 0);
    }

    function test_removeEmployee_revertsIfNotEmployee() public {
        uint256 groupId = _setupGroup();

        vm.prank(employer);
        vm.expectRevert(
            PayrollManager.PayrollManager__EmployeeNotFound.selector
        );
        manager.removeEmployee(groupId, employee2);
    }

    function test_removeEmployee_revertsWhenCycleActive() public {
        uint256 groupId = _setupGroupWithActiveCycle();

        vm.prank(employer);
        vm.expectRevert(
            PayrollManager.PayrollManager__GroupHasActiveCycle.selector
        );
        manager.removeEmployee(groupId, employee);
    }

    function test_updateSalary_updatesTotalPayrollDelta() public {
        uint256 groupId = _setupGroup();

        vm.prank(employer);
        manager.updateSalary(groupId, employee, 8_000e6);

        assertEq(manager.getTotalPayroll(employer, groupId), 8_000e6);
        assertEq(manager.getSalary(employer, groupId, employee), 8_000e6);
    }

    function test_updateSalary_revertsWhenCycleActive() public {
        uint256 groupId = _setupGroupWithActiveCycle();

        vm.prank(employer);
        vm.expectRevert(
            PayrollManager.PayrollManager__GroupHasActiveCycle.selector
        );
        manager.updateSalary(groupId, employee, 8_000e6);
    }

    // ─── Batch functions ─────────────────────────────────────────────────────

    function test_addEmployees_addsAllAndUpdatesTotalPayroll() public {
        vm.startPrank(employer);
        manager.registerEmployer();
        uint256 groupId = manager.createGroup("Engineering", CYCLE_DURATION);

        address[] memory emps = new address[](2);
        emps[0] = employee;
        emps[1] = employee2;

        uint256[] memory salaries = new uint256[](2);
        salaries[0] = EMPLOYEE_SALARY;
        salaries[1] = EMPLOYEE_SALARY2;

        manager.addEmployees(groupId, emps, salaries);
        vm.stopPrank();

        assertEq(
            manager.getTotalPayroll(employer, groupId),
            EMPLOYEE_SALARY + EMPLOYEE_SALARY2
        );
        assertEq(manager.getGroupEmployees(employer, groupId).length, 2);
    }

    function test_addEmployees_revertsOnLengthMismatch() public {
        vm.startPrank(employer);
        manager.registerEmployer();
        uint256 groupId = manager.createGroup("Engineering", CYCLE_DURATION);

        address[] memory emps = new address[](2);
        uint256[] memory salaries = new uint256[](1);

        vm.expectRevert(
            PayrollManager.PayrollManager__ArrayLengthMismatch.selector
        );
        manager.addEmployees(groupId, emps, salaries);
        vm.stopPrank();
    }

    function test_removeEmployees_removesAllAndUpdatesTotalPayroll() public {
        vm.startPrank(employer);
        manager.registerEmployer();
        uint256 groupId = manager.createGroup("Engineering", CYCLE_DURATION);

        address[] memory emps = new address[](2);
        emps[0] = employee;
        emps[1] = employee2;

        uint256[] memory salaries = new uint256[](2);
        salaries[0] = EMPLOYEE_SALARY;
        salaries[1] = EMPLOYEE_SALARY2;

        manager.addEmployees(groupId, emps, salaries);
        manager.removeEmployees(groupId, emps);
        vm.stopPrank();

        assertEq(manager.getTotalPayroll(employer, groupId), 0);
        assertEq(manager.getGroupEmployees(employer, groupId).length, 0);
    }

    function test_updateSalaries_updatesAllCorrectly() public {
        vm.startPrank(employer);
        manager.registerEmployer();
        uint256 groupId = manager.createGroup("Engineering", CYCLE_DURATION);

        address[] memory emps = new address[](2);
        emps[0] = employee;
        emps[1] = employee2;

        uint256[] memory salaries = new uint256[](2);
        salaries[0] = EMPLOYEE_SALARY;
        salaries[1] = EMPLOYEE_SALARY2;

        manager.addEmployees(groupId, emps, salaries);

        uint256[] memory newSalaries = new uint256[](2);
        newSalaries[0] = 7_000e6;
        newSalaries[1] = 4_000e6;

        manager.updateSalaries(groupId, emps, newSalaries);
        vm.stopPrank();

        assertEq(manager.getTotalPayroll(employer, groupId), 11_000e6);
        assertEq(manager.getSalary(employer, groupId, employee), 7_000e6);
        assertEq(manager.getSalary(employer, groupId, employee2), 4_000e6);
    }

    // =========================================================================
    // depositPayroll
    // =========================================================================

    function test_depositPayroll_pullsUSDCFromEmployer() public {
        uint256 groupId = _setupGroup();
        uint256 balBefore = usdc.balanceOf(employer);

        vm.prank(employer);
        manager.depositPayroll(groupId);

        assertEq(usdc.balanceOf(employer), balBefore - EMPLOYEE_SALARY);
    }

    function test_depositPayroll_managerHoldsZeroUSDCAfterDeposit() public {
        uint256 groupId = _setupGroup();

        vm.prank(employer);
        manager.depositPayroll(groupId);

        assertEq(usdc.balanceOf(address(manager)), 0);
    }

    function test_depositPayroll_setsActiveCycleId() public {
        uint256 groupId = _setupGroup();

        vm.prank(employer);
        manager.depositPayroll(groupId);

        PayrollManager.PayrollGroup memory group = manager.getGroup(
            employer,
            groupId
        );
        assertEq(group.activeCycleId, 1);
    }

    function test_depositPayroll_cycleExistsInYieldRouter() public {
        uint256 groupId = _setupGroupWithActiveCycle();

        PayrollManager.PayrollGroup memory group = manager.getGroup(
            employer,
            groupId
        );
        YieldRouter.PayrollCycle memory cycle = router.getCycle(
            employer,
            group.activeCycleId
        );

        assertEq(cycle.totalDeposited, EMPLOYEE_SALARY);
        assertTrue(cycle.isActive);
    }

    function test_depositPayroll_revertsIfAlreadyActive() public {
        uint256 groupId = _setupGroupWithActiveCycle();

        vm.prank(employer);
        vm.expectRevert(
            PayrollManager.PayrollManager__GroupHasActiveCycle.selector
        );
        manager.depositPayroll(groupId);
    }

    function test_depositPayroll_revertsIfNoEmployees() public {
        vm.startPrank(employer);
        manager.registerEmployer();
        uint256 groupId = manager.createGroup("Engineering", CYCLE_DURATION);

        vm.expectRevert(
            PayrollManager.PayrollManager__InsufficientPayroll.selector
        );
        manager.depositPayroll(groupId);
        vm.stopPrank();
    }

    function test_depositPayroll_revertsIfRouterNotSet() public {
        // Deploy fresh manager with no router wired
        vm.prank(owner);
        PayrollManager freshManager = new PayrollManager(
            address(usdc),
            feeRecipient,
            FEE_BPS
        );

        vm.startPrank(employer);
        freshManager.registerEmployer();
        uint256 groupId = freshManager.createGroup(
            "Engineering",
            CYCLE_DURATION
        );
        freshManager.addEmployee(groupId, employee, EMPLOYEE_SALARY);

        usdc.approve(address(freshManager), type(uint256).max);

        vm.expectRevert(PayrollManager.PayrollManager__RouterNotSet.selector);
        freshManager.depositPayroll(groupId);
        vm.stopPrank();
    }

    // =========================================================================
    // cancelCycle
    // =========================================================================

    function test_cancelCycle_returnsFullAmountToEmployer() public {
        uint256 groupId = _setupGroupWithActiveCycle();
        uint256 balBefore = usdc.balanceOf(employer);

        vm.prank(employer);
        manager.cancelCycle(groupId);

        assertEq(usdc.balanceOf(employer), balBefore + EMPLOYEE_SALARY);
    }

    function test_cancelCycle_resetsActiveCycleId() public {
        uint256 groupId = _setupGroupWithActiveCycle();

        vm.prank(employer);
        manager.cancelCycle(groupId);

        PayrollManager.PayrollGroup memory group = manager.getGroup(
            employer,
            groupId
        );
        assertEq(group.activeCycleId, 0);
    }

    function test_cancelCycle_groupAvailableForNewDepositAfterCancellation()
        public
    {
        uint256 groupId = _setupGroupWithActiveCycle();

        vm.prank(employer);
        manager.cancelCycle(groupId);

        // Should not revert — group is free again
        vm.prank(employer);
        manager.depositPayroll(groupId);
    }

    function test_cancelCycle_revertsIfNoActiveCycle() public {
        uint256 groupId = _setupGroup();

        vm.prank(employer);
        vm.expectRevert(PayrollManager.PayrollManager__NoActiveCycle.selector);
        manager.cancelCycle(groupId);
    }

    function test_cancelCycle_revertsIfFundsAlreadyDeployed() public {
        uint256 groupId = _setupGroupWithActiveCycle();

        // Agent rebalances — funds deployed to pool
        vm.prank(agentOperator);
        router.agentRebalance(employer, 1);

        vm.prank(employer);
        vm.expectRevert(YieldRouter.YieldRouter__CycleNotCancellable.selector);
        manager.cancelCycle(groupId);
    }

    // =========================================================================
    // SCHEDULE LOCK + LAZY RESET
    // =========================================================================

    function test_scheduleLock_allMutationsBlockedWhenCycleActive() public {
        uint256 groupId = _setupGroupWithActiveCycle();

        vm.startPrank(employer);

        vm.expectRevert(
            PayrollManager.PayrollManager__GroupHasActiveCycle.selector
        );
        manager.addEmployee(groupId, employee2, EMPLOYEE_SALARY2);

        vm.expectRevert(
            PayrollManager.PayrollManager__GroupHasActiveCycle.selector
        );
        manager.removeEmployee(groupId, employee);

        vm.expectRevert(
            PayrollManager.PayrollManager__GroupHasActiveCycle.selector
        );
        manager.updateSalary(groupId, employee, 8_000e6);

        vm.stopPrank();
    }

    function test_lazyReset_mutationsAllowedAfterCycleCloses() public {
        uint256 groupId = _setupGroupWithActiveCycle();

        // Warp to payday and let agent settle — dispatcher is wired, won't revert
        vm.warp(router.getCycle(employer, 1).payDay);
        vm.prank(agentOperator);
        router.agentRebalance(employer, 1);

        // Cycle is now closed in YieldRouter — _isGroupActive() detects stale state
        // and resets activeCycleId on next interaction
        vm.prank(employer);
        manager.addEmployee(groupId, employee2, EMPLOYEE_SALARY2);

        assertEq(
            manager.getSalary(employer, groupId, employee2),
            EMPLOYEE_SALARY2
        );
        assertEq(manager.getGroup(employer, groupId).activeCycleId, 0);
    }

    // =========================================================================
    // ACCESS CONTROL
    // =========================================================================

    function test_setYieldRouter_revertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        manager.setYieldRouter(stranger);
    }

    function test_setFeeRecipient_revertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        manager.setFeeRecipient(stranger);
    }

    function test_setFeeBps_revertsIfAboveMax() public {
        vm.prank(owner);
        vm.expectRevert(PayrollManager.PayrollManager__InvalidFeeBps.selector);
        manager.setFeeBps(2_001);
    }

    function test_pause_blocksAllEmployerActions() public {
        vm.prank(owner);
        manager.pause();

        vm.prank(employer);
        vm.expectRevert();
        manager.registerEmployer();
    }
}
