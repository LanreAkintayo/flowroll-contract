// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {YieldRouter}       from "../src/YieldRouter.sol";
import {PayrollManager}    from "../src/PayrollManager.sol";
import {MockUSDC}          from "../src/mocks/MockUSDC.sol";
import {MockPool}          from "../src/mocks/MockPool.sol";
import {ScenarioBase} from "./ScenarioBase.s.sol";

contract ScenarioC2FinalClaim is ScenarioBase {

    // ─── Run ─────────────────────────────────────────────────────────────────

    function run() external  {
        _setupEnvironment();

    
        uint256 employeeC2Key = vm.envUint("EMPLOYEE_C2_PRIVATE_KEY");
        address employeeC2 = vm.addr(employeeC2Key);

        // Employee C2 has also been finally settled. Employee C2 will claim. If there is yield, they should receive more than what they put in. Otherwise, it should remain the same.

        vm.startBroadcast(employeeC2Key);
        uint256 balanceBefore = usdc.balanceOf(employeeC2);
        console2.log("USDC Balance before claiming is", balanceBefore);
        
        uint256 balanceToClaim = payVault.getBalance(employeeC2);
        payVault.claim(balanceToClaim);

        uint256 balanceAfter = usdc.balanceOf(employeeC2);
        console2.log("USDC Balance after claiming is", balanceAfter);

        uint256 amountClaimed = balanceAfter - balanceBefore;
        console2.log("Amount claimed is", amountClaimed);
        vm.stopBroadcast();

    }    
}