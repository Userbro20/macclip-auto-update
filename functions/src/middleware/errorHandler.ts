import type { NextFunction, Request, Response } from "express";

export class ApiError extends Error {
  constructor(
    public readonly statusCode: number,
    message: string,
    public readonly details?: unknown
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export function notFoundHandler(_request: Request, response: Response): void {
  response.status(404).json({ error: "Not found." });
}

export function errorHandler(
  error: unknown,
  _request: Request,
  response: Response,
  _next: NextFunction
): void {
  if (error instanceof ApiError) {
    response.status(error.statusCode).json({
      error: error.message,
      ...(error.details === undefined ? {} : { details: error.details })
    });
    return;
  }

  const message = error instanceof Error ? error.message : "Internal server error.";
  console.error(error);
  response.status(500).json({ error: message });
}