// SPDX-License-Identifier: MIT
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
    // ─── Config ───────────────────────────────────────────────────────────────

    uint256 constant INITIAL_TVL     = 1_000_000e6;
    uint256 constant EMPLOYER_FUNDS  = 100_000e6;
    uint256 constant SALARY_1        = 5_000e6;
    uint256 constant SALARY_2        = 3_000e6;
    uint256 constant SALARY_3        = 2_000e6;
    uint256 constant ANVIL_CYCLE     = 2 minutes;
    uint256 constant TESTNET_CYCLE   = 4 days;

    // ─── State ────────────────────────────────────────────────────────────────

    MockUSDC            internal usdc;
    YieldRouter         internal router;
    PayrollManager      internal manager;
    PayVault            internal vault;
    MockPool            internal stablePool;
    MockPool            internal volatilePool;
    MockPoolAdapter     internal stableAdapter;
    MockPoolAdapter     internal volatileAdapter;
    PayrollDispatcher   internal dispatcher;
    uint256             internal deployerKey;
    address             internal deployer;

    // ─── Shared setup ─────────────────────────────────────────────────────────
    // Called at the top of every function to load env vars.

    function _setup() internal {
        usdc            = MockUSDC(vm.envAddress("MOCK_USDC_ADDRESS"));
        router          = YieldRouter(vm.envAddress("YIELD_ROUTER_ADDRESS"));
        manager         = PayrollManager(vm.envAddress("PAYROLL_MANAGER_ADDRESS"));
        stablePool      = MockPool(vm.envAddress("STABLE_POOL_ADDRESS"));
        volatilePool    = MockPool(vm.envAddress("VOLATILE_POOL_ADDRESS"));
        vault           = PayVault(vm.envAddress("PAY_VAULT_ADDRESS"));
        stableAdapter   = MockPoolAdapter(vm.envAddress("STABLE_ADAPTER_ADDRESS"));
        volatileAdapter = MockPoolAdapter(vm.envAddress("VOLATILE_ADAPTER_ADDRESS"));
        dispatcher      = PayrollDispatcher(vm.envAddress("PAYROLL_DISPATCHER_ADDRESS"));
        deployerKey     = vm.envUint("TESTNET_PRIVATE_KEY");
        deployer        = vm.addr(deployerKey);
    }

    // ─── Step 1: Wire contracts together ─────────────────────────────────────
    // Run this first and wait for all transactions to confirm before step 2.
    //
    // forge script script/WireContract.s.sol \
    //   --sig "wire()" \
    //   --rpc-url http://localhost:8545 \
    //   --broadcast \
    //   --slow

    function wire() external {
        _setup();

        console2.log("=== Step 1: Wiring contracts ===");
        vm.startBroadcast(deployerKey);

        router.setPayrollManager(address(manager));
        router.setPayVault(address(vault));
        router.addPool(address(stableAdapter), address(stablePool), true, 500);
        router.addPool(address(volatileAdapter), address(volatilePool), false, 500);
        console2.log("Router configured");

        manager.setYieldRouter(address(router));
        manager.setPayrollDispatcher(address(dispatcher));
        console2.log("Manager configured");

        dispatcher.setYieldRouter(address(router));
        dispatcher.setPayrollManager(address(manager));
        dispatcher.setPayVault(address(vault));
        console2.log("Dispatcher configured");

        vault.setDispatcher(address(dispatcher));
        vault.setYieldRouter(address(router));
        console2.log("Vault configured");

        vm.stopBroadcast();
        console2.log("=== Step 1 complete. Wait for confirmations then run seedPools() ===");
    }

    // ─── Step 2: Seed pools with initial TVL ─────────────────────────────────
    // Run after wire() is fully confirmed.
    // Pools need liquidity before any payroll cycle can deposit into them.
    //
    // forge script script/WireContract.s.sol \
    //   --sig "seedPools()" \
    //   --rpc-url http://localhost:8545 \
    //   --broadcast \
    //   --slow


    // create_empty_blocks= false
    // create_empty_blocks_interval=1m0s

    function seedPools() external {
        _setup();

        console2.log("=== Step 2: Seeding pools ===");
        vm.startBroadcast(deployerKey);

        usdc.mint(deployer, INITIAL_TVL * 2);
        console2.log("Minted USDC for pool seeding");

        usdc.approve(address(stablePool), INITIAL_TVL);
        stablePool.deposit(INITIAL_TVL, deployer);
        console2.log("Stable pool seeded");

        usdc.approve(address(volatilePool), INITIAL_TVL);
        volatilePool.deposit(INITIAL_TVL, deployer);
        console2.log("Volatile pool seeded");

        vm.stopBroadcast();
        console2.log("=== Step 2 complete. Wait for confirmations then run seedScenario() ===");
    }

    // ─── Step 3: Seed test scenario ───────────────────────────────────────────
    // Run after seedPools() is fully confirmed.
    // This registers the employer, creates a group, adds employees,
    // and kicks off the first payroll cycle.
    //
    // forge script script/WireContract.s.sol \
    //   --sig "seedScenario()" \
    //   --rpc-url http://localhost:8545 \
    //   --broadcast \
    //   --slow

    function seedScenario() external {
        _setup();

        string memory network = vm.envOr("NETWORK", string("anvil"));
        bool isTestnet = keccak256(bytes(network)) == keccak256(bytes("testnet"));
        uint256 cycleDuration = isTestnet ? TESTNET_CYCLE : ANVIL_CYCLE;

        address employee1 = makeAddress("employee1");
        address employee2 = makeAddress("employee2");
        address employee3 = makeAddress("employee3");

        console2.log("=== Step 3: Seeding test scenario ===");
        console2.log("Cycle duration (seconds):", cycleDuration);
        console2.log("Employee1:", employee1);
        console2.log("Employee2:", employee2);
        console2.log("Employee3:", employee3);

        vm.startBroadcast(deployerKey);

        // Fund employer
        usdc.mint(deployer, EMPLOYER_FUNDS);
        console2.log("Employer funded");

        // Register and set up payroll group
        manager.registerEmployer();
        console2.log("Employer registered");

        manager.createGroup("Engineering", cycleDuration);
        console2.log("Group created");

        manager.addEmployee(1, employee1, SALARY_1);
        manager.addEmployee(1, employee2, SALARY_2);
        manager.addEmployee(1, employee3, SALARY_3);
        console2.log("Employees added");

        // Approve manager to pull USDC for the cycle
        usdc.approve(address(manager), type(uint256).max);
        console2.log("USDC approved");

        // Start the cycle
        manager.depositPayroll(1);
        console2.log("Payroll deposited - cycle started");

        vm.stopBroadcast();
        console2.log("=== Step 3 complete. Test scenario is live. ===");
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    function makeAddress(string memory name) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(name)))));
    }
}