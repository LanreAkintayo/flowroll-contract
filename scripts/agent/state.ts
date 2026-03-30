import * as fs   from "fs";
import * as path from "path";
import { AgentState } from "./types";
import { logger }     from "./logger";
import { config }     from "./config";

const STATE_FILE = path.join(__dirname, "state.json");

const DEFAULT_STATE: AgentState = {
    lastScannedBlock: config.deploymentBlock,
    knownEmployers:   []
};

export function loadState(): AgentState {
    try {
        if (fs.existsSync(STATE_FILE)) {
            const raw   = fs.readFileSync(STATE_FILE, "utf-8");
            const state = JSON.parse(raw) as AgentState;
            logger.info(`State loaded — last block: ${state.lastScannedBlock}, employers: ${state.knownEmployers.length}`);
            return state;
        }
    } catch (e) {
        logger.warn(`Failed to load state file — starting fresh: ${e}`);
    }

    logger.info("No state file found — starting from deployment block");
    return { ...DEFAULT_STATE };
}

export function saveState(state: AgentState): void {
    try {
        fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
    } catch (e) {
        logger.error(`Failed to save state: ${e}`);
    }
}

export function addEmployer(state: AgentState, employer: string): boolean {
    const normalized = employer.toLowerCase();
    if (state.knownEmployers.map(e => e.toLowerCase()).includes(normalized)) {
        return false; // already known
    }
    state.knownEmployers.push(employer);
    return true; // newly added
}