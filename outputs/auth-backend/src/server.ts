import Fastify from "fastify";
import cors from "@fastify/cors";
import helmet from "@fastify/helmet";
import rateLimit from "@fastify/rate-limit";
import { ZodError } from "zod";
import { loadConfig } from "./config.js";
import { createPool } from "./db.js";
import { registerAuthRoutes } from "./authRoutes.js";

const config = loadConfig();
const pool = createPool(config);

const app = Fastify({
  logger: {
    level: config.nodeEnv === "production" ? "info" : "debug",
    redact: ["req.headers.authorization", "password", "refreshToken", "*.password", "*.refreshToken"]
  },
  trustProxy: config.nodeEnv === "production"
});

await app.register(helmet);
await app.register(cors, {
  origin: config.allowedOrigins.length > 0 ? config.allowedOrigins : false,
  credentials: false
});
await app.register(rateLimit, {
  max: 100,
  timeWindow: "1 minute"
});

app.setErrorHandler((error, _request, reply) => {
  if (error instanceof ZodError) {
    return reply.code(400).send({
      error: "validation_failed",
      message: "请求参数不合法"
    });
  }

  app.log.error(error);
  return reply.code(500).send({
    error: "internal_error",
    message: "服务暂时不可用"
  });
});

app.get("/health", async () => ({ ok: true }));

await registerAuthRoutes(app, config, pool);

const shutdown = async () => {
  await app.close();
  await pool.end();
};

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

await app.listen({ port: config.port, host: "0.0.0.0" });
