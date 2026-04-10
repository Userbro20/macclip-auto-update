# MacClipper Bot API Contract

Use this document as the single source of truth for any Copilot or bot setup against the local MacClipper backend in this repo.

## Base URL

```text
http://127.0.0.1:4173
```

## Bot authentication

All bot-only routes require this header:

```http
Authorization: Bearer <MACCLIPPER_BOT_SHARED_SECRET>
Content-Type: application/json
```

Print the current secret from this repo with:

```bash
cd /Users/meteorite/macclipper
npm run web:bot-secret
```

## Important identifier rule

This backend currently supports exactly these user lookup identifiers:

- `email`
- `userId`
- `appUuid`
- `discordUserId`

When a route says "lookup target", send exactly one of those keys.

## Shared user object

Most bot routes return this shape:

```json
{
  "user": {
    "id": "uuid",
    "appUuid": "uuid",
    "displayName": "Creator",
    "email": "user@example.com",
    "createdAt": "2026-04-09T00:00:00.000Z",
    "updatedAt": "2026-04-09T00:00:00.000Z",
    "role": "user",
    "accountStatus": "active",
    "subscriptionTier": "free",
    "paidFeatures": [],
    "discordUserId": "",
    "discordUsername": "",
    "clipCount": 0
  }
}
```

## Entitlement user object

The live entitlement route returns:

```json
{
  "user": {
    "id": "uuid",
    "accountStatus": "active",
    "subscriptionTier": "pro",
    "paidFeatures": ["4k-pro"],
    "updatedAt": "2026-04-09T00:00:00.000Z"
  }
}
```

## Activation URL format

Feature grants return a MacClipper deep link in this format:

```text
macclipper://purchase-complete?userId=<uuid>&appUuid=<uuid>&feature=<feature-key>&token=<sha256>
```

MacClipper already knows how to open and verify this URL.

## Health route

### `GET /api/health`

Response:

```json
{ "ok": true }
```

## Auth and account routes

These are cookie-auth routes used by the external website and purchase portal, not by a bundled frontend in this repo.

### `GET /api/auth/me`

Returns the signed-in website user or `null`.

Response:

```json
{ "user": null }
```

or:

```json
{ "user": { "id": "uuid", "displayName": "Creator", "email": "user@example.com" } }
```

### `POST /api/auth/signup`

Request body:

```json
{
  "displayName": "Creator",
  "email": "user@example.com",
  "password": "strong-password"
}
```

Success:

```json
{ "user": { "id": "uuid", "displayName": "Creator", "email": "user@example.com", "role": "user", "accountStatus": "active", "subscriptionTier": "free", "paidFeatures": [] } }
```

### `POST /api/auth/signin`

Request body:

```json
{
  "email": "user@example.com",
  "password": "strong-password"
}
```

Success:

```json
{ "user": { "id": "uuid", "displayName": "Creator", "email": "user@example.com" } }
```

### `POST /api/auth/app-uuid`

Cookie-auth route. Links the signed-in website account to a specific MacClipper install UUID.

Request body:

```json
{
  "appUuid": "uuid"
}
```

Success:

```json
{
  "user": {
    "id": "uuid",
    "appUuid": "uuid"
  }
}
```

### `POST /api/auth/signout`

Response:

```json
{ "ok": true }
```

## Entitlement and purchase routes

### `GET /api/entitlements/by-user-id`

Query params:

- `userId`
- `appUuid`

Provide exactly one.

Example:

```http
GET /api/entitlements/by-user-id?userId=8a8b3d61-1111-2222-3333-444444444444
GET /api/entitlements/by-user-id?appUuid=58c54620-1111-2222-3333-444444444444
```

Success:

```json
{
  "user": {
    "id": "8a8b3d61-1111-2222-3333-444444444444",
    "accountStatus": "active",
    "subscriptionTier": "pro",
    "paidFeatures": ["4k-pro"],
    "updatedAt": "2026-04-09T00:00:00.000Z"
  }
}
```

### `GET /api/entitlements/activation-link`

Cookie-auth route. Returns an activation link for a feature the signed-in user already owns.

Query params:

- `feature` default: `4k-pro`

Success:

```json
{
  "user": {
    "id": "uuid",
    "subscriptionTier": "pro",
    "paidFeatures": ["4k-pro"]
  },
  "activationURL": "macclipper://purchase-complete?userId=uuid&feature=4k-pro&token=..."
}
```

### `POST /api/purchases/4k-pro/complete`

Cookie-auth route. This is currently a simulated purchase completion route.

Success:

```json
{
  "user": {
    "id": "uuid",
    "subscriptionTier": "pro",
    "paidFeatures": ["4k-pro"]
  },
  "activationURL": "macclipper://purchase-complete?userId=uuid&feature=4k-pro&token=..."
}
```

## Bot-only routes

All routes below require the bearer secret header.

### `GET /api/bot/users/lookup`

Allowed query params:

- `email`
- `userId`
- `appUuid`
- `discordUserId`

Send exactly one.

Examples:

```http
GET /api/bot/users/lookup?userId=8a8b3d61-1111-2222-3333-444444444444
GET /api/bot/users/lookup?appUuid=58c54620-1111-2222-3333-444444444444
GET /api/bot/users/lookup?email=user@example.com
GET /api/bot/users/lookup?discordUserId=1491852847828959382
```

Success:

```json
{
  "user": {
    "id": "uuid",
    "appUuid": "uuid",
    "displayName": "Creator",
    "email": "user@example.com",
    "role": "user",
    "accountStatus": "active",
    "subscriptionTier": "free",
    "paidFeatures": [],
    "discordUserId": "",
    "discordUsername": "",
    "clipCount": 0
  }
}
```

### `POST /api/bot/users/link-discord`

Request body:

```json
{
  "appUuid": "uuid",
  "discordUserId": "1491852847828959382",
  "discordUsername": "Userbro20#0001"
}
```

You may use `email`, `userId`, or `discordUserId` instead of `appUuid` as the lookup key.

Success:

```json
{
  "user": {
    "id": "uuid",
    "discordUserId": "1491852847828959382",
    "discordUsername": "Userbro20#0001"
  }
}
```

### `POST /api/bot/users/admin`

Request body:

```json
{
  "appUuid": "uuid",
  "enabled": true
}
```

Success:

```json
{
  "user": {
    "id": "uuid",
    "role": "admin"
  }
}
```

### `POST /api/bot/users/status`

Allowed status values:

- `active`
- `banned`
- `terminated`

Request body:

```json
{
  "appUuid": "uuid",
  "status": "banned"
}
```

Notes:

- `banned` and `terminated` revoke active website sessions.
- `terminated` also resets role to `user`, tier to `free`, and clears paid features.

Success:

```json
{
  "user": {
    "id": "uuid",
    "accountStatus": "banned"
  }
}
```

### `POST /api/bot/users/subscription`

Allowed subscription tiers:

- `free`
- `pro`

Request body:

```json
{
  "appUuid": "uuid",
  "subscriptionTier": "pro",
  "paidFeatures": ["4k-pro"]
}
```

Notes:

- If tier is `pro`, the backend automatically includes `4k-pro` in `paidFeatures`.
- If `paidFeatures` is omitted, the tier default is used.

Success:

```json
{
  "user": {
    "id": "uuid",
    "subscriptionTier": "pro",
    "paidFeatures": ["4k-pro"]
  }
}
```

### `POST /api/bot/users/features/grant`

Request body:

```json
{
  "appUuid": "uuid",
  "feature": "4k-pro"
}
```

You may use `email`, `userId`, or `discordUserId` instead of `appUuid` as the lookup key.

Notes:

- Granting `4k-pro` also upgrades `subscriptionTier` to `pro`.
- This route returns the activation URL the Mac app can open.

Success:

```json
{
  "user": {
    "id": "uuid",
    "subscriptionTier": "pro",
    "paidFeatures": ["4k-pro"]
  },
  "activationURL": "macclipper://purchase-complete?userId=uuid&feature=4k-pro&token=..."
}
```

## Standard error shape

All failures return JSON like this:

```json
{ "error": "Message here" }
```

Common HTTP status behavior:

- `400` invalid payload, missing field, or invalid lookup usage
- `401` missing bot bearer secret or not signed in for cookie-auth routes
- `403` signed-in user does not own the requested feature, or account blocked from sign-in
- `404` user not found or video not found
- `409` duplicate signup email
- `503` bot secret not configured

## cURL examples for the bot

### Lookup by user ID

```bash
curl -H "Authorization: Bearer $MACCLIPPER_BOT_SHARED_SECRET" \
  "http://127.0.0.1:4173/api/bot/users/lookup?userId=<uuid>"
```

### Lookup by app UUID

```bash
curl -H "Authorization: Bearer $MACCLIPPER_BOT_SHARED_SECRET" \
  "http://127.0.0.1:4173/api/bot/users/lookup?appUuid=<uuid>"
```

### Link Discord

```bash
curl -X POST \
  -H "Authorization: Bearer $MACCLIPPER_BOT_SHARED_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"appUuid":"<uuid>","discordUserId":"1491852847828959382","discordUsername":"Userbro20#0001"}' \
  "http://127.0.0.1:4173/api/bot/users/link-discord"
```

### Ban account

```bash
curl -X POST \
  -H "Authorization: Bearer $MACCLIPPER_BOT_SHARED_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"appUuid":"<uuid>","status":"banned"}' \
  "http://127.0.0.1:4173/api/bot/users/status"
```

### Make admin

```bash
curl -X POST \
  -H "Authorization: Bearer $MACCLIPPER_BOT_SHARED_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"appUuid":"<uuid>","enabled":true}' \
  "http://127.0.0.1:4173/api/bot/users/admin"
```

### Grant 4K Pro

```bash
curl -X POST \
  -H "Authorization: Bearer $MACCLIPPER_BOT_SHARED_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"appUuid":"<uuid>","feature":"4k-pro"}' \
  "http://127.0.0.1:4173/api/bot/users/features/grant"
```

### Read live entitlements

```bash
curl "http://127.0.0.1:4173/api/entitlements/by-user-id?userId=<uuid>"
```

## Paste-ready prompt for Copilot in the bot repo

```text
Set up the Discord bot against this exact MacClipper API contract.

Base URL:
http://127.0.0.1:4173

Bot auth header:
Authorization: Bearer <MACCLIPPER_BOT_SHARED_SECRET>

Important: this backend only supports these lookup identifiers:
- email
- userId
- appUuid
- discordUserId

Implement a small API client with these routes:
- GET /api/bot/users/lookup with exactly one of email, userId, appUuid, discordUserId
- POST /api/bot/users/link-discord with a lookup field plus discordUserId and discordUsername
- POST /api/bot/users/admin with a lookup field plus enabled boolean
- POST /api/bot/users/status with a lookup field plus status in active|banned|terminated
- POST /api/bot/users/subscription with a lookup field plus subscriptionTier in free|pro and optional paidFeatures array
- POST /api/bot/users/features/grant with a lookup field plus feature string
- GET /api/entitlements/by-user-id with exactly one of userId or appUuid
- POST /api/auth/app-uuid for linking a signed-in website account to a Mac install UUID

Expected response shapes:
- Most bot routes return { user: { id, appUuid, displayName, email, createdAt, updatedAt, role, accountStatus, subscriptionTier, paidFeatures, discordUserId, discordUsername, clipCount } }
- Feature grant also returns activationURL
- Entitlement route returns { user: { id, accountStatus, subscriptionTier, paidFeatures, updatedAt } }
- Errors return { error: string }

Rules:
- Granting feature 4k-pro upgrades the user subscriptionTier to pro
- terminated resets role=user, subscriptionTier=free, and paidFeatures=[]
- banned and terminated revoke website sessions
- activationURL is a macclipper://purchase-complete deep link with userId and appUuid, and it should be shown back to the operator

Build the bot commands around appUuid first when you are targeting a specific Mac install, and fall back to website userId, email, or discordUserId when needed.
```