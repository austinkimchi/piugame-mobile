# Chrome Web Store submission

## Listing copy

**Name:** MyPIU Sync

**Summary:** Refresh MyPIU from the PIUGAME session already signed in on this device.

**Single purpose:** MyPIU Sync lets a signed-in MyPIU user manually import their own PIUGAME profile and recent-play data from the browser session on their device. This keeps PIUGAME traffic on the user's device rather than routing it through a shared MyPIU server.

**Detailed description:**

MyPIU Sync adds a user-initiated **Sync now** action to MyPIU. When used, it reads the signed-in player's PIUGAME profile, recent-play, and Pumbility pages, converts those pages into normalized performance fields in the browser, and sends the normalized result to the user's signed-in MyPIU account.

The extension does not read PIUGAME passwords, export cookies, upload raw PIUGAME HTML, inject advertisements, or run a background polling loop. If either session has expired, it opens the corresponding sign-in page and waits for the user to retry.

Privacy policy: `https://mypiu.austin.kim/privacy`

## Permission justifications

- `activeTab`: confirms that the user is invoking sync from an active MyPIU tab and sends the result back to that tab.
- `storage`: stores one random installation identifier used to make retried imports idempotent. It does not store credentials or page HTML.
- `https://mypiu.austin.kim/*`: reads the signed-in account's sync context and uploads normalized performance data to that same account.
- `https://www.piugame.com/*` and `https://phoenix.piugame.com/*`: fetch the profile, recent-play, and Pumbility pages using the browser's existing PIUGAME session.

No remotely hosted code is loaded or executed. All executable JavaScript is included in the submitted package.

## Data-use disclosure

The extension handles authentication state, website content, and user activity only to perform the user-requested MyPIU synchronization. Authentication cookies remain browser-managed and are never read as values or transmitted to MyPIU. Raw PIUGAME HTML is parsed in the extension and discarded. Normalized player identity, profile statistics, recent scores, judgments, chart details, and timestamps are sent only to the signed-in user's MyPIU account.

The data is not sold, used for advertising, used for credit or lending decisions, or transferred for an unrelated purpose.

## Reviewer flow

1. Sign in to a linked test account at `https://mypiu.austin.kim`.
2. Sign in to the matching player at the configured PIUGAME origin.
3. Open MyPIU in the active tab and choose the extension's **Sync now** action.
4. Confirm that the popup reports imported or already-saved plays and that MyPIU refreshes with the normalized data.

The publisher must provide the linked test credentials privately in the Web Store review notes. Do not commit them to this repository or include them in the extension package.

## Publisher checklist

- Create the matching `extension-v<version>` tag from `main`, then download and verify the ZIP from its prerelease.
- Upload that verified `mypiu-sync-chromium-v<version>.zip` to the Chrome Web Store.
- Supply store screenshots and promotional artwork from the production extension flow.
- Complete the privacy questionnaire using the disclosure above.
- Provide linked MyPIU and PIUGAME reviewer accounts through the store's private review instructions.
- Publish the approved version, then promote the matching GitHub prerelease to a release.
