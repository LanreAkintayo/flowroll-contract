import winston from "winston";
import Transport from "winston-transport";
import { Server } from "socket.io";
import { config } from "./config";

let ioInstance: Server | null = null;

export const setSocketServer = (io: Server): void => {
    ioInstance = io;
};

const getLogType = (level: string): string => {
    if (level === "error") return "error";
    if (level === "warn") return "warning";
    return "info";
};

// Pure functional Winston transport configuration
const customSocketTransport = new Transport({
    log: (info, callback) => {
        setImmediate(() => customSocketTransport.emit("logged", info));

        if (ioInstance) {
            const message = info.message;
            const lowerMsg = message.toLowerCase();

            const isSensitive = 
                lowerMsg.includes("postgres://") || 
                lowerMsg.includes("rpc") || 
                lowerMsg.includes("private_key") ||
                lowerMsg.includes("error: panic");

            const isPublicMilestone = 
                message.includes("TICK #") ||
                message.includes("Discovered") ||
                message.includes("Active registry") ||
                message.includes("Payday") ||
                message.includes("Strategies Rebalanced") ||
                message.includes("finalized in") ||
                message.includes("Status:") ||
                message.includes("---------------------------------------------------");

            if (isPublicMilestone && !isSensitive) {
                ioInstance.emit("agent-log", {
                    id: Math.random().toString(36).substring(7),
                    timestamp: info.timestamp,
                    message: message,
                    type: getLogType(info.level),
                });
            }
        }
        callback();
    }
});

const { combine, timestamp, printf, colorize } = winston.format;

const logFormat = printf(({ level, message, timestamp }) => {
    return `[${timestamp}] ${level.toUpperCase()}: ${message}`;
});

const timeFormat = timestamp({ format: "YYYY-MM-DD HH:mm:ss" });

export const logger = winston.createLogger({
    level: config.logLevel,
    format: combine(timeFormat, logFormat),
    transports: [
        new winston.transports.Console({
            format: combine(colorize(), timeFormat, logFormat)
        }),
        new winston.transports.File({
            filename: "agent.log"
        }),
        customSocketTransport
    ]
});