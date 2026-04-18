// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {YieldRouterBase} from "../../base/YieldRouterBase.t.sol";
import {YieldRouter} from "../../../src/YieldRouter.sol";

contract YieldRouterScoringTest is YieldRouterBase {

    uint256 internal constant IDLE_AMOUNT = 10_000e6; // well below 1M TVL — no liq penalty


    // =========================================================================
    // ZERO-SCORE GATES
    // =========================================================================

    function test_scorePool_returnsZero_inactivePool() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        vm.prank(owner);
        router.deactivatePool(0);

        assertEq(router.scorePool(0, IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med), 0);
    }

    function test_scorePool_returnsZero_apyBelowGlobalFloor() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        // Global floor = 200. Per-pool floor = 500. Set to 199 — below both.
        vm.prank(owner);
        stablePool.setApyBps(199);

        assertEq(router.scorePool(0, IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med), 0);
    }

    function test_scorePool_returnsZero_apyBelowPerPoolOverride() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        // Per-pool floor = 500. APY = 300 — above global (200) but below override.
        vm.prank(owner);
        stablePool.setApyBps(300);

        assertEq(router.scorePool(0, IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med), 0);
    }

    function test_scorePool_nonZero_apyExactlyAtFloor() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        vm.prank(owner);
        stablePool.setApyBps(STABLE_MIN_APY); // exactly at floor — should pass

        assertGt(router.scorePool(0, IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med), 0);
    }

    function test_scorePool_nonZero_whenIdleAmountIsZero() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        // idleAmount = 0 → liqFactor defaults to SCALE — no penalty
        assertGt(router.scorePool(0, 0, TIER_0_TIME_LEFT, high, med), 0);
    }

    function test_scorePool_reverts_invalidPoolIndex() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        vm.expectRevert(YieldRouter.YieldRouter__InvalidPoolIndex.selector);
        router.scorePool(99, IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med);
    }

    // =========================================================================
    // LIQUIDITY FACTOR
    // =========================================================================

    function test_scorePool_liqFactor_noPenaltyWhenIdleBelowTvl() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        // IDLE_AMOUNT (10k) << INITIAL_TVL (1M) — liqFactor = SCALE, no penalty
        uint256 scoreBelow = router.scorePool(0, IDLE_AMOUNT,  TIER_0_TIME_LEFT, high, med);
        uint256 scoreEqual = router.scorePool(0, INITIAL_TVL,  TIER_0_TIME_LEFT, high, med);

        assertEq(scoreBelow, scoreEqual);
    }

    function test_scorePool_liqFactor_penalisedWhenIdleExceedsTvl() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        uint256 normalScore    = router.scorePool(0, IDLE_AMOUNT,      TIER_0_TIME_LEFT, high, med);
        uint256 penalisedScore = router.scorePool(0, INITIAL_TVL * 10, TIER_0_TIME_LEFT, high, med);

        assertGt(normalScore, penalisedScore);
    }

    function test_scorePool_liqFactor_heavierPenaltyAtHigherRatio() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        uint256 score10x  = router.scorePool(0, INITIAL_TVL * 10,  TIER_0_TIME_LEFT, high, med);
        uint256 score100x = router.scorePool(0, INITIAL_TVL * 100, TIER_0_TIME_LEFT, high, med);

        assertGt(score10x, score100x);
    }

    // =========================================================================
    // IL FACTOR
    // =========================================================================

    function test_scorePool_ilFactor_stableScoresHigherThanVolatile_sameApy() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        vm.startPrank(owner);
        stablePool.setApyBps(1_000);
        volatilePool.setApyBps(1_000);
        vm.stopPrank();

        uint256 stableScore   = router.scorePool(0, IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med);
        uint256 volatileScore = router.scorePool(1, IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med);

        assertGt(stableScore, volatileScore);
    }

    function test_scorePool_ilFactor_volatilePenaltyIs30pct() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        vm.startPrank(owner);
        stablePool.setApyBps(1_000);
        volatilePool.setApyBps(1_000);
        vm.stopPrank();

        uint256 stableScore   = router.scorePool(0, IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med);
        uint256 volatileScore = router.scorePool(1, IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med);

        assertEq(volatileScore, (stableScore * 7_000) / 10_000);
    }

    // =========================================================================
    // RISK MULTIPLIER — CYCLE-RELATIVE THRESHOLDS
    // =========================================================================

    function test_scorePool_riskMult_highAboveHighThreshold() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        uint256 scoreHigh = router.scorePool(0, IDLE_AMOUNT, high + 1, high, med);
        uint256 scoreMed  = router.scorePool(0, IDLE_AMOUNT, med  + 1, high, med);

        assertGt(scoreHigh, scoreMed);
    }

    function test_scorePool_riskMult_medBetweenThresholds() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        uint256 scoreMed = router.scorePool(0, IDLE_AMOUNT, med + 1, high, med);
        uint256 scoreLow = router.scorePool(0, IDLE_AMOUNT, med - 1, high, med);

        assertGt(scoreMed, scoreLow);
    }

    function test_scorePool_riskMult_exactlyAtHighThreshold_isHigh() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        uint256 scoreAtHigh    = router.scorePool(0, IDLE_AMOUNT, high,     high, med);
        uint256 scoreJustBelow = router.scorePool(0, IDLE_AMOUNT, high - 1, high, med);

        assertGt(scoreAtHigh, scoreJustBelow);
    }

    function test_scorePool_riskMult_exactlyAtMedThreshold_isMed() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        uint256 scoreAtMed     = router.scorePool(0, IDLE_AMOUNT, med,     high, med);
        uint256 scoreJustBelow = router.scorePool(0, IDLE_AMOUNT, med - 1, high, med);

        assertGt(scoreAtMed, scoreJustBelow);
    }

    // =========================================================================
    // COMBINED — VOLATILE CAN BEAT STABLE
    // =========================================================================

    function test_scorePool_volatile_beatsStable_whenApyGapIsLarge() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        // Default: stable 8%, volatile 15%. 15% × 0.7 = 10.5% > 8%. Volatile wins.
        uint256 stableScore   = router.scorePool(0, IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med);
        uint256 volatileScore = router.scorePool(1, IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med);

        assertGt(volatileScore, stableScore);
    }

    function test_scorePool_stable_beatsVolatile_whenApyGapIsNarrow() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        // 1100 × 0.7 = 770 effective < 1000 stable — stable wins
        vm.startPrank(owner);
        stablePool.setApyBps(1_000);
        volatilePool.setApyBps(1_100);
        vm.stopPrank();

        uint256 stableScore   = router.scorePool(0, IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med);
        uint256 volatileScore = router.scorePool(1, IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med);

        assertGt(stableScore, volatileScore);
    }

    // =========================================================================
    // findBestPool
    // =========================================================================

    function test_findBestPool_returnsNoPool_whenAllInactive() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        vm.startPrank(owner);
        router.deactivatePool(0);
        router.deactivatePool(1);
        vm.stopPrank();

        (uint256 bestIdx, uint256 bestScore) = router.findBestPool(IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med);

        assertEq(bestIdx,   router.NO_POOL());
        assertEq(bestScore, 0);
    }

    function test_findBestPool_returnsNoPool_whenAllBelowApyFloor() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        vm.startPrank(owner);
        stablePool.setApyBps(100);
        volatilePool.setApyBps(100);
        vm.stopPrank();

        (uint256 bestIdx, uint256 bestScore) = router.findBestPool(IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med);

        assertEq(bestIdx,   router.NO_POOL());
        assertEq(bestScore, 0);
    }

    function test_findBestPool_returnsSingleValidPool() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        vm.prank(owner);
        router.deactivatePool(1);

        (uint256 bestIdx,) = router.findBestPool(IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med);
        assertEq(bestIdx, 0);
    }

    function test_findBestPool_returnsHigherScoringPool() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        (uint256 bestIdx,) = router.findBestPool(IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med);
        assertEq(bestIdx, 1); // volatile wins by default
    }

    function test_findBestPool_updatesWhenBestIsDeactivated() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        vm.prank(owner);
        router.deactivatePool(1);

        (uint256 bestIdx,) = router.findBestPool(IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med);
        assertEq(bestIdx, 0);
    }

    function test_findBestPool_scoreMatchesDirectScorePoolCall() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        (uint256 bestIdx, uint256 bestScore) = router.findBestPool(IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med);
        uint256 directScore = router.scorePool(bestIdx, IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med);

        assertEq(bestScore, directScore);
    }

    // =========================================================================
    // findWorstAllocatedPool
    // =========================================================================

    function test_findWorstAllocatedPool_returnsNoPool_noAllocations() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        (uint256 worstIdx,) = router.findWorstAllocatedPool(employer, 1, IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med);
        assertEq(worstIdx, router.NO_POOL());
    }

    function test_findWorstAllocatedPool_returnsSingleAllocation() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        _rebalance(employer, 1);

        uint256 stableShares   = router.poolAllocations(employer, 1, 0);
        uint256 allocatedIdx   = stableShares > 0 ? 0 : 1;

        (uint256 worstIdx,) = router.findWorstAllocatedPool(employer, 1, IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med);
        assertEq(worstIdx, allocatedIdx);
    }

    function test_findWorstAllocatedPool_returnsLowerScoringPool() public {
        _startCycle();
        (uint256 high, uint256 med) = _riskThresholds(1);

        _rebalance(employer, 1); // deploys to volatile (wins by default)

        // Flip scores — stable now wins, volatile becomes worst
        vm.startPrank(owner);
        stablePool.setApyBps(3_000);
        volatilePool.setApyBps(600);
        vm.stopPrank();

        _rebalance(employer, 1); // moves from volatile to stable

        // Only stable allocated — worst = only allocation = index 0
        (uint256 worstIdx,) = router.findWorstAllocatedPool(employer, 1, IDLE_AMOUNT, TIER_0_TIME_LEFT, high, med);
        assertEq(worstIdx, 0);
    }
}
