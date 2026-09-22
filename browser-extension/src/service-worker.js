const ORIGINS = {
  phoenix: "https://phoenix.piugame.com",
  phoenix2: "https://www.piugame.com"
};

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type !== "mypiu:fetch-piugame") return false;
  if (sender.url && !sender.url.startsWith("https://mypiu.austin.kim/")) {
    sendResponse({ ok: false, error: "MyPIU must be the active site." });
    return false;
  }

  void fetchPages(message.version === "phoenix" ? "phoenix" : "phoenix2")
    .then((pages) => sendResponse({ ok: true, pages }))
    .catch((error) => sendResponse({ ok: false, error: error instanceof Error ? error.message : "PIUGAME sync failed." }));
  return true;
});

async function fetchPages(version) {
  const origin = ORIGINS[version];
  const entries = await Promise.all([
    fetchPage(origin, "/my_page/play_data.php"),
    fetchPage(origin, "/my_page/recently_played.php"),
    fetchPage(origin, "/my_page/pumbility.php")
  ]);
  const [profile, recent, pumbility] = entries;
  if (!/subProfile_wrap|play_data_wrap|profile_name/i.test(profile)) {
    throw new Error("Sign in to PIUGAME in this browser, then retry.");
  }
  return { version, profile, recent, pumbility };
}

async function fetchPage(origin, path) {
  const response = await fetch(`${origin}${path}`, {
    credentials: "include",
    cache: "no-store",
    redirect: "follow",
    headers: { Accept: "text/html,application/xhtml+xml" }
  });
  if (!response.ok) throw new Error(`PIUGAME returned HTTP ${response.status}.`);
  return response.text();
}
