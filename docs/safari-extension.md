# Safari Web Extension

MyPIU Sync uses the same Manifest V3 runtime in Chromium and Safari. The files in `browser-extension/` remain the only source of extension behavior; generated Xcode projects are build artifacts rather than maintained source.

Apple documents this native-wrapper requirement in [Packaging a web extension for Safari](https://developer.apple.com/documentation/safariservices/packaging-a-web-extension-for-safari). Safari grants host access per website, so the shipping build also follows Apple's [Safari web extension permission model](https://developer.apple.com/documentation/safariservices/managing-safari-web-extension-permissions).

## Packaging probe

`npm run stage:safari` copies the audited runtime allowlist to `browser-extension/dist/safari-mv3`. On macOS with Xcode 26, the Safari extension workflow passes that directory to Apple's packager:

```sh
xcrun safari-web-extension-packager browser-extension/dist/safari-mv3 \
  --project-location browser-extension/dist/safari-project \
  --app-name "MyPIU Sync" \
  --bundle-identifier com.austinkimchi.mypiu.sync \
  --swift \
  --copy-resources \
  --no-open \
  --no-prompt \
  --force
```

Safari does not currently accept the Chromium `background.type` manifest key. Staging therefore bundles the shared module worker into a classic worker and removes that one key from the generated manifest; the authored Chromium sources remain unchanged. CI fails if Apple's packager reports any other unsupported manifest keys.

CI checks that the generated iOS scheme builds without signing, creates an unsigned Release archive for the macOS scheme, and verifies that the copied Safari resources exactly match the staged runtime. The generated project and unsigned archive are uploaded for seven days as packaging evidence.

## Integration boundary

The generated wrapper is a feasibility and compatibility artifact. `scripts/generate-ios-project.sh` stages the same Safari runtime into `ios/MyPIUSafariExtension/Resources`, then XcodeGen embeds `MyPIUSafariExtension.appex` in the existing MyPIU app. Generated resources and Xcode projects remain ignored so there is one authored JavaScript source.

The macOS wrapper has stable app and extension identities plus a documented signing and archive path in `macos-release.md`. Distribution still requires Apple Developer signing, App Store Connect records, privacy metadata, and physical-device verification of Safari's per-site permission prompts for PIUGAME and MyPIU.
