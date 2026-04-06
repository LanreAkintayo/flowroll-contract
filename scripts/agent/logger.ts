import winston from "winston";
import Transport from "winston-transport";
import { Server } from "socket.io";
import { config } from "./config";

let ioInstance: Server | null = null;

export const setSocketServer = (io: Server) => {
    ioInstance = io;
};

// Custom Winston transport to broadcast logs to frontend
class SocketTransport extends Transport {
    log(info: any, callback: () => void) {
        setImmediate(() => {
            this.emit("logged", info);
        });

        if (ioInstance) {
            let type = "info";
            if (info.level === "error") type = "error";
            if (info.level === "warn") type = "warning";

            ioInstance.emit("agent-log", {
                id: Math.random().toString(36).substring(7),
                timestamp: info.timestamp,
                message: info.message,
                type: type,
            });
        }
        callback();
    }
}

const { combine, timestamp, printf, colorize } = winston.format;

const logFormat = printf(({ level, message, timestamp }) => {
    return `[${timestamp}] ${level.toUpperCase()}: ${message}`;
});

export const logger = winston.createLogger({
    level: config.logLevel,
    format: combine(
        timestamp({ format: "YYYY-MM-DD HH:mm:ss" }),
        logFormat
    ),
    transports: [
        new winston.transports.Console({
            format: combine(
                colorize(),
                timestamp({ format: "YYYY-MM-DD HH:mm:ss" }),
                logFormat
            )
        }),
        new winston.transports.File({
            filename: "agent.log",
            format: combine(
                timestamp({ format: "YYYY-MM-DD HH:mm:ss" }),
                logFormat
            )
        }),
        new SocketTransport() 
    ]
});


// import winston from "winston";
// import { config } from "./config";

// const { combine, timestamp, printf, colorize } = winston.format;

// const logFormat = printf(({ level, message, timestamp }) => {
//     return `[${timestamp}] ${level.toUpperCase()}: ${message}`;
// });

// export const logger = winston.createLogger({
//     level: config.logLevel,
//     format: combine(
//         timestamp({ format: "YYYY-MM-DD HH:mm:ss" }),
//         logFormat
//     ),
//     transports: [
//         new winston.transports.Console({
//             format: combine(
//                 colorize(),
//                 timestamp({ format: "YYYY-MM-DD HH:mm:ss" }),
//                 logFormat
//             )
//         }),
//         new winston.transports.File({
//             filename: "agent.log",
//             format: combine(
//                 timestamp({ format: "YYYY-MM-DD HH:mm:ss" }),
//                 logFormat
//             )
//         })
//     ]
// });