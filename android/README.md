# MyPIU Android

The Android client begins after the mobile ingest contract has shipped through the iOS TestFlight vertical slice. It will be a native Kotlin and Jetpack Compose application, not a WebView wrapper.

Planned platform services:

- Android Keystore for PIUGAME credentials and MyPIU tokens.
- OkHttp with an isolated cookie jar for PIUGAME requests.
- WorkManager for best-effort refresh.
- Room for offline catalog and performance history.
