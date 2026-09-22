# Mobile sync contract draft

Proposed endpoint: `POST /api/mobile/v1/performance/import`

Authentication: a revocable MyPIU mobile access token issued through the MyPIU OAuth flow. PIUGAME credentials and cookies are forbidden in this payload.

```json
{
  "schemaVersion": 1,
  "idempotencyKey": "ios:device-install-id:2026-09-21T22:30:00Z",
  "source": "ios",
  "piuVersion": "phoenix2",
  "generatedAt": "2026-09-21T22:30:00Z",
  "profile": {
    "username": "player",
    "displayName": "PLAYER#1234",
    "pumbilityScore": 15770.43,
    "playCount": 1200,
    "clearCount": 640,
    "totalCharts": 3900
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
  "syncCursor": "opaque-server-cursor"
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
