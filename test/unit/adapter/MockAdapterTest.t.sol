// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {YieldRouterBase} from "../../base/YieldRouterBase.t.sol";
import {MockPoolAdapter} from "../../../src/adapters/MockPoolAdapter.sol";
import {BasePoolAdapter} from "../../../src/adapters/BasePoolAdapter.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {console2} from "forge-std/console2.sol";

contract MockPoolAdapterTest is YieldRouterBase {
    // ─── Helpers ─────────────────────────────────────────────────────────────

    uint256 internal constant ADAPTER_DEPOSIT = 10_000e6; // 10k USDC

    /// @dev Approve adapter and deposit directly — returns shares received
    function _adapterDeposit(
        MockPoolAdapter adapter,
        uint256 amount
    ) internal returns (uint256 shares) {
        usdc.approve(address(adapter), amount);
        shares = adapter.deposit(amount);
    }

    // =========================================================================
    // DEPOSIT
    // =========================================================================

    function test_deposit_revertsOnZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert();
        stableAdapter.deposit(0);
    }

    function test_deposit_pullsUSDCFromCaller() public {
        vm.startPrank(owner);
        usdc.mint(owner, ADAPTER_DEPOSIT);

        uint256 balanceBefore = usdc.balanceOf(owner);
        _adapterDeposit(stableAdapter, ADAPTER_DEPOSIT);
        uint256 balanceAfter = usdc.balanceOf(owner);

        assertEq(balanceAfter, balanceBefore - ADAPTER_DEPOSIT);
        vm.stopPrank();
    }

    function test_deposit_adapterHoldsSharesInPool() public {
        vm.startPrank(owner);
        usdc.mint(owner, ADAPTER_DEPOSIT);

        uint256 shares = _adapterDeposit(stableAdapter, ADAPTER_DEPOSIT);

        // Adapter holds exactly the returned shares in the pool
        assertEq(
            IERC4626(address(stablePool)).balanceOf(address(stableAdapter)),
            shares
        );
        vm.stopPrank();
    }

    function test_deposit_returnsNonZeroShares() public {
        vm.startPrank(owner);
        usdc.mint(owner, ADAPTER_DEPOSIT);

        uint256 shares = _adapterDeposit(stableAdapter, ADAPTER_DEPOSIT);
        assertGt(shares, 0);
        vm.stopPrank();
    }

    function test_deposit_callerReceivesNoShares() public {
        vm.startPrank(owner);
        usdc.mint(owner, ADAPTER_DEPOSIT);

        uint256 ownerSharesBefore = IERC4626(address(stablePool)).balanceOf(
            owner
        );

        _adapterDeposit(stableAdapter, ADAPTER_DEPOSIT);

        uint256 ownerSharesAfter = IERC4626(address(stablePool)).balanceOf(owner);


        // Caller should hold zero shares — adapter holds them
        assertEq(ownerSharesBefore, ownerSharesAfter);
        vm.stopPrank();
    }

    function test_deposit_poolUSDCBalanceIncrease() public {
        vm.startPrank(owner);
        usdc.mint(owner, ADAPTER_DEPOSIT);

        uint256 tvlBefore = stableAdapter.getTvl();
        _adapterDeposit(stableAdapter, ADAPTER_DEPOSIT);
        uint256 tvlAfter = stableAdapter.getTvl();

        assertEq(tvlAfter, tvlBefore + ADAPTER_DEPOSIT);
        vm.stopPrank();
    }

    function test_deposit_emitsDepositedEvent() public {
        vm.startPrank(owner);
        usdc.mint(owner, ADAPTER_DEPOSIT);
        usdc.approve(address(stableAdapter), ADAPTER_DEPOSIT);

        vm.expectEmit(false, false, false, true);
        emit BasePoolAdapter.Deposited(ADAPTER_DEPOSIT, ADAPTER_DEPOSIT);

        stableAdapter.deposit(ADAPTER_DEPOSIT);
        vm.stopPrank();
    }

    function test_deposit_stableAndVolatileAdaptersBothWork() public {
        vm.startPrank(owner);
        usdc.mint(owner, ADAPTER_DEPOSIT * 2);

        uint256 stableShares = _adapterDeposit(stableAdapter, ADAPTER_DEPOSIT);
        uint256 volatileShares = _adapterDeposit(
            volatileAdapter,
            ADAPTER_DEPOSIT
        );

        assertGt(stableShares, 0);
        assertGt(volatileShares, 0);
        vm.stopPrank();
    }

    // =========================================================================
    // WITHDRAW
    // =========================================================================

    function test_withdraw_revertsOnZeroShares() public {
        vm.prank(owner);
        vm.expectRevert();
        stableAdapter.withdraw(0);
    }

    function test_withdraw_returnsUSDCToCaller() public {
        vm.startPrank(owner);
        usdc.mint(owner, ADAPTER_DEPOSIT);

        uint256 shares = _adapterDeposit(stableAdapter, ADAPTER_DEPOSIT);

        uint256 balanceBefore = usdc.balanceOf(owner);
        stableAdapter.withdraw(shares);
        uint256 balanceAfter = usdc.balanceOf(owner);

        assertGt(balanceAfter, balanceBefore);
        vm.stopPrank();
    }

    function test_withdraw_returnsExactDepositedAmount_noYield() public {
        vm.startPrank(owner);
        usdc.mint(owner, ADAPTER_DEPOSIT);

        uint256 shares = _adapterDeposit(stableAdapter, ADAPTER_DEPOSIT);
        uint256 received = stableAdapter.withdraw(shares);

        assertEq(received, ADAPTER_DEPOSIT);
        vm.stopPrank();
    }

    function test_withdraw_adapterShareBalanceDropsToZero() public {
        vm.startPrank(owner);
        usdc.mint(owner, ADAPTER_DEPOSIT);

        uint256 shares = _adapterDeposit(stableAdapter, ADAPTER_DEPOSIT);
        stableAdapter.withdraw(shares);

        assertEq(
            IERC4626(address(stablePool)).balanceOf(address(stableAdapter)),
            0
        );
        vm.stopPrank();
    }

    function test_withdraw_partialShares_leavesRemainingInPool() public {
        vm.startPrank(owner);
        usdc.mint(owner, ADAPTER_DEPOSIT);

        uint256 shares = _adapterDeposit(stableAdapter, ADAPTER_DEPOSIT);
        uint256 halfShares = shares / 2;

        stableAdapter.withdraw(halfShares);

        uint256 remainingShares = IERC4626(address(stablePool)).balanceOf(
            address(stableAdapter)
        );
        assertEq(remainingShares, shares - halfShares);
        vm.stopPrank();
    }

    function test_withdraw_emitsWithdrawnEvent() public {
        vm.startPrank(owner);
        usdc.mint(owner, ADAPTER_DEPOSIT);

        uint256 shares = _adapterDeposit(stableAdapter, ADAPTER_DEPOSIT);
        usdc.approve(address(stableAdapter), shares);

        vm.expectEmit(false, false, false, false);
        emit BasePoolAdapter.Withdrawn(shares, ADAPTER_DEPOSIT);

        stableAdapter.withdraw(shares);
        vm.stopPrank();
    }

    // =========================================================================
    // YIELD INTERACTION
    // =========================================================================

    function test_withdraw_returnsMoreThanDeposited_afterYield() public {
        vm.startPrank(owner);
        usdc.mint(owner, ADAPTER_DEPOSIT);
        uint256 shares = _adapterDeposit(stableAdapter, ADAPTER_DEPOSIT);
        vm.stopPrank();

        // Simulate yield — appreciates share value
        _simulateYield(stablePool, 1_000e6);

        vm.startPrank(owner);
        uint256 received = stableAdapter.withdraw(shares);
        assertGt(received, ADAPTER_DEPOSIT);
        vm.stopPrank();
    }

    function test_sharesToValue_increasesAfterYield() public {
        vm.startPrank(owner);
        usdc.mint(owner, ADAPTER_DEPOSIT);
        uint256 shares = _adapterDeposit(stableAdapter, ADAPTER_DEPOSIT);
        vm.stopPrank();

        uint256 valueBefore = stableAdapter.sharesToValue(shares);
        _simulateYield(stablePool, 1_000e6);
        uint256 valueAfter = stableAdapter.sharesToValue(shares);

        assertGt(valueAfter, valueBefore);
    }

    function test_getTvl_increasesAfterYield() public {
        uint256 tvlBefore = stableAdapter.getTvl();
        _simulateYield(stablePool, 1_000e6);
        uint256 tvlAfter = stableAdapter.getTvl();

        assertGt(tvlAfter, tvlBefore);
    }

    // =========================================================================
    // READ FUNCTIONS
    // =========================================================================

    function test_getApyBps_returnsCorrectValue() public view {
        assertEq(stableAdapter.getApyBps(), STABLE_APY_BPS);
        assertEq(volatileAdapter.getApyBps(), VOLATILE_APY_BPS);
    }

    function test_getApyBps_updatesAfterPoolChange() public {
        vm.prank(owner);
        stablePool.setApyBps(2_000);

        assertEq(stableAdapter.getApyBps(), 2_000);
    }

    function test_getTvl_reflectsPoolTotalAssets() public view {
        // Both pools seeded with INITIAL_TVL in setUp
        assertEq(stableAdapter.getTvl(), INITIAL_TVL);
        assertEq(volatileAdapter.getTvl(), INITIAL_TVL);
    }

    function test_isStablePair_returnsCorrectValue() public view {
        assertTrue(stableAdapter.isStablePair());
        assertFalse(volatileAdapter.isStablePair());
    }

    function test_sharesToValue_returnsZero_forZeroShares() public view {
        assertEq(stableAdapter.sharesToValue(0), 0);
    }

    function test_sharesToValue_returnsCorrectUSDC_noYield() public {
        vm.startPrank(owner);
        usdc.mint(owner, ADAPTER_DEPOSIT);
        uint256 shares = _adapterDeposit(stableAdapter, ADAPTER_DEPOSIT);
        vm.stopPrank();

        // No yield — shares should be worth exactly what was deposited
        assertEq(stableAdapter.sharesToValue(shares), ADAPTER_DEPOSIT);
    }

    function test_getPositionValue_returnsCorrectValue() public {
        vm.startPrank(owner);
        usdc.mint(owner, ADAPTER_DEPOSIT);
        _adapterDeposit(stableAdapter, ADAPTER_DEPOSIT);
        vm.stopPrank();

        // Adapter holds the shares — its position value should equal deposit
        assertEq(
            stableAdapter.getPositionValue(address(stableAdapter)),
            ADAPTER_DEPOSIT
        );
    }

    function test_getPositionValue_returnsZero_forNonHolder() public view {
        assertEq(stableAdapter.getPositionValue(stranger), 0);
    }
}
