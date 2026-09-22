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
- Sign-out queues the MyPIU access token in encrypted storage until server revocation succeeds or the server confirms it is no longer valid.
- PIUGAME cookies remain in an in-memory OkHttp cookie jar.
- Raw PIUGAME HTML is parsed on-device and is never uploaded or persisted.
- WorkManager performs best-effort refresh using the same device-owned request path.

The current vertical slice covers MyPIU PKCE authorization, PIUGAME connection, foreground sync, normalized upload, recent-play display, and scheduled background refresh. Catalog, favorites, recommendations, progress, and offline history parity follow in later Stage 4 slices.
