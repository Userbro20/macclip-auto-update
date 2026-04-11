import type { NextFunction, Request, Response } from "express";
import { botSharedSecret } from "../config";

export function requireBotAuth(request: Request, response: Response, next: NextFunction): void {
  const configuredSecret = botSharedSecret();
  if (!configuredSecret) {
    response.status(503).json({ error: "The bot API secret is not configured yet." });
    return;
  }

  const authorizationHeader = String(request.headers.authorization || "");
  const token = authorizationHeader.startsWith("Bearer ")
    ? authorizationHeader.slice(7).trim()
    : "";

  if (token !== configuredSecret) {
    response.status(401).json({ error: "Bot API authorization failed." });
    return;
  }

  next();
}