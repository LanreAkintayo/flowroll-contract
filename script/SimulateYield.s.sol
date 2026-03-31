// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {YieldRouter}       from "../src/YieldRouter.sol";
import {PayrollManager}    from "../src/PayrollManager.sol";
import {MockUSDC}          from "../src/mocks/MockUSDC.sol";
import {MockPool}          from "../src/mocks/MockPool.sol";
import {ScenarioBase} from "./ScenarioBase.s.sol";

contract SimulateYield is ScenarioBase {

    // ─── Run ─────────────────────────────────────────────────────────────────

    function run() external  {
        _setupEnvironment();
        // This should be called like in the middle


        // Let's simulate a yield here
        vm.startBroadcast(deployerKey);
        usdc.mint(deployer,2_000e6); // fund deployer to simulate yield earnings
        usdc.approve(address(stable), 1_000e6);
        usdc.approve(address(volatile), 1_000e6);
        stable.simulateYield(1_000e6);
        volatile.simulateYield(1_000e6);
        vm.stopBroadcast();
    }    
}