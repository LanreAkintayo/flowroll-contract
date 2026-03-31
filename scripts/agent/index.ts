import { ethers }                              from "ethers";
import { config }                             from "./config";
import { logger }                             from "./logger";
import { loadState, saveState }               from "./state";
import { discoverNewEmployers, getActiveCycles } from "./discover";
import { rebalanceCycle }                     from "./rebalance";
import { notify }                             from "./webhook";
import { startHealthServer, metrics }         from "./health";
import { ActiveCycle }                        from "./types";
import YieldRouterABI                         from "./abis/YieldRouter.json";

// ─── Setup ───────────────────────────────────────────────────────────────────

const provider = new ethers.JsonRpcProvider(config.rpcUrl);
const signer   = new ethers.Wallet(config.privateKey, provider);
const router   = new ethers.Contract(
    config.yieldRouterAddress,
    YieldRouterABI,
    signer
);

let tickCount = 0;
let isRunning = false;

// ─── Main Tick ───────────────────────────────────────────────────────────────

async function tick(): Promise<void> {
    if (isRunning) {
        logger.warn("Previous tick still running — skipping");
        return;
    }

    isRunning         = true;
    metrics.isRunning = true;
    tickCount        += 1;
    metrics.tickCount = tickCount;

    const startTime = Date.now();
    logger.info(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
    logger.info(`TICK #${tickCount} started`);

    const state = loadState();
    metrics.state = state;

    let totalCycles    = 0;
    let successCount   = 0;
    let failureCount   = 0;
    let paydayCount    = 0;
    let rebalanceCount = 0;

    try {
        // ── Step 1: Discover new employers ────────────────────────────────────
        const newEmployers = await discoverNewEmployers(router, provider, state);
        if (newEmployers > 0) {
            logger.info(`Discovered ${newEmployers} new employer(s)`);
            await notify(`🔍 Flowroll Agent: ${newEmployers} new employer(s) discovered`);
        }

        logger.info(`Known employers: ${state.knownEmployers.length}`);

        // ── Step 2: Build work queue ──────────────────────────────────────────
        const workQueue: ActiveCycle[] = [];

        for (const employer of state.knownEmployers) {
            const activeCycleIds = await getActiveCycles(router, employer);
            for (const cycleId of activeCycleIds) {
                workQueue.push({ employer, cycleId });
            }
        }

        totalCycles = workQueue.length;
        logger.info(`Active cycles to process: ${totalCycles}`);

        // ── Step 3: Execute rebalances ────────────────────────────────────────
        for (const { employer, cycleId } of workQueue) {
            const result = await rebalanceCycle(router, employer, cycleId);

            if (result.success) {
                successCount++;

                if (result.actionType === "PaydayTriggered") {
                    paydayCount++;
                    // Webhook notification on payday — most important event
                    await notify(
                        `🎉 **Flowroll Payday Settled!**\n` +
                        `Employer: \`${employer}\`\n` +
                        `Cycle ID: ${cycleId}\n` +
                        `Tx: \`${result.txHash}\``
                    );
                }

                if (result.actionType === "Rebalanced") rebalanceCount++;

            } else {
                failureCount++;
                await notify(
                    `⚠️ **Flowroll Agent: Rebalance Failed**\n` +
                    `Employer: \`${employer}\`\n` +
                    `Cycle ID: ${cycleId}\n` +
                    `Error: ${result.error}`
                );
            }

            // Small delay between transactions — avoid nonce issues
            await sleep(1000);
        }

        // ── Step 4: Save state ────────────────────────────────────────────────
        saveState(state);

    } catch (e) {
        logger.error(`Tick failed unexpectedly: ${e}`);
        await notify(`🚨 **Flowroll Agent: Tick #${tickCount} failed**\n${e}`);
    } finally {
        isRunning         = false;
        metrics.isRunning = false;
    }

    // ── Update metrics ────────────────────────────────────────────────────────
    const duration = Date.now() - startTime;

    metrics.lastTickAt      = Date.now();
    metrics.lastTickMs      = duration;
    metrics.totalCycles    += totalCycles;
    metrics.totalSuccess   += successCount;
    metrics.totalFailures  += failureCount;
    metrics.totalPaydays   += paydayCount;
    metrics.totalRebalances += rebalanceCount;

    logger.info(`TICK #${tickCount} complete in ${(duration / 1000).toFixed(1)}s`);
    logger.info(`Cycles: ${totalCycles} total | ${successCount} success | ${failureCount} failed`);

    if (paydayCount    > 0) logger.info(`🎉 Paydays settled:  ${paydayCount}`);
    if (rebalanceCount > 0) logger.info(`♻️  Rebalances:       ${rebalanceCount}`);
    if (failureCount   > 0) logger.warn(`❌ Failures:          ${failureCount}`);

    logger.info(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
}

// ─── Startup ─────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
    logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    logger.info("  Flowroll Agent Starting");
    logger.info(`  RPC:      ${config.rpcUrl}`);
    logger.info(`  Router:   ${config.yieldRouterAddress}`);
    logger.info(`  Operator: ${signer.address}`);
    logger.info(`  Interval: ${config.intervalMs / 1000}s`);
    logger.info(`  Retries:  ${config.maxRetries}`);
    logger.info(`  Webhook:  ${config.webhookUrl ? config.webhookType : "disabled"}`);
    logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

    // ── Verify RPC connection ─────────────────────────────────────────────────
    try {
        const network    = await provider.getNetwork();
        const balance    = await provider.getBalance(signer.address);
        const balanceEth = ethers.formatEther(balance);

        logger.info(`Connected to chain ID: ${network.chainId}`);
        logger.info(`Agent balance: ${balanceEth} INIT`);

        if (balance === BigInt(0)) {
            logger.warn("⚠️  Agent wallet has zero balance — transactions will fail");
        }
    } catch (e) {
        logger.error(`Failed to connect to RPC: ${e}`);
        process.exit(1);
    }

    // ── Start health server ───────────────────────────────────────────────────
    startHealthServer();

    // ── Notify startup ────────────────────────────────────────────────────────
    await notify(
        `🚀 **Flowroll Agent Started**\n` +
        `RPC: ${config.rpcUrl}\n` +
        `Router: \`${config.yieldRouterAddress}\`\n` +
        `Interval: ${config.intervalMs / 1000}s`
    );

    // ── Run immediately then on interval ─────────────────────────────────────
    await tick();
    setInterval(tick, config.intervalMs);

    logger.info(`Agent running — ticking every ${config.intervalMs / 1000}s`);
}

// ─── Graceful shutdown ────────────────────────────────────────────────────────

process.on("SIGINT", async () => {
    logger.info("Shutting down agent gracefully...");
    await notify("🛑 Flowroll Agent: Shutting down");
    process.exit(0);
});

process.on("SIGTERM", async () => {
    logger.info("Shutting down agent gracefully...");
    await notify("🛑 Flowroll Agent: Shutting down");
    process.exit(0);
});

process.on("unhandledRejection", (reason) => {
    logger.error(`Unhandled rejection: ${reason}`);
});

// ─── Run ─────────────────────────────────────────────────────────────────────

main().catch((e) => {
    logger.error(`Fatal error: ${e}`);
    process.exit(1);
});



// import { ethers }             from "ethers";
// import { config }             from "./config";
// import { logger }             from "./logger";
// import { loadState, saveState } from "./state";
// import { discoverNewEmployers, getActiveCycles } from "./discover";
// import { rebalanceCycle }     from "./rebalance";
// import { ActiveCycle }        from "./types";
// import YieldRouterABI         from "./abis/YieldRouter.json";

// // ─── Setup ───────────────────────────────────────────────────────────────────

// const provider = new ethers.JsonRpcProvider(config.rpcUrl);
// const signer   = new ethers.Wallet(config.privateKey, provider);
// const router   = new ethers.Contract(
//     config.yieldRouterAddress,
//     YieldRouterABI,
//     signer
// );

// let tickCount = 0;
// let isRunning = false; // prevent overlapping ticks

// // ─── Main Tick ───────────────────────────────────────────────────────────────

// async function tick(): Promise<void> {
//     // Skip if previous tick still running
//     if (isRunning) {
//         logger.warn("Previous tick still running — skipping");
//         return;
//     }

//     isRunning  = true;
//     tickCount += 1;

//     const startTime = Date.now();
//     logger.info(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
//     logger.info(`TICK #${tickCount} started`);

//     const state = loadState();

//     let totalCycles    = 0;
//     let successCount   = 0;
//     let failureCount   = 0;
//     let paydayCount    = 0;
//     let rebalanceCount = 0;

//     try {
//         // ──  Discover new employers ────────────────────────────────────
//         const newEmployers = await discoverNewEmployers(router, provider, state);
//         if (newEmployers > 0) {
//             logger.info(`Discovered ${newEmployers} new employer(s)`);
//         }

//         logger.info(`Known employers: ${state.knownEmployers.length}`);

//         // ── Build work queue ──────────────────────────────────────────
//         const workQueue: ActiveCycle[] = [];

//         for (const employer of state.knownEmployers) {
//             const activeCycleIds = await getActiveCycles(router, employer);

//             for (const cycleId of activeCycleIds) {
//                 workQueue.push({ employer, cycleId });
//             }
//         }

//         totalCycles = workQueue.length;
//         logger.info(`Active cycles to process: ${totalCycles}`);

//         // ── Execute rebalances ────────────────────────────────────────
//         for (const { employer, cycleId } of workQueue) {
//             const result = await rebalanceCycle(router, employer, cycleId);

//             if (result.success) {
//                 successCount++;
//                 if (result.actionType === "PaydayTriggered") paydayCount++;
//                 if (result.actionType === "Rebalanced")      rebalanceCount++;
//             } else {
//                 failureCount++;
//             }

//             // Small delay between transactions — avoid nonce issues
//             await sleep(1000);
//         }

//         // ── Step 4: Save state ────────────────────────────────────────────────
//         saveState(state);

//     } catch (e) {
//         logger.error(`Tick failed unexpectedly: ${e}`);
//     } finally {
//         isRunning = false;
//     }

//     const duration = ((Date.now() - startTime) / 1000).toFixed(1);

//     logger.info(`TICK #${tickCount} complete in ${duration}s`);
//     logger.info(`Cycles: ${totalCycles} total | ${successCount} success | ${failureCount} failed`);

//     if (paydayCount    > 0) logger.info(`🎉 Paydays settled: ${paydayCount}`);
//     if (rebalanceCount > 0) logger.info(`♻️  Rebalances: ${rebalanceCount}`);

//     logger.info(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
// }

// // ─── Helpers ─────────────────────────────────────────────────────────────────

// function sleep(ms: number): Promise<void> {
//     return new Promise(resolve => setTimeout(resolve, ms));
// }

// // ─── Startup ─────────────────────────────────────────────────────────────────

// async function main(): Promise<void> {
//     logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
//     logger.info("  Flowroll Agent Starting");
//     logger.info(`  RPC:      ${config.rpcUrl}`);
//     logger.info(`  Router:   ${config.yieldRouterAddress}`);
//     logger.info(`  Operator: ${signer.address}`);
//     logger.info(`  Interval: ${config.intervalMs / 1000}s`);
//     logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

//     // Verify connection
//     try {
//         const network     = await provider.getNetwork();
//         const balance     = await provider.getBalance(signer.address);
//         const balanceEth  = ethers.formatEther(balance);

//         logger.info(`Connected to chain ID: ${network.chainId}`);
//         logger.info(`Agent balance: ${balanceEth} INIT`);

//         if (balance === BigInt(0)) {
//             logger.warn("⚠️  Agent wallet has zero balance — get testnet INIT from faucet");
//         }
//     } catch (e) {
//         logger.error(`Failed to connect to RPC: ${e}`);
//         process.exit(1);
//     }

//     // Run immediately on start
//     await tick();

//     // Then run every N milliseconds
//     setInterval(tick, config.intervalMs);

//     logger.info(`Agent running — ticking every ${config.intervalMs / 1000}s`);
// }

// // ─── Graceful shutdown ────────────────────────────────────────────────────────

// process.on("SIGINT", () => {
//     logger.info("Shutting down agent gracefully...");
//     process.exit(0);
// });

// process.on("SIGTERM", () => {
//     logger.info("Shutting down agent gracefully...");
//     process.exit(0);
// });

// process.on("unhandledRejection", (reason) => {
//     logger.error(`Unhandled rejection: ${reason}`);
// });

// // ─── Run ─────────────────────────────────────────────────────────────────────

// main().catch((e) => {
//     logger.error(`Fatal error: ${e}`);
//     process.exit(1);
// });


