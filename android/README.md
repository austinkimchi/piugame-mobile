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

Release version and upload-key signing inputs are supplied through environment variables; ordinary local and pull-request builds remain unsigned. See the [Android beta checklist](../docs/android-beta.md) for the protected signed-bundle workflow and Play internal-test process.

## Security boundary

- PIUGAME credentials and MyPIU access tokens are encrypted with an app-scoped Android Keystore AES-GCM key.
- The MyPIU account ID and preferred PIU version used to restore offline catalog data are encrypted and bound to the current access-token value; token replacement, expiry, account deletion, and sign-out invalidate them.
- Sign-out queues the MyPIU access token in encrypted storage until server revocation succeeds or the server confirms it is no longer valid.
- PIUGAME cookies remain in an in-memory OkHttp cookie jar.
- Raw PIUGAME HTML is parsed on-device and is never uploaded or persisted.
- WorkManager performs best-effort refresh using the same device-owned request path.

The parity baseline covers MyPIU PKCE authorization, PIUGAME connection, foreground sync, normalized upload, scheduled background refresh, searchable catalogs, recommendations, favorites, chart history, progress, Pumbility, recent-session activity, large-window navigation, account-scoped offline caching, and an accessibility code audit. Physical-device qualification and Play internal testing remain release gates.
