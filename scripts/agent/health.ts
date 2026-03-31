import * as http    from "http";
import { config }   from "./config";
import { logger }   from "./logger";
import { AgentState } from "./types";

// ─── Shared metrics — updated by index.ts each tick ──────────────────────────

export interface AgentMetrics {
    startTime:       number;
    tickCount:       number;
    lastTickAt:      number | null;
    lastTickMs:      number | null;
    totalCycles:     number;
    totalSuccess:    number;
    totalFailures:   number;
    totalPaydays:    number;
    totalRebalances: number;
    isRunning:       boolean;
    state:           AgentState | null;
}

export const metrics: AgentMetrics = {
    startTime:       Date.now(),
    tickCount:       0,
    lastTickAt:      null,
    lastTickMs:      null,
    totalCycles:     0,
    totalSuccess:    0,
    totalFailures:   0,
    totalPaydays:    0,
    totalRebalances: 0,
    isRunning:       false,
    state:           null,
};

// ─── Health server ────────────────────────────────────────────────────────────

export function startHealthServer(): void {
    const server = http.createServer((req, res) => {
        const url = req.url || "/";

        if (url === "/health") {
            // Simple liveness check
            res.writeHead(200, { "Content-Type": "application/json" });
            res.end(JSON.stringify({
                status:   "ok",
                uptime:   Math.floor((Date.now() - metrics.startTime) / 1000),
                lastTick: metrics.lastTickAt
                    ? new Date(metrics.lastTickAt).toISOString()
                    : null
            }));
            return;
        }

        if (url === "/status") {
            // Full agent status
            const uptimeSeconds = Math.floor((Date.now() - metrics.startTime) / 1000);
            const successRate   = metrics.totalCycles > 0
                ? ((metrics.totalSuccess / metrics.totalCycles) * 100).toFixed(1)
                : "0.0";

            res.writeHead(200, { "Content-Type": "application/json" });
            res.end(JSON.stringify({
                status:          "ok",
                uptime:          `${uptimeSeconds}s`,
                tickCount:       metrics.tickCount,
                lastTickAt:      metrics.lastTickAt
                    ? new Date(metrics.lastTickAt).toISOString()
                    : null,
                lastTickMs:      metrics.lastTickMs,
                isRunning:       metrics.isRunning,
                cycles: {
                    total:       metrics.totalCycles,
                    success:     metrics.totalSuccess,
                    failures:    metrics.totalFailures,
                    successRate: `${successRate}%`,
                    paydays:     metrics.totalPaydays,
                    rebalances:  metrics.totalRebalances,
                },
                knownEmployers:  metrics.state?.knownEmployers.length ?? 0,
                lastScannedBlock: metrics.state?.lastScannedBlock ?? 0,
                config: {
                    intervalMs:  config.intervalMs,
                    rpcUrl:      config.rpcUrl,
                    router:      config.yieldRouterAddress,
                }
            }, null, 2));
            return;
        }

        // 404 for everything else
        res.writeHead(404, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Not found" }));
    });

    server.listen(config.healthPort, () => {
        logger.info(`Health server running on http://localhost:${config.healthPort}`);
        logger.info(`  GET /health  — liveness check`);
        logger.info(`  GET /status  — full agent metrics`);
    });

    server.on("error", (e) => {
        logger.error(`Health server error: ${e}`);
    });
}