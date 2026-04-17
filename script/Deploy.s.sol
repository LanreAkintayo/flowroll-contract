// // SPDX-License-Identifier: MIT
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
    uint256 constant CREDIT_FEE_BPS = 150;
    uint256 constant MAX_ADVANCE_BPS = 8_000;

    uint256 constant USDC_PER_INIT = 10_000;
    uint256 constant GAS_PER_INIT = 5;
    uint256 constant MAX_ZAP = 100e18;

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
        MockERC20 bridgedInit = MockERC20(
            vm.envAddress("BRIDGED_INIT_ADDRESS")
        );

        // 3. Deploy the Zapper using the newly created mock addresses
        FlowrollZapper zapper = new FlowrollZapper(
            address(bridgedInit),
            address(usdc),
            USDC_PER_INIT,
            GAS_PER_INIT,
            MAX_ZAP
        );

        console2.log("MockUSDC:          ", address(usdc));
        console2.log("Mock Bridged INIT: ", address(bridgedInit));
        console2.log("Zapper:            ", address(zapper));
        console2.log("");

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
        FlowrollCredit flowrollCredit = new FlowrollCredit(
            address(usdc),
            CREDIT_FEE_BPS,
            MAX_ADVANCE_BPS
        );

        console2.log("YieldRouter:       ", address(router));
        console2.log("PayrollDispatcher: ", address(dispatcher));
        console2.log("PayVault:          ", address(vault));
        console2.log("PayrollManager:    ", address(manager));
        console2.log("FlowrollCredit: ", address(flowrollCredit));

        console2.log("Contracts wired");

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
        console2.log("FLOWROLL_CREDIT_ADDRESS=", address(flowrollCredit));
        console2.log("BRIDGED_INIT_ADDRESS=", address(bridgedInit));
        console2.log("FLOWROLL_ZAPPER_ADDRESS=", address(zapper));
        console2.log("DEPLOYMENT_BLOCK=0");
        console2.log("----------------------------------\n");
    }

    function makeAddress(string memory name) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(name)))));
    }
}
