import assert from "node:assert/strict";
import test from "node:test";

import { parseHTML } from "linkedom";

test("page sync results echo the request UUID and malformed requests are ignored", async () => {
  const { window } = parseHTML("<html></html>");
  const originalWindow = globalThis.window;
  const originalCustomEvent = globalThis.CustomEvent;
  const originalChrome = globalThis.chrome;
  const originalFetch = globalThis.fetch;
  const results = [];

  globalThis.window = window;
  globalThis.CustomEvent = window.CustomEvent;
  globalThis.fetch = async () => ({
    ok: true,
    json: async () => ({ piuVersion: "phoenix2" })
  });
  globalThis.chrome = {
    runtime: {
      getManifest: () => ({ version: "0.2.1" }),
      onMessage: { addListener() {} },
      sendMessage: async () => ({ ok: false, error: "PIUGAME unavailable", code: "test_failure" })
    }
  };

  try {
    window.addEventListener("mypiu:extension-sync-result", (event) => results.push(event.detail));
    await import(`../src/content-script.js?test=${Date.now()}`);

    window.dispatchEvent(new window.CustomEvent("mypiu:request-extension-sync", {
      detail: { requestId: "not-a-uuid" }
    }));
    await nextTurn();
    assert.deepEqual(results, []);

    const requestId = "d62d2ddc-3262-44e2-8f3b-dde40ff37760";
    window.dispatchEvent(new window.CustomEvent("mypiu:request-extension-sync", {
      detail: { requestId }
    }));
    await nextTurn();

    assert.equal(results.length, 1);
    assert.equal(results[0].requestId, requestId);
    assert.equal(results[0].ok, false);
    assert.equal(results[0].code, "test_failure");
  } finally {
    globalThis.window = originalWindow;
    globalThis.CustomEvent = originalCustomEvent;
    globalThis.chrome = originalChrome;
    globalThis.fetch = originalFetch;
  }
});

function nextTurn() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}
