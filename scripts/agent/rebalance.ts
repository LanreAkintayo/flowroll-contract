// import { ethers }                          from "ethers";
// import { RebalanceResult, ACTION_TYPE_LABELS } from "./types";
// import { logger }                          from "./logger";

// /**
//  * Call agentRebalance for a single cycle.
//  * Parses AgentAction event from receipt to determine what happened.
//  * Returns structured result regardless of success or failure.
//  */
// export async function rebalanceCycle(
//     router:   ethers.Contract,
//     employer: string,
//     cycleId:  bigint
// ): Promise<RebalanceResult> {
//     const label = `employer: ${employer.slice(0, 8)}... cycleId: ${cycleId}`;

//     try {
//         logger.info(`Rebalancing — ${label}`);

//         // Estimate gas first — catches reverts before broadcasting
//         const gasEstimate = await router.agentRebalance.estimateGas(
//             employer,
//             cycleId
//         );

//         // Add 20% buffer to gas estimate
//         const gasLimit = (gasEstimate * BigInt(120)) / BigInt(100);

//         const tx = await router.agentRebalance(employer, cycleId, {
//             gasLimit
//         });

//         logger.info(`Transaction sent: ${tx.hash} — ${label}`);

//         const receipt = await tx.wait();

//         if (!receipt || receipt.status === 0) {
//             return {
//                 employer,
//                 cycleId,
//                 success: false,
//                 actionType: "Unknown",
//                 txHash: tx.hash,
//                 error: "Transaction reverted"
//             };
//         }

//         // Parse AgentAction event from receipt
//         const actionType = parseAgentAction(router, receipt);

//         logger.info(`✅ ${actionType} — ${label} — tx: ${tx.hash} — gas: ${receipt.gasUsed}`);

//         // Special log for payday
//         if (actionType === "PaydayTriggered") {
//             logger.info(`🎉 PAYDAY SETTLED — ${label}`);
//         }

//         return {
//             employer,
//             cycleId,
//             success:    true,
//             actionType,
//             txHash:     tx.hash,
//             gasUsed:    receipt.gasUsed
//         };

//     } catch (e: any) {
//         // Gas estimation failed — likely a contract revert
//         const errorMsg = e?.message || String(e);

//         // Cycle might have been closed by another process — not a real error
//         if (errorMsg.includes("CycleNotActive") || errorMsg.includes("CycleNotFound")) {
//             logger.info(`Cycle already closed — ${label}`);
//             return {
//                 employer,
//                 cycleId,
//                 success:    true,
//                 actionType: "AlreadyClosed"
//             };
//         }

//         logger.error(`❌ Rebalance failed — ${label}: ${errorMsg}`);

//         return {
//             employer,
//             cycleId,
//             success:    false,
//             actionType: "Failed",
//             error:      errorMsg
//         };
//     }
// }

// /**
//  * Parse AgentAction event from transaction receipt.
//  * Returns the action type label string.
//  */
// function parseAgentAction(
//     router:  ethers.Contract,
//     receipt: ethers.TransactionReceipt
// ): string {
//     console.log("Receipts.logs: ", receipt.logs);
//     try {
//         for (const log of receipt.logs) {
//             try {
//                 const parsed = router.interface.parseLog({
//                     topics: [...log.topics],
//                     data:   log.data
//                 });

//                 console.log("Parsed inside parseAgentAction: ", parsed);

//                 if (parsed && parsed.name === "AgentAction") {
//                     const actionTypeNum = Number(parsed.args[3]);
//                     return ACTION_TYPE_LABELS[actionTypeNum] || `Unknown(${actionTypeNum})`;
//                 }
//             } catch {
//                 // Not an AgentAction log — skip
//             }
//         }
//     } catch (e) {
//         logger.warn(`Failed to parse AgentAction event: ${e}`);
//     }

//     return "Unknown";
// }


import { ethers }                              from "ethers";
import { RebalanceResult, ACTION_TYPE_LABELS } from "./types";
import { logger }                              from "./logger";
import { config }                              from "./config";

/**
 * Call agentRebalance for a single cycle.
 * Includes:
 *   - Pre-call cycle state check — skips inactive cycles
 *   - Gas price oracle — fetches current network gas price
 *   - Retry logic — retries once on failure before giving up
 *   - AgentAction event parsing — identifies what action was taken
 */
export async function rebalanceCycle(
    router:   ethers.Contract,
    employer: string,
    cycleId:  bigint
): Promise<RebalanceResult> {
    const label = `employer: ${employer.slice(0, 10)}... cycleId: ${cycleId}`;

    // ── Pre-call cycle state check ────────────────────────────────────────────
    // Skip inactive cycles before wasting gas on a call that will revert
    try {
        const cycle = await router.getCycle(employer, cycleId);
        if (!cycle.isActive) {
            logger.info(`Cycle already inactive — skipping ${label}`);
            return {
                employer,
                cycleId,
                success:    true,
                actionType: "AlreadyClosed"
            };
        }
    } catch (e) {
        logger.warn(`Could not read cycle state for ${label} — proceeding anyway: ${e}`);
    }

    // ── Attempt rebalance with retries ────────────────────────────────────────
    let lastError = "";

    for (let attempt = 1; attempt <= config.maxRetries; attempt++) {
        const result = await _attemptRebalance(router, employer, cycleId, label, attempt);

        if (result.success) return result;

        lastError = result.error || "Unknown error";

        // Don't retry if cycle is already closed — not a transient error
        if (
            lastError.includes("CycleNotActive") ||
            lastError.includes("CycleNotFound")  ||
            lastError.includes("AlreadyClosed")
        ) {
            logger.info(`Cycle already closed — ${label}`);
            return {
                employer,
                cycleId,
                success:    true,
                actionType: "AlreadyClosed"
            };
        }

        if (attempt < config.maxRetries) {
            logger.warn(`Attempt ${attempt} failed — retrying in ${config.retryDelayMs}ms`);
            await sleep(config.retryDelayMs);
        }
    }

    // All retries exhausted
    logger.error(`❌ All ${config.maxRetries} attempts failed — ${label}: ${lastError}`);
    return {
        employer,
        cycleId,
        success:    false,
        actionType: "Failed",
        error:      lastError
    };
}

// ─── Internal: single attempt ─────────────────────────────────────────────────

async function _attemptRebalance(
    router:   ethers.Contract,
    employer: string,
    cycleId:  bigint,
    label:    string,
    attempt:  number
): Promise<RebalanceResult> {
    try {
        if (attempt > 1) {
            logger.info(`Retry attempt ${attempt}/${config.maxRetries} — ${label}`);
        } else {
            logger.info(`Rebalancing — ${label}`);
        }

        // ── Gas price oracle — fetch current network gas price ────────────────
        const feeData    = await router.runner?.provider?.getFeeData();
        const gasPrice   = feeData?.gasPrice ?? undefined;

        if (gasPrice) {
            logger.debug(`Gas price: ${ethers.formatUnits(gasPrice, "gwei")} gwei`);
        }

        // ── Estimate gas ──────────────────────────────────────────────────────
        const gasEstimate = await router.agentRebalance.estimateGas(
            employer,
            cycleId
        );

        // Add 20% buffer
        const gasLimit = (gasEstimate * BigInt(120)) / BigInt(100);

        // ── Send transaction ──────────────────────────────────────────────────
        const txOptions: Record<string, unknown> = { gasLimit };
        if (gasPrice) txOptions.gasPrice = gasPrice;

        const tx = await router.agentRebalance(employer, cycleId, txOptions);

        logger.info(`Transaction sent: ${tx.hash} — ${label}`);

        const receipt = await tx.wait();

        if (!receipt || receipt.status === 0) {
            return {
                employer,
                cycleId,
                success:    false,
                actionType: "Unknown",
                txHash:     tx.hash,
                error:      "Transaction reverted on-chain"
            };
        }

        // ── Parse AgentAction event ───────────────────────────────────────────
        const actionType = parseAgentAction(router, receipt);

        logger.info(
            `✅ ${actionType} — ${label} — tx: ${tx.hash} — gas: ${receipt.gasUsed}`
        );

        return {
            employer,
            cycleId,
            success:    true,
            actionType,
            txHash:     tx.hash,
            gasUsed:    receipt.gasUsed
        };

    } catch (e: any) {
        const errorMsg = e?.message || String(e);
        logger.warn(`Attempt ${attempt} error — ${label}: ${errorMsg}`);

        return {
            employer,
            cycleId,
            success:    false,
            actionType: "Failed",
            error:      errorMsg
        };
    }
}

// ─── Parse AgentAction event ──────────────────────────────────────────────────

function parseAgentAction(
    router:  ethers.Contract,
    receipt: ethers.TransactionReceipt
): string {
    try {
        for (const log of receipt.logs) {
            try {
                const parsed = router.interface.parseLog({
                    topics: [...log.topics],
                    data:   log.data
                });

                if (parsed && parsed.name === "AgentAction") {
                    const actionTypeNum = Number(parsed.args[3]);
                    return ACTION_TYPE_LABELS[actionTypeNum] || `Unknown(${actionTypeNum})`;
                }
            } catch {
                // Not an AgentAction log — skip
            }
        }
    } catch (e) {
        logger.warn(`Failed to parse AgentAction event: ${e}`);
    }

    return "Unknown";
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
}