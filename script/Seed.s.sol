// script/Seed.s.sol
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {PayrollManager} from "../src/PayrollManager.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";

contract Seed is Script {
    function run() external {
        uint256 key      = vm.envUint("SECOND_PRIVATE_KEY");
        address employer = vm.addr(key);

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        // address deployer = vm.addr(deployerKey);

        address managerAddr = vm.envAddress("PAYROLL_MANAGER_ADDRESS");
        address usdcAddr    = vm.envAddress("MOCK_USDC_ADDRESS");

        PayrollManager manager = PayrollManager(managerAddr);
        MockUSDC usdc          = MockUSDC(usdcAddr);

        // Mint some USDC to the deployer
        vm.startBroadcast(deployerKey); 
        usdc.mint(employer, 50_000e6);
        vm.stopBroadcast();

        vm.startBroadcast(key);
        manager.registerEmployer();
        manager.createGroup("Sales", 10 minutes);
        manager.addEmployee(1, makeAddress("salesEmployee1"), 4_000e6);
        manager.addEmployee(1, makeAddress("salesEmployee2"), 2_000e6);
        usdc.approve(managerAddr, type(uint256).max);
        manager.depositPayroll(1);

        console2.log("New employer seeded:", employer);

        vm.stopBroadcast();
    }

    function makeAddress(string memory name) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(name)))));
    }
}