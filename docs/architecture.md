# Client-owned sync architecture

## Decision

MyPIU Mobile lives in a separate repository from `piugame-web`.

The native apps have independent App Store and Play Store releases, signing assets, platform entitlements, background-execution rules, and UI architecture. They share data contracts with the web backend, not a deployment unit or UI codebase.

## Product boundary

The app is a native MyPIU client, not a web container.

- iOS uses SwiftUI, URLSession, Keychain, BackgroundTasks, and platform navigation.
- Android will use Kotlin and Jetpack Compose after the ingest contract stabilizes.
- The backend remains the source of truth for catalog metadata, community data, favorites, recommendations, and cross-device history.
- The device is the source of PIUGAME network traffic and PIUGAME credentials.

## Trust boundaries

1. The user enters PIUGAME credentials into the native app.
2. The app authenticates directly with PIUGAME using an ephemeral URLSession cookie store.
3. The password is stored as an internet-password Keychain item with device-only accessibility after first unlock.
4. PIUGAME HTML is parsed on-device into versioned DTOs.
5. The app uploads normalized DTOs to MyPIU using a separate, revocable MyPIU access token.
6. MyPIU never needs the PIUGAME password or PIUGAME cookies.

Raw PIUGAME HTML is not part of the upload contract. This limits accidental credential, cookie, and markup leakage.

## Sync sequence

```text
MyPIU iOS             PIUGAME                 MyPIU API
    | POST login -------->|                         |
    | GET profile/recent->|                         |
    |<------ HTML --------|                         |
    | parse + normalize   |                         |
    | POST sync envelope -------------------------->|
    |<------------- accepted cursor ----------------|
```

Every upload includes a schema version, PIUGAME release, source, generated timestamp, and idempotency key. The backend validates ownership and performs the same deduplication used by server-originated syncs.

## Background behavior

Opening the app and pull-to-refresh always attempt a foreground sync. `BGAppRefreshTask` provides best-effort background refresh, but iOS decides when it runs; it is not an exact polling schedule. A failed background refresh never falls back to the mono-server.

The initial full-history import is foreground-only, uses a low concurrency limit, and is explicitly initiated by the user. Routine refresh fetches only profile, Pumbility, and recent plays.

## Shared contracts, separate implementations

The TypeScript `piugame-sdk` remains the behavior reference. Its Node-only dependencies and cookie implementation are not embedded in the native app. Parser fixtures and normalized DTO examples should be shared across repositories so Swift, Kotlin, and TypeScript implementations can be compared against the same inputs.
