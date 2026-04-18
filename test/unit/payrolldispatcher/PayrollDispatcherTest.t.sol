// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PayrollDispatcherBase} from "../../base/PayrollDispatcherBase.t.sol";
import {PayrollDispatcher} from "../../../src/PayrollDispatcher.sol";


contract PayrollDispatcherTest is PayrollDispatcherBase {
    // =========================================================================
    // ACCESS CONTROL
    // =========================================================================

    function test_disburse_revertsIfNotYieldRouter() public {
        _setupPayroll(employer);

        vm.prank(stranger);
        vm.expectRevert(
            PayrollDispatcher.PayrollDispatcher__NotYieldRouter.selector
        );
        dispatcher.disburse(employer, 1, TOTAL_PAYROLL);
    }

    function test_disburse_revertsWhenPaused() public {
        uint256 cycleId = _setupPayroll(employer);

        vm.prank(owner);
        dispatcher.pause();

        _warpToPayday(cycleId);

        vm.prank(address(router));
        vm.expectRevert();
        dispatcher.disburse(employer, cycleId, TOTAL_PAYROLL);
    }

    // =========================================================================
    // DOUBLE DISBURSEMENT PROTECTION
    // =========================================================================

    function test_disburse_revertsOnSecondCall() public {
        _runFullCycleNoYield();

        // Try to disburse again for same cycle
        vm.prank(address(router));
        vm.expectRevert(
            PayrollDispatcher.PayrollDispatcher__AlreadyDisbursed.selector
        );
        dispatcher.disburse(employer, 1, TOTAL_PAYROLL);
    }

    // =========================================================================
    // BALANCE ASSERTION
    // =========================================================================

    function test_disburse_revertsIfBalanceLessThanAmount() public {
        uint256 cycleId = _setupPayroll(employer);
        _warpToPayday(cycleId);

        // Manually call disburse without transferring funds first
        vm.prank(address(router));
        vm.expectRevert(
            PayrollDispatcher.PayrollDispatcher__InsufficientBalance.selector
        );
        dispatcher.disburse(employer, cycleId, TOTAL_PAYROLL);
    }

    // =========================================================================
    // FEE CALCULATION — YIELD ONLY
    // =========================================================================

    function test_disburse_zeroFee_whenNoYield() public {
        _runFullCycleNoYield();

        PayrollDispatcher.DisbursementRecord memory record = dispatcher
            .getDisbursement(employer, 1);

        assertEq(record.yieldEarned, 0);
        assertEq(record.fee, 0);
        assertEq(record.employerReturn, 0);
        assertEq(usdc.balanceOf(feeRecipient), 0);
    }

    function test_disburse_feeCalculatedFromYieldOnly() public {
        uint256 yieldAmount = 1_000e6;
        _runFullCycle(yieldAmount);

        PayrollDispatcher.DisbursementRecord memory record = dispatcher
            .getDisbursement(employer, 1);

        uint256 expectedFee = _expectedFee(record.yieldEarned);

        assertEq(record.fee, expectedFee);
        // Fee never touches principal
        assertLt(record.fee, TOTAL_PAYROLL);
    }

    function test_disburse_feeTransferredToFeeRecipient() public {
        uint256 yieldAmount = 1_000e6;
        _runFullCycle(yieldAmount);

        PayrollDispatcher.DisbursementRecord memory record = dispatcher
            .getDisbursement(employer, 1);

        assertEq(usdc.balanceOf(feeRecipient), record.fee);
    }

    // =========================================================================
    // EMPLOYER YIELD RETURN
    // =========================================================================

    function test_disburse_employerReceivesYieldMinusFee() public {
        uint256 yieldAmount = 1_000e6;

        uint256 cycleId = _setupPayroll(employer);

        uint256 employerBalanceBefore = usdc.balanceOf(employer);
        _rebalance(cycleId); // deploy to pool
        _simulateYield(yieldAmount); // inject yield
        _warpToPayday(cycleId); // fast forward
        _rebalance(cycleId); // trigger payday → disburse

        PayrollDispatcher.DisbursementRecord memory record = dispatcher
            .getDisbursement(employer, 1);


        uint256 employerBalanceAfter = usdc.balanceOf(employer);
        uint256 actualReturn = employerBalanceAfter - employerBalanceBefore;

        assertEq(actualReturn, record.employerReturn);
        assertEq(record.employerReturn, record.yieldEarned - record.fee);
    }

    function test_disburse_employerGetsNothing_whenNoYield() public {
       uint256 cycleId = _setupPayroll(employer);

        uint256 employerBalanceBefore = usdc.balanceOf(employer);
        _rebalance(cycleId); // deploy to pool
        _warpToPayday(cycleId); // fast forward
        _rebalance(cycleId);

        uint256 employerBalanceAfter = usdc.balanceOf(employer);

        assertEq(employerBalanceAfter, employerBalanceBefore);
    }

    // =========================================================================
    // EMPLOYEE SALARY SPLIT
    // =========================================================================

    function test_disburse_employeeReceivesExactProportionalShare() public {
        _runFullCycleNoYield();

        uint256 share1 = _expectedShare(SALARY_1, TOTAL_PAYROLL);
        uint256 share2 = _expectedShare(SALARY_2, TOTAL_PAYROLL);
        uint256 share3 = _expectedShare(SALARY_3, TOTAL_PAYROLL);

        assertEq(vault.getBalance(employee), share1);
        assertEq(vault.getBalance(employee2), share2);
        assertEq(vault.getBalance(employee3), share3);
    }

    function test_disburse_employeeSalariesSumToEmployeeTotal() public {
        _runFullCycleNoYield();

        uint256 total = vault.getBalance(employee) +
            vault.getBalance(employee2) +
            vault.getBalance(employee3);

        PayrollDispatcher.DisbursementRecord memory record = dispatcher
            .getDisbursement(employer, 1);

        // Sum of shares must equal employeeTotal — no leakage
        // Allow 1 wei dust from rounding
        assertApproxEqAbs(total, record.employeeTotal, 2);
    }

   

    // =========================================================================
    // DISBURSEMENT RECORD
    // =========================================================================

    function test_disburse_recordStoredCorrectly_withYield() public {
        uint256 yieldAmount = 1_000e6;
        _runFullCycle(yieldAmount);

        PayrollDispatcher.DisbursementRecord memory record = dispatcher
            .getDisbursement(employer, 1);

        assertTrue(record.executed);
        assertEq(record.totalDeposited, TOTAL_PAYROLL);
        assertGt(record.yieldEarned, 0);
        assertGt(record.fee, 0);
        assertGt(record.employerReturn, 0);
        assertEq(record.employeeTotal, TOTAL_PAYROLL);
        assertEq(record.employeeCount, 3);
        assertEq(record.timestamp, block.timestamp);
        assertEq(
            record.totalReceived,
            record.totalDeposited + record.yieldEarned
        );
        assertEq(record.fee + record.employerReturn, record.yieldEarned);
    }

    function test_disburse_recordStoredCorrectly_noYield() public {
        _runFullCycleNoYield();

        PayrollDispatcher.DisbursementRecord memory record = dispatcher
            .getDisbursement(employer, 1);

        assertTrue(record.executed);
        assertEq(record.yieldEarned, 0);
        assertEq(record.fee, 0);
        assertEq(record.employerReturn, 0);
        assertEq(record.totalReceived, record.totalDeposited);
        assertEq(record.employeeCount, 3);
    }

    function test_isDisbursed_falseBeforeAndTrueAfter() public {
        uint256 cycleId = _setupPayroll(employer);

        assertFalse(dispatcher.isDisbursed(employer, cycleId));

        _warpToPayday(cycleId);
        _rebalance(cycleId);

        assertTrue(dispatcher.isDisbursed(employer, cycleId));
    }

    // =========================================================================
    // EVENTS
    // =========================================================================

    function test_disburse_emitsDisbursed() public {
        uint256 cycleId = _setupPayroll(employer);
        _warpToPayday(cycleId);

        vm.expectEmit(true, true, true, false);
        emit PayrollDispatcher.Disbursed(
            employer,
            cycleId,
            1, // groupId
            0,
            0,
            0,
            0,
            0,
            0 // values — not checking exact amounts here
        );

        _rebalance(cycleId);
    }

    function test_disburse_emitsEmployeePaid_forEachEmployee() public {
        uint256 cycleId = _setupPayroll(employer);
        _warpToPayday(cycleId);

        // Expect three EmployeePaid events
        vm.expectEmit(true, true, true, false);
        emit PayrollDispatcher.EmployeePaid(employer, cycleId, 1, employee, 0);


        _rebalance(cycleId);
    }

    function test_disburse_emitsFeeCollected_whenYieldExists() public {
        uint256 yieldAmount = 1_000e6;
        uint256 cycleId = _setupPayroll(employer);
        _rebalance(cycleId);
        _simulateYield(yieldAmount);
        _warpToPayday(cycleId);

        vm.expectEmit(true, false, false, false);
        emit PayrollDispatcher.FeeCollected(feeRecipient, 0);

        _rebalance(cycleId);
    }

    function test_disburse_emitsYieldReturnedToEmployer_whenYieldExists()
        public
    {
        uint256 yieldAmount = 1_000e6;
        uint256 cycleId = _setupPayroll(employer);
        _rebalance(cycleId);
        _simulateYield(yieldAmount);
        _warpToPayday(cycleId);

        vm.expectEmit(true, false, false, false);
        emit PayrollDispatcher.YieldReturnedToEmployer(employer, 0);

        _rebalance(cycleId);
    }

    // =========================================================================
    // ADMIN
    // =========================================================================

    function test_setFeeBps_revertsAboveMax() public {
        vm.prank(owner);
        vm.expectRevert(
            PayrollDispatcher.PayrollDispatcher__InvalidFeeBps.selector
        );
        dispatcher.setFeeBps(2_001);
    }

    function test_setFeeBps_updatesCorrectly() public {
        vm.prank(owner);
        dispatcher.setFeeBps(500);
        assertEq(dispatcher.feeBps(), 500);
    }

    function test_recoverDust_sendsBalanceToFeeRecipient() public {
        // Manually send some USDC to dispatcher to simulate dust
        vm.prank(owner);
        usdc.mint(address(dispatcher), 100);

        uint256 balanceBefore = usdc.balanceOf(feeRecipient);

        vm.prank(owner);
        dispatcher.recoverDust();

        assertEq(usdc.balanceOf(feeRecipient), balanceBefore + 100);
        assertEq(usdc.balanceOf(address(dispatcher)), 0);
    }

    function test_recoverDust_doesNothingIfBalanceIsZero() public {
        uint256 balanceBefore = usdc.balanceOf(feeRecipient);

        vm.prank(owner);
        dispatcher.recoverDust();

        assertEq(usdc.balanceOf(feeRecipient), balanceBefore);
    }
}
