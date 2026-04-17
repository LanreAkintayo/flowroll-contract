// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {YieldRouter} from "../../../src/YieldRouter.sol"; 
import {MockUSDC} from "../../../src/mocks/MockUSDC.sol";
import {MockPool} from "../../../src/mocks/MockPool.sol";
import {MockPoolAdapter} from "../../../src/adapters/MockPoolAdapter.sol";
import {YieldRouterBase} from "../../base/YieldRouterBase.t.sol";

contract YieldRouterAccess is YieldRouterBase {

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
        router.startCycle(employer, DEPOSIT_AMOUNT, CYCLE_DURATION, address(dispatcher));
    }

    function test_startCycle_revertsIfCalledByEmployerDirectly() public {
        // Employers must go through Treasury — direct calls blocked
        vm.prank(employer);
        vm.expectRevert(YieldRouter.YieldRouter__NotAuthorizedCaller.selector);
        router.startCycle(employer, DEPOSIT_AMOUNT, CYCLE_DURATION, address(dispatcher));
    }

    function test_startCycle_treasuryCanCall() public {
        vm.prank(address(manager));
        router.startCycle(employer, DEPOSIT_AMOUNT, CYCLE_DURATION, address(dispatcher));
        // no revert = pass
    }

    function test_startCycle_ownerCanCall() public {
        // Owner bypass for testing convenience
        vm.startPrank(owner);
        usdc.mint(owner, DEPOSIT_AMOUNT);
        usdc.approve(address(router), DEPOSIT_AMOUNT);
        router.startCycle(employer, DEPOSIT_AMOUNT, CYCLE_DURATION, address(dispatcher));
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

    function test_setPayrollManager_revertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        router.setPayrollManager(stranger);
    }

    function test_pause_revertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        router.pause();
    }

    function test_startCycle_revertsWhenPaused() public {
        vm.prank(owner);
        router.pause();

        vm.prank(address(manager));
        vm.expectRevert();
        router.startCycle(employer, DEPOSIT_AMOUNT, CYCLE_DURATION, address(dispatcher));
    }

}
