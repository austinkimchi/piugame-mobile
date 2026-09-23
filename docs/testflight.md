# TestFlight release checklist

MyPIU is configured for automatic signing with bundle ID `com.austinkimchi.mypiu`. The repository intentionally does not contain an Apple Developer Team ID, signing certificate, provisioning profile, or App Store Connect credential. Once configured, the `ios-testflight` GitHub environment will supply a short-lived runner with an App Store Connect team key; Xcode uses automatic signing and Apple's cloud-managed distribution certificate, so no distribution certificate private key is copied into GitHub.

CI creates an unsigned generic-device Release archive and verifies the built app and embedded Safari extension identities, matching versions, dSYMs, privacy manifest, app icon assets, extension runtime, URL callback, background mode, and export-compliance declaration. The retained archive is packaging evidence only: it is not installable, cannot be uploaded to App Store Connect, and does not replace Apple's signed archive validation.

## One-time App Store Connect setup

The version-controlled English listing copy, TestFlight copy, screenshot plan, and private-value checklist live in [`ios/AppStore`](../ios/AppStore/README.md). Run `./scripts/verify-ios-store-metadata.sh` before copying them into App Store Connect.

1. Create explicit App IDs for `com.austinkimchi.mypiu` and `com.austinkimchi.mypiu.safari`, then create the App Store Connect app record for the main app ID.
2. Set the iOS privacy policy URL to `https://mypiu.austin.kim/privacy`.
3. Complete App Privacy using the same linked, non-tracking data categories declared in `PrivacyInfo.xcprivacy`: name, email address, user ID, device ID, gameplay content, and coarse location.
4. Add a feedback email, beta description, and testing notes under TestFlight test information.
5. Create an internal tester group. External testing requires beta app review.

## Protected release environment

The `ios-testflight` GitHub environment exists and its custom deployment policy permits only `main`. The current GitHub billing plan does not provide required-reviewer protection rules for private repositories. If the plan changes, add a reviewer who can verify the requested version and build number and disable administrator bypass. Until then, the workflow's `main` guard, manual dispatch, and export-only default are the available release controls. See [GitHub's environment availability notes](https://docs.github.com/en/rest/deployments/environments#about-deployment-environments).

After Apple Developer enrollment, add these environment values:

| Kind | Name | Value |
| --- | --- | --- |
| Variable | `APPLE_TEAM_ID` | The 10-character Apple Developer Team ID |
| Variable | `APP_STORE_CONNECT_KEY_ID` | The 10-character App Store Connect team-key ID |
| Variable | `APP_STORE_CONNECT_ISSUER_ID` | The App Store Connect issuer UUID |
| Secret | `APP_STORE_CONNECT_PRIVATE_KEY` | The complete one-time-downloaded `AuthKey_*.p8` contents |

Use a [team API key](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api), because Apple does not permit individual API keys to access provisioning endpoints. Give it only the [role needed to upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds), and ensure the team configuration grants access to Certificates, Identifiers & Profiles and [cloud-managed app distribution](https://developer.apple.com/help/account/certificates/cloud-managed-certificates). Revoke the key immediately if it is exposed. The workflow validates the identifiers and EC private key before contacting Apple, writes the key with mode `0600`, and removes it even when a later step fails.

## Automated archive and upload

1. Increment `CURRENT_PROJECT_VERSION` in `ios/project.yml`. Keep `MARKETING_VERSION` as three period-separated integers, such as `0.1.0`, and leave it unchanged for replacement beta builds of the same release.
2. Let the ordinary **iOS** workflow pass on `main`.
3. Check the commit and version, then run **iOS signed release** from the Actions page on `main` with **Upload the verified IPA to App Store Connect** disabled. If a required-reviewer rule becomes available later, approve the environment deployment separately.
4. Download `mypiu-ios-signed-<version>-<build>`, verify both checksum files with `shasum -a 256 -c`, and retain the IPA plus `MyPIU.xcarchive.zip` with the release record. GitHub retains this recovery copy for 90 days, but it is not a permanent archive.
5. Run the workflow again with upload enabled. The workflow exports and verifies the IPA, retains it with the matching archive and dSYMs, then gives that exact IPA to Apple's Transporter. An accepted upload still needs time to process before it appears in App Store Connect.

The signed workflow verifies the app and embedded Safari extension bundle IDs, versions, signatures, signing certificates, App Store provisioning profiles, expiration dates, team ownership, and production entitlements. It removes the API key before verification and artifact upload, then narrowly restores it only when an App Store upload was explicitly requested. Keep the downloaded Xcode archive permanently: Apple requires retaining every distributed archive, and its matching dSYMs preserve local crash-report symbolication if server-side symbols are unavailable. The workflow never selects a TestFlight group or submits an external beta for review; those remain separate operator decisions in App Store Connect.

## Local fallback

Use Xcode 26 or newer on a Mac signed in to the Apple Developer account:

```bash
./scripts/generate-ios-project.sh
open ios/MyPIU.xcodeproj
```

In Xcode, select the MyPIU and MyPIUSafariExtension targets, choose the same development team for both, and confirm automatic signing succeeds. Select a generic iOS device, then use **Product > Archive**. In Organizer, validate the archive and choose **Distribute App > TestFlight & App Store**.

After changing either version, let the iOS CI archive gate pass before creating the signed archive. The CI artifact is named `mypiu-ios-unsigned-archive-<commit>` and contains `MyPIU.xcarchive.zip` plus its SHA-256 file. It is retained for seven days for comparison with the signed release candidate. After downloading it on macOS, run `shasum -a 256 -c MyPIU.xcarchive.zip.sha256`, then extract it with `ditto -x -k MyPIU.xcarchive.zip .` so bundle permissions and metadata are preserved.

## Before inviting testers

- Confirm the backend account-deletion release is live.
- Exercise Google and Discord sign-in on a physical device.
- Connect PIUGAME, foreground sync, background refresh, sign-out, and account deletion.
- Confirm the archive contains `PrivacyInfo.xcprivacy` and the 1024-point App Store icon.
- Confirm the archive contains `MyPIU Sync Extension.appex`, then enable it in Safari and grant access to MyPIU and the selected PIUGAME version on a physical device.
- Confirm App Store Connect reports no missing export-compliance or privacy information.
