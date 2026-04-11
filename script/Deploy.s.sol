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

contract Deploy is Script {
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
    uint256 constant TESTNET_CYCLE = 10 minutes; // short enough to demo, long enough to observe

    function run() external {
        // ── Detect network ────────────────────────────────────────────────────
        string memory network = vm.envOr("NETWORK", string("anvil"));
        bool isTestnet = keccak256(bytes(network)) ==
            keccak256(bytes("testnet"));

        uint256 deployerKey;
        if (isTestnet) {
            deployerKey = vm.envUint("TESTNET_PRIVATE_KEY");
        } else {
            deployerKey = vm.envUint("ANVIL_PRIVATE_KEY");
        }


        address deployer = vm.addr(deployerKey);
        address agentOp = vm.envOr("AGENT_OPERATOR", deployer);
        address feeRecipient = vm.envOr("FEE_RECIPIENT", deployer);
        uint256 cycleDuration = isTestnet ? TESTNET_CYCLE : ANVIL_CYCLE;

        console2.log("=== Flowroll Deploy ===");
        console2.log("Deployer key: ", deployerKey);
        console2.log("Network:    ", isTestnet ? "Initia Testnet" : "Anvil");
        console2.log("Deployer:   ", deployer);
        console2.log("AgentOp:    ", agentOp);
        console2.log("Fee Recip:  ", feeRecipient);
        console2.log("Cycle:      ", cycleDuration, "seconds");
        console2.log("");

        vm.startBroadcast(deployerKey);

        // ── 1. MockUSDC ───────────────────────────────────────────────────────
        // MockUSDC usdc = new MockUSDC(INITIAL_SUPPLY);
        MockUSDC usdc = MockUSDC(vm.envAddress("MOCK_USDC_ADDRESS"));

        console2.log("MockUSDC:          ", address(usdc));

        // ── 2. Pools ──────────────────────────────────────────────────────────
        MockPool stablePool = new MockPool(
            address(usdc),
            "Flowroll Stable Yield Vault",
            STABLE_APY_BPS,
            true,
            "Flowroll Stable Shares",
            "frUSDC-S"
        );

        MockPool volatilePool = new MockPool(
            address(usdc),
            "Flowroll INIT-Linked Vault",
            VOLATILE_APY_BPS,
            false,
            "Flowroll Volatile Shares",
            "frUSDC-V"
        );

        console2.log("StablePool:        ", address(stablePool));
        console2.log("VolatilePool:      ", address(volatilePool));

        // ── 3. Seed pools ─────────────────────────────────────────────────────
        // usdc.approve(address(stablePool), INITIAL_TVL);
        // usdc.approve(address(volatilePool), INITIAL_TVL);
        // stablePool.deposit(INITIAL_TVL, deployer);
        // volatilePool.deposit(INITIAL_TVL, deployer);

        // ── 4. Adapters ───────────────────────────────────────────────────────
        MockPoolAdapter stableAdapter = new MockPoolAdapter(
            address(usdc),
            address(stablePool)
        );
        MockPoolAdapter volatileAdapter = new MockPoolAdapter(
            address(usdc),
            address(volatilePool)
        );
        console2.log("StableAdapter:     ", address(stableAdapter));
        console2.log("VolatileAdapter:   ", address(volatileAdapter));

        // ── 5. Core contracts ─────────────────────────────────────────────────
        YieldRouter router = new YieldRouter(agentOp, address(usdc));
        PayrollDispatcher dispatcher = new PayrollDispatcher(
            address(usdc),
            feeRecipient,
            FEE_BPS
        );
        PayVault vault = new PayVault(address(usdc), feeRecipient, FEE_BPS);
        PayrollManager manager = new PayrollManager(
            address(usdc),
            feeRecipient,
            FEE_BPS
        );

        console2.log("YieldRouter:       ", address(router));
        console2.log("PayrollDispatcher: ", address(dispatcher));
        console2.log("PayVault:          ", address(vault));
        console2.log("PayrollManager:    ", address(manager));

        // ── 6. Wire up ────────────────────────────────────────────────────────
        // router.setPayrollManager(address(manager));
        // router.setPayVault(address(vault));
        // router.addPool(address(stableAdapter), address(stablePool), true, 500);
        // router.addPool(
        //     address(volatileAdapter),
        //     address(volatilePool),
        //     false,
        //     500
        // );

        // manager.setYieldRouter(address(router));
        // manager.setPayrollDispatcher(address(dispatcher));

        // dispatcher.setYieldRouter(address(router));
        // dispatcher.setPayrollManager(address(manager));
        // dispatcher.setPayVault(address(vault));

        // vault.setDispatcher(address(dispatcher));
        // vault.setYieldRouter(address(router));

        console2.log("Contracts wired");

        // ── 7. Seed test scenario ─────────────────────────────────────────────
        // address employee1 = makeAddress("employee1");
        // address employee2 = makeAddress("employee2");
        // address employee3 = makeAddress("employee3");

        // usdc.mint(deployer, EMPLOYER_FUNDS);
        // manager.registerEmployer();
        // manager.createGroup("Engineering", cycleDuration);
        // manager.addEmployee(1, employee1, SALARY_1);
        // manager.addEmployee(1, employee2, SALARY_2);
        // manager.addEmployee(1, employee3, SALARY_3);
        // usdc.approve(address(manager), type(uint256).max);
        // manager.depositPayroll(1);

        // console2.log("Test cycle started");
        // console2.log("Employee1:         ", employee1);
        // console2.log("Employee2:         ", employee2);
        // console2.log("Employee3:         ", employee3);

        vm.stopBroadcast();

       // ── 8. Print env block ────────────────────────────────────────────────
        console2.log("\n--- COPY TO scripts/agent/.env ---");
        // console2.log("NETWORK=", network);
        console2.log("MOCK_USDC_ADDRESS=", address(usdc));
        console2.log("STABLE_POOL_ADDRESS=", address(stablePool));
        console2.log("VOLATILE_POOL_ADDRESS=", address(volatilePool));
        console2.log("STABLE_ADAPTER_ADDRESS=", address(stableAdapter));
        console2.log("VOLATILE_ADAPTER_ADDRESS=", address(volatileAdapter));
        console2.log("YIELD_ROUTER_ADDRESS=", address(router));
        console2.log("PAYROLL_MANAGER_ADDRESS=", address(manager));
        console2.log("PAYROLL_DISPATCHER_ADDRESS=", address(dispatcher));
        console2.log("PAY_VAULT_ADDRESS=", address(vault));
        console2.log("DEPLOYMENT_BLOCK=0");
        console2.log("----------------------------------\n");
    }

    function makeAddress(string memory name) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(name)))));
    }
}

// pragma solidity ^0.8.24;

// import {Script, console2} from "forge-std/Script.sol";
// import {YieldRouter} from "../src/YieldRouter.sol";
// import {PayrollManager} from "../src/PayrollManager.sol";
// import {PayrollDispatcher} from "../src/PayrollDispatcher.sol";
// import {PayVault} from "../src/PayVault.sol";
// import {MockUSDC} from "../src/mocks/MockUSDC.sol";
// import {MockPool} from "../src/mocks/MockPool.sol";
// import {MockPoolAdapter} from "../src/adapters/MockPoolAdapter.sol";

// contract Deploy is Script {
//     // ─── Config ──────────────────────────────────────────────────────────────

//     uint256 constant INITIAL_SUPPLY = 10_000_000e6; // 10M USDC
//     uint256 constant INITIAL_TVL = 1_000_000e6; // 1M USDC per pool
//     uint256 constant STABLE_APY_BPS = 800; // 8%
//     uint256 constant VOLATILE_APY_BPS = 1_500; // 15%
//     uint256 constant FEE_BPS = 1_000; // 10% of yield
//     uint256 constant EMPLOYER_FUNDS = 100_000e6; // 100k USDC
//     uint256 constant SALARY_1 = 5_000e6; // 5k USDC
//     uint256 constant SALARY_2 = 3_000e6; // 3k USDC
//     uint256 constant SALARY_3 = 2_000e6; // 2k USDC
//     uint256 constant CYCLE_DURATION = 2 minutes; // short for local testing

//     function run() external {
//         uint256 deployerKey = vm.envUint("PRIVATE_KEY");
//         address deployer = vm.addr(deployerKey);
//         address agentOp = vm.envOr("AGENT_OPERATOR", deployer);
//         address feeRecipient = vm.envOr("FEE_RECIPIENT", deployer);

//         vm.startBroadcast(deployerKey);

//         // ── 1. Deploy MockUSDC ────────────────────────────────────────────────
//         MockUSDC usdc = new MockUSDC(INITIAL_SUPPLY);
//         console2.log("MockUSDC:          ", address(usdc));

//         // ── 2. Deploy Pools ───────────────────────────────────────────────────
//         MockPool stablePool = new MockPool(
//             address(usdc),
//             "Flowroll Stable Yield Vault",
//             STABLE_APY_BPS,
//             true,
//             "Flowroll Stable Shares",
//             "frUSDC-S"
//         );
//         console2.log("StableVault:         ", address(stablePool));

//         MockPool volatilePool = new MockPool(
//             address(usdc),
//             "Flowroll INIT-Linked Vault",
//             VOLATILE_APY_BPS,
//             false,
//             "Flowroll Volatile Shares",
//             "frUSDC-V"
//         );
//         console2.log("VolatileVault:       ", address(volatilePool));

//         // ── 3. Seed pools with initial TVL ────────────────────────────────────
//         usdc.approve(address(stablePool), INITIAL_TVL);
//         usdc.approve(address(volatilePool), INITIAL_TVL);
//         stablePool.deposit(INITIAL_TVL, deployer);
//         volatilePool.deposit(INITIAL_TVL, deployer);
//         console2.log("Pools seeded with initial TVL");

//         // ── 4. Deploy Adapters ────────────────────────────────────────────────
//         MockPoolAdapter stableAdapter = new MockPoolAdapter(
//             address(usdc),
//             address(stablePool)
//         );
//         console2.log("StableAdapter:     ", address(stableAdapter));

//         MockPoolAdapter volatileAdapter = new MockPoolAdapter(
//             address(usdc),
//             address(volatilePool)
//         );
//         console2.log("VolatileAdapter:   ", address(volatileAdapter));

//         // ── 5. Deploy YieldRouter ─────────────────────────────────────────────
//         YieldRouter router = new YieldRouter(agentOp, address(usdc));
//         console2.log("YieldRouter:       ", address(router));

//         // ── 6. Deploy PayrollDispatcher ───────────────────────────────────────
//         PayrollDispatcher dispatcher = new PayrollDispatcher(
//             address(usdc),
//             feeRecipient,
//             FEE_BPS
//         );
//         console2.log("PayrollDispatcher: ", address(dispatcher));

//         // ── 7. Deploy PayVault ────────────────────────────────────────────────
//         PayVault vault = new PayVault(address(usdc), feeRecipient, FEE_BPS);
//         console2.log("PayVault:          ", address(vault));

//         // ── 8. Deploy PayrollManager ──────────────────────────────────────────
//         PayrollManager manager = new PayrollManager(
//             address(usdc),
//             feeRecipient,
//             FEE_BPS
//         );
//         console2.log("PayrollManager:    ", address(manager));

//         // ── 9. Wire everything up ─────────────────────────────────────────────
//         // YieldRouter
//         router.setPayrollManager(address(manager));
//         router.setPayVault(address(vault));
//         router.setAgentOperator(agentOp);
//         router.addPool(address(stableAdapter), address(stablePool), true, 500);
//         router.addPool(
//             address(volatileAdapter),
//             address(volatilePool),
//             false,
//             500
//         );

//         // PayrollManager
//         manager.setYieldRouter(address(router));
//         manager.setPayrollDispatcher(address(dispatcher));

//         // PayrollDispatcher
//         dispatcher.setYieldRouter(address(router));
//         dispatcher.setPayrollManager(address(manager));
//         dispatcher.setPayVault(address(vault));

//         // PayVault
//         vault.setDispatcher(address(dispatcher));
//         vault.setYieldRouter(address(router));

//         console2.log("All contracts wired up");

//         // ── 10. Seed test employer + cycle ────────────────────────────────────
//         // Fund employer
//         address employer = deployer; // use deployer as employer for local test
//         address employee1 = makeAddress("employee1");
//         address employee2 = makeAddress("employee2");
//         address employee3 = makeAddress("employee3");

//         usdc.mint(employer, EMPLOYER_FUNDS);

//         // Register employer
//         manager.registerEmployer();

//         // Create group
//         manager.createGroup("Engineering", CYCLE_DURATION);

//         // Add employees
//         manager.addEmployee(1, employee1, SALARY_1);
//         manager.addEmployee(1, employee2, SALARY_2);
//         manager.addEmployee(1, employee3, SALARY_3);

//         // Approve and deposit payroll
//         usdc.approve(address(manager), type(uint256).max);
//         manager.depositPayroll(1);

//         console2.log("Test employer setup complete");
//         console2.log("Employee1:         ", employee1);
//         console2.log("Employee2:         ", employee2);
//         console2.log("Employee3:         ", employee3);
//         console2.log("Cycle duration:     10 minutes");

//         vm.stopBroadcast();

//         // ── 11. Print .env values ─────────────────────────────────────────────
//         console2.log("\n--- COPY TO scripts/agent/.env ---");
//         console2.log("YIELD_ROUTER_ADDRESS=", address(router));
//         console2.log("MOCK_USDC_ADDRESS=", address(usdc));
//         console2.log("DEPLOYMENT_BLOCK=0");
//         console2.log("----------------------------------\n");
//     }

//     function makeAddress(string memory name) internal pure returns (address) {
//         return address(uint160(uint256(keccak256(abi.encodePacked(name)))));
//     }
// }
