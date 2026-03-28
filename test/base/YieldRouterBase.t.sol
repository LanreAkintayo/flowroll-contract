// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SharedBase} from "./SharedBase.t.sol";
import {YieldRouter} from "../../src/YieldRouter.sol";
import {MockPool} from "../../src/mocks/MockPool.sol";
import {MockPoolAdapter} from "../../src/adapters/MockPoolAdapter.sol";

import {MockPayrollDispatcher} from "../../src/mocks/MockPayrollDispatcher.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract YieldRouterBase is SharedBase {

    // ─── Contracts ───────────────────────────────────────────────────────────

    YieldRouter        internal router;
    MockPool           internal stablePool;
    MockPool           internal volatilePool;
    MockPoolAdapter    internal stableAdapter;
    MockPoolAdapter    internal volatileAdapter;
    MockPayrollDispatcher     internal mockDispatcher;

    // ─── Pool Constants ───────────────────────────────────────────────────────

    uint256 internal constant STABLE_APY_BPS   = 800;         // 8%
    uint256 internal constant VOLATILE_APY_BPS = 1_500;       // 15%
    uint256 internal constant INITIAL_TVL      = 1_000_000e6; // 1M USDC
    uint256 internal constant STABLE_MIN_APY   = 500;
    uint256 internal constant VOLATILE_MIN_APY = 500;

    // ─── Buffer Tier Constants (default config, 30 day cycle) ────────────────

    // Tier thresholds — timeLeft values that land cleanly inside each tier
    uint256 internal constant TIER_0_TIME_LEFT = 21 days; // > 70% = 21 days
    uint256 internal constant TIER_1_TIME_LEFT = 15 days; // > 50% = 15 days
    uint256 internal constant TIER_2_TIME_LEFT = 9 days; // > 30% = 9 days
    uint256 internal constant TIER_3_TIME_LEFT = 7 days + 12 hours;  // > 25% = 7.5 days
    uint256 internal constant TIER_4_TIME_LEFT = 3 days;  // > 10% = 3 days
    uint256 internal constant TIER_5_TIME_LEFT = 0 days;  // catch-all

    // Expected buffer bps per tier
    uint256 internal constant TIER_0_BPS =    500;
    uint256 internal constant TIER_1_BPS =  1_000;
    uint256 internal constant TIER_2_BPS =  1_500;
    uint256 internal constant TIER_3_BPS =  4_000;
    uint256 internal constant TIER_4_BPS = 10_000;
    uint256 internal constant TIER_5_BPS = 10_500;

    // ─── Setup ───────────────────────────────────────────────────────────────

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(owner);

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

        // Seed pools with initial TVL so share math works from the start
        usdc.mint(owner, INITIAL_TVL * 2);
        usdc.approve(address(stablePool),   INITIAL_TVL);
        usdc.approve(address(volatilePool), INITIAL_TVL);
        stablePool.deposit(INITIAL_TVL,   owner);
        volatilePool.deposit(INITIAL_TVL, owner);

        // Deploy adapters
        stableAdapter   = new MockPoolAdapter(address(usdc), address(stablePool));
        volatileAdapter = new MockPoolAdapter(address(usdc), address(volatilePool));

        // Deploy router
        router = new YieldRouter(agentOperator, address(usdc));

        // Deploy and wire dispatcher
        mockDispatcher = new MockPayrollDispatcher();

        // Wire up
        router.setTreasury(treasury);
        router.setPayrollDispatcher(address(mockDispatcher));
        router.addPool(address(stableAdapter),   address(stablePool),   true,  STABLE_MIN_APY);
        router.addPool(address(volatileAdapter), address(volatilePool), false, VOLATILE_MIN_APY);

        vm.stopPrank();

        // Treasury approves router once — covers all cycle deposits
        vm.prank(treasury);
        usdc.approve(address(router), type(uint256).max);
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    /// @dev Start a single cycle from treasury on behalf of employer
    function _startCycle() internal {
        vm.prank(treasury);
        router.startCycle(employer, DEPOSIT_AMOUNT, CYCLE_DURATION);
    }

    /// @dev Start a cycle with a custom deposit amount
    function _startCycleWithAmount(uint256 amount) internal {
        vm.prank(treasury);
        router.startCycle(employer, amount, CYCLE_DURATION);
    }

    /// @dev Start a cycle with a custom duration
    function _startCycleWithDuration(uint256 duration) internal {
        vm.prank(treasury);
        router.startCycle(employer, DEPOSIT_AMOUNT, duration);
    }

    /// @dev Warp so that exactly `timeLeft` seconds remain before payday
    function _warpToTimeLeft(uint256 timeLeft) internal {
        router.getCycle(employer, 1);
        uint256 payday = router.getCycle(employer, 1).payDay;
        vm.warp(payday - timeLeft);
    }

    /// @dev Warp to exactly payday
    function _warpToPayday() internal {
        uint256 payday = router.getCycle(employer, 1).payDay;
        vm.warp(payday);
    }

    /// @dev Simulate yield on a pool — owner injects assets directly
    function _simulateYield(MockPool pool, uint256 amount) internal {
        vm.startPrank(owner);
        usdc.mint(owner, amount);
        usdc.approve(address(pool), amount);
        pool.simulateYield(amount);
        vm.stopPrank();
    }

    /// @dev Run agentRebalance as the agent operator
    function _rebalance(address _employer, uint256 cycleId) internal {
        vm.prank(agentOperator);
        router.agentRebalance(_employer, cycleId);
    }

     /// @dev Returns snapshotted risk thresholds from cycle 1
    function _riskThresholds(uint256 cycleId) internal view returns (uint256 high, uint256 med) {
        YieldRouter.PayrollCycle memory cycle = router.getCycle(employer, cycleId);
        high = cycle.highRiskThreshold;
        med  = cycle.medRiskThreshold;
    }
}