// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {PayrollManager}    from "../src/PayrollManager.sol";
import {MockUSDC}          from "../src/mocks/MockUSDC.sol";

/**
 * @title SeedE
 * @notice Seeds Scenario E - late employer discovery.
 *
 * @dev Run this AFTER the agent has completed TICK #1.
 *      The agent will discover employerE via CycleStarted event on TICK #2.
 *
 * Run:
 *   forge script script/SeedE.s.sol \
 *     --rpc-url http://localhost:8545  \
 *     --broadcast                      \
 *     --private-key $PRIVATE_KEY
 */
contract SeedE is Script {

    uint256 constant CYCLE_DURATION = 10 minutes;
    uint256 constant EMPLOYER_FUNDS = 20_000e6;
    uint256 constant SALARY_E1      = 5_000e6;

    function run() external {
        address usdcAddr    = vm.envAddress("MOCK_USDC_ADDRESS");
        address managerAddr = vm.envAddress("PAYROLL_MANAGER_ADDRESS");

        MockUSDC       usdc    = MockUSDC(usdcAddr);
        PayrollManager manager = PayrollManager(managerAddr);

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address employerE   = makeAddress("employerE");
        address empE1       = makeAddress("empE1");

        // Fund employerE
        vm.startBroadcast(deployerKey);
        usdc.mint(employerE, EMPLOYER_FUNDS);
        vm.stopBroadcast();

        // Register and deposit as employerE
        vm.startPrank(employerE);

        manager.registerEmployer();
        manager.createGroup("Product", CYCLE_DURATION);
        manager.addEmployee(1, empE1, SALARY_E1);

        usdc.approve(address(manager), SALARY_E1);
        manager.depositPayroll(1);

        vm.stopPrank();

        console2.log("==============================================");
        console2.log("  Scenario E seeded - late employer discovery");
        console2.log("==============================================");
        console2.log("  Employer E:", employerE);
        console2.log("  Employee E1:", empE1);
        console2.log("  Watch TICK #2 - agent discovers employerE");
        console2.log("  via CycleStarted event and rebalances");
        console2.log("==============================================");
    }

    function makeAddress(string memory name) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(name)))));
    }
}
