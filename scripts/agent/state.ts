import * as fs from "fs";
import * as path from "path";
import { AgentState } from "./types";
import { logger } from "./logger";
import { config } from "./config";

/**
 * Path to the local persistence file.
 */
const STATE_FILE = path.join(__dirname, "agent-state.json");

/**
 * Initial state configuration used when no persistence file is detected.
 */
const DEFAULT_STATE: AgentState = {
    lastScannedBlock: config.deploymentBlock,
    knownEmployers: []
};

/**
 * Retrieves the agent state from the local file system.
 * Defaults to the deployment block if the state file is missing or corrupt.
 * * @returns The persisted AgentState or a fresh default state.
 */
export function loadState(): AgentState {
    try {
        if (!fs.existsSync(STATE_FILE)) {
            logger.info("No persistence file found; initializing from deployment block.");
            return { ...DEFAULT_STATE };
        }

        const raw = fs.readFileSync(STATE_FILE, "utf-8");
        const state = JSON.parse(raw) as AgentState;

        logger.info(`State recovered | Last Block: ${state.lastScannedBlock} | Employers: ${state.knownEmployers.length}`);
        return state;
    } catch (error) {
        const msg = error instanceof Error ? error.message : String(error);
        logger.warn(`Persistence recovery failed; starting fresh. Reason: ${msg}`);
        return { ...DEFAULT_STATE };
    }
}

/**
 * Persists the current agent state to the disk.
 * * @param state The AgentState instance to be saved.
 */
export function saveState(state: AgentState): void {
    try {
        const data = JSON.stringify(state, null, 2);
        fs.writeFileSync(STATE_FILE, data);
    } catch (error) {
        logger.error(`State synchronization failed: ${error}`);
    }
}

/**
 * Registers a new employer address if it is not already tracked.
 * * @param state The current agent state.
 * @param employer The address to be registered.
 * @returns True if the employer was newly added; false if already exists.
 */
export function addEmployer(state: AgentState, employer: string): boolean {
    const normalized = employer.toLowerCase();
    const exists = state.knownEmployers.some(e => e.toLowerCase() === normalized);

    if (exists) {
        return false;
    }

    state.knownEmployers.push(employer);
    return true;
}