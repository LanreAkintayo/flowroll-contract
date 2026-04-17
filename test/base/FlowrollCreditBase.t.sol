// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FlowrollCredit} from "../../src/FlowrollCredit.sol";
import {SharedBase} from "./SharedBase.t.sol";
import {PayVault} from "../../src/PayVault.sol";
import {PayrollManagerBase} from "./PayrollManagerBase.t.sol";
import {PayrollManager} from "../../src/PayrollManager.sol";
import {YieldRouter} from "../../src/YieldRouter.sol";
import {MockPool} from "../../src/mocks/MockPool.sol";
import {MockPoolAdapter} from "../../src/adapters/MockPoolAdapter.sol";
import {PayrollDispatcher} from "../../src/PayrollDispatcher.sol";

abstract contract FlowrollCreditBase is SharedBase {
    // ─── Contracts ───────────────────────────────────────────────────────────

    // PayrollManager internal manager;
    // YieldRouter internal router;
    // MockPool internal stablePool;
    // MockPoolAdapter internal stableAdapter;
    // PayrollDispatcher internal dispatcher;
    // FlowrollCredit internal credit;
    // PayVault internal vault;

    // ─── Constants ───────────────────────────────────────────────────────────

    // uint256 internal constant INITIAL_TVL = 1_000_000e6;
    // uint256 internal constant STABLE_APY_BPS = 800;
    // uint256 internal constant STABLE_MIN_APY = 500;
    // uint256 internal constant CREDIT_FEE_BPS = 150; // 1.5%
    // uint256 internal constant MAX_ADVANCE_BPS = 8_000;
    // uint256 internal constant CYCLE_DURATION   = 30 days;
    // uint256 internal constant EMPLOYEE_SALARY = 5_000e6; // $5k
    // uint256 internal constant EMPLOYEE_SALARY2 = 3_000e6; // $3k
    // uint256 internal constant CREDIT_LIQUIDITY = 100_000e6; // 100k USDC for CREDIT_LIQUIDITY

    // address internal feeRecipient = makeAddr("feeRecipient");
    // address internal employee2 = makeAddr("employee2");
    // address internal employee3 = makeAddr("employee3");

    // ─── Setup ───────────────────────────────────────────────────────────────

    function setUp() public virtual override {
        super.setUp();

        // vm.startPrank(owner);

        // // Deploy pool and adapter — needed for YieldRouter pool registration
        // stablePool = new MockPool(
        //     address(usdc),
        //     "USDC/iUSD Stable Pool",
        //     STABLE_APY_BPS,
        //     true,
        //     "Flowroll Stable Shares",
        //     "frUSDC-S"
        // );

        // usdc.mint(owner, INITIAL_TVL);
        // usdc.approve(address(stablePool), INITIAL_TVL);
        // stablePool.deposit(INITIAL_TVL, owner);

        // stableAdapter = new MockPoolAdapter(address(usdc), address(stablePool));

        // // Deploy YieldRouter
        // router = new YieldRouter(agentOperator, address(usdc));
        // router.addPool(
        //     address(stableAdapter),
        //     address(stablePool),
        //     true,
        //     STABLE_MIN_APY
        // );

        // // Deploy PayrollManager
        // manager = new PayrollManager(
        //     address(usdc),
        //     feeRecipient,
        //     CREDIT_FEE_BPS
        // );

        // dispatcher = new PayrollDispatcher(
        //     address(usdc),
        //     feeRecipient,
        //     CREDIT_FEE_BPS
        // );

        // // Deploy FlowrollCredit
        // credit = new FlowrollCredit(
        //     address(usdc),
        //     CREDIT_FEE_BPS,
        //     MAX_ADVANCE_BPS
        // );

        // // Deploy PayVault
        // vault = new PayVault(address(usdc), owner, 500);


        // // Wire up contracts
        // router.setPayrollManager(address(manager));
        // router.setPayVault(address(vault));

        // manager.setYieldRouter(address(router));
        // manager.setPayrollDispatcher(address(dispatcher));
        // manager.setPayVault(address(vault));

        // credit.setPayrollManager(address(manager));
        // credit.setPayVault(address(vault));

        // dispatcher.setPayrollManager(address(manager));
        // dispatcher.setPayVault(address(vault));
        // dispatcher.setYieldRouter(address(router));

        // vault.setPayrollManager(address(manager));
        // vault.setDispatcher(address(dispatcher));
        // vault.setYieldRouter(address(router));
        // vault.setFlowrollCredit(address(credit));
        

        // // Let's put liquidity in FLowroll Credit
        // usdc.mint(address(credit), CREDIT_LIQUIDITY);
        // vm.stopPrank();


        // vm.prank(employer);
        // usdc.approve(address(manager), type(uint256).max);
    }

    function _setupStandardPayroll() internal returns (uint256 groupId) {
        address[] memory employees = new address[](1);
        employees[0] = employee;

        uint256[] memory salaries = new uint256[](1);
        salaries[0] = EMPLOYEE_SALARY;

        vm.startPrank(employer);
        groupId = manager.createGroup("Tech Team", CYCLE_DURATION);

        usdc.approve(address(manager), type(uint256).max);
        manager.setUpPayroll(groupId, employees, salaries);
        vm.stopPrank();

        vm.prank(agentOperator);
        router.agentRebalance(employer, 1);
    }
}
