// // SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {YieldRouter} from "../src/YieldRouter.sol";
import {PayrollManager} from "../src/PayrollManager.sol";
import {PayrollDispatcher} from "../src/PayrollDispatcher.sol";
import {PayVault} from "../src/PayVault.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockPool} from "../src/mocks/MockPool.sol";
import {MockPoolAdapter} from "../src/adapters/MockPoolAdapter.sol";

contract WireContract is Script {
    // ─── Config ──────────────────────────────────────────────────────────────

    uint256 constant INITIAL_SUPPLY = 10_000_000e6;
    uint256 constant INITIAL_TVL = 1_000_000e6;
    uint256 constant STABLE_APY_BPS = 800;
    uint256 constant VOLATILE_APY_BPS = 1_500;
    uint256 constant FEE_BPS = 1_000;
    uint256 constant EMPLOYER_FUNDS = 100_000e6;
    uint256 constant SALARY_1 = 5_000e6;
    uint256 constant SALARY_2 = 3_000e6;
    uint256 constant SALARY_3 = 2_000e6;

    // Cycle duration differs per network
    uint256 constant ANVIL_CYCLE = 2 minutes;
    uint256 constant TESTNET_CYCLE = 4 days; // short enough to demo, long enough to observe


     MockUSDC       internal usdc;
    YieldRouter    internal router;
    PayrollManager internal manager;
    PayVault       internal vault;
    MockPool       internal stable;
    MockPool       internal volatile;
    uint256        internal deployerKey;
    address        internal deployer;
    address        internal agentOp;
    address        internal feeRecipient;
    MockPool       internal stablePool;
    MockPool       internal volatilePool;
    MockPoolAdapter internal stableAdapter;
    MockPoolAdapter internal volatileAdapter;
    PayrollDispatcher internal dispatcher;


    function run() external {
        // ── Detect network ────────────────────────────────────────────────────
        string memory network = vm.envOr("NETWORK", string("anvil"));
        bool isTestnet = keccak256(bytes(network)) ==
            keccak256(bytes("testnet"));

        console2.log("Is it testnet: ", isTestnet);

        usdc        = MockUSDC(vm.envAddress("MOCK_USDC_ADDRESS"));
        router      = YieldRouter(vm.envAddress("YIELD_ROUTER_ADDRESS"));
        manager     = PayrollManager(vm.envAddress("PAYROLL_MANAGER_ADDRESS"));
        stablePool      = MockPool(vm.envAddress("STABLE_POOL_ADDRESS"));
        volatilePool    = MockPool(vm.envAddress("VOLATILE_POOL_ADDRESS"));
        vault    = PayVault(vm.envAddress("PAY_VAULT_ADDRESS"));
        stableAdapter = MockPoolAdapter(vm.envAddress("STABLE_ADAPTER_ADDRESS"));
        volatileAdapter = MockPoolAdapter(vm.envAddress("VOLATILE_ADAPTER_ADDRESS"));
        dispatcher = PayrollDispatcher(vm.envAddress("PAYROLL_DISPATCHER_ADDRESS"));

        if (isTestnet) {
            deployerKey = vm.envUint("TESTNET_PRIVATE_KEY");
        } else {
            // deployerKey = vm.envUint("ANVIL_PRIVATE_KEY");
            deployerKey = vm.envUint("TESTNET_PRIVATE_KEY");
        }

        deployer = vm.addr(deployerKey);
        agentOp = vm.envOr("AGENT_OPERATOR", deployer);
        feeRecipient = vm.envOr("FEE_RECIPIENT", deployer);
        uint256 cycleDuration = isTestnet ? TESTNET_CYCLE : ANVIL_CYCLE;

        console2.log("=== Wiring Contract ===");
        vm.startBroadcast(deployerKey);


        // ── Seed pools ─────────────────────────────────────────────────────
        usdc.approve(address(stablePool), INITIAL_TVL);
        usdc.approve(address(volatilePool), INITIAL_TVL);
        stablePool.deposit(INITIAL_TVL, deployer);
        volatilePool.deposit(INITIAL_TVL, deployer);

        console2.log("Pools seeded with initial TVL");


        // ── 6. Wire up ────────────────────────────────────────────────────────
        router.setPayrollManager(address(manager));
        router.setPayVault(address(vault));
        router.addPool(address(stableAdapter), address(stablePool), true, 500);
        router.addPool(
            address(volatileAdapter),
            address(volatilePool),
            false,
            500
        );

        console2.log("router set up");

        manager.setYieldRouter(address(router));
        manager.setPayrollDispatcher(address(dispatcher));

        console2.log("manager set up");

        dispatcher.setYieldRouter(address(router));
        dispatcher.setPayrollManager(address(manager));
        dispatcher.setPayVault(address(vault));

        console2.log("dispatcher set up");

        vault.setDispatcher(address(dispatcher));
        vault.setYieldRouter(address(router));

        console2.log("Contracts wired");

        // ── Seed test scenario ─────────────────────────────────────────────
        console2.log("Seeding test scenario");
        address employee1 = makeAddress("employee1");
        address employee2 = makeAddress("employee2");
        address employee3 = makeAddress("employee3");

        usdc.mint(deployer, EMPLOYER_FUNDS);
        manager.registerEmployer();
        manager.createGroup("Engineering", cycleDuration);
        manager.addEmployee(1, employee1, SALARY_1);
        manager.addEmployee(1, employee2, SALARY_2);
        manager.addEmployee(1, employee3, SALARY_3);
        usdc.approve(address(manager), type(uint256).max);
        manager.depositPayroll(1);

        console2.log("Test cycle started");
        console2.log("Employee1:         ", employee1);
        console2.log("Employee2:         ", employee2);
        console2.log("Employee3:         ", employee3);

        vm.stopBroadcast();
    }

    function makeAddress(string memory name) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(name)))));
    }
}

