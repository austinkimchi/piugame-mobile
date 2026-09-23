# App Store submission package

The committed files under `metadata/en-US` and `testflight/en-US` are the source of truth for MyPIU's first English App Store and TestFlight listings. Validate them before copying the values into App Store Connect:

```bash
./scripts/verify-ios-store-metadata.sh
```

The validator enforces Apple's current length and URL-format limits without making CI depend on external websites. Before each submission, an operator must also confirm that the support, marketing, and privacy URLs return successfully.

## App Store Connect values

- Primary language: English (U.S.)
- Primary category: Health & Fitness
- Secondary category: Entertainment
- Price: Free
- Copyright: enter the current year and account holder name in App Store Connect
- Content rights: declare that the app contains or displays third-party content and provide any documentation Apple requests
- App privacy: use the linked, non-tracking categories in `MyPIU/Resources/PrivacyInfo.xcprivacy`
- Encryption: the bundle declares that the app does not use non-exempt encryption

Do not commit the App Review contact, phone number, reviewer account credentials, or TestFlight feedback email. Enter those private values directly in App Store Connect. The reviewer account must be stable, must not require a one-time code, and must have linked MyPIU and PIUGAME data sufficient to exercise the review flow.

## Screenshot plan

Capture real production UI with a seeded review account and redact personal information. Do not use simulator-only placeholder data in a submitted screenshot.

Use one consistent portrait size for each required family:

- iPhone 6.9-inch: `1320 x 2868` pixels
- iPad 13-inch: `2064 x 2752` pixels

Provide this sequence for both families:

1. Home dashboard with the player's current progress and Pumbility.
2. Searchable Songs catalog with chart levels visible.
3. Song detail with a personal chart history.
4. Recommendations with several playable charts.
5. Activity with recent sessions and scores.

App Store Connect requires at least one screenshot and accepts at most ten per supported device size and localization. The app supports both iPhone and iPad, so both families need coverage.

## TestFlight setup

Copy `beta_description.txt` into Beta App Description and `what_to_test.txt` into the build's What to Test field. Set a monitored feedback email separately. For external testing, give TestFlight App Review the same stable reviewer accounts and the sign-in details needed for both MyPIU and PIUGAME.
