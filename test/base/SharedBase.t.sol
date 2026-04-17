// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";
import {FlowrollCredit} from "../../src/FlowrollCredit.sol";
// import {SharedBase} from "./SharedBase.t.sol";
import {PayVault} from "../../src/PayVault.sol";
// import {PayrollManagerBase} from "./PayrollManagerBase.t.sol";
import {PayrollManager} from "../../src/PayrollManager.sol";
import {YieldRouter} from "../../src/YieldRouter.sol";
import {MockPool} from "../../src/mocks/MockPool.sol";
import {MockPoolAdapter} from "../../src/adapters/MockPoolAdapter.sol";
import {PayrollDispatcher} from "../../src/PayrollDispatcher.sol";

abstract contract SharedBase is Test {

    // ─── Actors ──────────────────────────────────────────────────────────────

    address internal owner        = makeAddr("owner");
    address internal agentOperator = makeAddr("agentOperator");
    address internal treasury     = makeAddr("treasury");
    address internal employer     = makeAddr("employer");
    address internal stranger     = makeAddr("stranger");
    address internal employee     = makeAddr("employee");
    address internal employee2     = makeAddr("employee2");
    address internal employee3     = makeAddr("employee3");
    address internal feeRecipient = makeAddr("feeRecipient");

    // ─── Tokens ──────────────────────────────────────────────────────────────

    MockUSDC internal usdc;
    PayrollManager internal manager;
    YieldRouter internal router;
    MockPool internal stablePool;
    MockPool internal volatilePool;
    MockPoolAdapter internal stableAdapter;
    MockPoolAdapter internal volatileAdapter;
    PayrollDispatcher internal dispatcher;
    FlowrollCredit internal credit;
    PayVault internal vault;

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 internal constant INITIAL_SUPPLY  = 10_000_000e6; // 10M USDC
    uint256 internal constant DEPOSIT_AMOUNT  = 50_000e6;     // 50k USDC
    uint256 internal constant CYCLE_DURATION  = 30 days;
    uint256 internal constant SCALE           = 10_000;
    uint256 internal constant FEE_BPS          = 1_000; // 10%

    uint256 internal constant INITIAL_TVL = 1_000_000e6;
    uint256 internal constant STABLE_APY_BPS = 800;
    uint256 internal constant STABLE_MIN_APY = 500;
    uint256 internal constant VOLATILE_APY_BPS = 1_500; // 15%
    uint256 internal constant VOLATILE_MIN_APY = 500;

    uint256 internal constant CREDIT_FEE_BPS = 150; // 1.5%
    uint256 internal constant MAX_ADVANCE_BPS = 8_000;
    // uint256 internal constant CYCLE_DURATION   = 30 days;
    uint256 internal constant EMPLOYEE_SALARY = 5_000e6; // $5k
    // uint256 internal constant EMPLOYEE_SALARY2 = 3_000e6; // $3k
    uint256 internal constant CREDIT_LIQUIDITY = 100_000e6; // 100k USDC for CREDIT_LIQUIDITY

    // ─── Setup ───────────────────────────────────────────────────────────────

    function setUp() public virtual {
        vm.startPrank(owner);
        usdc = new MockUSDC(INITIAL_SUPPLY);
        usdc.mint(treasury,  DEPOSIT_AMOUNT * 10);
        usdc.mint(employer,  DEPOSIT_AMOUNT * 10);
        usdc.mint(employee,  DEPOSIT_AMOUNT * 10);
        vm.stopPrank();

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

        volatilePool = new MockPool(
            address(usdc),
            "USDC/INIT Volatile Pool",
            VOLATILE_APY_BPS,
            false,
            "Flowroll Volatile Shares",
            "frUSDC-V"
        );

        usdc.mint(owner, INITIAL_TVL);

        usdc.approve(address(stablePool), INITIAL_TVL);
        usdc.approve(address(volatilePool), INITIAL_TVL);

        stablePool.deposit(INITIAL_TVL, owner);
        volatilePool.deposit(INITIAL_TVL, owner);

        stableAdapter = new MockPoolAdapter(address(usdc), address(stablePool));
        volatileAdapter = new MockPoolAdapter(
            address(usdc),
            address(volatilePool)
        );


        // Deploy YieldRouter
        router = new YieldRouter(agentOperator, address(usdc));
        router.addPool(
            address(stableAdapter),
            address(stablePool),
            true,
            STABLE_MIN_APY
        );
         router.addPool(
            address(volatileAdapter),
            address(volatilePool),
            false,
            VOLATILE_MIN_APY
        );


        // Deploy PayrollManager
        manager = new PayrollManager(
            address(usdc),
            feeRecipient,
            CREDIT_FEE_BPS
        );

        dispatcher = new PayrollDispatcher(
            address(usdc),
            feeRecipient,
            CREDIT_FEE_BPS
        );

        // Deploy FlowrollCredit
        credit = new FlowrollCredit(
            address(usdc),
            CREDIT_FEE_BPS,
            MAX_ADVANCE_BPS
        );

        // Deploy PayVault
        vault = new PayVault(address(usdc), feeRecipient, CREDIT_FEE_BPS);


        // Wire up contracts
        router.setPayrollManager(address(manager));
        router.setPayVault(address(vault));

        manager.setYieldRouter(address(router));
        manager.setPayrollDispatcher(address(dispatcher));
        manager.setPayVault(address(vault));

        credit.setPayrollManager(address(manager));
        credit.setPayVault(address(vault));

        dispatcher.setPayrollManager(address(manager));
        dispatcher.setPayVault(address(vault));
        dispatcher.setYieldRouter(address(router));

        vault.setPayrollManager(address(manager));
        vault.setDispatcher(address(dispatcher));
        vault.setYieldRouter(address(router));
        vault.setFlowrollCredit(address(credit));
        

        // Let's put liquidity in FLowroll Credit
        usdc.mint(address(credit), CREDIT_LIQUIDITY);
        usdc.mint(address(manager), DEPOSIT_AMOUNT * 10);
        // usdc.mint(employer, DEPOSIT_AMOUNT);
        // usdc.mint(employer, DEPOSIT_AMOUNT);
        
        vm.stopPrank();


        vm.prank(employer);
        usdc.approve(address(manager), type(uint256).max);
    }


    function _setupPayroll(address caller) internal returns(uint256 cycleId) {
        address[] memory employees = new address[](1);
        employees[0] = employee;

        uint256[] memory salaries = new uint256[](1);
        salaries[0] = DEPOSIT_AMOUNT;

        vm.startPrank(caller);
        uint256 groupId = manager.createGroup("Tech Team", CYCLE_DURATION);

        usdc.approve(address(manager), DEPOSIT_AMOUNT);

        cycleId = manager.setUpPayroll(groupId, employees, salaries);
        vm.stopPrank();
    }

      /// @dev Warp to exactly payday
    function _warpToPayday() internal {
        uint256 payday = router.getCycle(employer, 1).payDay;
        vm.warp(payday + 1);
    }

     /// @dev Warp so that exactly `timeLeft` seconds remain before payday
    function _warpToTimeLeft(uint256 timeLeft) internal {
        router.getCycle(employer, 1);
        uint256 payday = router.getCycle(employer, 1).payDay;
        vm.warp(payday - timeLeft);
    }
}