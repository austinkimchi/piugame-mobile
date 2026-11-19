# Local iOS qualification — November 19, 2026

This check used an isolated worktree based on `3e5ab8eaf83476a7a5ee9ffa39a5026be03f09fa`, followed by the iPad orientation metadata correction in this change. The existing local Xcode project and signing settings were preserved.

## Environment and results

| Check | Result |
| --- | --- |
| Host | macOS 15.6.1, Xcode 26.2 (17C52), XcodeGen 2.46.0, Node.js 24.17.0 |
| Project generation | `generate-ios-project.sh` passed; generated project and Safari resources matched tracked files |
| Generic simulator build | Passed with signing disabled |
| XCTest | 60 passed, 0 failed, 0 skipped on iPhone 17 Pro / iOS 26.2 |
| Unsigned Release archive | Passed for version 0.1.0, build 1 |
| Archive verification | Passed, including app/extension identities, versions, dSYMs, privacy manifest, icons, callback URL, and staged Safari runtime |
| iPad orientation correction | Updated verifier rejected the original archive; rebuilt archive passed and no longer emitted the orientation warning |

The XCTest run preceded the plist-only orientation correction. No Swift code changed; the corrected artifact was validated with a fresh device archive and the archive verifier. The built iPhone orientation list remains portrait and both landscapes.

## Orientation correction

The app's shared orientation list omitted portrait upside-down and Xcode warned that the iPad app needed all interface orientations. `UISupportedInterfaceOrientations~ipad` now lists all four orientations. The archive verifier checks this declaration to prevent regression. Apple's [orientation guidance](https://developer.apple.com/documentation/uikit/uiviewcontroller/supportedinterfaceorientations) describes the iPad multitasking requirement; [device-specific plist keys](https://developer.apple.com/documentation/BundleResources/Information-Property-List/UISupportedInterfaceOrientations) allow the iPhone declaration to remain unchanged.

## Remaining qualification

This is build and automated-test evidence, not a distribution approval. The following remain unverified in this run:

- Runtime Google, Discord, and Apple sign-in, token recovery, and account switching.
- Live PIUGAME authentication, foreground/background sync, and performance upload.
- Physical iPhone/iPad, connectivity, accessibility, rotation, and multitasking behavior.
- Safari extension installation and per-site permission recovery on physical devices.
- Signed archive validation, App Store Connect processing, and TestFlight distribution.

No physical iPhone was reachable during this check. No Apple enrollment, credentials, release settings, or paid services were changed. See [issue #39](https://github.com/austinkimchi/piugame-mobile/issues/39), the [TestFlight checklist](testflight.md), and the [accessibility checklist](accessibility-audit.md) for the remaining gates.

The existing `SongsView.swift` switch-pattern warning and the AppIntents metadata-extraction notices remain; neither failed the build. The switch warning concerns `.idle` matching without the `.loading` case's condition, while the current model initializes `.idle` with an empty listing.

## Storage

Only the existing iOS 26.2 runtime was used, with one simulator test destination and one Xcode build at a time. No runtimes were installed. Audit-specific DerivedData was removed after retaining the unsigned archive (approximately 40 MiB), XCTest result bundle (approximately 900 KiB), and logs outside the repository. Existing simulator devices and the user's other build data were preserved.
