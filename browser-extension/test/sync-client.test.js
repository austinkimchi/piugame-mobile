import assert from "node:assert/strict";
import test from "node:test";

import { parseAndUploadSync } from "../src/sync-client.js";

test("the browser sync flow always uploads the normalized parser result", async () => {
  const normalizedPayload = {
    profile: { displayName: "PLAYER#1234" },
    recentPlays: [{ songName: "BATTLE NO.1" }]
  };
  let uploadedPayload = null;
  let parserOptions = null;

  const result = await parseAndUploadSync({
    pages: { profile: "profile", recent: "recent", pumbility: "pumbility" },
    context: {
      piuUsername: "player",
      piuDisplayName: "PLAYER#1234"
    },
    installationId: "browser-installation",
    appVersion: "0.2.0",
    parseSyncPayload: (_pages, options) => {
      parserOptions = options;
      return normalizedPayload;
    },
    uploadPerformancePayload: async (payload) => {
      uploadedPayload = payload;
      return {
        importedRecentPlays: 1,
        duplicateRecentPlays: 0,
        duplicateRequest: false
      };
    }
  });

  assert.equal(parserOptions.username, "player");
  assert.equal(parserOptions.installationId, "browser-installation");
  assert.equal(parserOptions.appVersion, "0.2.0");
  assert.equal(uploadedPayload, normalizedPayload);
  assert.deepEqual(result, {
    displayName: "PLAYER#1234",
    recentPlayCount: 1,
    importedRecentPlays: 1,
    duplicateRecentPlays: 0,
    duplicateRequest: false
  });
});
