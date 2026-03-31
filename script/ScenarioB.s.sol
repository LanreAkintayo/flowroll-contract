// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {YieldRouter}       from "../src/YieldRouter.sol";
import {PayrollManager}    from "../src/PayrollManager.sol";
import {MockUSDC}          from "../src/mocks/MockUSDC.sol";
import {MockPool}          from "../src/mocks/MockPool.sol";
import {ScenarioBase} from "./ScenarioBase.s.sol";

contract ScenarioB is ScenarioBase {

    // ─── Run ─────────────────────────────────────────────────────────────────

    function run() external  {
        _setupEnvironment();


        _scenarioB();

    }


    // ─── Scenario B — Buffer tier 3 ───────────────────────────────────────────

    function _scenarioB() internal {

         uint256 employerBKey = vm.envUint("EMPLOYER_B_PRIVATE_KEY");
        address employerB = vm.addr(employerBKey);

        _fundEmployer(employerB, EMPLOYER_FUNDS);


        uint256 cycleStart = block.timestamp;

        _setupEmployer(EmployerSetup({
            employerAddr:  employerB,
            employerKey:   employerBKey,
            groupName:     "Sales",
            employee1:     makeAddress("empB1"),
            employee2:     makeAddress("empB2"),
            salary1:       4_000e6,
            salary2:       1_000e6,
            cycleDuration: CYCLE_DURATION
        }));

        // vm.warp(cycleStart + (CYCLE_DURATION * 75) / 100);

        vm.startBroadcast(deployerKey);
        usdc.mint(deployer,500e6); // fund deployer to simulate yield earnings
        usdc.approve(address(stable), 500e6);
        stable.simulateYield(500e6);
        vm.stopBroadcast();

        console2.log("Scenario B seeded - buffer tier 3");
        console2.log("  Employer B:", employerB);
    }

    
}