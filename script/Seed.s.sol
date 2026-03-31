// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {YieldRouter}       from "../src/YieldRouter.sol";
import {PayrollManager}    from "../src/PayrollManager.sol";
import {MockUSDC}          from "../src/mocks/MockUSDC.sol";
import {MockPool}          from "../src/mocks/MockPool.sol";

contract Seed is Script {

    // ─── Structs ─────────────────────────────────────────────────────────────

    struct EmployerSetup {
        address employerAddr;
        string  groupName;
        address employee1;
        address employee2;
        uint256 salary1;
        uint256 salary2;
        uint256 cycleDuration;
    }

    // ─── Config ──────────────────────────────────────────────────────────────

    uint256 constant CYCLE_DURATION = 10 minutes;
    uint256 constant EMPLOYER_FUNDS = 50_000e6;

    // ─── Shared state (set once in run, read by scenario functions) ───────────

    MockUSDC       internal usdc;
    YieldRouter    internal router;
    PayrollManager internal manager;
    MockPool       internal stable;
    uint256        internal deployerKey;
    address        internal deployer;

    // ─── Run ─────────────────────────────────────────────────────────────────

    function run() external {
        usdc       = MockUSDC(vm.envAddress("MOCK_USDC_ADDRESS"));
        router     = YieldRouter(vm.envAddress("YIELD_ROUTER_ADDRESS"));
        manager    = PayrollManager(vm.envAddress("PAYROLL_MANAGER_ADDRESS"));
        stable     = MockPool(vm.envAddress("STABLE_POOL_ADDRESS"));
        deployerKey = vm.envUint("PRIVATE_KEY");
        deployer    = vm.addr(deployerKey);

        _fundEmployers();
        _scenarioA();
        _scenarioB();
        _scenarioC();
        _scenarioD();
        _scenarioF();
        _printSummary();
    }

    // ─── Fund ────────────────────────────────────────────────────────────────

    function _fundEmployers() internal {
        vm.startBroadcast(deployerKey);
        usdc.mint(deployer, EMPLOYER_FUNDS);
        usdc.mint(makeAddress("employerA"), EMPLOYER_FUNDS);
        usdc.mint(makeAddress("employerB"), EMPLOYER_FUNDS);
        usdc.mint(makeAddress("employerC"), EMPLOYER_FUNDS);
        usdc.mint(makeAddress("employerD"), EMPLOYER_FUNDS);
        usdc.mint(makeAddress("employerF"), EMPLOYER_FUNDS);
        vm.stopBroadcast();
        console2.log("Employers funded");
    }

    // ─── Scenario A — Fresh cycle ─────────────────────────────────────────────

    function _scenarioA() internal {
        address employerA = makeAddress("employerA");

        _setupEmployer(EmployerSetup({
            employerAddr:  employerA,
            groupName:     "Engineering",
            employee1:     makeAddress("empA1"),
            employee2:     makeAddress("empA2"),
            salary1:       3_000e6,
            salary2:       2_000e6,
            cycleDuration: CYCLE_DURATION
        }));

        console2.log("Scenario A seeded - fresh cycle");
        console2.log("  Employer A:", employerA);
    }

    // ─── Scenario B — Buffer tier 3 ───────────────────────────────────────────

    function _scenarioB() internal {
        address employerB  = makeAddress("employerB");
        uint256 cycleStart = block.timestamp;

        _setupEmployer(EmployerSetup({
            employerAddr:  employerB,
            groupName:     "Sales",
            employee1:     makeAddress("empB1"),
            employee2:     makeAddress("empB2"),
            salary1:       4_000e6,
            salary2:       1_000e6,
            cycleDuration: CYCLE_DURATION
        }));

        vm.warp(cycleStart + (CYCLE_DURATION * 75) / 100);

        vm.startBroadcast(deployerKey);
        usdc.mint(deployer,500e6); // fund deployer to simulate yield earnings
        usdc.approve(address(stable), 500e6);
        stable.simulateYield(500e6);
        vm.stopBroadcast();

        console2.log("Scenario B seeded - buffer tier 3");
        console2.log("  Employer B:", employerB);
    }

    // ─── Scenario C — Past payday ─────────────────────────────────────────────

    function _scenarioC() internal {
        address employerC  = makeAddress("employerC");
        uint256 cycleStart = block.timestamp;

        _setupEmployer(EmployerSetup({
            employerAddr:  employerC,
            groupName:     "Design",
            employee1:     makeAddress("empC1"),
            employee2:     makeAddress("empC2"),
            salary1:       2_500e6,
            salary2:       2_500e6,
            cycleDuration: CYCLE_DURATION
        }));

        vm.warp(cycleStart + CYCLE_DURATION + 1 minutes);

        vm.startBroadcast(deployerKey);
        usdc.mint(deployer,1_000e6); // fund deployer to simulate yield earnings
        usdc.approve(address(stable), 1_000e6);

        stable.simulateYield(1_000e6);
        vm.stopBroadcast();

        console2.log("Scenario C seeded - past payday");
        console2.log("  Employer C:", employerC);
    }

    // ─── Scenario D — Already closed ─────────────────────────────────────────

    function _scenarioD() internal {
        address employerD  = makeAddress("employerD");
        uint256 cycleStart = block.timestamp;

        _setupEmployer(EmployerSetup({
            employerAddr:  employerD,
            groupName:     "Marketing",
            employee1:     makeAddress("empD1"),
            employee2:     makeAddress("empD2"),
            salary1:       3_000e6,
            salary2:       2_000e6,
            cycleDuration: CYCLE_DURATION
        }));

        vm.warp(cycleStart + CYCLE_DURATION + 2 minutes);

        vm.startBroadcast(deployerKey);
        try router.agentRebalance(employerD, 1) {
            console2.log("Scenario D - cycle pre-settled");
        } catch {
            console2.log("Scenario D - pre-settle failed");
        }
        vm.stopBroadcast();

        console2.log("Scenario D seeded - pre-closed cycle");
        console2.log("  Employer D:", employerD);
    }

    // ─── Scenario F — Auto-save ───────────────────────────────────────────────

    function _scenarioF() internal {
        address employerF  = makeAddress("employerF");
        uint256 cycleStart = block.timestamp;

        _setupEmployer(EmployerSetup({
            employerAddr:  employerF,
            groupName:     "Operations",
            employee1:     makeAddress("empF1"),
            employee2:     makeAddress("empF2"),
            salary1:       6_000e6,
            salary2:       2_000e6,
            cycleDuration: CYCLE_DURATION
        }));

        vm.warp(cycleStart + CYCLE_DURATION + 3 minutes);

        vm.startBroadcast(deployerKey);
        usdc.mint(deployer, 800e6);
        usdc.approve(address(stable), 800e6);

        stable.simulateYield(800e6);
        vm.stopBroadcast();

        console2.log("Scenario F seeded - auto-save flow");
        console2.log("  Employer F:", employerF);
        console2.log("  Employee F1:", makeAddress("empF1"));
    }

    // ─── Summary ─────────────────────────────────────────────────────────────

    function _printSummary() internal pure {
        console2.log("\n==============================================");
        console2.log("  SEED COMPLETE - 5 scenarios ready");
        console2.log("==============================================");
        console2.log("  A  Fresh cycle          -> Rebalanced");
        console2.log("  B  Buffer tier 3        -> BufferAdjusted");
        console2.log("  C  Past payday          -> PaydayTriggered");
        console2.log("  D  Already closed       -> Graceful skip");
        console2.log("  E  Run SeedE.s.sol after TICK #1");
        console2.log("  F  Auto-save flow       -> PaydayTriggered");
        console2.log("==============================================");
        console2.log("Now run the agent:");
        console2.log("  cd scripts/agent && npm start");
        console2.log("==============================================");
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    function _setupEmployer(EmployerSetup memory s) internal {
        vm.startPrank(s.employerAddr);
        manager.registerEmployer();
        manager.createGroup(s.groupName, s.cycleDuration);
        manager.addEmployee(1, s.employee1, s.salary1);
        manager.addEmployee(1, s.employee2, s.salary2);
        usdc.approve(address(manager), s.salary1 + s.salary2);
        manager.depositPayroll(1);
        vm.stopPrank();
    }

    function makeAddress(string memory name) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(name)))));
    }
}