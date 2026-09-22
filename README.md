# MyPIU Mobile

Native clients for MyPIU. The iOS app is the first supported platform; Android follows after the device-sync contract is stable.

The mobile clients fetch PIUGAME data from the user's device, normalize it locally, and send only normalized performance data to MyPIU. PIUGAME credentials remain in the device keychain and are never uploaded to MyPIU.

## Repository layout

- `ios/` - SwiftUI iPhone and iPad app plus native PIUGAME client.
- `browser-extension/` - tested and reproducibly packaged Manifest V3 Chromium extension for toolbar and first-party MyPIU page sync.
- `docs/` - architecture, security boundaries, contracts, and delivery milestones.
- `android/` - Android implementation notes until the Compose client begins.

## iOS development

Requirements:

- Xcode 26 or newer
- XcodeGen 2.46 or newer
- Node.js 22 or newer

```bash
./scripts/generate-ios-project.sh
open ios/MyPIU.xcodeproj
```

The generation script installs the pinned extension build dependencies, creates the Safari-compatible runtime from the shared browser-extension sources, and embeds the Safari Web Extension target in MyPIU.

The first vertical slice connects directly to PIUGAME PHOENIX 2, stores credentials in Keychain, parses the profile and recent-play pages on-device, and renders a native SwiftUI dashboard.

For signing, privacy, and beta-distribution steps, see [the TestFlight checklist](docs/testflight.md).

## Status

This repository is pre-release and private. See [the delivery milestones](docs/milestones.md) for the path to TestFlight and Android.
