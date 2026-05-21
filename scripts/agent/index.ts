import { ethers } from "ethers";
import { config } from "./config";
import { logger } from "./logger";
import { loadState, saveState } from "./state";
import { discoverNewEmployers, getActiveCycles } from "./discover";
import { rebalanceCycle } from "./rebalance";
import { notify } from "./webhook";
import { startHealthServer, metrics } from "./health";
import { ActiveCycle } from "./types";
import YieldRouterABI from "./abis/YieldRouter.json";

const provider = new ethers.JsonRpcProvider(config.rpcUrl);
const signer = new ethers.Wallet(config.privateKey, provider);
const router = new ethers.Contract(
    config.yieldRouterAddress,
    YieldRouterABI,
    signer
);

let tickCount = 0;
let isRunning = false;

function getCleanHost(urlStr: string): string {
    try {
        const urlObj = new URL(urlStr);
        return urlObj.hostname;
    } catch {
        return "custom-rpc";
    }
}

async function tick(): Promise<void> {
    if (isRunning) {
        logger.warn("Previous tick still active; skipping execution.");
        return;
    }

    isRunning = true;
    metrics.isRunning = true;
    tickCount += 1;
    metrics.tickCount = tickCount;

    const startTime = Date.now();
    logger.info(`TICK #${tickCount} initiated`);

    const state = await loadState();

    let totalCycles = 0;
    let successCount = 0;
    let failureCount = 0;
    let paydayCount = 0;
    let rebalanceCount = 0;

    try {
        const newEmployers = await discoverNewEmployers(router, provider, state);
        if (newEmployers > 0) {
            logger.info(`Discovered ${newEmployers} new employer(s)`);
            await notify(`🔍 Flowroll Agent: ${newEmployers} new employer(s) discovered`);
        }

        logger.info(`Active registry: ${state.knownEmployers.length} employers`);

        const workQueue: ActiveCycle[] = [];
        for (const employer of state.knownEmployers) {
            const activeCycleIds = await getActiveCycles(router, employer);
            for (const cycleId of activeCycleIds) {
                workQueue.push({ employer, cycleId });
            }
        }

        totalCycles = workQueue.length;
        logger.info(`Processing queue: ${totalCycles} active cycles`);

        for (const { employer, cycleId } of workQueue) {
            const result = await rebalanceCycle(router, employer, cycleId);

            if (result.success) {
                successCount++;

                if (result.actionType === "PaydayTriggered") {
                    paydayCount++;
                    await notify(
                        `🎉 **Flowroll Payday Settled!**\n` +
                        `Employer: \`${employer}\`\n` +
                        `Cycle ID: ${cycleId}\n` +
                        `Tx: \`${result.txHash}\``
                    );
                }

                if (result.actionType === "Rebalanced") {
                    rebalanceCount++;
                }
            } else {
                failureCount++;
                await notify(
                    `⚠️ **Flowroll Agent: Rebalance Failed**\n` +
                    `Employer: \`${employer}\`\n` +
                    `Cycle ID: ${cycleId}\n` +
                    `Error: ${result.error}`
                );
            }

            await sleep(1000);
        }

        await saveState(state);

    } catch (error) {
        const msg = error instanceof Error ? error.message : String(error);
        logger.error(`Tick #${tickCount} aborted: ${msg}`);
        await notify(`🚨 **Flowroll Agent: Tick #${tickCount} failed**\n${msg}`);
    } finally {
        isRunning = false;
        metrics.isRunning = false;
    }

    const duration = Date.now() - startTime;
    updateMetrics(duration, totalCycles, successCount, failureCount, paydayCount, rebalanceCount);
    logTickSummary(duration, successCount, failureCount, paydayCount, rebalanceCount);
}

function logTickSummary(
    duration: number, 
    success: number, 
    failed: number, 
    paydays: number, 
    rebalances: number
): void {
    logger.info(`TICK #${tickCount} finalized in ${(duration / 1000).toFixed(1)}s`);
    logger.info(`Status: ${success} success | ${failed} failed`);
    
    if (paydays > 0) logger.info(`Paydays Settled: ${paydays}`);
    if (rebalances > 0) logger.info(`Strategies Rebalanced: ${rebalances}`);
    logger.info("-------------------------------------------------------");
}

function updateMetrics(
    duration: number, 
    total: number, 
    success: number, 
    failed: number, 
    paydayCount: number, 
    rebalanceCount: number
): void {
    metrics.lastTickAt = Date.now();
    metrics.lastTickMs = duration;
    metrics.totalCycles += total;
    metrics.totalSuccess += success;
    metrics.totalFailures += failed;
    metrics.totalPaydays += paydayCount;
    metrics.totalRebalances += rebalanceCount;
}

function sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function main(): Promise<void> {
    logger.info("Starting Flowroll Agent");
    logger.info(`Context: RPC=${getCleanHost(config.rpcUrl)} | Operator=${signer.address}`);

    try {
        const network = await provider.getNetwork();
        const balance = await provider.getBalance(signer.address);

        // logger.info(`Connected to Chain ID: ${network.chainId}`);
        // logger.info(`Operator Balance: ${ethers.formatEther(balance)} INIT`);

        if (balance === 0n) {
            logger.warn("Agent balance is zero; outbound transactions will fail.");
        }
    } catch (error) {
        logger.error(`Initialization failed: ${error}`);
        process.exit(1);
    }

    startHealthServer();

    await notify(
        `🚀 **Flowroll Agent Started**\n` +
        `RPC Node Host: \`${getCleanHost(config.rpcUrl)}\`\n` +
        `Router: \`${config.yieldRouterAddress}\``
    );

    await tick();
    setInterval(tick, config.intervalMs);
}

const shutdown = async (signal: string) => {
    logger.info(`${signal} received: shutting down gracefully.`);
    await notify(`🛑 Flowroll Agent: Shutting down (${signal})`);
    process.exit(0);
};

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("unhandledRejection", (reason) => {
    logger.error(`Unhandled Promise Rejection: ${reason}`);
});

main().catch((error) => {
    logger.error(`Fatal Startup Error: ${error}`);
    process.exit(1);
});