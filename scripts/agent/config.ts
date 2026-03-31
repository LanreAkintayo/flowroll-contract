// import * as dotenv from "dotenv";
// dotenv.config();

// function required(key: string): string {
//     const value = process.env[key];
//     if (!value) throw new Error(`Missing required env var: ${key}`);
//     return value;
// }

// export const config = {
//     privateKey:          required("PRIVATE_KEY"),
//     rpcUrl:              required("INITIA_EVM_RPC"),
//     yieldRouterAddress:  required("YIELD_ROUTER_ADDRESS"),
//     intervalMs:          parseInt(process.env.AGENT_INTERVAL_MS || "30000"),
//     logLevel:            process.env.LOG_LEVEL || "info",

//     // Block to start scanning from — set to deployment block
//     // If not set, scans from block 0 (slower on first run)
//     deploymentBlock:     parseInt(process.env.DEPLOYMENT_BLOCK || "0"),
// } as const;

import * as dotenv from "dotenv";
dotenv.config();

function required(key: string): string {
    const value = process.env[key];
    if (!value) throw new Error(`Missing required env var: ${key}`);
    return value;
}

export const config = {
    privateKey:         required("PRIVATE_KEY"),
    rpcUrl:             required("INITIA_EVM_RPC"),
    yieldRouterAddress: required("YIELD_ROUTER_ADDRESS"),
    intervalMs:         parseInt(process.env.AGENT_INTERVAL_MS || "30000"),
    logLevel:           process.env.LOG_LEVEL || "info",
    deploymentBlock:    parseInt(process.env.DEPLOYMENT_BLOCK || "0"),

    // Health endpoint
    healthPort:         parseInt(process.env.HEALTH_PORT || "3000"),

    // Webhook — optional, leave blank to disable
    webhookUrl:         process.env.WEBHOOK_URL || "",
    webhookType:        (process.env.WEBHOOK_TYPE || "discord") as "discord" | "telegram",

    // Retry
    maxRetries:         parseInt(process.env.MAX_RETRIES || "2"),
    retryDelayMs:       parseInt(process.env.RETRY_DELAY_MS || "2000"),
} as const;