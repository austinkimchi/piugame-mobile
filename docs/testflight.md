# TestFlight release checklist

MyPIU is configured for automatic signing with bundle ID `com.austinkimchi.mypiu`. The repository intentionally does not contain an Apple Developer Team ID, signing certificate, provisioning profile, or App Store Connect credential.

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

In Xcode, select the MyPIU target, choose the correct development team, and confirm automatic signing succeeds. Select a generic iOS device, then use **Product > Archive**. In Organizer, validate the archive and choose **Distribute App > TestFlight & App Store**.

For each upload, increment `CURRENT_PROJECT_VERSION` in `project.yml`. Keep `MARKETING_VERSION` unchanged for replacement beta builds of the same release.

## Before inviting testers

- Confirm the backend account-deletion release is live.
- Exercise Google and Discord sign-in on a physical device.
- Connect PIUGAME, foreground sync, background refresh, sign-out, and account deletion.
- Confirm the archive contains `PrivacyInfo.xcprivacy` and the 1024-point App Store icon.
- Confirm the archive contains `MyPIU Sync Extension.appex`, then enable it in Safari and grant access to MyPIU and the selected PIUGAME version on a physical device.
- Confirm App Store Connect reports no missing export-compliance or privacy information.
