import { ethers } from "ethers";
import { RebalanceResult, ACTION_TYPE_LABELS } from "./types";
import { logger } from "./logger";
import { config } from "./config";

/**
 * Orchestrates the rebalancing of a single payroll cycle.
 * Performs pre-flight checks, manages execution retries, and parses resulting on-chain events.
 * * @param router The YieldRouter contract instance.
 * @param employer Address of the employer owning the cycle.
 * @param cycleId Unique identifier for the payroll cycle.
 * @returns Result of the rebalance operation including action metadata.
 */
export async function rebalanceCycle(
    router: ethers.Contract,
    employer: string,
    cycleId: bigint
): Promise<RebalanceResult> {
    const context = `employer: ${employer.slice(0, 10)}... | cycleId: ${cycleId}`;

    // Pre-flight check: Prevent gas waste on inactive cycles
    try {
        const cycle = await router.getCycle(employer, cycleId);
        if (!cycle.isActive) {
            logger.info(`Cycle inactive; skipping ${context}`);
            return {
                employer,
                cycleId,
                success: true,
                actionType: "AlreadyClosed"
            };
        }
    } catch (error) {
        logger.warn(`Cycle state check failed for ${context}; attempting rebalance regardless.`);
    }

    let lastError = "";

    // Retry loop for transient network or provider issues
    for (let attempt = 1; attempt <= config.maxRetries; attempt++) {
        const result = await _attemptRebalance(router, employer, cycleId, context, attempt);

        if (result.success) return result;

        lastError = result.error || "Unknown operational error";

        // Terminal errors: Do not retry if the state is invalid
        const isTerminal = ["CycleNotActive", "CycleNotFound", "AlreadyClosed"]
            .some(err => lastError.includes(err));

        if (isTerminal) {
            return {
                employer,
                cycleId,
                success: true,
                actionType: "AlreadyClosed"
            };
        }

        if (attempt < config.maxRetries) {
            logger.warn(`Attempt ${attempt} failed; retrying in ${config.retryDelayMs}ms`);
            await sleep(config.retryDelayMs);
        }
    }

    logger.error(`Exhausted all ${config.maxRetries} attempts for ${context}: ${lastError}`);
    return {
        employer,
        cycleId,
        success: false,
        actionType: "Failed",
        error: lastError
    };
}

// --- INTERNAL ---

/**
 * Executes a single transaction attempt for the rebalance operation.
 */
async function _attemptRebalance(
    router: ethers.Contract,
    employer: string,
    cycleId: bigint,
    label: string,
    attempt: number
): Promise<RebalanceResult> {
    try {
        logger.info(`${attempt > 1 ? `Retry ${attempt}/${config.maxRetries}` : "Rebalancing"} - ${label}`);

        // Gas price acquisition
        const feeData = await router.runner?.provider?.getFeeData();
        const gasPrice = feeData?.gasPrice ?? undefined;

        // Estimation with dynamic safety buffer (20%)
        const gasEstimate = await router.agentRebalance.estimateGas(employer, cycleId);
        const gasLimit = (gasEstimate * 120n) / 100n;

        const txOptions: ethers.TransactionRequest = { gasLimit };
        if (gasPrice) txOptions.gasPrice = gasPrice;

        const tx = await router.agentRebalance(employer, cycleId, txOptions);
        logger.info(`TX broadcast: ${tx.hash}`);

        const receipt = await tx.wait();

        if (!receipt || receipt.status === 0) {
            return {
                employer,
                cycleId,
                success: false,
                actionType: "Unknown",
                txHash: tx.hash,
                error: "Execution reverted on-chain"
            };
        }

        const actionType = _parseAgentAction(router, receipt);
        logger.info(`✅ ${actionType} | gas: ${receipt.gasUsed} | tx: ${tx.hash}`);

        return {
            employer,
            cycleId,
            success: true,
            actionType,
            txHash: tx.hash,
            gasUsed: receipt.gasUsed
        };

    } catch (error: any) {
        const msg = error?.message || String(error);
        logger.warn(`Attempt ${attempt} failed for ${label}: ${msg}`);

        return {
            employer,
            cycleId,
            success: false,
            actionType: "Failed",
            error: msg
        };
    }
}

/**
 * Extracts and decodes the AgentAction event from transaction logs.
 */
function _parseAgentAction(
    router: ethers.Contract,
    receipt: ethers.TransactionReceipt
): string {
    try {
        for (const log of receipt.logs) {
            try {
                const parsed = router.interface.parseLog({
                    topics: [...log.topics],
                    data: log.data
                });

                if (parsed?.name === "AgentAction") {
                    const actionTypeNum = Number(parsed.args[3]);
                    return ACTION_TYPE_LABELS[actionTypeNum] || `Unknown(${actionTypeNum})`;
                }
            } catch {
                continue; // Log not matching YieldRouter interface
            }
        }
    } catch (error) {
        logger.warn(`Event parsing failed: ${error}`);
    }

    return "Unknown";
}

function sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
}