import { Pool } from "pg";
import { AgentState } from "./types";
import { logger } from "./logger";
import { config } from "./config";

const pool = new Pool({
    connectionString: config.externalDatabaseUrl,
    ssl: process.env.NODE_ENV === "production" ? { rejectUnauthorized: false } : false
});

/**
 * Recovers the agent state from the database or initializes it if missing.
 */
export async function loadState(): Promise<AgentState> {
    try {
        const stateRes = await pool.query(
            "SELECT last_scanned_block FROM agent_state WHERE id = 1"
        );

        if (stateRes.rows.length === 0) {
            logger.info("Initializing remote agent state tracking row.");
            await pool.query(
                "INSERT INTO agent_state (id, last_scanned_block) VALUES (1, $1)",
                [19_000_000]
            );
            return { lastScannedBlock: 19_000_000, knownEmployers: [] };
        }

        const employersRes = await pool.query("SELECT address FROM known_employers");
        const employers = employersRes.rows.map(row => row.address);

        return {
            // pg driver returns bigint columns as strings to prevent precision loss
            lastScannedBlock: Number(stateRes.rows[0].last_scanned_block),
            knownEmployers: employers
        };
    } catch (error) {
        logger.warn(`Database state recovery failed; running fallback: ${error}`);
        return { lastScannedBlock: config.deploymentBlock, knownEmployers: [] };
    }
}

/**
 * Persists the current blockchain scan pointer.
 */
export async function saveState(state: AgentState): Promise<void> {
    try {
        await pool.query(
            `INSERT INTO agent_state (id, last_scanned_block, updated_at) 
             VALUES (1, $1, NOW()) 
             ON CONFLICT (id) 
             DO UPDATE SET last_scanned_block = $1, updated_at = NOW()`,
            [state.lastScannedBlock]
        );
    } catch (error) {
        logger.error(`Database block sync failed: ${error}`);
    }
}

/**
 * Permanently stores a new employer address in the database and updates local cache.
 */
export async function addEmployer(state: AgentState, employer: string): Promise<boolean> {
    const normalized = employer.toLowerCase();
    const exists = state.knownEmployers.some(e => e.toLowerCase() === normalized);

    if (exists) {
        return false;
    }

    try {
        await pool.query(
            "INSERT INTO known_employers (address) VALUES ($1) ON CONFLICT DO NOTHING",
            [normalized]
        );
        state.knownEmployers.push(normalized);
        return true;
    } catch (error) {
        logger.error(`Failed to persist new employer row: ${error}`);
        return false;
    }
}


// import * as fs from "fs";
// import * as path from "path";
// import { AgentState } from "./types";
// import { logger } from "./logger";
// import { config } from "./config";

// /**
//  * Path to the local persistence file.
//  */
// const STATE_FILE = path.join(__dirname, "agent-state.json");

// /**
//  * Initial state configuration used when no persistence file is detected.
//  */
// const DEFAULT_STATE: AgentState = {
//     lastScannedBlock: config.deploymentBlock,
//     knownEmployers: []
// };

// /**
//  * Retrieves the agent state from the local file system.
//  * Defaults to the deployment block if the state file is missing or corrupt.
//  * * @returns The persisted AgentState or a fresh default state.
//  */
// export function loadState(): AgentState {
//     try {
//         if (!fs.existsSync(STATE_FILE)) {
//             logger.info("No persistence file found; initializing from deployment block.");
//             return { ...DEFAULT_STATE };
//         }

//         const raw = fs.readFileSync(STATE_FILE, "utf-8");
//         const state = JSON.parse(raw) as AgentState;

//         logger.info(`State recovered | Last Block: ${state.lastScannedBlock} | Employers: ${state.knownEmployers.length}`);
//         return state;
//     } catch (error) {
//         const msg = error instanceof Error ? error.message : String(error);
//         logger.warn(`Persistence recovery failed; starting fresh. Reason: ${msg}`);
//         return { ...DEFAULT_STATE };
//     }
// }

// /**
//  * Persists the current agent state to the disk.
//  * * @param state The AgentState instance to be saved.
//  */
// export function saveState(state: AgentState): void {
//     try {
//         const data = JSON.stringify(state, null, 2);
//         fs.writeFileSync(STATE_FILE, data);
//     } catch (error) {
//         logger.error(`State synchronization failed: ${error}`);
//     }
// }

// /**
//  * Registers a new employer address if it is not already tracked.
//  * * @param state The current agent state.
//  * @param employer The address to be registered.
//  * @returns True if the employer was newly added; false if already exists.
//  */
// export function addEmployer(state: AgentState, employer: string): boolean {
//     const normalized = employer.toLowerCase();
//     const exists = state.knownEmployers.some(e => e.toLowerCase() === normalized);

//     if (exists) {
//         return false;
//     }

//     state.knownEmployers.push(employer);
//     return true;
// }