// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PayVaultBase} from "../../base/PayVaultBase.t.sol";
import {PayVault} from "../../../src/PayVault.sol";
import {YieldRouter} from "../../../src/YieldRouter.sol"; //
import {console} from "forge-std/console.sol";

contract PayVaultTest is PayVaultBase {
    // =========================================================================
    // CREDIT
    // =========================================================================

    function test_credit_revertsIfNotDispatcher() public {
        vm.prank(stranger);
        vm.expectRevert(PayVault.PayVault__NotDispatcher.selector);
        vault.credit(employee, CREDIT_AMOUNT);
    }

    function test_credit_revertsOnZeroAmount() public {
        vm.prank(address(dispatcher));
        vm.expectRevert(PayVault.PayVault__ZeroAmount.selector);
        vault.credit(employee, 0);
    }

    function test_credit_revertsOnZeroAddress() public {
        vm.startPrank(owner);
        usdc.mint(address(dispatcher), CREDIT_AMOUNT);
        vm.stopPrank();

        vm.prank(address(dispatcher));
        vm.expectRevert(PayVault.PayVault__ZeroAddress.selector);
        vault.credit(address(0), CREDIT_AMOUNT);
    }

    function test_credit_increasesEmployeeBalance() public {
        _credit(employee, CREDIT_AMOUNT);
        assertEq(vault.getBalance(employee), CREDIT_AMOUNT);
    }

    function test_credit_incrementsTotalEmployeeBalances() public {
        _credit(employee, CREDIT_AMOUNT);
        assertEq(vault.totalEmployeeBalances(), CREDIT_AMOUNT);
    }

    function test_credit_accumulatesAcrossMultipleCalls() public {
        _credit(employee, CREDIT_AMOUNT);
        console.log(
            "Balance of the employee after the first credit: ",
            vault.getBalance(employee)
        );
        _credit(employee, CREDIT_AMOUNT);
        console.log(
            "Balance of the employee after the second credit: ",
            vault.getBalance(employee)
        );
        assertEq(vault.getBalance(employee), CREDIT_AMOUNT * 2);
        assertEq(vault.totalEmployeeBalances(), CREDIT_AMOUNT * 2);
    }


    // =========================================================================
    // CLAIM
    // =========================================================================

    function test_claim_revertsOnZeroAmount() public {
        _credit(employee, CREDIT_AMOUNT);

        vm.prank(employee);
        vm.expectRevert(PayVault.PayVault__ZeroAmount.selector);
        vault.claim(0);
    }

    function test_claim_revertsIfInsufficientBalance() public {
        _credit(employee, CREDIT_AMOUNT);

        vm.prank(employee);
        vm.expectRevert(PayVault.PayVault__InsufficientBalance.selector);
        vault.claim(CREDIT_AMOUNT + 1);
    }

    function test_claim_decreasesEmployeeBalance() public {
        _credit(employee, CREDIT_AMOUNT);
        uint256 claimAmount = 600e6;

        vm.prank(employee);
        vault.claim(claimAmount);

        assertEq(vault.getBalance(employee), CREDIT_AMOUNT - claimAmount);
    }

    function test_claim_transfersUSDCToEmployee() public {
        _credit(employee, CREDIT_AMOUNT);
        uint256 balanceBefore = usdc.balanceOf(employee);

        vm.prank(employee);
        vault.claim(CREDIT_AMOUNT);

        assertEq(usdc.balanceOf(employee), balanceBefore + CREDIT_AMOUNT);
    }

    function test_claim_decrementsTotalEmployeeBalances() public {
        _credit(employee, CREDIT_AMOUNT);

        vm.prank(employee);
        vault.claim(CREDIT_AMOUNT);

        assertEq(vault.totalEmployeeBalances(), 0);
    }

    function test_claim_emitsClaimed() public {
        _credit(employee, CREDIT_AMOUNT);

        vm.expectEmit(true, false, false, true);
        emit PayVault.Claimed(employee, CREDIT_AMOUNT, block.timestamp);

        vm.prank(employee);
        vault.claim(CREDIT_AMOUNT);
    }

    // =========================================================================
    // CLAIM AND SAVE
    // =========================================================================

    function test_claimAndSave_revertsOnZeroAmount() public {
        _credit(employee, CREDIT_AMOUNT);

        vm.prank(employee);
        vm.expectRevert(PayVault.PayVault__ZeroAmount.selector);
        vault.claimAndSave(0, SAVE_PCT, SAVE_DURATION);
    }

    function test_claimAndSave_revertsOnZeroSavePct() public {
        _credit(employee, CREDIT_AMOUNT);

        vm.prank(employee);
        vm.expectRevert(PayVault.PayVault__InvalidSavePct.selector);
        vault.claimAndSave(CREDIT_AMOUNT, 0, SAVE_DURATION);
    }

    function test_claimAndSave_revertsIfSavePctAboveMax() public {
        _credit(employee, CREDIT_AMOUNT);

        vm.prank(employee);
        vm.expectRevert(PayVault.PayVault__InvalidSavePct.selector);
        vault.claimAndSave(CREDIT_AMOUNT, 10_001, SAVE_DURATION);
    }

    function test_claimAndSave_revertsOnZeroDuration() public {
        _credit(employee, CREDIT_AMOUNT);

        vm.prank(employee);
        vm.expectRevert(PayVault.PayVault__ZeroDuration.selector);
        vault.claimAndSave(CREDIT_AMOUNT, SAVE_PCT, 0);
    }

    function test_claimAndSave_revertsIfInsufficientBalance() public {
        _credit(employee, CREDIT_AMOUNT);

        vm.prank(employee);
        vm.expectRevert(PayVault.PayVault__InsufficientBalance.selector);
        vault.claimAndSave(CREDIT_AMOUNT + 1, SAVE_PCT, SAVE_DURATION);
    }

    function test_claimAndSave_deductsFullAmountFromBalance() public {
        _credit(employee, CREDIT_AMOUNT);

        vm.prank(employee);
        vault.claimAndSave(CREDIT_AMOUNT, SAVE_PCT, SAVE_DURATION);

        assertEq(vault.getBalance(employee), 0);
    }

    function test_claimAndSave_decrementsTotalEmployeeBalances() public {
        _credit(employee, CREDIT_AMOUNT);

        vm.prank(employee);
        vault.claimAndSave(CREDIT_AMOUNT, SAVE_PCT, SAVE_DURATION);

        assertEq(vault.totalEmployeeBalances(), 0);
    }

    function test_claimAndSave_transfersRemainderToEmployee() public {
        _credit(employee, CREDIT_AMOUNT);

        uint256 savedAmount = (CREDIT_AMOUNT * SAVE_PCT) / SCALE;
        uint256 claimedAmount = CREDIT_AMOUNT - savedAmount;
        uint256 balanceBefore = usdc.balanceOf(employee);

        vm.prank(employee);
        vault.claimAndSave(CREDIT_AMOUNT, SAVE_PCT, SAVE_DURATION);

        assertEq(usdc.balanceOf(employee), balanceBefore + claimedAmount);
    }

    function test_claimAndSave_startsYieldRouterCycle() public {
        _credit(employee, CREDIT_AMOUNT);

        uint256 cyclesBefore = router.getCycleCount(employee);

        vm.prank(employee);
        vault.claimAndSave(CREDIT_AMOUNT, SAVE_PCT, SAVE_DURATION);

        assertEq(router.getCycleCount(employee), cyclesBefore + 1);
    }

    function test_claimAndSave_cycleStoredWithCorrectFields() public {
        _credit(employee, CREDIT_AMOUNT);
        uint256 savedAmount = (CREDIT_AMOUNT * SAVE_PCT) / SCALE;

        vm.prank(employee);
        vault.claimAndSave(CREDIT_AMOUNT, SAVE_PCT, SAVE_DURATION);

        PayVault.AutoSaveCycle memory cycle = vault.getAutoSaveCycle(
            employee,
            0
        );

        assertEq(cycle.cycleId, 1);
        assertEq(cycle.amountSaved, savedAmount);
        assertEq(cycle.duration, SAVE_DURATION);
        assertTrue(cycle.isActive);
    }

    function test_claimAndSave_vaultSetAsDispatcher() public {
        _credit(employee, CREDIT_AMOUNT);

        vm.prank(employee);
        vault.claimAndSave(CREDIT_AMOUNT, SAVE_PCT, SAVE_DURATION);

        // The cycle in YieldRouter must have PayVault as its dispatcher
        YieldRouter.PayrollCycle memory cycle = router.getCycle(employee, 1);
        assertEq(cycle.dispatcher, address(vault));
    }

    function test_claimAndSave_fullSavePct_noTransferToWallet() public {
        _credit(employee, CREDIT_AMOUNT);
        uint256 balanceBefore = usdc.balanceOf(employee);

        vm.prank(employee);
        vault.claimAndSave(CREDIT_AMOUNT, 10_000, SAVE_DURATION); // 100% save

        // Nothing transferred to wallet
        assertEq(usdc.balanceOf(employee), balanceBefore);
    }

    function test_claimAndSave_emitsAutoSaveStarted() public {
        _credit(employee, CREDIT_AMOUNT);

        uint256 savedAmount = (CREDIT_AMOUNT * SAVE_PCT) / SCALE;
        uint256 claimedAmount = CREDIT_AMOUNT - savedAmount;

        vm.expectEmit(true, true, false, true);
        emit PayVault.AutoSaveStarted(
            employee,
            1,
            savedAmount,
            claimedAmount,
            SAVE_DURATION,
            block.timestamp
        );

        vm.prank(employee);
        vault.claimAndSave(CREDIT_AMOUNT, SAVE_PCT, SAVE_DURATION);
    }

    // =========================================================================
    // DISBURSE — AUTO-SAVE PAYDAY
    // =========================================================================

    function test_disburse_revertsIfNotYieldRouter() public {
        vm.prank(stranger);
        vm.expectRevert(PayVault.PayVault__NotYieldRouter.selector);
        vault.disburse(employee, 1, CREDIT_AMOUNT);
    }

    function test_disburse_revertsOnZeroAmount() public {
        vm.prank(address(router));
        vm.expectRevert(PayVault.PayVault__ZeroAmount.selector);
        vault.disburse(employee, 1, 0);
    }

    function test_disburse_revertsIfAlreadySettled() public {
        uint256 cycleId = _startAutoSave(
            employee,
            CREDIT_AMOUNT,
            SAVE_PCT,
            SAVE_DURATION
        );
        _settleAutoSave(employee, cycleId);

        vm.prank(address(router));
        vm.expectRevert(PayVault.PayVault__AlreadyDisbursed.selector);
        vault.disburse(employee, cycleId, CREDIT_AMOUNT);
    }

    function test_disburse_revertsIfCycleNotFound() public {
        // Deposit some funds into payvault
        vm.startPrank(owner);
        usdc.mint(address(vault), CREDIT_AMOUNT + 1);
        vm.stopPrank();

        vm.prank(address(router));
        vm.expectRevert(PayVault.PayVault__CycleNotFound.selector);
        vault.disburse(employee, 999, CREDIT_AMOUNT);
    }

    function test_disburse_creditsNetAmountToBalance_noYield() public {
        uint256 cycleId = _startAutoSave(
            employee,
            CREDIT_AMOUNT,
            SAVE_PCT,
            SAVE_DURATION
        );
        uint256 savedAmount = (CREDIT_AMOUNT * SAVE_PCT) / SCALE;

        _settleAutoSave(employee, cycleId);

        // No yield — full principal credited back
        assertEq(vault.getBalance(employee), savedAmount);
    }

    function test_disburse_creditsNetAmountToBalance_withYield() public {
        uint256 cycleId = _startAutoSave(
            employee,
            CREDIT_AMOUNT,
            SAVE_PCT,
            SAVE_DURATION
        );
        uint256 savedAmount = (CREDIT_AMOUNT * SAVE_PCT) / SCALE;
        uint256 yieldAmount = 100e6;

        assertEq(vault.getBalance(employee), 0);

        // Simulate yield before payday
        _simulateYield(yieldAmount);

        _settleAutoSave(employee, cycleId);

        PayVault.AutoSaveCycle memory cycle = vault.getAutoSaveCycle(
            employee,
            0
        );

        // Balance should be greater than savedAmount due to yield
        assertGt(vault.getBalance(employee), savedAmount);

        // Cycle must be settled
        assertFalse(cycle.isActive);
    }

    function test_disburse_zeroFee_whenNoYield() public {
        uint256 cycleId = _startAutoSave(
            employee,
            CREDIT_AMOUNT,
            SAVE_PCT,
            SAVE_DURATION
        );
        uint256 feeRecipientBefore = usdc.balanceOf(feeRecipient);

        _settleAutoSave(employee, cycleId);

        // No yield means no fee
        assertEq(usdc.balanceOf(feeRecipient), feeRecipientBefore);
    }

    function test_disburse_feeTransferredToFeeRecipient_withYield() public {
        uint256 cycleId = _startAutoSave(
            employee,
            CREDIT_AMOUNT,
            SAVE_PCT,
            SAVE_DURATION
        );
        uint256 feeRecipientBefore = usdc.balanceOf(feeRecipient);

        _simulateYield(500e6);
        _settleAutoSave(employee, cycleId);

        assertGt(usdc.balanceOf(feeRecipient), feeRecipientBefore);
    }

    function test_disburse_marksCycleInactive() public {
        uint256 cycleId = _startAutoSave(
            employee,
            CREDIT_AMOUNT,
            SAVE_PCT,
            SAVE_DURATION
        );
        _settleAutoSave(employee, cycleId);

        PayVault.AutoSaveCycle memory cycle = vault.getAutoSaveCycle(
            employee,
            0
        );
        assertFalse(cycle.isActive);
    }

    function test_disburse_setsCycleSettledFlag() public {
        uint256 cycleId = _startAutoSave(
            employee,
            CREDIT_AMOUNT,
            SAVE_PCT,
            SAVE_DURATION
        );
        assertFalse(vault.isCycleSettled(employee, cycleId));

        _settleAutoSave(employee, cycleId);
        assertTrue(vault.isCycleSettled(employee, cycleId));
    }

    function test_disburse_incrementsTotalEmployeeBalances() public {
        uint256 cycleId = _startAutoSave(
            employee,
            CREDIT_AMOUNT,
            SAVE_PCT,
            SAVE_DURATION
        );
        uint256 savedAmount = (CREDIT_AMOUNT * SAVE_PCT) / SCALE;

        assertEq(vault.totalEmployeeBalances(), 0);

        _settleAutoSave(employee, cycleId);

        // totalEmployeeBalances should reflect net credited amount
        assertGe(vault.totalEmployeeBalances(), savedAmount);
    }

    function test_disburse_emitsAutoSaveSettled() public {
        uint256 cycleId = _startAutoSave(
            employee,
            CREDIT_AMOUNT,
            SAVE_PCT,
            SAVE_DURATION
        );

        vm.expectEmit(true, true, false, false);
        emit PayVault.AutoSaveSettled(employee, cycleId, 0, 0, 0, 0, 0);

        _settleAutoSave(employee, cycleId);
    }

    // =========================================================================
    // MULTIPLE AUTO-SAVE CYCLES
    // =========================================================================

    function test_multipleAutoSaveCycles_trackedIndependently() public {
        _credit(employee, CREDIT_AMOUNT * 2);

        vm.prank(employee);
        vault.claimAndSave(CREDIT_AMOUNT, SAVE_PCT, SAVE_DURATION);

        vm.prank(employee);
        vault.claimAndSave(CREDIT_AMOUNT, SAVE_PCT, SAVE_DURATION * 2);

        PayVault.AutoSaveCycle[] memory cycles = vault.getAutoSaveCycles(
            employee
        );

        assertEq(cycles.length, 2);
        assertEq(cycles[0].cycleId, 1);
        assertEq(cycles[1].cycleId, 2);
        assertEq(cycles[0].duration, SAVE_DURATION);
        assertEq(cycles[1].duration, SAVE_DURATION * 2);
        assertTrue(cycles[0].isActive);
        assertTrue(cycles[1].isActive);
    }

    function test_settlingOneCycle_doesNotAffectOther() public {
        _credit(employee, CREDIT_AMOUNT * 2);

        vm.prank(employee);
        vault.claimAndSave(CREDIT_AMOUNT, SAVE_PCT, SAVE_DURATION);

        vm.prank(employee);
        vault.claimAndSave(CREDIT_AMOUNT, SAVE_PCT, SAVE_DURATION * 2);

        // Settle cycle 1 only
        _settleAutoSave(employee, 1);

        PayVault.AutoSaveCycle[] memory cycles = vault.getAutoSaveCycles(
            employee
        );

        assertFalse(cycles[0].isActive); // cycle 1 settled
        assertTrue(cycles[1].isActive); // cycle 2 still active
    }

    // =========================================================================
    // FULL EMPLOYER → EMPLOYEE → AUTO-SAVE FLOW
    // =========================================================================

    function test_fullFlow_employerPayrollToAutoSaveToWithdraw() public {
        // Step 1 — run employer payroll cycle
        _runPayrollCycle(0);

        // Step 2 — employee has balance in PayVault
        uint256 balance = vault.getBalance(employee);
        assertGt(balance, 0);

        // Step 3 — employee starts auto-save
        uint256 cycleId = router.getCycleCount(employee) + 1;

        vm.prank(employee);
        vault.claimAndSave(balance, SAVE_PCT, SAVE_DURATION);

        // Step 4 — auto-save cycle matures
        _settleAutoSave(employee, cycleId);

        // Step 5 — employee has balance back in PayVault
        assertGt(vault.getBalance(employee), 0);

        // Step 6 — employee claims full balance
        uint256 finalBalance = vault.getBalance(employee);
        uint256 walletBefore = usdc.balanceOf(employee);

        vm.prank(employee);
        vault.claim(finalBalance);

        assertEq(usdc.balanceOf(employee), walletBefore + finalBalance);
        assertEq(vault.getBalance(employee), 0);
    }

    // =========================================================================
    // RECOVER DUST
    // =========================================================================

    function test_recoverDust_onlyRecoversDustAboveEmployeeBalances() public {
        _credit(employee, CREDIT_AMOUNT);

        // Manually send extra dust directly to vault
        vm.startPrank(owner);
        usdc.mint(address(vault), 100);
        vm.stopPrank();

        uint256 feeRecipientBefore = usdc.balanceOf(feeRecipient);

        vm.prank(owner);
        vault.recoverDust();

        // Only the 100 dust should be recovered — not CREDIT_AMOUNT
        assertEq(usdc.balanceOf(feeRecipient), feeRecipientBefore + 100);
        assertEq(vault.getBalance(employee), CREDIT_AMOUNT);
    }

    function test_recoverDust_doesNothingIfNoDust() public {
        _credit(employee, CREDIT_AMOUNT);

        uint256 feeRecipientBefore = usdc.balanceOf(feeRecipient);

        vm.prank(owner);
        vault.recoverDust();

        assertEq(usdc.balanceOf(feeRecipient), feeRecipientBefore);
    }

    // =========================================================================
    // ADMIN
    // =========================================================================

    function test_setFeeBps_revertsAboveMax() public {
        vm.prank(owner);
        vm.expectRevert(PayVault.PayVault__InvalidFeeBps.selector);
        vault.setFeeBps(2_001);
    }

    function test_setDispatcher_revertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(PayVault.PayVault__ZeroAddress.selector);
        vault.setDispatcher(address(0));
    }

    function test_setYieldRouter_revertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(PayVault.PayVault__ZeroAddress.selector);
        vault.setYieldRouter(address(0));
    }
}
