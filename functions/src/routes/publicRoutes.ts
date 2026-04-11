import { Router } from "express";
import { lookupEntitlements, resolveAppInstallation } from "../services/accountService";

export function createPublicRoutes(): Router {
  const router = Router();

  router.get("/health", (_request, response) => {
    response.json({ ok: true });
  });

  router.post("/app-installations/resolve", async (request, response, next) => {
    try {
      const result = await resolveAppInstallation(request.body as Record<string, unknown>);
      response.status(result.created ? 201 : 200).json({ installation: result.installation });
    } catch (error) {
      next(error);
    }
  });

  router.get("/entitlements/by-user-id", async (request, response, next) => {
    try {
      const result = await lookupEntitlements(request.query as Record<string, unknown>);
      response.json(result);
    } catch (error) {
      next(error);
    }
  });

  return router;
}