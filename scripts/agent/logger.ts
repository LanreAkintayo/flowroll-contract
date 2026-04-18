import winston from "winston";
import Transport from "winston-transport";
import { Server } from "socket.io";
import { config } from "./config";

/**
 * Global reference for the Socket.IO server to enable real-time log broadcasting.
 */
let ioInstance: Server | null = null;

/**
 * Injects the Socket.IO instance into the logging module.
 */
export const setSocketServer = (io: Server): void => {
    ioInstance = io;
};

/**
 * Interface representing the structure of Winston log information.
 */
interface LogInfo {
    level: string;
    message: string;
    timestamp?: string;
    [key: string]: any;
}

/**
 * Custom Winston transport that broadcasts logs to connected clients via Socket.IO.
 */
class SocketTransport extends Transport {
    public log(info: LogInfo, callback: () => void): void {
        setImmediate(() => this.emit("logged", info));

        if (ioInstance) {
            const type = this._getLogType(info.level);

            ioInstance.emit("agent-log", {
                id: Math.random().toString(36).substring(7),
                timestamp: info.timestamp,
                message: info.message,
                type: type,
            });
        }
        callback();
    }

    private _getLogType(level: string): string {
        if (level === "error") return "error";
        if (level === "warn") return "warning";
        return "info";
    }
}

const { combine, timestamp, printf, colorize } = winston.format;

/**
 * Standardized log output format.
 */
const logFormat = printf(({ level, message, timestamp }) => {
    return `[${timestamp}] ${level.toUpperCase()}: ${message}`;
});

/**
 * Shared configuration for timestamping logs.
 */
const timeFormat = timestamp({ format: "YYYY-MM-DD HH:mm:ss" });

/**
 * Core logger instance managing Console, File, and Socket outputs.
 */
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
        new SocketTransport()
    ]
});