import { ethers }                          from "ethers";
import { RebalanceResult, ACTION_TYPE_LABELS } from "./types";
import { logger }                          from "./logger";

/**
 * Call agentRebalance for a single cycle.
 * Parses AgentAction event from receipt to determine what happened.
 * Returns structured result regardless of success or failure.
 */
export async function rebalanceCycle(
    router:   ethers.Contract,
    employer: string,
    cycleId:  bigint
): Promise<RebalanceResult> {
    const label = `employer: ${employer.slice(0, 8)}... cycleId: ${cycleId}`;

    try {
        logger.info(`Rebalancing — ${label}`);

        // Estimate gas first — catches reverts before broadcasting
        const gasEstimate = await router.agentRebalance.estimateGas(
            employer,
            cycleId
        );

        // Add 20% buffer to gas estimate
        const gasLimit = (gasEstimate * BigInt(120)) / BigInt(100);

        const tx = await router.agentRebalance(employer, cycleId, {
            gasLimit
        });

        logger.info(`Transaction sent: ${tx.hash} — ${label}`);

        const receipt = await tx.wait();

        if (!receipt || receipt.status === 0) {
            return {
                employer,
                cycleId,
                success: false,
                actionType: "Unknown",
                txHash: tx.hash,
                error: "Transaction reverted"
            };
        }

        // Parse AgentAction event from receipt
        const actionType = parseAgentAction(router, receipt);

        logger.info(`✅ ${actionType} — ${label} — tx: ${tx.hash} — gas: ${receipt.gasUsed}`);

        // Special log for payday
        if (actionType === "PaydayTriggered") {
            logger.info(`🎉 PAYDAY SETTLED — ${label}`);
        }

        return {
            employer,
            cycleId,
            success:    true,
            actionType,
            txHash:     tx.hash,
            gasUsed:    receipt.gasUsed
        };

    } catch (e: any) {
        // Gas estimation failed — likely a contract revert
        const errorMsg = e?.message || String(e);

        // Cycle might have been closed by another process — not a real error
        if (errorMsg.includes("CycleNotActive") || errorMsg.includes("CycleNotFound")) {
            logger.info(`Cycle already closed — ${label}`);
            return {
                employer,
                cycleId,
                success:    true,
                actionType: "AlreadyClosed"
            };
        }

        logger.error(`❌ Rebalance failed — ${label}: ${errorMsg}`);

        return {
            employer,
            cycleId,
            success:    false,
            actionType: "Failed",
            error:      errorMsg
        };
    }
}

/**
 * Parse AgentAction event from transaction receipt.
 * Returns the action type label string.
 */
function parseAgentAction(
    router:  ethers.Contract,
    receipt: ethers.TransactionReceipt
): string {
    console.log("Receipts.logs: ", receipt.logs);
    try {
        for (const log of receipt.logs) {
            try {
                const parsed = router.interface.parseLog({
                    topics: [...log.topics],
                    data:   log.data
                });

                console.log("Parsed inside parseAgentAction: ", parsed);

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