# MyPIU Android

MyPIU Android is a native Kotlin and Jetpack Compose client. It sends PIUGAME requests from the device, parses normalized profile and recent-play data locally, and uploads only the versioned mobile contract to MyPIU.

## Requirements

- JDK 17 or newer
- Android SDK 37.0 with Build Tools 36.0.0

```sh
cd android
./gradlew testDebugUnitTest lintDebug assembleDebug
```

The debug APK is written under `app/build/outputs/apk/debug/`.

## Security boundary

- PIUGAME credentials and MyPIU access tokens are encrypted with an app-scoped Android Keystore AES-GCM key.
- The MyPIU account ID and preferred PIU version used to restore offline catalog data are encrypted and bound to the current access-token value; token replacement, expiry, account deletion, and sign-out invalidate them.
- Sign-out queues the MyPIU access token in encrypted storage until server revocation succeeds or the server confirms it is no longer valid.
- PIUGAME cookies remain in an in-memory OkHttp cookie jar.
- Raw PIUGAME HTML is parsed on-device and is never uploaded or persisted.
- WorkManager performs best-effort refresh using the same device-owned request path.

The current slices cover MyPIU PKCE authorization, PIUGAME connection, foreground sync, normalized upload, recent-play display, and scheduled background refresh. The native Songs destination adds searchable PHOENIX and PHOENIX 2 catalogs, paginated recommendation and favorite feeds, song/chart detail, personal chart history, and a bounded account-and-version-scoped offline cache. The Progress destination adds completion, score-health, momentum, coverage, and Pumbility contribution views with a local PIUGAME fallback. Session-dashboard, large-screen, and accessibility parity follow in later Stage 4 slices.
