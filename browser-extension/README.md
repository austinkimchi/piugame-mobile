# MyPIU browser sync proof

This unpacked Manifest V3 extension proves that PIUGAME requests can originate from a user's browser rather than the MyPIU server.

It is intentionally not store-ready. The MyPIU ingest endpoint and page integration described in `../docs/mobile-sync-contract.md` must ship before publishing the extension.

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

The popup reports the parsed player and recent-play count. It does not upload data until the versioned ingest endpoint is available.
