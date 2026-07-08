# WeatherAlarm Auth Backend

这是天气闹钟 App 的账号系统后端骨架，目标是给 iOS 端提供真实登录、注册、当前用户和退出登录 API。

## 目录

```text
auth-backend
├── docker-compose.yml
├── migrations
│   └── 001_auth_schema.sql
├── src
│   ├── authRoutes.ts
│   ├── config.ts
│   ├── db.ts
│   ├── security.ts
│   └── server.ts
├── .env.example
├── package.json
└── tsconfig.json
```

## 数据库

数据库使用 PostgreSQL，迁移文件创建：

- `users`：用户、邮箱、Argon2id 密码哈希、失败登录次数、锁定时间。
- `refresh_tokens`：刷新令牌哈希、过期时间、撤销时间。
- `auth_audit_log`：注册、登录失败、登录成功、退出登录等审计事件。
- `referral_edges` / `user_coupons`：邀请关系、IDFV/IP 哈希去重、券发放和退款回滚状态。

本地启动数据库：

```powershell
cd outputs/auth-backend
docker compose up -d
```

## 环境变量

复制 `.env.example` 为 `.env`，然后填入真实 secret。

生成 Ed25519 JWT key：

```bash
openssl genpkey -algorithm Ed25519 -out jwt-private.pem
openssl pkey -in jwt-private.pem -pubout -out jwt-public.pem
base64 -i jwt-private.pem
base64 -i jwt-public.pem
```

生成 refresh token pepper：

```bash
openssl rand -base64 32
```

Windows PowerShell 可以用：

```powershell
[Convert]::ToBase64String([System.IO.File]::ReadAllBytes("jwt-private.pem"))
[Convert]::ToBase64String([System.IO.File]::ReadAllBytes("jwt-public.pem"))
```

## 启动 API

```powershell
cd outputs/auth-backend
npm install
npm run dev
```

## 免费部署方案：Render Free Web + Supabase Free Postgres

仓库根目录已经提供 `render.yaml` Blueprint。为了避免付费，当前配置只创建 Render 免费 Web Service，不创建 Render PostgreSQL。

数据库建议使用 Supabase Free Postgres。创建 Supabase 项目后，把 pooled connection string 复制出来，作为 Render 环境变量 `DATABASE_URL`。

1. 登录 Supabase，创建一个 Free 项目。
2. 打开项目的 `Connect` 面板，复制 Supavisor/Pooler 连接字符串，格式类似：

```text
postgresql://postgres.PROJECT_REF:PASSWORD@REGION.pooler.supabase.com:6543/postgres?sslmode=require
```

3. 如果迁移提示扩展不可用，在 Supabase Dashboard 的 Database Extensions 页面启用 `citext` 和 `pgcrypto` 后重新部署。
4. 登录 Render。
5. 选择 `New` -> `Blueprint`。
6. 连接 GitHub 仓库 `DomenWang/codex`。
7. Render 会读取仓库根目录的 `render.yaml`，创建免费 Web Service：`domenwang-weather-alarm-auth`。
8. Render 提示填写 `DATABASE_URL` 时，粘贴 Supabase 的连接字符串。
9. 部署完成后，后端地址预计为：

```text
https://domenwang-weather-alarm-auth.onrender.com
```

如果 Render 提示服务名已被占用，请按 Render 生成的新域名同步修改 iOS 项目的 `AuthAPIBaseURL`。

注意：Render 免费服务会冷启动，长时间没人访问后第一次请求可能较慢。这不影响测试登录系统，但正式上线建议换成稳定付费实例。

iOS 端需要把 `WeatherAlarm/Info.plist` 和 `project.yml` 里的 `AuthAPIBaseURL` 改为你的 HTTPS 后端地址，例如：

```text
https://api.your-domain.example
```

本地开发可以临时用：

```text
http://localhost:8080
```

正式环境必须使用 HTTPS。

## 安全基线

- 密码只存 Argon2id 哈希，不存明文，不做可逆加密。
- Access token 15 分钟过期。
- `/auth/refresh` 会轮换 refresh token，旧 refresh token 立即撤销。
- Refresh token 只在客户端保存明文，数据库只存 HMAC 哈希。
- 登录失败 5 次锁定 15 分钟。
- 邀请奖励必须由后端结合 App Store Server Notifications / 交易校验发放和回滚，客户端只做展示与防误操作。
- API 启用 Helmet、CORS 白名单、全局限流。
- 日志会 redact `Authorization`、`password`、`refreshToken`。
- 生产环境数据库连接启用 TLS。

## 还需要上线前补齐

- 邮箱验证和找回密码流程。
- MFA/Passkey。
- 更细的设备管理和远程登出。
- 监控、告警、备份、WAF/CDN、HSTS、密钥轮换。
