# Delivery milestones

## Stage 0: foundation

- Separate private repository and native iOS project.
- Device-owned PIUGAME authentication and recent-play parsing.
- Keychain-only PIUGAME credentials.
- Native signed-out, loading, error, and dashboard states.
- Parser fixtures and CI build.
- Browser-extension feasibility proof and explicit permission boundary.

## Stage 1: iOS vertical slice

Current: the native iOS production baseline, mobile ingest contract, privacy manifest, account deletion/disconnect behavior, unsigned generic-device archive gate, and protected signed IPA/TestFlight upload workflow are available. App Store Connect enrollment, release-environment credentials, and physical-device TestFlight qualification remain.

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

Current: the Chromium extension performs toolbar- or MyPIU-page-initiated normalized uploads, coordinates concurrent refreshes, recovers expired sessions, and produces a verified store-upload ZIP with a tag-driven release. Safari packaging stages the same audited source for Apple's native wrapper, embeds the iOS extension in MyPIU, and produces a verified unsigned macOS Release archive with stable bundle identities. Chrome Web Store publication, signed Apple distribution, and physical Safari permission testing remain before this stage is complete.

- Manifest V3 Chromium beta.
- MyPIU page integration and normalized-data upload.
- PIUGAME session-expiry recovery.
- Safari Web Extension packaged with MyPIU for iOS and macOS.

## Stage 4: Android

Current: the native Kotlin/Compose app connects directly to PIUGAME, parses profile, Pumbility, and recent-play data on-device, encrypts credentials and MyPIU tokens with Android Keystore, uploads through the mobile ingest contract, and schedules best-effort WorkManager refreshes. Its native Songs destination covers searchable versioned catalogs, recommendations, favorites, song/chart detail, personal chart history, pagination, and account-scoped offline caching. Progress combines chart completion, score health, momentum, coverage, and a ranked Pumbility contribution breakdown while retaining an on-device fallback. Activity provides recent plays, chart bests, an on-device fallback, and complete recent-session summaries. Navigation adapts between a compact bottom bar and a large-window rail while preserving destination state. The parity baseline and accessibility code audit are complete, and a protected workflow can produce a versioned, pinned-upload-key-signed AAB. Play enrollment, internal-track rollout, and physical-device qualification remain.

- Kotlin/Compose app using the stable ingest contract.
- Android Keystore credentials and WorkManager best-effort refresh.
- Feature parity with the iOS production baseline.
