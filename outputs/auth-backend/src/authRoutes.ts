import type { FastifyInstance, FastifyRequest } from "fastify";
import type pg from "pg";
import { z } from "zod";
import type { AppConfig } from "./config.js";
import {
  createRefreshToken,
  hashPassword,
  hashRefreshToken,
  issueAccessToken,
  verifyAccessToken,
  verifyPassword
} from "./security.js";

const credentialsSchema = z.object({
  email: z.string().email().max(320),
  password: z.string().min(12).max(256)
});

const registerSchema = credentialsSchema.extend({
  displayName: z.string().trim().min(1).max(80).optional()
});

const logoutSchema = z.object({
  refreshToken: z.string().min(32).max(512)
});

type UserRow = {
  id: string;
  email: string;
  display_name: string | null;
  password_hash: string;
  failed_login_count: number;
  locked_until: Date | null;
};

type PublicUser = {
  id: string;
  email: string;
  displayName: string | null;
};

type RefreshTokenRow = {
  id: string;
  user_id: string;
  email: string;
  display_name: string | null;
};

function toPublicUser(row: Pick<UserRow, "id" | "email" | "display_name">): PublicUser {
  return {
    id: row.id,
    email: row.email,
    displayName: row.display_name
  };
}

function clientIp(request: FastifyRequest): string | null {
  return request.ip || null;
}

function userAgent(request: FastifyRequest): string | null {
  const header = request.headers["user-agent"];
  return typeof header === "string" ? header : null;
}

async function writeAudit(
  pool: pg.Pool,
  request: FastifyRequest,
  eventType: string,
  userId?: string,
  metadata: Record<string, unknown> = {}
): Promise<void> {
  await pool.query(
    `INSERT INTO auth_audit_log (user_id, event_type, ip_address, user_agent, metadata)
     VALUES ($1, $2, $3::inet, $4, $5::jsonb)`,
    [userId ?? null, eventType, clientIp(request), userAgent(request), JSON.stringify(metadata)]
  );
}

async function createSession(
  config: AppConfig,
  pool: pg.Pool,
  request: FastifyRequest,
  user: PublicUser
) {
  const accessToken = await issueAccessToken(config, user.id, user.email);
  const refreshToken = createRefreshToken();
  const tokenHash = hashRefreshToken(refreshToken, config.refreshTokenPepper);

  await pool.query(
    `INSERT INTO refresh_tokens (user_id, token_hash, user_agent, ip_address, expires_at)
     VALUES ($1, $2, $3, $4::inet, now() + interval '30 days')`,
    [user.id, tokenHash, userAgent(request), clientIp(request)]
  );

  return {
    user,
    tokens: {
      accessToken,
      refreshToken
    }
  };
}

export async function registerAuthRoutes(
  app: FastifyInstance,
  config: AppConfig,
  pool: pg.Pool
) {
  app.post("/auth/register", async (request, reply) => {
    const input = registerSchema.parse(request.body);
    const email = input.email.toLowerCase();
    const passwordHash = await hashPassword(input.password);

    try {
      const result = await pool.query<UserRow>(
        `INSERT INTO users (email, display_name, password_hash)
         VALUES ($1, $2, $3)
         RETURNING id, email, display_name, password_hash, failed_login_count, locked_until`,
        [email, input.displayName ?? null, passwordHash]
      );

      const user = toPublicUser(result.rows[0]);
      await writeAudit(pool, request, "user.registered", user.id);
      return reply.code(201).send(await createSession(config, pool, request, user));
    } catch (error: any) {
      if (error?.code === "23505") {
        await writeAudit(pool, request, "user.register_conflict", undefined, { email });
        return reply.code(409).send({ error: "email_exists", message: "该邮箱已注册" });
      }
      throw error;
    }
  });

  app.post("/auth/login", async (request, reply) => {
    const input = credentialsSchema.parse(request.body);
    const email = input.email.toLowerCase();
    const result = await pool.query<UserRow>(
      `SELECT id, email, display_name, password_hash, failed_login_count, locked_until
       FROM users
       WHERE email = $1 AND deleted_at IS NULL`,
      [email]
    );

    const userRow = result.rows[0];
    if (userRow?.locked_until != null && userRow.locked_until > new Date()) {
      await writeAudit(pool, request, "user.login_locked", userRow.id);
      return reply.code(423).send({ error: "account_locked", message: "登录尝试过多，请稍后再试" });
    }

    const passwordOk = userRow == null
      ? false
      : await verifyPassword(userRow.password_hash, input.password);

    if (!passwordOk || userRow == null) {
      if (userRow != null) {
        const nextFailedCount = userRow.failed_login_count + 1;
        await pool.query(
          `UPDATE users
           SET failed_login_count = $1,
               locked_until = CASE WHEN $1 >= 5 THEN now() + interval '15 minutes' ELSE locked_until END,
               updated_at = now()
           WHERE id = $2`,
          [nextFailedCount, userRow.id]
        );
        await writeAudit(pool, request, "user.login_failed", userRow.id);
      } else {
        await writeAudit(pool, request, "user.login_failed_unknown", undefined, { email });
      }

      return reply.code(401).send({ error: "invalid_credentials", message: "邮箱或密码不正确" });
    }

    await pool.query(
      `UPDATE users SET failed_login_count = 0, locked_until = NULL, updated_at = now() WHERE id = $1`,
      [userRow.id]
    );

    const user = toPublicUser(userRow);
    await writeAudit(pool, request, "user.login_succeeded", user.id);
    return createSession(config, pool, request, user);
  });

  app.get("/auth/me", async (request, reply) => {
    const authorization = request.headers.authorization;
    const token = authorization?.startsWith("Bearer ") ? authorization.slice(7) : null;
    if (token == null) {
      return reply.code(401).send({ error: "missing_token", message: "缺少访问令牌" });
    }

    let userId: string;
    try {
      userId = await verifyAccessToken(config, token);
    } catch {
      return reply.code(401).send({ error: "invalid_token", message: "访问令牌无效" });
    }

    const result = await pool.query<UserRow>(
      `SELECT id, email, display_name, password_hash, failed_login_count, locked_until
       FROM users
       WHERE id = $1 AND deleted_at IS NULL`,
      [userId]
    );

    const userRow = result.rows[0];
    if (userRow == null) {
      return reply.code(404).send({ error: "user_not_found", message: "账号不存在" });
    }

    return toPublicUser(userRow);
  });

  app.post("/auth/refresh", async (request, reply) => {
    const input = logoutSchema.parse(request.body);
    const tokenHash = hashRefreshToken(input.refreshToken, config.refreshTokenPepper);
    const result = await pool.query<RefreshTokenRow>(
      `SELECT rt.id, rt.user_id, u.email, u.display_name
       FROM refresh_tokens rt
       JOIN users u ON u.id = rt.user_id
       WHERE rt.token_hash = $1
         AND rt.revoked_at IS NULL
         AND rt.expires_at > now()
         AND u.deleted_at IS NULL`,
      [tokenHash]
    );

    const row = result.rows[0];
    if (row == null) {
      return reply.code(401).send({ error: "invalid_refresh_token", message: "登录已失效，请重新登录" });
    }

    await pool.query(
      `UPDATE refresh_tokens SET revoked_at = now() WHERE id = $1`,
      [row.id]
    );

    const user = {
      id: row.user_id,
      email: row.email,
      displayName: row.display_name
    };

    await writeAudit(pool, request, "user.token_refreshed", user.id);
    return createSession(config, pool, request, user);
  });

  app.post("/auth/logout", async (request, reply) => {
    const input = logoutSchema.parse(request.body);
    const tokenHash = hashRefreshToken(input.refreshToken, config.refreshTokenPepper);

    await pool.query(
      `UPDATE refresh_tokens
       SET revoked_at = now()
       WHERE token_hash = $1 AND revoked_at IS NULL`,
      [tokenHash]
    );

    await writeAudit(pool, request, "user.logout");
    return reply.send({});
  });
}
