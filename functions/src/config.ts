export const API_SERVICE_NAME = "macclipper-app-bot-api";
export const API_BASE_PATH = "/api";
export const ACTIVATION_HMAC_PEPPER = "macclipper-app-feature-grant-v1";
export const PAID_FEATURES = ["4k-pro"] as const;
export const DEFAULT_PRO_FEATURES = ["4k-pro"] as const;
export const FUNCTIONS_REGION = "us-central1";
export const FUNCTIONS_TIMEOUT_SECONDS = 30;

export function botSharedSecret(): string {
  return (process.env.MACCLIPPER_BOT_SHARED_SECRET || "").trim();
}

export function activationTokenSecret(): string {
  return (process.env.ACTIVATION_TOKEN_SECRET || "").trim();
}