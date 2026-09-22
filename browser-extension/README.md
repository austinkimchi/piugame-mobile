# MyPIU browser sync proof

This unpacked Manifest V3 extension proves that PIUGAME requests can originate from a user's browser rather than the MyPIU server.

It is intentionally not store-ready. It targets the versioned ingest and extension-context endpoints described in `../docs/mobile-sync-contract.md`; those endpoints must ship before publishing the extension.

## Test

```bash
npm install
npm test
```

## Manual proof

1. Load this directory as an unpacked extension in a Chromium browser.
2. Sign in to `https://www.piugame.com` in the same browser profile.
3. Open `https://mypiu.austin.kim`.
4. Use the extension toolbar action and select **Read PIUGAME now**.

The popup reports the parsed player and recent-play count. MyPIU can also request an authenticated upload through the page event bridge after the backend endpoint is deployed.
