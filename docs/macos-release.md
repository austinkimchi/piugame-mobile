# macOS Safari release

MyPIU Sync is packaged as a macOS containing app with an embedded Safari Web Extension. Apple's Xcode 26 packager generates the native wrapper from the same staged Manifest V3 runtime used by Chromium and iOS.

## Generate the project

On a Mac with Xcode 26 or newer and Node.js 22 or newer:

```sh
./scripts/generate-macos-safari-project.sh
open "browser-extension/dist/safari-project/MyPIU Sync/MyPIU Sync.xcodeproj"
```

The generated project uses these stable release identities:

- Containing app: `com.austinkimchi.mypiu.sync`
- Safari extension: `com.austinkimchi.mypiu.sync.Extension`

Generated projects and archives are build artifacts. The authored extension remains under `browser-extension/`.

## Sign and archive

Register both explicit App IDs in the Apple Developer account. In Xcode, select the MyPIU Sync macOS app and extension targets, choose the same development team for both, and confirm automatic signing succeeds. Select **Any Mac**, then use **Product > Archive**.

CI creates an unsigned Release archive and verifies its app, embedded extension, bundle identities, native extension point, adapted manifest, and classic service worker. That artifact proves packaging only; it is not installable distribution media.

Use Organizer to validate and distribute the signed archive through the Mac App Store. A direct download instead requires a Developer ID archive, hardened runtime, notarization, and stapling before publication.

## Release check

On a physical Mac:

1. Install the signed app and open it once.
2. Enable MyPIU Sync under Safari Settings > Extensions.
3. Grant website access to MyPIU and the selected PIUGAME version.
4. Sign in to both sites, trigger a sync, and confirm the normalized upload appears in MyPIU.
5. Deny and restore each site permission to verify recovery copy and retry behavior.
