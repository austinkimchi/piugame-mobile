# Mobile sync contract

Endpoint: `POST /api/mobile/v1/performance/import`

Authentication: a revocable MyPIU mobile access token issued through the authorization-code and PKCE flow. PIUGAME credentials, cookies, and raw HTML are forbidden in this payload.

```json
{
  "schemaVersion": 1,
  "idempotencyKey": "ios:device-install-id:2026-09-21T22:30:00Z",
  "installationId": "device-install-id",
  "source": "ios",
  "appVersion": "0.1.0",
  "piuVersion": "phoenix2",
  "generatedAt": "2026-09-21T22:30:00Z",
  "profile": {
    "username": "player",
    "displayName": "PLAYER#1234",
    "titleName": "CONRAD FOLLOWER",
    "gameId": "PLAYER",
    "pumpTag": "PLAYER#1234",
    "avatarUrl": "https://www.piugame.com/avatar.png",
    "pumbilityScore": 15770.43,
    "pp": 1034,
    "rating": 18318,
    "playCount": 1200,
    "clearCount": 640,
    "totalCharts": 3900,
    "progressPercent": 16,
    "plateCounts": { "rg": 12 },
    "recentArcade": "ROUND1",
    "lastAccess": "2026-09-21 12:30:00"
  },
  "recentPlays": [
    {
      "songName": "BATTLE NO.1",
      "mode": "S",
      "level": "19",
      "score": 954848,
      "grade": "s",
      "plate": "rg",
      "stageBreak": false,
      "judgments": {
        "perfect": 1234,
        "great": 20,
        "good": 4,
        "bad": 0,
        "miss": 1
      },
      "playedAt": "2026-09-21 12:30:00 (GMT+9)"
    }
  ]
}
```

Expected response:

```json
{
  "accepted": true,
  "importedRecentPlays": 1,
  "duplicateRecentPlays": 0,
  "syncCursor": "opaque-server-cursor",
  "duplicateRequest": false
}
```

## Validation requirements

- Reject unknown schema versions.
- Require an idempotency key and retain it long enough to cover mobile retries.
- Confirm that the PIUGAME username matches the account linked to the MyPIU user.
- Apply strict size and item-count limits.
- Normalize mode, level, grade, timestamps, and song names server-side before persistence.
- Record the client source and app version for observability without treating them as trusted data.
- Rate-limit by MyPIU user and mobile installation, not by a shared egress IP.
- Preserve plays from delayed snapshots without allowing old profile metrics to replace newer data.

## Authentication endpoints

- `GET /api/mobile/v1/authorize` starts Google or Discord sign-in with a PKCE S256 challenge.
- `POST /api/mobile/v1/token` exchanges the short-lived code for a 90-day access token.
- `DELETE /api/mobile/v1/token` revokes the current token.
- `GET /api/mobile/v1/me` returns the authenticated MyPIU account and linked PIUGAME identity.

The native callback is `mypiu://oauth/callback`. Access tokens are stored in Keychain using device-only accessibility and are never written to preferences or logs.

## Performance read endpoint

`GET /api/mobile/v1/performance` returns the authenticated user's persisted MyPIU dashboard. It uses the same mobile bearer token and returns `{ "performance": { ... } }` with the profile summary, aggregate totals, recent plays, and top charts.

This endpoint is read-only, private, and uncached. It never contacts PIUGAME. Native clients should keep their latest on-device snapshot available when this endpoint is offline or has not received an import yet.
