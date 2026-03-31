import { config }  from "./config";
import { logger }  from "./logger";

/**
 * Send a notification to Discord or Telegram webhook.
 * Silently skips if WEBHOOK_URL is not configured.
 */
export async function notify(message: string): Promise<void> {
    if (!config.webhookUrl) return;

    try {
        if (config.webhookType === "discord") {
            await sendDiscord(message);
        } else {
            await sendTelegram(message);
        }
    } catch (e) {
        // Never let webhook failure affect agent operation
        logger.warn(`Webhook notification failed: ${e}`);
    }
}

async function sendDiscord(message: string): Promise<void> {
    const body = JSON.stringify({ content: message });

    const res = await fetch(config.webhookUrl, {
        method:  "POST",
        headers: { "Content-Type": "application/json" },
        body
    });

    if (!res.ok) {
        throw new Error(`Discord webhook returned ${res.status}`);
    }
}

async function sendTelegram(message: string): Promise<void> {
    // Telegram webhook URL format:
    // https://api.telegram.org/bot<TOKEN>/sendMessage?chat_id=<CHAT_ID>
    const url = `${config.webhookUrl}&text=${encodeURIComponent(message)}`;

    const res = await fetch(url, { method: "POST" });

    if (!res.ok) {
        throw new Error(`Telegram webhook returned ${res.status}`);
    }
}