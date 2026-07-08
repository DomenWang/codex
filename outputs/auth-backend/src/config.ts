export type AppConfig = {
  nodeEnv: string;
  port: number;
  databaseUrl: string;
  jwtIssuer: string;
  jwtAudience: string;
  jwtSecret: string;
  refreshTokenPepper: string;
  allowedOrigins: string[];
};

function required(name: string): string {
  const value = process.env[name];
  if (value == null || value.trim() === "") {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

export function loadConfig(): AppConfig {
  return {
    nodeEnv: process.env.NODE_ENV ?? "development",
    port: Number(process.env.PORT ?? 8080),
    databaseUrl: required("DATABASE_URL"),
    jwtIssuer: process.env.JWT_ISSUER ?? "weather-alarm",
    jwtAudience: process.env.JWT_AUDIENCE ?? "weather-alarm-ios",
    jwtSecret: required("JWT_SECRET"),
    refreshTokenPepper: required("REFRESH_TOKEN_PEPPER"),
    allowedOrigins: (process.env.ALLOWED_ORIGINS ?? "")
      .split(",")
      .map((origin) => origin.trim())
      .filter(Boolean)
  };
}
