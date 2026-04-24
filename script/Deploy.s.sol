// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {YieldRouter} from "../src/YieldRouter.sol";
import {PayrollManager} from "../src/PayrollManager.sol";
import {PayrollDispatcher} from "../src/PayrollDispatcher.sol";
import {PayVault} from "../src/PayVault.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockPool} from "../src/mocks/MockPool.sol";
import {MockPoolAdapter} from "../src/adapters/MockPoolAdapter.sol";
import {FlowrollCredit} from "../src/FlowrollCredit.sol";
import {FlowrollZapper} from "../src/FlowrollZapper.sol";

/**
 * @title Deploy
 * @dev Deployment script for the Flowroll protocol ecosystem on Anvil or Initia Testnet.
 */
contract Deploy is Script {
    // --- CONFIG ---

    uint256 constant INITIAL_SUPPLY = 10_000_000e6;
    uint256 constant INITIAL_TVL = 1_000_000e6;
    uint256 constant STABLE_APY_BPS = 800;
    uint256 constant VOLATILE_APY_BPS = 1_500;
    uint256 constant FEE_BPS = 1_000;
    uint256 constant CREDIT_FEE_BPS = 150;
    uint256 constant MAX_ADVANCE_BPS = 8_000;

    uint256 constant USDC_PER_INIT = 10_000;
    uint256 constant GAS_PER_INIT = 5;
    uint256 constant MAX_ZAP = 100e18;

    uint256 constant ANVIL_CYCLE = 2 minutes;
    uint256 constant TESTNET_CYCLE = 10 minutes;

    // --- EXTERNAL ---

    /**
     * @dev Main execution function for the deployment script.
     */
    function run() external {
        string memory network = vm.envOr("NETWORK", string("anvil"));
        bool isTestnet = keccak256(bytes(network)) == keccak256(bytes("testnet"));

        uint256 deployerKey = isTestnet ? vm.envUint("TESTNET_PRIVATE_KEY") : vm.envUint("ANVIL_PRIVATE_KEY");

        address deployer = vm.addr(deployerKey);
        address agentOp = vm.envOr("AGENT_OPERATOR", deployer);
        address feeRecipient = vm.envOr("FEE_RECIPIENT", deployer);
        uint256 cycleDuration = isTestnet ? TESTNET_CYCLE : ANVIL_CYCLE;

        console2.log("=== Flowroll Deploy ===");
        console2.log("Network: ", isTestnet ? "Initia Testnet" : "Anvil");
        console2.log("Deployer: ", deployer);
        console2.log("Cycle: ", cycleDuration);
        console2.log("");

        vm.startBroadcast(deployerKey);

        // --- ASSETS ---
        // MockUSDC usdc = MockUSDC(vm.envAddress("MOCK_USDC_ADDRESS"));
        // MockERC20 bridgedInit = MockERC20(vm.envAddress("BRIDGED_INIT_ADDRESS"));
        MockUSDC usdc = new MockUSDC(INITIAL_SUPPLY);
        MockERC20 bridgedInit = new MockERC20("INIT", "INIT", 18);

        FlowrollZapper zapper = new FlowrollZapper(
            address(bridgedInit),
            address(usdc),
            USDC_PER_INIT,
            GAS_PER_INIT,
            MAX_ZAP
        );

        // --- POOLS & ADAPTERS ---
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

        MockPoolAdapter stableAdapter = new MockPoolAdapter(address(usdc), address(stablePool));
        MockPoolAdapter volatileAdapter = new MockPoolAdapter(address(usdc), address(volatilePool));

        // --- CORE PROTOCOL ---
        YieldRouter router = new YieldRouter(agentOp, address(usdc));
        PayrollDispatcher dispatcher = new PayrollDispatcher(address(usdc), feeRecipient, FEE_BPS);
        PayVault vault = new PayVault(address(usdc), feeRecipient, FEE_BPS);
        PayrollManager manager = new PayrollManager(address(usdc), feeRecipient, FEE_BPS);
        FlowrollCredit flowrollCredit = new FlowrollCredit(address(usdc), CREDIT_FEE_BPS, MAX_ADVANCE_BPS);

        vm.stopBroadcast();

        console2.log("\n--- COPY TO scripts/agent/.env ---");
        console2.log("MOCK_USDC_ADDRESS=", address(usdc));
        console2.log("STABLE_POOL_ADDRESS=", address(stablePool));
        console2.log("VOLATILE_POOL_ADDRESS=", address(volatilePool));
        console2.log("STABLE_ADAPTER_ADDRESS=", address(stableAdapter));
        console2.log("VOLATILE_ADAPTER_ADDRESS=", address(volatileAdapter));
        console2.log("YIELD_ROUTER_ADDRESS=", address(router));
        console2.log("PAYROLL_MANAGER_ADDRESS=", address(manager));
        console2.log("PAYROLL_DISPATCHER_ADDRESS=", address(dispatcher));
        console2.log("PAY_VAULT_ADDRESS=", address(vault));
        console2.log("FLOWROLL_CREDIT_ADDRESS=", address(flowrollCredit));
        console2.log("BRIDGED_INIT_ADDRESS=", address(bridgedInit));
        console2.log("FLOWROLL_ZAPPER_ADDRESS=", address(zapper));
        console2.log("DEPLOYMENT_BLOCK=0");
        console2.log("----------------------------------\n");
    }
   
}