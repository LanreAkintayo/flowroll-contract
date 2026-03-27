// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {YieldRouter} from "../src/YieldRouter.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockPool} from "../src/mocks/MockPool.sol";
import {MockPoolAdapter} from "../src/adapters/MockPoolAdapter.sol";

contract YieldRouterTest is Test {
    // ─── Contracts ───────────────────────────────────────────────────────────

    YieldRouter internal router;
    MockUSDC internal usdc;
    MockPool internal stablePool;
    MockPool internal volatilePool;
    MockPoolAdapter internal stableAdapter;
    MockPoolAdapter internal volatileAdapter;

    // ─── Actors ──────────────────────────────────────────────────────────────

    address internal owner = makeAddr("owner");
    address internal agentOperator = makeAddr("agentOperator");
    address internal treasury = makeAddr("treasury");
    address internal employer = makeAddr("employer");
    address internal stranger = makeAddr("stranger");

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 internal constant INITIAL_SUPPLY = 10_000_000e6; // 10M USDC
    uint256 internal constant DEPOSIT_AMOUNT = 50_000e6; // 50k USDC
    uint256 internal constant CYCLE_DURATION = 30 days; // 30 days
    uint256 internal constant STABLE_APY_BPS = 800; // 8%
    uint256 internal constant VOLATILE_APY_BPS = 1_500; // 15%
    uint256 internal constant INITIAL_TVL = 1_000_000e6; // 1M USDC

    // ─── Setup ───────────────────────────────────────────────────────────────

    function setUp() public {
        vm.startPrank(owner);

        // Deploy MockUSDC and fund actors
        usdc = new MockUSDC(INITIAL_SUPPLY);
        usdc.mint(treasury, DEPOSIT_AMOUNT * 10);
        usdc.mint(employer, DEPOSIT_AMOUNT * 10);

        // Deploy pools
        stablePool = new MockPool(
            address(usdc),
            "USDC/iUSD Stable Pool",
            STABLE_APY_BPS,
            true,
            "Flowroll Stable Shares",
            "frUSDC-S"
        );

        volatilePool = new MockPool(
            address(usdc),
            "USDC/INIT Volatile Pool",
            VOLATILE_APY_BPS,
            false,
            "Flowroll Volatile Shares",
            "frUSDC-V"
        );

        // Seed pools with initial TVL so share math works
        usdc.approve(address(stablePool), INITIAL_TVL);
        usdc.approve(address(volatilePool), INITIAL_TVL);
        stablePool.deposit(INITIAL_TVL, owner);
        volatilePool.deposit(INITIAL_TVL, owner);

        // Deploy adapters
        stableAdapter = new MockPoolAdapter(address(usdc), address(stablePool));
        volatileAdapter = new MockPoolAdapter(
            address(usdc),
            address(volatilePool)
        );

        // Deploy YieldRouter
        router = new YieldRouter(agentOperator, address(usdc));

        // Wire up
        router.setTreasury(treasury);
        router.addPool(address(stableAdapter), address(stablePool), true, 500);
        router.addPool(
            address(volatileAdapter),
            address(volatilePool),
            false,
            500
        );

        vm.stopPrank();

        // Treasury approves router to pull USDC for cycle deposits
        vm.prank(treasury);
        usdc.approve(address(router), type(uint256).max);
    }

    // =========================================================================
    // ACCESS CONTROL
    // =========================================================================

    // ─── agentRebalance ──────────────────────────────────────────────────────

    function test_agentRebalance_revertsIfNotAgent() public {
        _startCycle();

        vm.prank(stranger);
        vm.expectRevert(YieldRouter.YieldRouter__NotAgent.selector);
        router.agentRebalance(employer, 1);
    }

    function test_agentRebalance_ownerCanActAsAgent() public {
        _startCycle();

        vm.prank(owner);
        router.agentRebalance(employer, 1); // should not revert
    }

    function test_agentRebalance_agentOperatorCanCall() public {
        _startCycle();

        vm.prank(agentOperator);
        router.agentRebalance(employer, 1); // should not revert
    }

    // ─── startCycle ──────────────────────────────────────────────────────────

    function test_startCycle_revertsIfNotAuthorizedCaller() public {
        vm.prank(stranger);
        vm.expectRevert(YieldRouter.YieldRouter__NotAuthorizedCaller.selector);
        router.startCycle(employer, DEPOSIT_AMOUNT, CYCLE_DURATION);
    }

    function test_startCycle_revertsIfCalledByEmployerDirectly() public {
        // Employers must go through Treasury — direct calls blocked
        vm.prank(employer);
        vm.expectRevert(YieldRouter.YieldRouter__NotAuthorizedCaller.selector);
        router.startCycle(employer, DEPOSIT_AMOUNT, CYCLE_DURATION);
    }

    function test_startCycle_treasuryCanCall() public {
        vm.prank(treasury);
        router.startCycle(employer, DEPOSIT_AMOUNT, CYCLE_DURATION);
        // no revert = pass
    }

    function test_startCycle_ownerCanCall() public {
        // Owner bypass for testing convenience
        vm.startPrank(owner);
        usdc.mint(owner, DEPOSIT_AMOUNT);
        usdc.approve(address(router), DEPOSIT_AMOUNT);
        router.startCycle(employer, DEPOSIT_AMOUNT, CYCLE_DURATION);
        vm.stopPrank();
    }

    // ─── Pool management ─────────────────────────────────────────────────────

    function test_addPool_revertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        router.addPool(address(stableAdapter), address(stablePool), true, 500);
    }

    function test_deactivatePool_revertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        router.deactivatePool(0);
    }

    function test_deactivatePool_revertsIfAlreadyInactive() public {
        vm.startPrank(owner);
        router.deactivatePool(0);
        vm.expectRevert(YieldRouter.YieldRouter__PoolAlreadyInactive.selector);
        router.deactivatePool(0);
        vm.stopPrank();
    }

    // ─── Admin setters ───────────────────────────────────────────────────────

    function test_setAgentOperator_revertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        router.setAgentOperator(stranger);
    }

    function test_setAgentOperator_revertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(YieldRouter.YieldRouter__ZeroAddress.selector);
        router.setAgentOperator(address(0));
    }

    function test_setTreasury_revertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        router.setTreasury(stranger);
    }

    function test_setPayrollDispatcher_revertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        router.setPayrollDispatcher(stranger);
    }

    function test_pause_revertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        router.pause();
    }

    function test_startCycle_revertsWhenPaused() public {
        vm.prank(owner);
        router.pause();

        vm.prank(treasury);
        vm.expectRevert();
        router.startCycle(employer, DEPOSIT_AMOUNT, CYCLE_DURATION);
    }

    // =========================================================================
    // CYCLE LIFECYCLE
    // =========================================================================

    // ─── startCycle: input validation ────────────────────────────────────────

    function test_startCycle_revertsOnZeroDeposit() public {
        vm.prank(treasury);
        vm.expectRevert(YieldRouter.YieldRouter__ZeroDeposit.selector);
        router.startCycle(employer, 0, CYCLE_DURATION);
    }

    function test_startCycle_revertsOnZeroDuration() public {
        vm.prank(treasury);
        vm.expectRevert(YieldRouter.YieldRouter__ZeroDuration.selector);
        router.startCycle(employer, DEPOSIT_AMOUNT, 0);
    }

    // ─── startCycle: state correctness ───────────────────────────────────────

    function test_startCycle_pullsUSDCFromCaller() public {
        uint256 balanceBefore = usdc.balanceOf(treasury);

        _startCycle();

        assertEq(usdc.balanceOf(treasury), balanceBefore - DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(address(router)), DEPOSIT_AMOUNT);
    }

    function test_startCycle_storesCycleCorrectly() public {
        uint256 startTime = block.timestamp;
        _startCycle();

        YieldRouter.PayrollCycle memory cycle = router.getCycle(employer, 1);

        assertEq(cycle.cycleId, 1);
        assertEq(cycle.totalDeposited, DEPOSIT_AMOUNT);
        assertEq(cycle.cycleStartTime, startTime);
        assertEq(cycle.payDay, startTime + (CYCLE_DURATION));
        assertEq(cycle.currentAllocation, 0);
        assertEq(cycle.yieldEarned, 0);
        assertTrue(cycle.isActive);
    }

    function test_startCycle_emitsCycleStarted() public {
        uint256 expectedPayday = block.timestamp + (CYCLE_DURATION);

        vm.expectEmit(true, true, false, true);
        emit YieldRouter.CycleStarted(
            employer,
            1,
            DEPOSIT_AMOUNT,
            expectedPayday
        );

        _startCycle();
    }

    // ─── Multiple concurrent cycles ──────────────────────────────────────────

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
        router.startCycle(employerB, DEPOSIT_AMOUNT, CYCLE_DURATION);
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

    // ─── Cycle getters ───────────────────────────────────────────────────────

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

    // ─── Pool getters ─────────────────────────────────────────────────────────

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

    // =========================================================================
    // BUFFER CALCULATION
    // =========================================================================



    // =========================================================================
    // INTERNAL HELPERS
    // =========================================================================

    /// @dev Starts a single cycle from treasury on behalf of employer
    function _startCycle() internal {
        vm.prank(treasury);
        router.startCycle(employer, DEPOSIT_AMOUNT, CYCLE_DURATION);
    }
}
