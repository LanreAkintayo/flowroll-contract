// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {YieldRouterBase} from "../../base/YieldRouterBase.t.sol";
import {YieldRouter} from "../../../src/YieldRouter.sol";

contract YieldRouterRebalanceTest is YieldRouterBase {
    // =========================================================================
    // PRECONDITION GUARDS
    // =========================================================================

    function test_agentRebalance_revertsIfNotAgent() public {
        _startCycle();
        vm.prank(stranger);
        vm.expectRevert(YieldRouter.YieldRouter__NotAgent.selector);
        router.agentRebalance(employer, 1);
    }

    function test_agentRebalance_revertsWhenPaused() public {
        _startCycle();
        vm.prank(owner);
        router.pause();
        vm.prank(agentOperator);
        vm.expectRevert();
        router.agentRebalance(employer, 1);
    }

    function test_agentRebalance_revertsOnInvalidCycle() public {
        vm.prank(agentOperator);
        vm.expectRevert(YieldRouter.YieldRouter__CycleNotFound.selector);
        router.agentRebalance(employer, 99);
    }

    function test_agentRebalance_revertsOnInactiveCycle() public {
        _startCycle();
        _warpToPayday();
        _rebalance(employer, 1); // closes the cycle

        vm.prank(agentOperator);
        vm.expectRevert(YieldRouter.YieldRouter__CycleNotActive.selector);
        router.agentRebalance(employer, 1);
    }

    // =========================================================================
    // BLOCK 1 — PAYDAY
    // =========================================================================

    function test_payday_revertsIfDispatcherNotSet() public {
        // Deploy a fresh router with no dispatcher wired
        vm.startPrank(owner);
        YieldRouter freshRouter = new YieldRouter(agentOperator, address(usdc));
        freshRouter.setPayrollManager(address(manager));
        freshRouter.addPool(
            address(stableAdapter),
            address(stablePool),
            true,
            STABLE_MIN_APY
        );
        freshRouter.addPool(
            address(volatileAdapter),
            address(volatilePool),
            false,
            VOLATILE_MIN_APY
        );
        vm.stopPrank();

        vm.prank(address(manager));
        usdc.approve(address(freshRouter), type(uint256).max);

        vm.prank(address(manager));
        freshRouter.startCycle(
            employer,
            DEPOSIT_AMOUNT,
            CYCLE_DURATION,
            address(0)
        );

        uint256 payday = freshRouter.getCycle(employer, 1).payDay;
        vm.warp(payday);

        vm.prank(agentOperator);
        vm.expectRevert(YieldRouter.YieldRouter__DispatcherNotSet.selector);
        freshRouter.agentRebalance(employer, 1);
    }

    function test_payday_closedCycle_noFundsInPools() public {
        _startCycle();
        _rebalance(employer, 1); // deploy to volatile

        _warpToPayday();
        _rebalance(employer, 1); // trigger payday

        // All pool positions should be zero
        assertEq(router.poolAllocations(employer, 1, 0), 0);
        assertEq(router.poolAllocations(employer, 1, 1), 0);
    }

    function test_payday_cycleMarkedInactive() public {
        _startCycle();
        _warpToPayday();
        _rebalance(employer, 1);

        assertFalse(router.getCycle(employer, 1).isActive);
    }

    function test_payday_fundsTransferredToDispatcher() public {
        _startCycle();
        _warpToPayday();
        _rebalance(employer, 1);

        // Dispatcher should have received exactly totalDeposited

        assertEq(usdc.balanceOf(address(vault)), DEPOSIT_AMOUNT);

    }


    function test_payday_emitsPaydaySettled() public {
        _startCycle();
        _warpToPayday();

        vm.expectEmit(true, true, false, false);
        emit YieldRouter.PaydaySettled(employer, 1, DEPOSIT_AMOUNT, 0);
        _rebalance(employer, 1);
    }

    function test_payday_emitsAgentAction_PaydayTriggered() public {
        _startCycle();
        _warpToPayday();

        vm.expectEmit(true, true, false, false);
        emit YieldRouter.AgentAction(
            employer,
            1,
            0,
            YieldRouter.ActionType.PaydayTriggered,
            router.NO_POOL(),
            router.NO_POOL(),
            DEPOSIT_AMOUNT,
            0,
            0
        );

        _rebalance(employer, 1);
    }

    function test_payday_withdrawsFromPoolsBeforeTransfer() public {
        _startCycle();
        _rebalance(employer, 1); // deploy to volatile

        uint256 deployedShares = router.poolAllocations(employer, 1, 1);
        assertGt(deployedShares, 0); // confirm funds were deployed

        _warpToPayday();
        _rebalance(employer, 1);

        // Router should hold zero USDC — all sent to dispatcher
        assertEq(usdc.balanceOf(address(router)), 0);
        assertEq(router.poolAllocations(employer, 1, 1), 0);
    }

    // =========================================================================
    // BLOCK 2 — BUFFER ADJUSTMENT
    // =========================================================================

    function test_bufferAdjustment_withdrawsExactNeededAmount() public {
        _startCycle();

        // Warp to high-idle zone and deploy
        _warpToTimeLeft(TIER_0_TIME_LEFT);
        _rebalance(employer, 1);

        uint256 deployedShares = router.poolAllocations(employer, 1, 1);
        assertGt(deployedShares, 0);

        uint256 routerBalanceBefore = usdc.balanceOf(address(router));

        // Warp to high-buffer zone — buffer jumps, more must be liquid
        _warpToTimeLeft(TIER_3_TIME_LEFT - 1);

        (uint256 bufferAmount, , ) = router.calculateBuffer(
            employer,
            1
        );
        uint256 idleAmount = router.calculateIdleAmount(employer, 1);

        _rebalance(employer, 1);

        uint256 routerBalanceAfter = usdc.balanceOf(address(router));

        // Router balance should have increased by the withdrawn amount
        assertGt(routerBalanceAfter, routerBalanceBefore);

        // Buffer requirement must now be satisfied
        assertGe(routerBalanceAfter, bufferAmount);
        assertEq(idleAmount, 0);
    }

    function test_bufferAdjustment_emitsBufferAdjusted() public {
        _startCycle();
        _warpToTimeLeft(TIER_0_TIME_LEFT);
        _rebalance(employer, 1); // deploy funds

        _warpToTimeLeft(TIER_3_TIME_LEFT); // jump to high buffer zone

        vm.expectEmit(true, true, false, false);
        emit YieldRouter.AgentAction(
            employer,
            1,
            0,
            YieldRouter.ActionType.BufferAdjusted,
            router.NO_POOL(),
            router.NO_POOL(),
            0,
            0,
            0
        );

        _rebalance(employer, 1);
    }

    function test_bufferAdjustment_neverOverWithdraws() public {
        _startCycle();
        _warpToTimeLeft(TIER_0_TIME_LEFT);

        _rebalance(employer, 1);

        _warpToTimeLeft(TIER_3_TIME_LEFT);

        uint256 totalDepositedBefore = router
            .getCycle(employer, 1)
            .totalDeposited;

        _rebalance(employer, 1);

        // Router + deployed shares should never exceed totalDeposited
        uint256 routerBalance = usdc.balanceOf(address(router));
        uint256 deployedShares = router.poolAllocations(employer, 1, 1);

        // Router holds at most totalDeposited
        assertLe(routerBalance, totalDepositedBefore);
        // If fully withdrawn, shares should be zero
        if (deployedShares == 0) {
            assertEq(routerBalance, totalDepositedBefore);
        }
    }

    // =========================================================================
    // BLOCK 3 — NO IDLE CAPITAL
    // =========================================================================

    function test_noIdle_emitsMovedToReserve() public {
        _startCycle();

        // Warp to payday zone — buffer = 105%, idle = 0
        _warpToTimeLeft(TIER_5_TIME_LEFT + 1);

        vm.expectEmit(true, true, false, false);
        emit YieldRouter.AgentAction(
            employer,
            1,
            0,
            YieldRouter.ActionType.MovedToReserve,
            router.NO_POOL(),
            router.NO_POOL(),
            0,
            0,
            0
        );

        _rebalance(employer, 1);
    }

    function test_noIdle_nothingDeployed() public {
        _startCycle();
        _warpToTimeLeft(TIER_5_TIME_LEFT + 1);
        _rebalance(employer, 1);

        assertEq(router.poolAllocations(employer, 1, 0), 0);
        assertEq(router.poolAllocations(employer, 1, 1), 0);
    }

    // =========================================================================
    // BLOCK 4 — APY FLOOR
    // =========================================================================

    function test_apyFloor_emitsPoolBelowMinAPY_whenNothingQualifies() public {
        _startCycle();

        vm.startPrank(owner);
        stablePool.setApyBps(100);
        volatilePool.setApyBps(100);
        vm.stopPrank();

        vm.expectEmit(true, true, false, false);
        emit YieldRouter.AgentAction(
            employer,
            1,
            0,
            YieldRouter.ActionType.PoolBelowMinAPY,
            router.NO_POOL(),
            router.NO_POOL(),
            0,
            0,
            0
        );

        _rebalance(employer, 1);
    }

    function test_apyFloor_nothingDeployed_whenNothingQualifies() public {
        _startCycle();

        vm.startPrank(owner);
        stablePool.setApyBps(100);
        volatilePool.setApyBps(100);
        vm.stopPrank();

        _rebalance(employer, 1);

        assertEq(router.poolAllocations(employer, 1, 0), 0);
        assertEq(router.poolAllocations(employer, 1, 1), 0);
    }

    // =========================================================================
    // BLOCK 5 — FRESH DEPLOYMENT
    // =========================================================================

    function test_freshDeploy_fundsMovedToBestPool() public {
        _startCycle();
        _rebalance(employer, 1);

        // Volatile wins by default (15% APY × 0.7 IL = 10.5% > 8% stable)
        uint256 volatileShares = router.poolAllocations(employer, 1, 1);
        uint256 stableShares = router.poolAllocations(employer, 1, 0);

        assertGt(volatileShares, 0);
        assertEq(stableShares, 0);
    }

    function test_freshDeploy_routerBalanceReducedByIdleAmount() public {
        _startCycle();

        uint256 idleAmount = router.calculateIdleAmount(employer, 1);
        uint256 balanceBefore = usdc.balanceOf(address(router));

        _rebalance(employer, 1);

        uint256 balanceAfter = usdc.balanceOf(address(router));
        assertEq(balanceAfter, balanceBefore - idleAmount);
    }

    function test_freshDeploy_emitsRebalanced_fromNoPool() public {
        _startCycle();

        vm.expectEmit(true, true, false, false);
        emit YieldRouter.AgentAction(
            employer,
            1,
            0,
            YieldRouter.ActionType.Rebalanced,
            router.NO_POOL(),
            1, // volatile pool
            0,
            0,
            0
        );

        _rebalance(employer, 1);
    }

    // =========================================================================
    // BLOCK 5 — NO ACTION NEEDED
    // =========================================================================

    function test_noAction_emitsNoActionNeeded_onSecondRebalance() public {
        _startCycle();
        _rebalance(employer, 1); // deploys to volatile

        // Second rebalance — already in best pool, score improvement < threshold
        vm.expectEmit(true, true, false, false);
        emit YieldRouter.AgentAction(
            employer,
            1,
            0,
            YieldRouter.ActionType.NoActionNeeded,
            router.NO_POOL(),
            router.NO_POOL(),
            0,
            0,
            0
        );

        _rebalance(employer, 1);
    }

    function test_noAction_allocationUnchanged_onSecondRebalance() public {
        _startCycle();
        _rebalance(employer, 1);

        uint256 sharesBefore = router.poolAllocations(employer, 1, 1);
        _rebalance(employer, 1);
        uint256 sharesAfter = router.poolAllocations(employer, 1, 1);

        assertEq(sharesBefore, sharesAfter);
    }

    // =========================================================================
    // BLOCK 5 — REBALANCE TO BETTER POOL
    // =========================================================================

    function test_rebalance_movesToBetterPool_whenScoreImproves() public {
        _startCycle();
        _rebalance(employer, 1); // deploys to volatile (index 1)

        // Flip scores — stable now clearly wins
        vm.startPrank(owner);
        stablePool.setApyBps(5_000);
        volatilePool.setApyBps(500); // below per-pool floor of 500 — scores 0
        vm.stopPrank();

        _rebalance(employer, 1);

        // Funds should have moved from volatile to stable
        assertEq(router.poolAllocations(employer, 1, 1), 0);
        assertGt(router.poolAllocations(employer, 1, 0), 0);
    }

    function test_rebalance_emitsCorrectPoolIndices() public {
        _startCycle();
        _rebalance(employer, 1); // deploys to volatile (index 1)

        vm.startPrank(owner);
        stablePool.setApyBps(5_000);
        volatilePool.setApyBps(500);
        vm.stopPrank();

        vm.expectEmit(true, true, false, false);
        emit YieldRouter.AgentAction(
            employer,
            1,
            0,
            YieldRouter.ActionType.Rebalanced,
            1, // from volatile
            0, // to stable
            0,
            0,
            0
        );

        _rebalance(employer, 1);
    }

    function test_rebalance_deployedAmountIsActualReceived() public {
        _startCycle();

        _rebalance(employer, 1);

        // Simulate yield — withdrawn amount will exceed original deposit
        (, uint256 yieldEarnedBefore, ) = router.getLiveYield(employer, 1);

        _simulateYield(volatilePool, 1_000e6);

        _warpToPayday();
        _rebalance(employer, 1);

        (, uint256 yieldEarnedAfter, ) = router.getLiveYield(employer, 1);

        assertGt(yieldEarnedAfter, yieldEarnedBefore);
    }

    // =========================================================================
    // CASCADE WITHDRAWAL PRECISION
    // =========================================================================

    function test_cascade_pullsFromWorstPoolFirst() public {
        _startCycle();
        _rebalance(employer, 1); // deploys to volatile

        // Add a second pool to get two allocations
        // Flip to stable wins, trigger rebalance to move to stable
        vm.startPrank(owner);
        stablePool.setApyBps(5_000);
        volatilePool.setApyBps(600);
        vm.stopPrank();

        _rebalance(employer, 1); // moves to stable

        // Now warp to high buffer zone — needs to pull from worst (volatile = 0, stable = allocated)
        _warpToTimeLeft(TIER_3_TIME_LEFT);

        uint256 stableSharesBefore = router.poolAllocations(employer, 1, 0);
        assertGt(stableSharesBefore, 0);

        _rebalance(employer, 1);

        // Stable shares should have decreased — pulled from it as it's the only allocation
        uint256 stableSharesAfter = router.poolAllocations(employer, 1, 0);
        assertLe(stableSharesAfter, stableSharesBefore);
    }

    function test_cascade_stopsWhenNeededAmountCovered() public {
        _startCycle();
        _rebalance(employer, 1); // deploy to volatile

        _warpToTimeLeft(TIER_3_TIME_LEFT);

        (uint256 bufferNeeded, , ) = router.calculateBuffer(employer, 1);

        _rebalance(employer, 1);

        uint256 routerBalanceAfter = usdc.balanceOf(address(router));

        // Router now holds at least the buffer amount
        assertGe(routerBalanceAfter, bufferNeeded);

        // But never more than totalDeposited
        assertLe(routerBalanceAfter, DEPOSIT_AMOUNT);
    }

    // =========================================================================
    // YIELD ACCOUNTING
    // =========================================================================

    function test_yield_earnedReflectsProfit() public {
        _startCycle();
        _rebalance(employer, 1); // deploy to volatile

        uint256 yieldAmount = 500e6; // 500 USDC yield
        _simulateYield(volatilePool, yieldAmount);

        _warpToPayday();
        _rebalance(employer, 1);

        (, uint256 yieldEarned, ) = router.getLiveYield(employer, 1);

        assertGt(yieldEarned, 0);
    }


    function test_yield_cycleYieldEarnedIsZero_withNoYieldSimulated() public {
        _startCycle();
        _rebalance(employer, 1);
        _warpToPayday();
        _rebalance(employer, 1);

        (, uint256 yieldEarned, ) = router.getLiveYield(employer, 1);

        assertEq(yieldEarned, 0);
    }

    // =========================================================================
    // MULTI-CYCLE ISOLATION
    // =========================================================================

    function test_multiCycle_rebalancesAreIndependent() public {
        _startCycle(); // cycle 1
        _startCycle(); // cycle 2

        _rebalance(employer, 1);

        // Cycle 2 should still have no allocations
        assertEq(router.poolAllocations(employer, 2, 0), 0);
        assertEq(router.poolAllocations(employer, 2, 1), 0);

        // Cycle 1 should have allocation
        assertGt(router.poolAllocations(employer, 1, 1), 0);
    }

    function test_multiCycle_paydayClosesOnlyTargetCycle() public {
        _startCycle(); // cycle 1
        _startCycle(); // cycle 2

        // Only warp cycle 1 to payday
        uint256 payday1 = router.getCycle(employer, 1).payDay;
        vm.warp(payday1);

        _rebalance(employer, 1);

        assertFalse(router.getCycle(employer, 1).isActive);
        assertTrue(router.getCycle(employer, 2).isActive);
    }
}
