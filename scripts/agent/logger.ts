import winston from "winston";
import { config } from "./config";

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
        })
    ]
});