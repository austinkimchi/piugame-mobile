let parserPromise;

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== "mypiu:sync") return false;
  void sync(false).then(sendResponse);
  return true;
});

window.addEventListener("mypiu:request-extension-sync", () => {
  void sync(true).then((result) => {
    window.dispatchEvent(new CustomEvent("mypiu:extension-sync-result", {
      detail: result.ok
        ? { ok: true, recentPlayCount: result.recentPlayCount }
        : { ok: false, error: result.error }
    }));
  });
});

async function sync(upload) {
  try {
    const version = document.documentElement.dataset.piuVersion === "phoenix" ? "phoenix" : "phoenix2";
    const result = await chrome.runtime.sendMessage({ type: "mypiu:fetch-piugame", version });
    if (!result?.ok) return { ok: false, error: result?.error ?? "PIUGAME sync failed." };
    parserPromise ??= import(chrome.runtime.getURL("src/parser.js"));
    const { parseSyncPayload } = await parserPromise;
    const payload = parseSyncPayload(result.pages, {
      username: document.documentElement.dataset.piuUsername ?? null
    });

    if (upload) {
      const response = await fetch("/api/mobile/v1/performance/import", {
        method: "POST",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      });
      if (!response.ok) throw new Error(`MyPIU import returned HTTP ${response.status}.`);
    }

    return {
      ok: true,
      displayName: payload.profile.displayName,
      recentPlayCount: payload.recentPlays.length
    };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : "PIUGAME sync failed." };
  }
}
