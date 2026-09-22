# Delivery milestones

## Stage 0: foundation

- Separate private repository and native iOS project.
- Device-owned PIUGAME authentication and recent-play parsing.
- Keychain-only PIUGAME credentials.
- Native signed-out, loading, error, and dashboard states.
- Parser fixtures and CI build.
- Browser-extension feasibility proof and explicit permission boundary.

## Stage 1: iOS vertical slice

- MyPIU mobile OAuth and revocable access tokens.
- Versioned mobile ingest endpoint in `piugame-web`.
- Foreground profile and recent-play sync end to end.
- Server reconciliation, idempotency, and sync diagnostics.
- TestFlight build with privacy copy and account deletion/disconnect behavior.

## Stage 2: PumpStats-plus product surface

Complete: native catalog, recommendations, favorites, offline cache, adaptive iPad navigation, completion progress, Pumbility breakdown, personal chart history, complete recent-session summaries, and the accessibility audit are available. Release candidates retain the device smoke-test checklist in `accessibility-audit.md`.

- Searchable song catalog and chart detail.
- Personal best history, recent attempts, Pumbility breakdown, and session summaries.
- Recommendations, favorites, and progress views.
- Offline catalog cache and responsive iPad navigation.
- Accessibility, Dynamic Type, VoiceOver, and reduced-motion audit.

## Stage 3: companion web extension

Current: the Chromium extension performs toolbar- or MyPIU-page-initiated normalized uploads, coordinates concurrent refreshes, recovers expired sessions, and produces a verified store-upload ZIP with a tag-driven release. Safari packaging stages the same audited source for Apple's native wrapper, verifies generated iOS and macOS builds, and embeds the iOS extension in MyPIU. Chrome Web Store publication, physical Safari permission testing, and the macOS release wrapper remain before this stage is complete.

- Manifest V3 Chromium beta.
- MyPIU page integration and normalized-data upload.
- PIUGAME session-expiry recovery.
- Safari Web Extension packaged with MyPIU for iOS and macOS.

## Stage 4: Android

- Kotlin/Compose app using the stable ingest contract.
- Android Keystore credentials and WorkManager best-effort refresh.
- Feature parity with the iOS production baseline.
