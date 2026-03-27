// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Script.sol";
// import "../src/YieldRouter.sol";
// import {MockPool} from "../src/mocks/MockPool.sol";

// /**
//  * @title Deploy
//  * @notice Deploys YieldRouter + MockPools to any EVM environment
//  *
//  * @dev Environment switching is purely via addresses — same script for all envs:
//  *
//  *   Local (Anvil):
//  *     forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
//  *
//  *   Initia Testnet (MockPools):
//  *     forge script script/Deploy.s.sol \
//  *       --rpc-url $INITIA_RPC_URL \
//  *       --broadcast \
//  *       --private-key $DEPLOYER_KEY
//  *
//  *   Initia Testnet (real InitiaDEX pools):
//  *     Set STABLE_POOL_ADDRESS, WEIGHTED_POOL_ADDRESS, RESERVE_POOL_ADDRESS in .env
//  *     Then run with --sig "runWithRealPools()"
//  *
//  * Required .env variables:
//  *   DEPLOYER_KEY            — deployer private key
//  *   AGENT_OPERATOR_ADDRESS  — agent backend wallet address
//  *   USDC_ADDRESS            — USDC token address for this environment
//  *
//  * Optional (for runWithRealPools):
//  *   STABLE_POOL_ADDRESS     — real InitiaDEX iUSD-USDC pool
//  *   WEIGHTED_POOL_ADDRESS   — real InitiaDEX INIT-iUSD pool
//  *   RESERVE_POOL_ADDRESS    — real InitiaDEX reserve pool
//  */
// contract Deploy is Script {

//     // ─── Run with MockPools (local / early testnet) ───────────────────────────

//     function run() external {
//         uint256 deployerKey   = vm.envUint("DEPLOYER_KEY");
//         address agentOperator = vm.envAddress("AGENT_OPERATOR_ADDRESS");
//         address usdcAddress   = vm.envAddress("USDC_ADDRESS");

//         vm.startBroadcast(deployerKey);

//         // 1. Deploy MockPools
//         MockPool stablePool = new MockPool(
//             "USDC-iUSD Stable",
//             800,                // 8% APY
//             500_000 * 1e6,      // $500k initial TVL
//             true                // stable pair, no IL risk
//         );

//         MockPool weightedPool = new MockPool(
//             "USDC-INIT Weighted",
//             1200,               // 12% APY
//             300_000 * 1e6,      // $300k initial TVL
//             false               // volatile pair, IL risk present
//         );

//         MockPool reservePool = new MockPool(
//             "Super Safe Reserve",
//             400,                // 4% APY
//             1_000_000 * 1e6,    // $1M initial TVL
//             true                // stable pair, no IL risk
//         );

//         // 2. Deploy YieldRouter
//         YieldRouter router = new YieldRouter(agentOperator, usdcAddress);

//         // 3. Register MockPools in whitelist
//         router.addPool(address(stablePool),   "USDC-iUSD Stable",   true,  200);
//         router.addPool(address(weightedPool), "USDC-INIT Weighted", false, 200);
//         router.addPool(address(reservePool),  "Super Safe Reserve", true,  200);

//         vm.stopBroadcast();

//         _printDeployment(
//             address(router),
//             address(stablePool),
//             address(weightedPool),
//             address(reservePool),
//             usdcAddress,
//             agentOperator,
//             true
//         );
//     }

//     // ─── Run with real InitiaDEX pools (testnet / mainnet) ───────────────────

//     function runWithRealPools() external {
//         uint256 deployerKey      = vm.envUint("DEPLOYER_KEY");
//         address agentOperator    = vm.envAddress("AGENT_OPERATOR_ADDRESS");
//         address usdcAddress      = vm.envAddress("USDC_ADDRESS");
//         address stablePoolAddr   = vm.envAddress("STABLE_POOL_ADDRESS");
//         address weightedPoolAddr = vm.envAddress("WEIGHTED_POOL_ADDRESS");
//         address reservePoolAddr  = vm.envAddress("RESERVE_POOL_ADDRESS");

//         vm.startBroadcast(deployerKey);

//         // Deploy YieldRouter only — pools already exist on-chain
//         YieldRouter router = new YieldRouter(agentOperator, usdcAddress);

//         // Register real InitiaDEX pool addresses
//         router.addPool(stablePoolAddr,   "USDC-iUSD Stable",   true,  200);
//         router.addPool(weightedPoolAddr, "USDC-INIT Weighted", false, 200);
//         router.addPool(reservePoolAddr,  "Super Safe Reserve", true,  200);

//         vm.stopBroadcast();

//         _printDeployment(
//             address(router),
//             stablePoolAddr,
//             weightedPoolAddr,
//             reservePoolAddr,
//             usdcAddress,
//             agentOperator,
//             false
//         );
//     }

//     // ─── Helper ──────────────────────────────────────────────────────────────

//     function _printDeployment(
//         address router,
//         address stablePool,
//         address weightedPool,
//         address reservePool,
//         address usdc,
//         address agentOperator,
//         bool isMock
//     ) internal pure {
//         console.log("\n=== Flowroll YieldRouter Deployment ===");
//         console.log("Pool mode:          ", isMock ? "MockPools" : "Real InitiaDEX");
//         console.log("YieldRouter:        ", router);
//         console.log("USDC:               ", usdc);
//         console.log("Agent Operator:     ", agentOperator);
//         console.log("Pool[0] Stable:     ", stablePool);
//         console.log("Pool[1] Weighted:   ", weightedPool);
//         console.log("Pool[2] Reserve:    ", reservePool);
//         console.log("\n--- Copy to your .env ---");
//         console.log("YIELD_ROUTER_ADDRESS=", router);
//         console.log("STABLE_POOL_ADDRESS=",  stablePool);
//         console.log("WEIGHTED_POOL_ADDRESS=", weightedPool);
//         console.log("RESERVE_POOL_ADDRESS=",  reservePool);
//         console.log("=====================================\n");
//     }
// }
