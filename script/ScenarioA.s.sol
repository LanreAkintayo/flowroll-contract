// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {YieldRouter}       from "../src/YieldRouter.sol";
import {PayrollManager}    from "../src/PayrollManager.sol";
import {MockUSDC}          from "../src/mocks/MockUSDC.sol";
import {MockPool}          from "../src/mocks/MockPool.sol";
import {ScenarioBase} from "./ScenarioBase.s.sol";

contract ScenarioA is ScenarioBase {

    // ─── Run ─────────────────────────────────────────────────────────────────

    function run() external  {
        _setupEnvironment();


        _scenarioA();

    }


    // ─── Scenario A — Fresh cycle ─────────────────────────────────────────────

    function _scenarioA() internal {
        uint256 employerAKey = vm.envUint("EMPLOYER_A_PRIVATE_KEY");
        address employerA = vm.addr(employerAKey);

        _fundEmployer(employerA, EMPLOYER_FUNDS);


        _setupEmployer(EmployerSetup({
            employerAddr:  employerA,
            employerKey:   employerAKey,
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


    
}