(() => {
  // src/piugame-session.js
  var PIUGAME_ORIGINS = Object.freeze({
    phoenix: "https://phoenix.piugame.com",
    phoenix2: "https://www.piugame.com"
  });
  function normalizePIUGameVersion(value) {
    return value === "phoenix" ? "phoenix" : "phoenix2";
  }
  function piuSignInURL(version) {
    return `${PIUGAME_ORIGINS[normalizePIUGameVersion(version)]}/bbs/login.php`;
  }
  function isAuthenticatedProfilePage(page) {
    const url = String(page?.url ?? "");
    const html = String(page?.html ?? "");
    if (/\/(?:bbs\/)?login\.php(?:[?#]|$)/i.test(url)) return false;
    if (/form[^>]+action=["'][^"']*login_check\.php/i.test(html)) return false;
    return /subProfile_wrap|play_data_wrap|profile_name/i.test(html);
  }

  // src/service-worker.js
  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message?.type !== "mypiu:fetch-piugame") return false;
    if (sender.url && !sender.url.startsWith("https://mypiu.austin.kim/")) {
      sendResponse({ ok: false, error: "MyPIU must be the active site." });
      return false;
    }
    void fetchPages(normalizePIUGameVersion(message.version)).then((pages) => sendResponse({ ok: true, pages })).catch((error) => sendResponse(serializeError(error)));
    return true;
  });
  async function fetchPages(version) {
    const origin = PIUGAME_ORIGINS[version];
    const entries = await Promise.all([
      fetchPage(origin, "/my_page/play_data.php"),
      fetchPage(origin, "/my_page/recently_played.php"),
      fetchPage(origin, "/my_page/pumbility.php")
    ]);
    const [profile, recent, pumbility] = entries;
    if (!isAuthenticatedProfilePage(profile)) {
      throw new PIUGameSessionRequiredError(version);
    }
    return {
      version,
      profile: profile.html,
      recent: recent.html,
      pumbility: pumbility.html
    };
  }
  async function fetchPage(origin, path) {
    const response = await fetch(`${origin}${path}`, {
      credentials: "include",
      cache: "no-store",
      redirect: "follow",
      headers: { Accept: "text/html,application/xhtml+xml" }
    });
    if (!response.ok) throw new Error(`PIUGAME returned HTTP ${response.status}.`);
    return { url: response.url, html: await response.text() };
  }
  var PIUGameSessionRequiredError = class extends Error {
    constructor(version) {
      super("Sign in to PIUGAME in this browser, then retry.");
      this.name = "PIUGameSessionRequiredError";
      this.version = version;
    }
  };
  function serializeError(error) {
    if (error instanceof PIUGameSessionRequiredError) {
      return {
        ok: false,
        error: error.message,
        code: "piugame_session_required",
        recovery: { kind: "piugame", url: piuSignInURL(error.version) }
      };
    }
    return {
      ok: false,
      error: error instanceof Error ? error.message : "PIUGAME sync failed.",
      code: "piugame_fetch_failed"
    };
  }
})();
