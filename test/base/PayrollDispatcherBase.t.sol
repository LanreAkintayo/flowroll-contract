// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SharedBase} from "./SharedBase.t.sol";
import {PayrollDispatcher} from "../../src/PayrollDispatcher.sol";
import {PayrollManager} from "../../src/PayrollManager.sol";
import {YieldRouter} from "../../src/YieldRouter.sol";
import {MockPool} from "../../src/mocks/MockPool.sol";
import {MockPoolAdapter} from "../../src/adapters/MockPoolAdapter.sol";
import {MockPayVault} from "../../src/mocks/MockPayVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";


abstract contract PayrollDispatcherBase is SharedBase {

    // ─── Contracts ───────────────────────────────────────────────────────────

    PayrollDispatcher   internal dispatcher;
    PayrollManager      internal payrollManager;
    YieldRouter         internal router;
    MockPayVault        internal mockVault;
    MockPool            internal stablePool;
    MockPool            internal volatilePool;
    MockPoolAdapter     internal stableAdapter;
    MockPoolAdapter     internal volatileAdapter;

    // ─── Additional Actors ────────────────────────────────────────────────────

    address internal employee2   = makeAddr("employee2");
    address internal employee3   = makeAddr("employee3");
    address internal feeRecipient = makeAddr("feeRecipient");

    // ─── Payroll Constants ────────────────────────────────────────────────────

    uint256 internal constant STABLE_APY_BPS   = 800;
    uint256 internal constant VOLATILE_APY_BPS = 1_500;
    uint256 internal constant INITIAL_TVL      = 1_000_000e6;
    uint256 internal constant STABLE_MIN_APY   = 500;
    uint256 internal constant VOLATILE_MIN_APY = 500;
    uint256 internal constant FEE_BPS          = 1_000; // 10% fee on yield

    // ─── Payroll Schedule ─────────────────────────────────────────────────────

    // Three employees with different salaries
    // Total = 9_000e6
    uint256 internal constant SALARY_1 = 5_000e6; // employee  — 55.5%
    uint256 internal constant SALARY_2 = 2_500e6; // employee2 — 27.8%
    uint256 internal constant SALARY_3 = 1_500e6; // employee3 — 16.7%
    uint256 internal constant TOTAL_PAYROLL = SALARY_1 + SALARY_2 + SALARY_3; // 9_000e6

    // ─── Setup ───────────────────────────────────────────────────────────────

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(owner);

        // ── Deploy pools ──────────────────────────────────────────────────────
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

        // Seed pools with initial TVL
        usdc.mint(owner, INITIAL_TVL * 2);
        usdc.approve(address(stablePool),   INITIAL_TVL);
        usdc.approve(address(volatilePool), INITIAL_TVL);
        stablePool.deposit(INITIAL_TVL,   owner);
        volatilePool.deposit(INITIAL_TVL, owner);

        // ── Deploy adapters ───────────────────────────────────────────────────
        stableAdapter   = new MockPoolAdapter(address(usdc), address(stablePool));
        volatileAdapter = new MockPoolAdapter(address(usdc), address(volatilePool));

        // ── Deploy YieldRouter ────────────────────────────────────────────────
        router = new YieldRouter(agentOperator, address(usdc));

        // ── Deploy PayrollManager ─────────────────────────────────────────────
        payrollManager = new PayrollManager(address(usdc), feeRecipient, FEE_BPS);

        // ── Deploy MockPayVault ───────────────────────────────────────────────
        mockVault = new MockPayVault();

        // ── Deploy PayrollDispatcher ──────────────────────────────────────────
        dispatcher = new PayrollDispatcher(
            address(usdc),
            feeRecipient,
            FEE_BPS
        );

        // ── Wire everything up ────────────────────────────────────────────────
        router.setTreasury(address(payrollManager));
        router.setPayrollDispatcher(address(dispatcher));
        router.addPool(address(stableAdapter),   address(stablePool),   true,  STABLE_MIN_APY);
        router.addPool(address(volatileAdapter), address(volatilePool), false, VOLATILE_MIN_APY);

        payrollManager.setYieldRouter(address(router));

        dispatcher.setYieldRouter(address(router));
        dispatcher.setPayrollManager(address(payrollManager));
        dispatcher.setPayVault(address(mockVault));

        vm.stopPrank();

        // ── Fund additional employees ─────────────────────────────────────────
        vm.startPrank(owner);
        usdc.mint(employee2, DEPOSIT_AMOUNT * 10);
        usdc.mint(employee3, DEPOSIT_AMOUNT * 10);
        vm.stopPrank();

        // ── Register employer and set up payroll group ────────────────────────
        vm.startPrank(employer);
        payrollManager.registerEmployer();
        payrollManager.createGroup("Engineering", CYCLE_DURATION);

        // Approve payrollManager to pull payroll funds
        usdc.approve(address(payrollManager), type(uint256).max);

        // Add three employees to group 1
        payrollManager.addEmployee(1, employee,  SALARY_1);
        payrollManager.addEmployee(1, employee2, SALARY_2);
        payrollManager.addEmployee(1, employee3, SALARY_3);
        vm.stopPrank();
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    /// @dev Deposit payroll and return the cycleId
    function _depositPayroll() internal returns (uint256 cycleId) {
        vm.prank(employer);
        payrollManager.depositPayroll(1);
        cycleId = payrollManager.getGroup(employer, 1).activeCycleId;
    }

    /// @dev Warp to payday for a specific cycle
    function _warpToPayday(uint256 cycleId) internal {
        uint256 payday = router.getCycle(employer, cycleId).payDay;
        vm.warp(payday);
    }

    /// @dev Run agentRebalance as agent operator
    function _rebalance(uint256 cycleId) internal {
        vm.prank(agentOperator);
        router.agentRebalance(employer, cycleId);
    }


    // 500,000

    /// @dev Simulate yield on volatile pool
    function _simulateYield(uint256 amount) internal {
        vm.startPrank(owner);
        usdc.mint(owner, amount);
        usdc.approve(address(volatilePool), amount);
        volatilePool.simulateYield(amount);
        vm.stopPrank();
    }

    /// @dev Full cycle — deposit, rebalance, simulate yield, warp to payday, trigger payday
    function _runFullCycle(uint256 yieldAmount) internal returns (uint256 cycleId) {
        cycleId = _depositPayroll();
        _rebalance(cycleId);                    // deploy to pool
        _simulateYield(yieldAmount);            // inject yield
        _warpToPayday(cycleId);                 // fast forward

        _rebalance(cycleId);                    // trigger payday → disburse

    }

    /// @dev Full cycle with no yield
    function _runFullCycleNoYield() internal returns (uint256 cycleId) {
        cycleId = _depositPayroll();
        _warpToPayday(cycleId);
        _rebalance(cycleId);
    }

    /// @dev Calculate expected fee from yield amount
    function _expectedFee(uint256 yieldAmount) internal pure returns (uint256) {
        return (yieldAmount * FEE_BPS) / SCALE;
    }

    /// @dev Calculate expected employee share
    function _expectedShare(uint256 salary, uint256 employeeTotal) internal pure returns (uint256) {
        return (salary * employeeTotal) / TOTAL_PAYROLL;
    }
}