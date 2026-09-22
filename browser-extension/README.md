# MyPIU Sync Chromium beta

This unpacked Manifest V3 beta fetches PIUGAME from the user's browser session and uploads only normalized performance data to MyPIU. PIUGAME requests originate from the user's device rather than the MyPIU server.

The beta uses the production versioned ingest and extension-context endpoints described in `../docs/mobile-sync-contract.md`. It does not read passwords, export cookies, or upload raw PIUGAME HTML.

## Test

```bash
npm ci
npm test
```

## Install the beta

1. Load this directory as an unpacked extension in a Chromium browser.
2. Sign in to PIUGAME in the same browser profile.
3. Sign in to `https://mypiu.austin.kim` and link the matching PIUGAME account.
4. Refresh the MyPIU tab once after installing or updating the extension.
5. Use the extension toolbar action and select **Sync now**.

The popup reports new and duplicate plays returned by MyPIU. If either browser session has expired, it offers the appropriate sign-in action and leaves the sync retry under the user's control.

The content script also exposes a readiness handshake and the authenticated sync event bridge used by the MyPIU performance page. Page requests and results carry the same UUID so a late response cannot complete a newer retry.

## Current boundary

This is an unpacked Chromium beta, not a Chrome Web Store package. Background polling is intentionally excluded: Manifest V3 service workers are not a reliable high-frequency scheduler, so sync remains user initiated.
