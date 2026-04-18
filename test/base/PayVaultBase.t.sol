// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SharedBase} from "./SharedBase.t.sol";

/**
 * @title PayVaultBase
 * @dev Base test contract for PayVault logic. Handles employee balances and auto-save simulations.
 */
abstract contract PayVaultBase is SharedBase {
    uint256 internal constant SALARY_1 = 5_000e6;
    uint256 internal constant SALARY_2 = 4_000e6;
    uint256 internal constant TOTAL_PAYROLL = SALARY_1 + SALARY_2;

    uint256 internal constant CREDIT_AMOUNT = 1_000e6;
    uint256 internal constant SAVE_DURATION = 30 days;
    uint256 internal constant SAVE_PCT = 2_000;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(owner);
        usdc.mint(employee2, DEPOSIT_AMOUNT * 10);
        vm.stopPrank();

        vm.prank(address(dispatcher));
        usdc.approve(address(vault), type(uint256).max);

        vm.startPrank(employer);
        manager.createGroup("Engineering", CYCLE_DURATION);
        usdc.approve(address(manager), type(uint256).max);
        manager.addEmployee(1, employee, SALARY_1);
        manager.addEmployee(1, employee2, SALARY_2);
        vm.stopPrank();
    }

    /// @dev Credits employee balance by executing a focused payroll cycle.
    function _credit(address emp, uint256 amount) internal {
        address[] memory employees = new address[](1);
        employees[0] = emp;

        uint256[] memory salaries = new uint256[](1);
        salaries[0] = amount;

        vm.startPrank(employer);
        uint256 groupId = manager.createGroup("Tech Team", CYCLE_DURATION);
        usdc.approve(address(manager), DEPOSIT_AMOUNT);
        uint256 cycleId = manager.setUpPayroll(groupId, employees, salaries);
        vm.stopPrank();

        uint256 payday = router.getCycle(employer, cycleId).payDay;
        vm.warp(payday);

        vm.prank(agentOperator);
        router.agentRebalance(employer, cycleId);
    }

    /// @dev Executes a full payroll cycle with optional yield simulation.
    function _runPayrollCycle(uint256 yieldAmount) internal returns (uint256 cycleId) {
        cycleId = _setupPayroll(employer);

        vm.prank(agentOperator);
        router.agentRebalance(employer, cycleId);

        if (yieldAmount > 0) {
            vm.startPrank(owner);
            usdc.mint(owner, yieldAmount);
            usdc.approve(address(volatilePool), yieldAmount);
            volatilePool.simulateYield(yieldAmount);
            vm.stopPrank();
        }

        uint256 payday = router.getCycle(employer, cycleId).payDay;
        vm.warp(payday);

        vm.prank(agentOperator);
        router.agentRebalance(employer, cycleId);
    }

    /// @dev Initiates an auto-save cycle for an employee and returns the cycle identifier.
    function _startAutoSave(
        address emp,
        uint256 creditAmount,
        uint256 savePct,
        uint256 duration
    ) internal returns (uint256 cycleId) {
        _credit(emp, creditAmount);

        uint256 cyclesBefore = router.getCycleCount(emp);

        vm.prank(emp);
        vault.claimAndSave(creditAmount, savePct, duration);

        vm.prank(agentOperator);
        router.agentRebalance(emp, cyclesBefore + 1);

        cycleId = cyclesBefore + 1;
    }

    /// @dev Warps to payday and settles an active auto-save cycle.
    function _settleAutoSave(address emp, uint256 cycleId) internal {
        uint256 payday = router.getCycle(emp, cycleId).payDay;
        vm.warp(payday);

        vm.prank(agentOperator);
        router.agentRebalance(emp, cycleId);
    }
}