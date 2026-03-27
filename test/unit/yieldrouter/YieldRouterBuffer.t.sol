// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {YieldRouterBase} from "../../base/YieldRouterBase.t.sol";
import {YieldRouter} from "../../../src/YieldRouter.sol";

contract YieldRouterBufferTest is YieldRouterBase {

    // =========================================================================
    // HAPPY PATH — ONE TEST PER TIER
    // =========================================================================

    function test_buffer_tier0_correctBps() public {
        _startCycle();
        _warpToTimeLeft(TIER_0_TIME_LEFT);

        (, uint256 bufferBps,) = router.calculateBuffer(employer, 1);
        assertEq(bufferBps, TIER_0_BPS);
    }

    function test_buffer_tier1_correctBps() public {
        _startCycle();
        _warpToTimeLeft(TIER_1_TIME_LEFT);

        (, uint256 bufferBps,) = router.calculateBuffer(employer, 1);
        assertEq(bufferBps, TIER_1_BPS);
    }

    // =========================================================================
    // BOUNDARY PRECISION — THREE POINTS PER THRESHOLD
    // Threshold: 70% of 30 days = 21 days
    // =========================================================================

    function test_buffer_threshold70pct_oneSecondAbove() public {
        _startCycle();
        _warpToTimeLeft(21 days + 1);

        (, uint256 bufferBps,) = router.calculateBuffer(employer, 1);
        assertEq(bufferBps, TIER_0_BPS); // still in tier 0
    }

    function test_buffer_threshold70pct_exactlyAt() public {
        _startCycle();
        _warpToTimeLeft(21 days);

        (, uint256 bufferBps,) = router.calculateBuffer(employer, 1);
        assertEq(bufferBps, TIER_0_BPS); // >= check, exactly at threshold = tier 0
    }

    function test_buffer_threshold70pct_oneSecondBelow() public {
        _startCycle();
        _warpToTimeLeft(21 days - 1);

        (, uint256 bufferBps,) = router.calculateBuffer(employer, 1);
        assertEq(bufferBps, TIER_1_BPS); // dropped to tier 1
    }

    // Threshold: 50% of 30 days = 15 days

    function test_buffer_threshold50pct_oneSecondAbove() public {
        _startCycle();
        _warpToTimeLeft(15 days + 1);

        (, uint256 bufferBps,) = router.calculateBuffer(employer, 1);
        assertEq(bufferBps, TIER_1_BPS);
    }

    function test_buffer_threshold50pct_exactlyAt() public {
        _startCycle();
        _warpToTimeLeft(15 days);

        (, uint256 bufferBps,) = router.calculateBuffer(employer, 1);
        assertEq(bufferBps, TIER_1_BPS);
    }

    function test_buffer_threshold50pct_oneSecondBelow() public {
        _startCycle();
        _warpToTimeLeft(15 days - 1);

        (, uint256 bufferBps,) = router.calculateBuffer(employer, 1);
        assertEq(bufferBps, TIER_2_BPS);
    }

    // Threshold: 30% of 30 days = 9 days

    function test_buffer_threshold30pct_oneSecondAbove() public {
        _startCycle();
        _warpToTimeLeft(9 days + 1);

        (, uint256 bufferBps,) = router.calculateBuffer(employer, 1);
        assertEq(bufferBps, TIER_2_BPS);
    }

    function test_buffer_threshold30pct_exactlyAt() public {
        _startCycle();
        _warpToTimeLeft(9 days);

        (, uint256 bufferBps,) = router.calculateBuffer(employer, 1);
        assertEq(bufferBps, TIER_2_BPS);
    }

    function test_buffer_threshold30pct_oneSecondBelow() public {
        _startCycle();
        _warpToTimeLeft(9 days - 1);

        (, uint256 bufferBps,) = router.calculateBuffer(employer, 1);
        assertEq(bufferBps, TIER_3_BPS);
    }

    // Threshold: 25% of 30 days = 7.5 days → 7 days (integer truncation)

    function test_buffer_threshold25pct_oneSecondAbove() public {
        _startCycle();
        _warpToTimeLeft(7 days + 1);

        (, uint256 bufferBps,) = router.calculateBuffer(employer, 1);
        assertEq(bufferBps, TIER_4_BPS);
    }

    function test_buffer_threshold25pct_exactlyAt() public {
        _startCycle();
        _warpToTimeLeft(7 days);

        (, uint256 bufferBps,) = router.calculateBuffer(employer, 1);
        assertEq(bufferBps, TIER_4_BPS);
    }

    function test_buffer_threshold25pct_oneSecondBelow() public {
        _startCycle();
        _warpToTimeLeft(7 days - 1);

        (, uint256 bufferBps,) = router.calculateBuffer(employer, 1);
        assertEq(bufferBps, TIER_4_BPS);
    }

    // Threshold: 10% of 30 days = 3 days

    function test_buffer_threshold10pct_oneSecondAbove() public {
        _startCycle();
        _warpToTimeLeft(3 days + 1);

        (, uint256 bufferBps,) = router.calculateBuffer(employer, 1);
        assertEq(bufferBps, TIER_4_BPS);
    }

    function test_buffer_threshold10pct_exactlyAt() public {
        _startCycle();
        _warpToTimeLeft(3 days);

        (, uint256 bufferBps,) = router.calculateBuffer(employer, 1);
        assertEq(bufferBps, TIER_4_BPS);
    }

    function test_buffer_threshold10pct_oneSecondBelow() public {
        _startCycle();
        _warpToTimeLeft(3 days - 1);

        (, uint256 bufferBps,) = router.calculateBuffer(employer, 1);
        assertEq(bufferBps, TIER_5_BPS);
    }

    // =========================================================================
    // BUFFER AMOUNT MATH
    // =========================================================================

    function test_bufferAmount_tier0_exactValue() public {
        _startCycle();
        _warpToTimeLeft(TIER_0_TIME_LEFT);

        // 5% of 50_000e6 = 2_500e6
        (uint256 bufferAmount,,) = router.calculateBuffer(employer, 1);
        assertEq(bufferAmount, (DEPOSIT_AMOUNT * TIER_0_BPS) / SCALE);
    }

    function test_bufferAmount_tier1_exactValue() public {
        _startCycle();
        _warpToTimeLeft(TIER_1_TIME_LEFT);

        // 10% of 50_000e6 = 5_000e6
        (uint256 bufferAmount,,) = router.calculateBuffer(employer, 1);
        assertEq(bufferAmount, (DEPOSIT_AMOUNT * TIER_1_BPS) / SCALE);
    }

    function test_bufferAmount_tier2_exactValue() public {
        _startCycle();
        _warpToTimeLeft(TIER_2_TIME_LEFT);

        // 15% of 50_000e6 = 7_500e6
        (uint256 bufferAmount,,) = router.calculateBuffer(employer, 1);
        assertEq(bufferAmount, (DEPOSIT_AMOUNT * TIER_2_BPS) / SCALE);
    }

    function test_bufferAmount_tier3_exactValue() public {
        _startCycle();
        _warpToTimeLeft(TIER_3_TIME_LEFT);

        // 40% of 50_000e6 = 20_000e6
        (uint256 bufferAmount,,) = router.calculateBuffer(employer, 1);
        assertEq(bufferAmount, (DEPOSIT_AMOUNT * TIER_3_BPS) / SCALE);
    }

    function test_bufferAmount_tier4_exactValue() public {
        _startCycle();
        _warpToTimeLeft(TIER_4_TIME_LEFT);

        // 80% of 50_000e6 = 40_000e6
        (uint256 bufferAmount,,) = router.calculateBuffer(employer, 1);
        assertEq(bufferAmount, (DEPOSIT_AMOUNT * TIER_4_BPS) / SCALE);
    }

    // =========================================================================
    // CAP AT totalDeposited
    // =========================================================================

    function test_bufferAmount_cappedAtTotalDeposited() public {
        _startCycle();
        _warpToTimeLeft(TIER_5_TIME_LEFT); // catch-all → 105%

        // 105% would exceed deposit — must be capped at exactly totalDeposited
        (uint256 bufferAmount,,) = router.calculateBuffer(employer, 1);
        assertEq(bufferAmount, DEPOSIT_AMOUNT);
    }

    function test_bufferAmount_neverExceedsTotalDeposited() public {
        _startCycle();
        _warpToTimeLeft(1); // 1 second left — deepest catch-all

        (uint256 bufferAmount,,) = router.calculateBuffer(employer, 1);
        assertLe(bufferAmount, DEPOSIT_AMOUNT);
    }

    // =========================================================================
    // PAYDAY AND PAST-PAYDAY
    // =========================================================================

    function test_buffer_atExactPayday_timeLeftIsZero() public {
        _startCycle();
        _warpToPayday();

        (uint256 bufferAmount,, uint256 timeLeft) = router.calculateBuffer(employer, 1);
        assertEq(timeLeft,     0);
        assertEq(bufferAmount, DEPOSIT_AMOUNT); // capped at 105%
    }

    function test_buffer_pastPayday_doesNotRevertOrUnderflow() public {
        _startCycle();
        uint256 payday = router.getCycle(employer, 1).payDay;
        vm.warp(payday + 7 days); // well past payday

        (uint256 bufferAmount,, uint256 timeLeft) = router.calculateBuffer(employer, 1);
        assertEq(timeLeft,     0);
        assertEq(bufferAmount, DEPOSIT_AMOUNT);
    }

    // =========================================================================
    // CONFIG SNAPSHOT ISOLATION
    // =========================================================================

    function test_buffer_configSnapshot_oldCycleUnaffectedByConfigChange() public {
        _startCycle(); // cycle 1 snapshots default config

        // Change global config to a completely different ladder
        uint256[] memory newPcts = new uint256[](3);
        newPcts[0] = 9_000; // 90%
        newPcts[1] = 5_000; // 50%
        newPcts[2] = 0; // 50%

        uint256[] memory newBps = new uint256[](3);
        newBps[0] =   100; // 1%
        newBps[1] =   200; // 2%
        newBps[2] = 10_500; // 105%

        vm.prank(owner);
        router.setBufferConfig(newPcts, newBps);

        // Old cycle must still use its snapshotted config
        _warpToTimeLeft(TIER_0_TIME_LEFT);
        (, uint256 bufferBps,) = router.calculateBuffer(employer, 1);
        assertEq(bufferBps, TIER_0_BPS); // original tier 0 bps, not 1%
    }

    function test_buffer_configSnapshot_newCycleUsesUpdatedConfig() public {
        _startCycle(); // cycle 1 — default config

        uint256[] memory newPcts = new uint256[](3);
        newPcts[0] = 9_000;
        newPcts[1] = 5_000;
        newPcts[2] = 0;

        uint256[] memory newBps = new uint256[](3);
        newBps[0] =   100;
        newBps[1] =   200;
        newBps[2] = 10_500;

        vm.prank(owner);
        router.setBufferConfig(newPcts, newBps);

        _startCycle(); // cycle 2 — new config

        // At 22 days left: 22/30 = 73% remaining → above 90% threshold? No → above 50%? Yes → tier 1 = 200 bps
        _warpToTimeLeft(TIER_0_TIME_LEFT);
        (, uint256 bufferBpsOld,) = router.calculateBuffer(employer, 1);
        (, uint256 bufferBpsNew,) = router.calculateBuffer(employer, 2);

        assertEq(bufferBpsOld, TIER_0_BPS); // cycle 1: original 500 bps
        assertNotEq(bufferBpsNew, TIER_0_BPS); // cycle 2: different config
    }

    // =========================================================================
    // calculateIdleAmount CONSISTENCY
    // =========================================================================

    function test_idleAmount_isExactComplementOfBuffer() public {
        _startCycle();
        _warpToTimeLeft(TIER_0_TIME_LEFT);

        (uint256 bufferAmount,,) = router.calculateBuffer(employer, 1);
        uint256 idleAmount       = router.calculateIdleAmount(employer, 1);

        assertEq(bufferAmount + idleAmount, DEPOSIT_AMOUNT);
    }

    function test_idleAmount_isZeroWhenBufferCapped() public {
        _startCycle();
        _warpToTimeLeft(TIER_5_TIME_LEFT); // 105% → fully capped

        uint256 idleAmount = router.calculateIdleAmount(employer, 1);
        assertEq(idleAmount, 0);
    }

    function test_idleAmount_neverUnderflows() public {
        _startCycle();
        _warpToPayday();

        // Should return 0, not underflow
        uint256 idleAmount = router.calculateIdleAmount(employer, 1);
        assertEq(idleAmount, 0);
    }

    // =========================================================================
    // SHORT CYCLE — VERIFY SCALING WORKS IN MINUTES
    // =========================================================================

    function test_buffer_shortCycle_tiersScaleCorrectly() public {
        uint256 shortDuration = 10 minutes;
        _startCycleWithDuration(shortDuration);

        // 70% of 10 minutes = 7 minutes
        uint256 payday = router.getCycle(employer, 1).payDay;
        vm.warp(payday - 7 minutes - 1); // just above 70% threshold

        (, uint256 bufferBps,) = router.calculateBuffer(employer, 1);
        assertEq(bufferBps, TIER_0_BPS); // tier 0 at 5%
    }

    function test_buffer_shortCycle_catchAllAtEnd() public {
        uint256 shortDuration = 10 minutes;
        _startCycleWithDuration(shortDuration);

        uint256 payday = router.getCycle(employer, 1).payDay;
        vm.warp(payday - 30 seconds); // deep in catch-all zone

        (uint256 bufferAmount,,) = router.calculateBuffer(employer, 1);
        assertEq(bufferAmount, DEPOSIT_AMOUNT); // capped
    }

    // =========================================================================
    // REVERTS
    // =========================================================================

    function test_calculateBuffer_revertsOnNonExistentCycle() public {
        vm.expectRevert(YieldRouter.YieldRouter__CycleNotFound.selector);
        router.calculateBuffer(employer, 1);
    }

    function test_calculateBuffer_revertsOnCycleIdZero() public {
        vm.expectRevert(YieldRouter.YieldRouter__CycleNotFound.selector);
        router.calculateBuffer(employer, 0);
    }
}
