import { Router } from "express";
import { API_SERVICE_NAME } from "../config";
import { requireBotAuth } from "../middleware/authMiddleware";
import {
  BOT_API_CAPABILITIES,
  grantAccountFeature,
  linkDiscord,
  lookupAccount,
  revokeAccountFeature,
  setAccountAdmin,
  setAccountStatus,
  setAccountSubscription
} from "../services/accountService";

export function createBotRoutes(): Router {
  const router = Router();

  router.get("/bot/health", (_request, response) => {
    response.json({
      ok: true,
      service: API_SERVICE_NAME,
      capabilities: [...BOT_API_CAPABILITIES]
    });
  });

  router.get("/bot/users/lookup", requireBotAuth, async (request, response, next) => {
    try {
      response.json(await lookupAccount(request.query as Record<string, unknown>));
    } catch (error) {
      next(error);
    }
  });

  router.post("/bot/users/link-discord", requireBotAuth, async (request, response, next) => {
    try {
      response.json(await linkDiscord(request.body as Record<string, unknown>));
    } catch (error) {
      next(error);
    }
  });

  router.post("/bot/users/admin", requireBotAuth, async (request, response, next) => {
    try {
      response.json(await setAccountAdmin(request.body as Record<string, unknown>));
    } catch (error) {
      next(error);
    }
  });

  router.post("/bot/users/status", requireBotAuth, async (request, response, next) => {
    try {
      response.json(await setAccountStatus(request.body as Record<string, unknown>));
    } catch (error) {
      next(error);
    }
  });

  router.post("/bot/users/subscription", requireBotAuth, async (request, response, next) => {
    try {
      response.json(await setAccountSubscription(request.body as Record<string, unknown>));
    } catch (error) {
      next(error);
    }
  });

  router.post("/bot/users/features/grant", requireBotAuth, async (request, response, next) => {
    try {
      response.json(await grantAccountFeature(request.body as Record<string, unknown>));
    } catch (error) {
      next(error);
    }
  });

  router.post("/bot/users/features/revoke", requireBotAuth, async (request, response, next) => {
    try {
      response.json(await revokeAccountFeature(request.body as Record<string, unknown>));
    } catch (error) {
      next(error);
    }
  });

  return router;
}