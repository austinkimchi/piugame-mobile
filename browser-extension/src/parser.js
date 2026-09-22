export function parseSyncPayload(pages, { generatedAt = new Date().toISOString(), username = null } = {}) {
  const profileDocument = documentFor(pages.profile);
  const recentDocument = documentFor(pages.recent);
  const pumbilityDocument = documentFor(pages.pumbility);

  return {
    schemaVersion: 1,
    source: "browser-extension",
    piuVersion: pages.version,
    generatedAt,
    profile: {
      username: clean(username),
      displayName: clean(profileDocument.querySelector(".profile_name .name_w .t2")?.textContent),
      pumbilityScore: decimal(pumbilityDocument.querySelector(".pumbility_total_wrap .t2")?.textContent),
      playCount: integer(profileDocument.querySelector(".board_search .total .t2, .board_search .total_wrap .t2")?.textContent),
      clearCount: integer(profileDocument.querySelector(".clear_w .l_con .t1")?.textContent?.split("/")[0]),
      totalCharts: integer(profileDocument.querySelector(".clear_w .l_con .t1")?.textContent?.split("/")[1])
    },
    recentPlays: [...recentDocument.querySelectorAll(".recently_playeList > li")].flatMap(parseRecentPlay)
  };
}

function parseRecentPlay(item) {
  const songName = clean(item.querySelector(".song_name p")?.textContent);
  if (!songName) return [];
  const scoreText = clean(item.querySelector(".con2 .list > li:nth-child(2) .tx")?.textContent);
  const stageBreak = /stage break/i.test(scoreText ?? "");
  const modeSource = item.querySelector(".stepBall_in .tw img")?.getAttribute("src")?.toLowerCase() ?? "";
  const mode = modeSource.includes("/s_text") ? "S" : modeSource.includes("/d_text") ? "D" : modeSource.includes("/c_text") ? "C" : null;
  const level = [...item.querySelectorAll(".stepBall_in .numw img")]
    .map((image) => image.getAttribute("src")?.match(/(?:num_|_)(\d)\.[a-z]+$/i)?.[1] ?? "")
    .join("") || null;
  const assetCode = (path) => {
    const source = [...item.querySelectorAll("img")].map((image) => image.getAttribute("src") ?? "").find((value) => value.includes(path));
    return source?.split("/").pop()?.replace(/\.[^.]+$/, "").toLowerCase() ?? null;
  };

  return [{
    songName,
    mode,
    level,
    score: stageBreak ? null : integer(scoreText),
    grade: assetCode("/grade/"),
    plate: assetCode("/plate/"),
    stageBreak,
    playedAt: clean(item.querySelector(".recently_date_tt")?.textContent)
  }];
}

function documentFor(html) {
  return new DOMParser().parseFromString(html, "text/html");
}

function clean(value) {
  const result = value?.replace(/\s+/g, " ").trim();
  return result || null;
}

function integer(value) {
  const digits = String(value ?? "").replace(/\D/g, "");
  return digits ? Number.parseInt(digits, 10) : null;
}

function decimal(value) {
  const normalized = String(value ?? "").replace(/[^\d.]/g, "");
  return normalized ? Number.parseFloat(normalized) : null;
}
