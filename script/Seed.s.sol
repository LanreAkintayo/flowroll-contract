// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Script.sol";
// import "../src/YieldRouter.sol";

// /**
//  * @title Seed
//  * @notice Seeds a deployed YieldRouter with demo data for hackathon demo
//  *
//  * @dev Run AFTER Deploy.s.sol. Starts live payroll cycles for demo employers
//  *      so the dashboard shows real data from day one of the demo.
//  *
//  * Usage:
//  *   forge script script/Seed.s.sol \
//  *     --rpc-url $INITIA_RPC_URL \
//  *     --broadcast \
//  *     --private-key $DEPLOYER_KEY
//  *
//  * Required .env:
//  *   DEPLOYER_KEY           — must be funded with USDC for seeding
//  *   YIELD_ROUTER_ADDRESS   — from Deploy.s.sol output
//  *   USDC_ADDRESS           — USDC token on this network
//  *   DEMO_EMPLOYER_1        — first demo employer address
//  *   DEMO_EMPLOYER_2        — second demo employer address (optional)
//  */
// contract Seed is Script {

//     function run() external {
//         uint256 deployerKey  = vm.envUint("DEPLOYER_KEY");
//         address routerAddr   = vm.envAddress("YIELD_ROUTER_ADDRESS");
//         address usdcAddr     = vm.envAddress("USDC_ADDRESS");
//         address demoEmployer = vm.envAddress("DEMO_EMPLOYER_1");

//         YieldRouter router = YieldRouter(routerAddr);

//         // Minimal IERC20 for approval
//         IERC20Like usdc = IERC20Like(usdcAddr);

//         vm.startBroadcast(deployerKey);

//         // Seed employer 1 — $50,000 / 30-day cycle
//         uint256 payroll1 = 50_000 * 1e6;
//         usdc.approve(routerAddr, payroll1);

//         // Start cycle as the demo employer (requires USDC in deployer wallet)
//         // In practice each employer calls startCycle themselves via the frontend
//         // This seed script simulates that for demo purposes
//         router.startCycle(payroll1, 30);

//         console.log("Seeded cycle for:", demoEmployer);
//         console.log("Payroll amount:   $50,000 USDC");
//         console.log("Cycle duration:   30 days");

//         vm.stopBroadcast();

//         console.log("\n=== Seed Complete ===");
//         console.log("YieldRouter:", routerAddr);
//         console.log("Run the agent to begin yield farming:");
//         console.log("  cd agent && npx ts-node src/agent.ts --loop");
//     }
// }

// interface IERC20Like {
//     function approve(address spender, uint256 amount) external returns (bool);
// }
