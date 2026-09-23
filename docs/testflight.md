# TestFlight release checklist

MyPIU is configured for automatic signing with bundle ID `com.austinkimchi.mypiu`. The repository intentionally does not contain an Apple Developer Team ID, signing certificate, provisioning profile, or App Store Connect credential.

CI creates an unsigned generic-device Release archive and verifies the built app and embedded Safari extension identities, matching versions, dSYMs, privacy manifest, app icon assets, extension runtime, URL callback, background mode, and export-compliance declaration. The retained archive is packaging evidence only: it is not installable, cannot be uploaded to App Store Connect, and does not replace Apple's signed archive validation.

## One-time App Store Connect setup

1. Create the explicit App ID and App Store Connect app record for `com.austinkimchi.mypiu`.
2. Set the iOS privacy policy URL to `https://mypiu.austin.kim/privacy`.
3. Complete App Privacy using the same linked, non-tracking data categories declared in `PrivacyInfo.xcprivacy`: name, email address, user ID, device ID, gameplay content, and coarse location.
4. Add a feedback email, beta description, and testing notes under TestFlight test information.
5. Create an internal tester group. External testing requires beta app review.

## Archive and upload

Use Xcode 26 or newer on a Mac signed in to the Apple Developer account:

```bash
./scripts/generate-ios-project.sh
open ios/MyPIU.xcodeproj
```

In Xcode, select the MyPIU and MyPIUSafariExtension targets, choose the same development team for both, and confirm automatic signing succeeds. Select a generic iOS device, then use **Product > Archive**. In Organizer, validate the archive and choose **Distribute App > TestFlight & App Store**.

For each upload, increment `CURRENT_PROJECT_VERSION` in `project.yml`. Keep `MARKETING_VERSION` unchanged for replacement beta builds of the same release.

After changing either version, let the iOS CI archive gate pass before creating the signed archive. The CI artifact is named `mypiu-ios-unsigned-archive-<commit>` and contains `MyPIU.xcarchive.zip` plus its SHA-256 file. It is retained for seven days for comparison with the signed release candidate. After downloading it on macOS, run `shasum -a 256 -c MyPIU.xcarchive.zip.sha256`, then extract it with `ditto -x -k MyPIU.xcarchive.zip .` so bundle permissions and metadata are preserved.

## Before inviting testers

- Confirm the backend account-deletion release is live.
- Exercise Google and Discord sign-in on a physical device.
- Connect PIUGAME, foreground sync, background refresh, sign-out, and account deletion.
- Confirm the archive contains `PrivacyInfo.xcprivacy` and the 1024-point App Store icon.
- Confirm the archive contains `MyPIU Sync Extension.appex`, then enable it in Safari and grant access to MyPIU and the selected PIUGAME version on a physical device.
- Confirm App Store Connect reports no missing export-compliance or privacy information.
