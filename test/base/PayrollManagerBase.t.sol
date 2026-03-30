// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SharedBase} from "./SharedBase.t.sol";
import {PayrollManager} from "../../src/PayrollManager.sol";
import {YieldRouter} from "../../src/YieldRouter.sol";
import {MockPool} from "../../src/mocks/MockPool.sol";
import {MockPoolAdapter} from "../../src/adapters/MockPoolAdapter.sol";
import {MockPayrollDispatcher} from "../../src/mocks/MockPayrollDispatcher.sol";

/**
 * @dev Deploys the full stack — PayrollManager wired to a real YieldRouter.
 *      We use the real YieldRouter rather than a mock so depositPayroll and
 *      cancelCycle tests exercise the actual integration path.
 */
abstract contract PayrollManagerBase is SharedBase {

    // ─── Contracts ───────────────────────────────────────────────────────────

    PayrollManager        internal manager;
    YieldRouter           internal router;
    MockPool              internal stablePool;
    MockPoolAdapter       internal stableAdapter;
    MockPayrollDispatcher internal dispatcher;

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 internal constant INITIAL_TVL      = 1_000_000e6;
    uint256 internal constant STABLE_APY_BPS   = 800;
    uint256 internal constant STABLE_MIN_APY   = 500;
    uint256 internal constant FEE_BPS          = 200; // 2%
    // uint256 internal constant CYCLE_DURATION   = 30 days;
    uint256 internal constant EMPLOYEE_SALARY  = 5_000e6;  // $5k
    uint256 internal constant EMPLOYEE_SALARY2 = 3_000e6;  // $3k

    address internal feeRecipient = makeAddr("feeRecipient");
    address internal employee2    = makeAddr("employee2");
    address internal employee3    = makeAddr("employee3");

    // ─── Setup ───────────────────────────────────────────────────────────────

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(owner);

        // Deploy pool and adapter — needed for YieldRouter pool registration
        stablePool = new MockPool(
            address(usdc),
            "USDC/iUSD Stable Pool",
            STABLE_APY_BPS,
            true,
            "Flowroll Stable Shares",
            "frUSDC-S"
        );

        usdc.mint(owner, INITIAL_TVL);
        usdc.approve(address(stablePool), INITIAL_TVL);
        stablePool.deposit(INITIAL_TVL, owner);

        stableAdapter = new MockPoolAdapter(address(usdc), address(stablePool));

        // Deploy YieldRouter
        router = new YieldRouter(agentOperator, address(usdc));
        router.addPool(address(stableAdapter), address(stablePool), true, STABLE_MIN_APY);

        // Deploy PayrollManager
        manager = new PayrollManager(address(usdc), feeRecipient, FEE_BPS);

        // Deploy MockPayrollDispatcher
        dispatcher = new MockPayrollDispatcher();

        // Wire up
        // router.setTreasury(address(manager));
        router.setPayrollManager(address(manager));

        // router.setPayrollDispatcher(address(dispatcher));
        manager.setYieldRouter(address(router));
        manager.setPayrollDispatcher(address(dispatcher));

        vm.stopPrank();

        // Fund employer and pre-approve manager
        vm.startPrank(owner);
        usdc.mint(employer, DEPOSIT_AMOUNT * 20);
        vm.stopPrank();

        vm.prank(employer);
        usdc.approve(address(manager), type(uint256).max);
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    /// @dev Register employer and create a group with one employee
    function _setupGroup() internal returns (uint256 groupId) {
        vm.startPrank(employer);
        manager.registerEmployer();
        groupId = manager.createGroup("Engineering", CYCLE_DURATION);
        manager.addEmployee(groupId, employee, EMPLOYEE_SALARY);
        vm.stopPrank();
    }

    /// @dev Full setup + deposit payroll — group has active cycle after this
    function _setupGroupWithActiveCycle() internal returns (uint256 groupId) {
        groupId = _setupGroup();
        vm.prank(employer);
        manager.depositPayroll(groupId);
    }
}
