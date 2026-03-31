// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {YieldRouter}       from "../src/YieldRouter.sol";
import {PayrollManager}    from "../src/PayrollManager.sol";
import {MockUSDC}          from "../src/mocks/MockUSDC.sol";
import {MockPool}          from "../src/mocks/MockPool.sol";
import {ScenarioBase} from "./ScenarioBase.s.sol";

contract ScenarioCClaim is ScenarioBase {

    // ─── Run ─────────────────────────────────────────────────────────────────

    function run() external  {
        _setupEnvironment();

         uint256 employeeCKey = vm.envUint("EMPLOYEE_C_PRIVATE_KEY");
        address employeeC = vm.addr(employeeCKey);
        uint256 employeeCSalary = 2_500e6;

        uint256 employeeC2Key = vm.envUint("EMPLOYEE_C2_PRIVATE_KEY");
        address employeeC2 = vm.addr(employeeC2Key);
        uint256 employeeC2Salary = 2_500e6;
        uint256 savePct = 5_000; // 50%
        uint256 saveDuration = 3 minutes;

        // Employee C has been paid but hasn't claimed yet. Employee C will just claim without autosaving.
        vm.startBroadcast(employeeCKey);
        console2.log("USDC Balance before claiming is", usdc.balanceOf(employeeC));
        payVault.claim(employeeCSalary);
        console2.log("USDC Balance after claiming is", usdc.balanceOf(employeeC));
        vm.stopBroadcast();

        // Employee C2 has also been paid. Employee C2 will claim and autosave.

        // Quick one: Let us make payvault an authorized caller of startCycle in yield router
        vm.startBroadcast(deployerKey);
        router.setPayVault(address(payVault));
        vm.stopBroadcast();

        vm.startBroadcast(employeeC2Key);
        console2.log("USDC Balance before claiming is", usdc.balanceOf(employeeC2));
        payVault.claimAndSave(employeeC2Salary, savePct, saveDuration );
        console2.log("USDC Balance after claiming is", usdc.balanceOf(employeeC2));
        vm.stopBroadcast();
    }    
}