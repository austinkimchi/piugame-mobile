let clientPromise;

window.addEventListener("mypiu:request-extension-status", announceExtension);
announceExtension();

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== "mypiu:sync") return false;
  void sync().then(sendResponse);
  return true;
});

window.addEventListener("mypiu:request-extension-sync", () => {
  void sync().then((result) => {
    window.dispatchEvent(new CustomEvent("mypiu:extension-sync-result", {
      detail: result.ok
        ? {
            ok: true,
            recentPlayCount: result.recentPlayCount,
            importedRecentPlays: result.importedRecentPlays,
            duplicateRecentPlays: result.duplicateRecentPlays,
            duplicateRequest: result.duplicateRequest
          }
        : { ok: false, error: result.error, code: result.code, recovery: result.recovery }
    }));
  });
});

async function sync() {
  try {
    const context = await syncContext();
    const version = context.piuVersion === "phoenix" ? "phoenix" : "phoenix2";
    const result = await chrome.runtime.sendMessage({ type: "mypiu:fetch-piugame", version });
    if (!result?.ok) {
      return {
        ok: false,
        error: result?.error ?? "PIUGAME sync failed.",
        code: result?.code ?? "piugame_fetch_failed",
        recovery: result?.recovery ?? null
      };
    }
    clientPromise ??= Promise.all([
      import(chrome.runtime.getURL("src/parser.js")),
      import(chrome.runtime.getURL("src/import-client.js")),
      import(chrome.runtime.getURL("src/sync-client.js"))
    ]);
    const [
      { parseSyncPayload },
      { uploadPerformancePayload },
      { parseAndUploadSync }
    ] = await clientPromise;
    const syncResult = await parseAndUploadSync({
      pages: result.pages,
      context,
      installationId: await installationId(),
      appVersion: chrome.runtime.getManifest().version,
      parseSyncPayload,
      uploadPerformancePayload
    });

    return { ok: true, ...syncResult };
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : "PIUGAME sync failed.",
      code: typeof error?.code === "string" ? error.code : "sync_failed",
      recovery: error?.recovery ?? null
    };
  }
}

async function syncContext() {
  const response = await fetch("/api/mobile/v1/extension/context", {
    credentials: "same-origin",
    headers: { Accept: "application/json" }
  });
  if (response.ok) return response.json();
  const error = new Error(
    response.status === 409
      ? "Link a PIUGAME account in MyPIU before syncing."
      : "Sign in to MyPIU and link a PIUGAME account first."
  );
  error.code = response.status === 409 ? "piu_account_not_linked" : "mypiu_session_required";
  error.recovery = { kind: "mypiu", url: "https://mypiu.austin.kim" };
  throw error;
}

async function installationId() {
  const key = "mypiuInstallationId";
  const stored = await chrome.storage.local.get(key);
  if (stored[key]) return stored[key];
  const value = crypto.randomUUID();
  await chrome.storage.local.set({ [key]: value });
  return value;
}

function announceExtension() {
  window.dispatchEvent(new CustomEvent("mypiu:extension-ready", {
    detail: { version: chrome.runtime.getManifest().version }
  }));
}
