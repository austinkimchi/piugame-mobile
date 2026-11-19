# MyPIU Mobile

[![iOS](https://github.com/austinkimchi/piugame-mobile/actions/workflows/ios.yml/badge.svg)](https://github.com/austinkimchi/piugame-mobile/actions/workflows/ios.yml)
[![Android](https://github.com/austinkimchi/piugame-mobile/actions/workflows/android.yml/badge.svg)](https://github.com/austinkimchi/piugame-mobile/actions/workflows/android.yml)
[![Browser extension](https://github.com/austinkimchi/piugame-mobile/actions/workflows/browser-extension.yml/badge.svg)](https://github.com/austinkimchi/piugame-mobile/actions/workflows/browser-extension.yml)
[![Safari extension](https://github.com/austinkimchi/piugame-mobile/actions/workflows/safari-extension.yml/badge.svg)](https://github.com/austinkimchi/piugame-mobile/actions/workflows/safari-extension.yml)

Native iOS and Android clients, plus companion browser extensions, for [MyPIU](https://mypiu.austin.kim). Track your Pump It Up progress and explore songs, charts, and recommendations.

This private project is **pre-release**. Device qualification and store distribution remain in progress.

## Features

- Searchable song catalog, chart details, favorites, recommendations, and offline catalog caching.
- Personal bests, Pumbility, completion progress, recent plays, and session history.
- On-device PIUGAME sync with credentials held in Keychain or Android Keystore; only normalized performance data is uploaded to MyPIU.
- Chromium and Safari extensions for syncing from an existing PIUGAME browser session.

## iOS setup

Requires **Xcode 26+**, **XcodeGen 2.46+**, and **Node.js 22+** on macOS.

```sh
./scripts/generate-ios-project.sh
open ios/MyPIU.xcodeproj
```

The generator stages the shared Safari extension and regenerates the checked-in Xcode project. Keep local signing changes separate before regenerating. For Android setup, see [android/README.md](android/README.md); for the browser extension, see [browser-extension/README.md](browser-extension/README.md).

## Development

Run the `MyPIU` scheme's tests on an available iPhone simulator in Xcode. Portable checks:

```sh
./scripts/verify-ios-store-metadata.sh
./scripts/test-ios-release-helpers.sh
npm --prefix browser-extension ci
npm --prefix browser-extension test
npm --prefix browser-extension run check:syntax
```

App source lives in `ios/` and `android/`; shared extension source lives in `browser-extension/`. [CI](docs/continuous-integration.md) checks generated artifacts, builds, tests, and unsigned release packaging for relevant changes. Unsigned archives do not qualify as installable or TestFlight builds.

## Documentation

- [Architecture](docs/architecture.md) and [mobile sync contract](docs/mobile-sync-contract.md)
- [Delivery milestones](docs/milestones.md) and [local qualification results](docs/qualification-2026-11-19.md)
- [Accessibility checks](docs/accessibility-audit.md)
- [iOS / TestFlight release](docs/testflight.md) and [App Store metadata](ios/AppStore/README.md)
- [Android beta](docs/android-beta.md), [iOS Safari extension](docs/safari-extension.md), and [macOS Safari release](docs/macos-release.md)
