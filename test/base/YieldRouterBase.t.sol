// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SharedBase} from "./SharedBase.t.sol";
import {YieldRouter} from "../../src/YieldRouter.sol";
import {MockPool} from "../../src/mocks/MockPool.sol";

/**
 * @title YieldRouterBase
 * @dev Base test contract for YieldRouter logic. Provides buffer tier constants and cycle helpers.
 */
abstract contract YieldRouterBase is SharedBase {
    uint256 internal constant TIER_0_TIME_LEFT = 21 days;
    uint256 internal constant TIER_1_TIME_LEFT = 15 days;
    uint256 internal constant TIER_2_TIME_LEFT = 9 days;
    uint256 internal constant TIER_3_TIME_LEFT = 7 days + 12 hours;
    uint256 internal constant TIER_4_TIME_LEFT = 3 days;
    uint256 internal constant TIER_5_TIME_LEFT = 0 days;

    uint256 internal constant TIER_0_BPS = 500;
    uint256 internal constant TIER_1_BPS = 1_000;
    uint256 internal constant TIER_2_BPS = 1_500;
    uint256 internal constant TIER_3_BPS = 4_000;
    uint256 internal constant TIER_4_BPS = 10_000;
    uint256 internal constant TIER_5_BPS = 10_500;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(address(manager));
        usdc.approve(address(router), type(uint256).max);
    }

    /// @dev Starts a single cycle using the standard payroll setup.
    function _startCycle() internal {
        _setupPayroll(employer);
    }

    /// @dev Starts a cycle with a custom deposit amount.
    function _startCycleWithAmount(uint256 amount) internal {
        vm.prank(address(manager));
        router.startCycle(employer, amount, CYCLE_DURATION, address(dispatcher));
    }

    /// @dev Starts a cycle with a custom duration.
    function _startCycleWithDuration(uint256 duration) internal {
        vm.prank(address(manager));
        router.startCycle(employer, DEPOSIT_AMOUNT, duration, address(dispatcher));
    }

    /// @dev Simulates yield by directly minting and depositing assets into a pool.
    function _simulateYield(MockPool pool, uint256 amount) internal {
        vm.startPrank(owner);
        usdc.mint(owner, amount);
        usdc.approve(address(pool), amount);
        pool.simulateYield(amount);
        vm.stopPrank();
    }

    /// @dev Executes the agent rebalance logic for a specific employer cycle.
    function _rebalance(address _employer, uint256 cycleId) internal {
        vm.prank(agentOperator);
        router.agentRebalance(_employer, cycleId);
    }

    /// @dev Fetches snapshotted risk thresholds for a given cycle.
    function _riskThresholds(uint256 cycleId) internal view returns (uint256 high, uint256 med) {
        YieldRouter.PayrollCycle memory cycle = router.getCycle(employer, cycleId);
        high = cycle.highRiskThreshold;
        med = cycle.medRiskThreshold;
    }
}