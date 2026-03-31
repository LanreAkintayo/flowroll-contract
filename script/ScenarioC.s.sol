// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {YieldRouter}       from "../src/YieldRouter.sol";
import {PayrollManager}    from "../src/PayrollManager.sol";
import {MockUSDC}          from "../src/mocks/MockUSDC.sol";
import {MockPool}          from "../src/mocks/MockPool.sol";
import {ScenarioBase} from "./ScenarioBase.s.sol";

contract ScenarioC is ScenarioBase {

    // ─── Run ─────────────────────────────────────────────────────────────────

    function run() external  {
        _setupEnvironment();
        _scenarioC();

    }


    // ─── Scenario B — Buffer tier 3 ───────────────────────────────────────────

    function _scenarioC() internal {
        uint256 employerCKey = vm.envUint("EMPLOYER_C_PRIVATE_KEY");
        address employerC = vm.addr(employerCKey);

        _fundEmployer(employerC, EMPLOYER_FUNDS);

        uint256 employeeCKey = vm.envUint("EMPLOYEE_C_PRIVATE_KEY");
        address employeeC = vm.addr(employeeCKey);

        uint256 employeeC2Key = vm.envUint("EMPLOYEE_C2_PRIVATE_KEY");
        address employeeC2 = vm.addr(employeeC2Key);


        _setupEmployer(EmployerSetup({
            employerAddr:  employerC,
            employerKey:   employerCKey,
            groupName:     "Design",
            employee1:     employeeC,
            employee2:     employeeC2,
            salary1:       2_500e6,
            salary2:       2_500e6,
            cycleDuration: CYCLE_DURATION
        }));

        // vm.warp(cycleStart + CYCLE_DURATION + 1 minutes);

        vm.startBroadcast(deployerKey);
        usdc.mint(deployer,1_000e6); // fund deployer to simulate yield earnings
        usdc.approve(address(stable), 1_000e6);

        stable.simulateYield(1_000e6);
        vm.stopBroadcast();

        // console2.log("Scenario C seeded - past payday");
        console2.log("  Employer C:", employerC);
    }

    
}