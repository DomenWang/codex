import crypto from "node:crypto";
import argon2 from "argon2";
import { SignJWT, jwtVerify } from "jose";
import type { AppConfig } from "./config.js";

export async function hashPassword(password: string): Promise<string> {
  return argon2.hash(password, {
    type: argon2.argon2id,
    memoryCost: 64 * 1024,
    timeCost: 3,
    parallelism: 1
  });
}

export function verifyPassword(hash: string, password: string): Promise<boolean> {
  return argon2.verify(hash, password);
}

export function createRefreshToken(): string {
  return crypto.randomBytes(48).toString("base64url");
}

export function hashRefreshToken(token: string, pepper: string): string {
  return crypto.createHmac("sha256", pepper).update(token).digest("base64url");
}

export async function issueAccessToken(
  config: AppConfig,
  userId: string,
  email: string
): Promise<string> {
  const secret = new TextEncoder().encode(config.jwtSecret);
  return new SignJWT({ email })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setSubject(userId)
    .setIssuer(config.jwtIssuer)
    .setAudience(config.jwtAudience)
    .setIssuedAt()
    .setExpirationTime("15m")
    .sign(secret);
}

export async function verifyAccessToken(config: AppConfig, token: string): Promise<string> {
  const secret = new TextEncoder().encode(config.jwtSecret);
  const result = await jwtVerify(token, secret, {
    issuer: config.jwtIssuer,
    audience: config.jwtAudience
  });

  if (result.payload.sub == null) {
    throw new Error("Missing subject");
  }

  return result.payload.sub;
}
