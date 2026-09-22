import assert from "node:assert/strict";
import test from "node:test";

import { importError, uploadPerformancePayload } from "../src/import-client.js";

test("uploads normalized performance with the MyPIU browser session", async () => {
  const payload = { source: "browser-extension", recentPlays: [] };
  const result = await uploadPerformancePayload(payload, {
    fetchImpl: async (url, options) => {
      assert.equal(url, "/api/mobile/v1/performance/import");
      assert.equal(options.credentials, "same-origin");
      assert.deepEqual(JSON.parse(options.body), payload);
      return new Response(JSON.stringify({
        importedRecentPlays: 2,
        duplicateRecentPlays: 1,
        duplicateRequest: false
      }), { status: 201, headers: { "Content-Type": "application/json" } });
    }
  });

  assert.deepEqual(result, {
    importedRecentPlays: 2,
    duplicateRecentPlays: 1,
    duplicateRequest: false
  });
});

test("returns a MyPIU recovery action when the browser session expires", () => {
  const error = importError(
    new Response(null, { status: 401 }),
    { error: "authentication_required" }
  );

  assert.equal(error.code, "authentication_required");
  assert.equal(error.recovery.kind, "mypiu");
  assert.equal(error.recovery.url, "https://mypiu.austin.kim");
});

test("preserves the server retry interval for rate limits", () => {
  const error = importError(
    new Response(null, { status: 429, headers: { "Retry-After": "37" } }),
    { error: "rate_limited" }
  );

  assert.match(error.message, /37 seconds/);
  assert.equal(error.code, "rate_limited");
});
