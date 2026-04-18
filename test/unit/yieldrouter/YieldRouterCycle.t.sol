// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {YieldRouter} from "../../../src/YieldRouter.sol";
import {YieldRouterBase} from "../../base/YieldRouterBase.t.sol";

contract YieldRouterCycle is YieldRouterBase {
    // =========================================================================
    // CYCLE LIFECYCLE
    // =========================================================================

    //  startCycle: input validation 

    function test_startCycle_revertsOnZeroDeposit() public {
        vm.prank(address(manager));
        vm.expectRevert(YieldRouter.YieldRouter__ZeroDeposit.selector);
        router.startCycle(employer, 0, CYCLE_DURATION, address(dispatcher));
    }

    function test_startCycle_revertsOnZeroDuration() public {
        vm.prank(address(manager));
        vm.expectRevert(YieldRouter.YieldRouter__ZeroDuration.selector);
        router.startCycle(employer, DEPOSIT_AMOUNT, 0, address(dispatcher));
    }

    //  startCycle: state correctness 

    function test_startCycle_storesCycleCorrectly() public {
        uint256 startTime = block.timestamp;
        _startCycle();

        YieldRouter.PayrollCycle memory cycle = router.getCycle(employer, 1);

        assertEq(cycle.cycleId, 1);
        assertEq(cycle.totalDeposited, DEPOSIT_AMOUNT);
        assertEq(cycle.cycleStartTime, startTime);
        assertEq(cycle.payDay, startTime + (CYCLE_DURATION));
        assertEq(cycle.idleBalance, cycle.totalDeposited);

        assertTrue(cycle.isActive);
    }

    //  Multiple concurrent cycles 

    function test_startCycle_incrementsCycleIdPerEmployer() public {
        _startCycle();
        _startCycle();
        _startCycle();

        assertEq(router.getCycleCount(employer), 3);
        assertEq(router.getCycle(employer, 1).cycleId, 1);
        assertEq(router.getCycle(employer, 2).cycleId, 2);
        assertEq(router.getCycle(employer, 3).cycleId, 3);
    }

    function test_startCycle_cyclesAreIsolatedPerEmployer() public {
        address employerB = makeAddr("employerB");
        vm.startPrank(owner);
        usdc.mint(employerB, DEPOSIT_AMOUNT * 10);

        // Give employerB a separate treasury-like setup — use owner as caller
        usdc.approve(address(router), type(uint256).max);
        vm.stopPrank();

        _startCycle(); // employer cycle 1

        // Start a cycle for employerB via owner
        vm.startPrank(owner);
        usdc.mint(owner, DEPOSIT_AMOUNT);
        usdc.approve(address(router), DEPOSIT_AMOUNT);
        router.startCycle(
            employerB,
            DEPOSIT_AMOUNT,
            CYCLE_DURATION,
            address(dispatcher)
        );
        vm.stopPrank();

        // Each employer has exactly one cycle, independently
        assertEq(router.getCycleCount(employer), 1);
        assertEq(router.getCycleCount(employerB), 1);
        assertEq(router.getCycle(employer, 1).totalDeposited, DEPOSIT_AMOUNT);
        assertEq(router.getCycle(employerB, 1).totalDeposited, DEPOSIT_AMOUNT);
    }

    function test_startCycle_concurrentCyclesHoldCorrectUSDC() public {
        _startCycle();
        _startCycle();

        // Both cycles deposited — router holds 2x
        assertEq(usdc.balanceOf(address(router)), DEPOSIT_AMOUNT * 2);
    }

    //  Cycle getters 

    function test_getCycle_revertsOnInvalidCycleId() public {
        vm.expectRevert(YieldRouter.YieldRouter__CycleNotFound.selector);
        router.getCycle(employer, 0);

        vm.expectRevert(YieldRouter.YieldRouter__CycleNotFound.selector);
        router.getCycle(employer, 1); // no cycles started yet
    }

    function test_getCycleHistory_returnsAllCycles() public {
        _startCycle();
        _startCycle();

        YieldRouter.PayrollCycle[] memory history = router.getCycleHistory(
            employer
        );
        assertEq(history.length, 2);
    }

    function test_getActiveCycles_returnsOnlyActiveCycles() public {
        _startCycle();
        _startCycle();

        YieldRouter.PayrollCycle[] memory active = router.getActiveCycles(
            employer
        );
        assertEq(active.length, 2);
        assertTrue(active[0].isActive);
        assertTrue(active[1].isActive);
    }

    function test_getCycleCount_returnsCorrectCount() public {
        assertEq(router.getCycleCount(employer), 0);
        _startCycle();
        assertEq(router.getCycleCount(employer), 1);
        _startCycle();
        assertEq(router.getCycleCount(employer), 2);
    }

    //  Pool getters 

    function test_getPoolCount_returnsCorrectCount() public view {
        assertEq(router.getPoolCount(), 2);
    }

    function test_getPool_revertsOnInvalidIndex() public {
        vm.expectRevert(YieldRouter.YieldRouter__InvalidPoolIndex.selector);
        router.getPool(99);
    }

    function test_getPool_returnsCorrectPool() public view {
        YieldRouter.PoolEntry memory p = router.getPool(0);
        assertEq(p.adapterAddress, address(stableAdapter));
        assertTrue(p.isStablePair);
        assertTrue(p.isActive);
    }
}
