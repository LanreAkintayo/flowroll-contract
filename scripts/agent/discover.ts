import { ethers } from "ethers";
import { AgentState, CycleStartedEvent } from "./types";
import { logger } from "./logger";
import { addEmployer } from "./state";

/**
 * Scan for CycleStarted events since last scanned block.
 * Extracts new employer addresses and adds them to state.
 * Updates lastScannedBlock to current block.
 */
export async function discoverNewEmployers(
  router: ethers.Contract,
  provider: ethers.JsonRpcProvider,
  state: AgentState,
): Promise<number> {
  const currentBlock = await provider.getBlockNumber();
  const fromBlock = state.lastScannedBlock;
  const toBlock = currentBlock;

  if (fromBlock >= toBlock) {
    logger.debug("No new blocks to scan");
    return 0;
  }

  logger.info(`Scanning blocks ${fromBlock} → ${toBlock} for new cycles`);

  let newCount = 0;

  try {
    // Query CycleStarted events
    const filter = router.filters.CycleStarted();
    const events = await router.queryFilter(filter, fromBlock, toBlock);

    for (const event of events) {
      const parsed = event as ethers.EventLog;
      // console.log("Parsed: ", parsed);
      const employer = parsed.args[0] as string;

      const isNew = await addEmployer(state, employer);

      if (isNew) {
        newCount++;
        logger.info(`New employer discovered: ${employer}`);
      }
    }

    // Update last scanned block
    state.lastScannedBlock = toBlock;

    if (events.length > 0) {
      logger.info(
        `Found ${events.length} CycleStarted events — ${newCount} new employers`,
      );
    }
  } catch (e) {
    logger.error(`Event discovery failed: ${e}`);
    // Don't update lastScannedBlock on failure — retry next tick
  }

  return newCount;
}

/**
 * Get all active cycles for a given employer.
 * Returns array of cycleIds that are currently active.
 */
export async function getActiveCycles(
  router: ethers.Contract,
  employer: string,
): Promise<bigint[]> {
  try {
    const cycles = await router.getActiveCycles(employer);
    return cycles
      .filter((c: any) => c.isActive)
      .map((c: any) => c.cycleId as bigint);
  } catch (e) {
    logger.error(`Failed to get active cycles for ${employer}: ${e}`);
    return [];
  }
}
