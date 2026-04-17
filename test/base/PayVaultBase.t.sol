// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SharedBase} from "./SharedBase.t.sol";
import {PayVault} from "../../src/PayVault.sol";
import {PayrollDispatcher} from "../../src/PayrollDispatcher.sol";
import {PayrollManager} from "../../src/PayrollManager.sol";
import {YieldRouter} from "../../src/YieldRouter.sol";
import {MockPool} from "../../src/mocks/MockPool.sol";
import {MockPoolAdapter} from "../../src/adapters/MockPoolAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

abstract contract PayVaultBase is SharedBase {
    // ─── Contracts ───────────────────────────────────────────────────────────

    // PayVault            internal vault;
    // PayrollDispatcher   internal dispatcher;
    // PayrollManager      internal manager;
    // YieldRouter         internal router;
    // MockPool            internal stablePool;
    // MockPool            internal volatilePool;
    // MockPoolAdapter     internal stableAdapter;
    // MockPoolAdapter     internal volatileAdapter;

    // ─── Additional Actors ────────────────────────────────────────────────────

    // address internal employee2    = makeAddr("employee2");

    // ─── Constants ───────────────────────────────────────────────────────────

    // uint256 internal constant STABLE_APY_BPS   = 800;
    // uint256 internal constant VOLATILE_APY_BPS = 1_500;
    // uint256 internal constant INITIAL_TVL      = 1_000_000e6;
    // uint256 internal constant STABLE_MIN_APY   = 500;
    // uint256 internal constant VOLATILE_MIN_APY = 500;

    uint256 internal constant SALARY_1 = 5_000e6;
    uint256 internal constant SALARY_2 = 4_000e6;
    uint256 internal constant TOTAL_PAYROLL = SALARY_1 + SALARY_2;

    uint256 internal constant CREDIT_AMOUNT = 1_000e6;
    uint256 internal constant SAVE_DURATION = 30 days;
    uint256 internal constant SAVE_PCT = 2_000; // 20%

    // ─── Setup ───────────────────────────────────────────────────────────────

    function setUp() public virtual override {
        super.setUp();

        // vm.startPrank(owner);

        // // ── Deploy pools ──────────────────────────────────────────────────────
        // stablePool = new MockPool(
        //     address(usdc),
        //     "USDC/iUSD Stable Pool",
        //     STABLE_APY_BPS,
        //     true,
        //     "Flowroll Stable Shares",
        //     "frUSDC-S"
        // );

        // volatilePool = new MockPool(
        //     address(usdc),
        //     "USDC/INIT Volatile Pool",
        //     VOLATILE_APY_BPS,
        //     false,
        //     "Flowroll Volatile Shares",
        //     "frUSDC-V"
        // );

        // // Seed pools with initial TVL
        // usdc.mint(owner, INITIAL_TVL * 2);
        // usdc.approve(address(stablePool),   INITIAL_TVL);
        // usdc.approve(address(volatilePool), INITIAL_TVL);
        // stablePool.deposit(INITIAL_TVL,   owner);
        // volatilePool.deposit(INITIAL_TVL, owner);

        // // ── Deploy adapters ───────────────────────────────────────────────────
        // stableAdapter   = new MockPoolAdapter(address(usdc), address(stablePool));
        // volatileAdapter = new MockPoolAdapter(address(usdc), address(volatilePool));

        // // ── Deploy YieldRouter ────────────────────────────────────────────────
        // router = new YieldRouter(agentOperator, address(usdc));

        // // ── Deploy PayrollManager ─────────────────────────────────────────────
        // manager = new PayrollManager(
        //     address(usdc),
        //     feeRecipient,
        //     FEE_BPS
        // );

        // // ── Deploy PayrollDispatcher ──────────────────────────────────────────
        // dispatcher = new PayrollDispatcher(
        //     address(usdc),
        //     feeRecipient,
        //     FEE_BPS
        // );

        // // ── Deploy PayVault ───────────────────────────────────────────────────
        // vault = new PayVault(
        //     address(usdc),
        //     feeRecipient,
        //     FEE_BPS
        // );

        // // ── Wire YieldRouter ──────────────────────────────────────────────────
        // router.setPayVault(address(vault));
        // router.setPayrollManager(address(manager));
        // router.addPool(address(stableAdapter),   address(stablePool),   true,  STABLE_MIN_APY);
        // router.addPool(address(volatileAdapter), address(volatilePool), false, VOLATILE_MIN_APY);

        // // ── Wire PayrollManager ───────────────────────────────────────────────
        // manager.setYieldRouter(address(router));
        // manager.setPayrollDispatcher(address(dispatcher));

        // // ── Wire PayrollDispatcher ────────────────────────────────────────────
        // dispatcher.setYieldRouter(address(router));
        // dispatcher.setPayrollManager(address(manager));
        // dispatcher.setPayVault(address(vault));

        // // ── Wire PayVault ─────────────────────────────────────────────────────
        // vault.setDispatcher(address(dispatcher));
        // vault.setYieldRouter(address(router));

        // vm.stopPrank();

        // ── Fund actors ───────────────────────────────────────────────────────
        vm.startPrank(owner);
        usdc.mint(employee2, DEPOSIT_AMOUNT * 10);
        vm.stopPrank();

        // ── Dispatcher approves PayVault to pull USDC ─────────────────────────
        vm.prank(address(dispatcher));
        usdc.approve(address(vault), type(uint256).max);

        // ── Register employer and set up payroll group ────────────────────────
        vm.startPrank(employer);
        // manager.registerEmployer();
        manager.createGroup("Engineering", CYCLE_DURATION);
        usdc.approve(address(manager), type(uint256).max);
        manager.addEmployee(1, employee, SALARY_1);
        manager.addEmployee(1, employee2, SALARY_2);
        vm.stopPrank();
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    /// @dev Credit employee balance directly via dispatcher
    function _credit(address emp, uint256 amount) internal {
        address[] memory employees = new address[](1);
        employees[0] = emp;

        uint256[] memory salaries = new uint256[](1);
        salaries[0] = amount;

        vm.startPrank(employer);
        uint256 groupId = manager.createGroup("Tech Team", CYCLE_DURATION);

        usdc.approve(address(manager), DEPOSIT_AMOUNT);

        uint256 cycleId = manager.setUpPayroll(groupId, employees, salaries);
        console.log("Cycleee id", cycleId);
        vm.stopPrank();

        uint256 payday = router.getCycle(employer, cycleId).payDay;
        vm.warp(payday);

        vm.prank(agentOperator);
        router.agentRebalance(employer, cycleId);

        // vm.startPrank(owner);
        // usdc.mint(address(dispatcher), amount);
        // vm.stopPrank();

        // vm.prank(address(dispatcher));
        // vault.credit(emp, amount);
    }

    /// @dev Run full employer payroll cycle — returns cycleId
    function _runPayrollCycle(
        uint256 yieldAmount
    ) internal returns (uint256 cycleId) {
        cycleId = _setupPayroll(employer);
        // cycleId = manager.getGroup(employer, 1).activeCycleId;

        vm.prank(agentOperator);
        router.agentRebalance(employer, cycleId);

        if (yieldAmount > 0) {
            vm.startPrank(owner);
            usdc.mint(owner, yieldAmount);
            usdc.approve(address(volatilePool), yieldAmount);
            volatilePool.simulateYield(yieldAmount);
            vm.stopPrank();
        }

        uint256 payday = router.getCycle(employer, cycleId).payDay;
        vm.warp(payday);

        vm.prank(agentOperator);
        router.agentRebalance(employer, cycleId);
    }

    /// @dev Credit employee then start auto-save cycle — returns cycleId
    function _startAutoSave(
        address emp,
        uint256 creditAmount,
        uint256 savePct,
        uint256 duration
    ) internal returns (uint256 cycleId) {
        _credit(emp, creditAmount);

        uint256 cyclesBefore = router.getCycleCount(emp);

        vm.prank(emp);
        vault.claimAndSave(creditAmount, savePct, duration);

        vm.prank(agentOperator);
        router.agentRebalance(emp, cyclesBefore + 1);

        // cycleId is cyclesBefore + 1
        cycleId = cyclesBefore + 1;
    }

    /// @dev Warp auto-save cycle to payday and trigger settlement
    function _settleAutoSave(address emp, uint256 cycleId) internal {
        uint256 payday = router.getCycle(emp, cycleId).payDay;
        vm.warp(payday);

        vm.prank(agentOperator);
        router.agentRebalance(emp, cycleId);
    }

    /// @dev Simulate yield on volatile pool
    function _simulateYield(uint256 amount) internal {
        vm.startPrank(owner);
        usdc.mint(owner, amount);
        usdc.approve(address(volatilePool), amount);
        volatilePool.simulateYield(amount);
        vm.stopPrank();
    }
}
