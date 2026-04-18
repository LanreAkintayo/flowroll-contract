// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FlowrollCreditBase} from "../../base/FlowrollCreditBase.t.sol";
import {FlowrollCredit} from "../../../src/FlowrollCredit.sol";

contract FlowrollCreditTest is FlowrollCreditBase {

    function test_requestSalary_succeeds() public {
        _setupStandardPayroll();

        uint256 advanceAmount = 1_000e6; 
        uint256 expectedFee = (advanceAmount * CREDIT_FEE_BPS) / 10_000;
        uint256 expectedNet = advanceAmount - expectedFee;

        uint256 employeeBalBefore = usdc.balanceOf(employee);

        vm.prank(employee);
        credit.requestSalary(advanceAmount);

        assertEq(usdc.balanceOf(employee), employeeBalBefore + expectedNet);
        assertEq(credit.getEmployeeDebt(employee), advanceAmount);
        assertEq(credit.totalCollectedFees(), expectedFee);
    }

    function test_requestSalary_revertsExceedsMaxAdvance() public {
        _setupStandardPayroll();

        uint256 tooMuch = (EMPLOYEE_SALARY * 9000) / 10000; 

        vm.prank(employee);
        vm.expectRevert(FlowrollCredit.FlowrollCredit__ExceedsMaxAdvance.selector);
        credit.requestSalary(tooMuch);
    }

    function test_repayDebt_succeeds() public {
        _setupStandardPayroll();

        uint256 advanceAmount = 1_000e6;
        vm.prank(employee);
        credit.requestSalary(advanceAmount);

        vm.startPrank(employee);
        usdc.approve(address(credit), advanceAmount);

        credit.repayDebt(employee, advanceAmount);
        vm.stopPrank();

        assertEq(credit.getEmployeeDebt(employee), 0);
    }

    function test_fullLifecycle_AdvanceAndDisburse() public {
        _setupStandardPayroll();

        uint256 advanceAmount = 2_000e6; 
        uint256 fee = (advanceAmount * CREDIT_FEE_BPS) / 10000;
        uint256 netAdvance = advanceAmount - fee;

        uint256 initialEmployeeBal = usdc.balanceOf(employee);

        vm.prank(employee);
        credit.requestSalary(advanceAmount);

        assertEq(usdc.balanceOf(employee), initialEmployeeBal + netAdvance);
        assertEq(credit.getEmployeeDebt(employee), advanceAmount);

        vm.warp(block.timestamp + CYCLE_DURATION + 20 seconds);

        vm.prank(agentOperator);
        router.agentRebalance(employer, 1);

        uint256 pendingSalary = manager.getEmployeeTotalPendingSalary(employee);

        assertEq(pendingSalary, 0);
        assertEq(credit.getEmployeeDebt(employee), 0);
    }

    function test_withdrawFees_onlyOwner() public {
        _setupStandardPayroll();

        vm.prank(employee);
        credit.requestSalary(1_000e6);

        uint256 collectedFees = credit.totalCollectedFees();
        assertGt(collectedFees, 0);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", stranger));
        credit.withdrawFees();

        uint256 ownerBalBefore = usdc.balanceOf(owner);
        vm.prank(owner);
        credit.withdrawFees();

        assertEq(usdc.balanceOf(owner), ownerBalBefore + collectedFees);
        assertEq(credit.totalCollectedFees(), 0);
    }
}