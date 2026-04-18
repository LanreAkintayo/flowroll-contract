import * as http from "http";
import { Server as SocketIOServer } from "socket.io";
import { config } from "./config";
import { logger, setSocketServer } from "./logger"; // Make sure setSocketServer is exported from logger.ts!
import { AgentState } from "./types";

// Shared metrics — updated by index.ts each tick 

export interface AgentMetrics {
  startTime: number;
  tickCount: number;
  lastTickAt: number | null;
  lastTickMs: number | null;
  totalCycles: number;
  totalSuccess: number;
  totalFailures: number;
  totalPaydays: number;
  totalRebalances: number;
  isRunning: boolean;
  state: AgentState | null;
}

export const metrics: AgentMetrics = {
  startTime: Date.now(),
  tickCount: 0,
  lastTickAt: null,
  lastTickMs: null,
  totalCycles: 0,
  totalSuccess: 0,
  totalFailures: 0,
  totalPaydays: 0,
  totalRebalances: 0,
  isRunning: false,
  state: null,
};

// ─── Health server & WebSockets ─────────────────────────────────────────────────

export function startHealthServer(): void {
  const server = http.createServer((req, res) => {
    // --- 1. CORS Headers for REST API ---
    // This allows your Next.js frontend to fetch /status without browser errors
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");

    // Handle preflight requests instantly
    if (req.method === "OPTIONS") {
      res.writeHead(200);
      res.end();
      return;
    }

    const url = req.url || "/";

    if (url === "/health") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(
        JSON.stringify({
          status: "ok",
          uptime: Math.floor((Date.now() - metrics.startTime) / 1000),
          lastTick: metrics.lastTickAt
            ? new Date(metrics.lastTickAt).toISOString()
            : null,
        }),
      );
      return;
    }

    if (url === "/status") {
      const uptimeSeconds = Math.floor((Date.now() - metrics.startTime) / 1000);
      const successRate =
        metrics.totalCycles > 0
          ? ((metrics.totalSuccess / metrics.totalCycles) * 100).toFixed(1)
          : "0.0";

      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(
        JSON.stringify(
          {
            status: "ok",
            uptime: `${uptimeSeconds}s`,
            tickCount: metrics.tickCount,
            lastTickAt: metrics.lastTickAt
              ? new Date(metrics.lastTickAt).toISOString()
              : null,
            lastTickMs: metrics.lastTickMs,
            isRunning: metrics.isRunning,
            cycles: {
              total: metrics.totalCycles,
              success: metrics.totalSuccess,
              failures: metrics.totalFailures,
              successRate: `${successRate}%`,
              paydays: metrics.totalPaydays,
              rebalances: metrics.totalRebalances,
            },
            knownEmployers: metrics.state?.knownEmployers.length ?? 0,
            lastScannedBlock: metrics.state?.lastScannedBlock ?? 0,
            config: {
              intervalMs: config.intervalMs,
              rpcUrl: config.rpcUrl,
              router: config.yieldRouterAddress,
            },
          },
          null,
          2,
        ),
      );
      return;
    }

    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Not found" }));
  });

  // --- 2. Attach Socket.io to the Native HTTP Server ---
  const io = new SocketIOServer(server, {
    cors: {
      origin: "*", // Allow Next.js to connect
      methods: ["GET", "POST"],
    },
  });

  // Pass the active socket instance over to your Winston logger
  setSocketServer(io);

  // Connection events for debugging
  io.on("connection", (socket) => {
    logger.info(`Frontend Command Center connected! (ID: ${socket.id})`);

    socket.on("disconnect", () => {
      console.log(`Frontend disconnected: ${socket.id}`);
    });
  });

  // --- 3. Start Listening ---
  server.listen(config.healthPort, () => {
    logger.info(
      `Health & Socket server running on http://localhost:${config.healthPort}`,
    );
    logger.info(`  GET /health  — liveness check`);
    logger.info(`  GET /status  — full agent metrics`);
  });

  server.on("error", (e) => {
    logger.error(`Health server error: ${e}`);
  });
}
