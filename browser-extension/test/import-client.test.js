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

test("rejects an HTML success response instead of reporting a zero-item import", async () => {
  await assert.rejects(
    uploadPerformancePayload({ source: "browser-extension", recentPlays: [] }, {
      fetchImpl: async () => new Response("<html>Sign in</html>", {
        status: 200,
        headers: { "Content-Type": "text/html" }
      })
    }),
    (error) => {
      assert.equal(error.code, "invalid_import_receipt");
      assert.equal(error.recovery.kind, "mypiu");
      assert.equal(error.recovery.url, "https://mypiu.austin.kim");
      return true;
    }
  );
});

test("rejects an incomplete JSON success receipt", async () => {
  await assert.rejects(
    uploadPerformancePayload({ source: "browser-extension", recentPlays: [] }, {
      fetchImpl: async () => new Response(JSON.stringify({ importedRecentPlays: 2 }), {
        status: 201,
        headers: { "Content-Type": "application/json" }
      })
    }),
    { code: "invalid_import_receipt" }
  );
});

test("keeps unreadable error responses on the HTTP error path", async () => {
  await assert.rejects(
    uploadPerformancePayload({ source: "browser-extension", recentPlays: [] }, {
      fetchImpl: async () => new Response("upstream unavailable", { status: 503 })
    }),
    (error) => {
      assert.equal(error.status, 503);
      assert.equal(error.code, null);
      assert.match(error.message, /HTTP 503/);
      return true;
    }
  );
});
