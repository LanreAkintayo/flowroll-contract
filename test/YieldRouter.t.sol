// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {YieldRouter} from "../src/YieldRouter.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockPool} from "../src/mocks/MockPool.sol";
import {MockPoolAdapter} from "../src/adapters/MockPoolAdapter.sol";

contract YieldRouterTest is Test {

    // ─── Contracts ───────────────────────────────────────────────────────────

    YieldRouter      internal router;
    MockUSDC         internal usdc;
    MockPool         internal stablePool;
    MockPool         internal volatilePool;
    MockPoolAdapter  internal stableAdapter;
    MockPoolAdapter  internal volatileAdapter;

    // ─── Actors ──────────────────────────────────────────────────────────────

    address internal owner          = makeAddr("owner");
    address internal agentOperator  = makeAddr("agentOperator");
    address internal treasury       = makeAddr("treasury");
    address internal employer       = makeAddr("employer");
    address internal stranger       = makeAddr("stranger");

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 internal constant INITIAL_SUPPLY    = 10_000_000e6;  // 10M USDC
    uint256 internal constant DEPOSIT_AMOUNT    = 50_000e6;      // 50k USDC
    uint256 internal constant CYCLE_DURATION    = 30;            // 30 days
    uint256 internal constant STABLE_APY_BPS    = 800;           // 8%
    uint256 internal constant VOLATILE_APY_BPS  = 1_500;         // 15%
    uint256 internal constant INITIAL_TVL       = 1_000_000e6;   // 1M USDC

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
        usdc.approve(address(stablePool),   INITIAL_TVL);
        usdc.approve(address(volatilePool), INITIAL_TVL);
        stablePool.deposit(INITIAL_TVL,   owner);
        volatilePool.deposit(INITIAL_TVL, owner);

        // Deploy adapters
        stableAdapter   = new MockPoolAdapter(address(usdc), address(stablePool));
        volatileAdapter = new MockPoolAdapter(address(usdc), address(volatilePool));

        // Deploy YieldRouter
        router = new YieldRouter(agentOperator, address(usdc));

        // Wire up
        router.setTreasury(treasury);
        router.addPool(address(stableAdapter),   address(stablePool),   true,  500);
        router.addPool(address(volatileAdapter), address(volatilePool), false, 500);

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
    // INTERNAL HELPERS
    // =========================================================================

    /// @dev Starts a single cycle from treasury on behalf of employer
    function _startCycle() internal {
        vm.prank(treasury);
        router.startCycle(employer, DEPOSIT_AMOUNT, CYCLE_DURATION);
    }
}
