export function parseSyncPayload(pages, {
  generatedAt = new Date().toISOString(),
  username = null,
  expectedDisplayName = null,
  installationId = null,
  appVersion = null
} = {}) {
  const profileDocument = documentFor(pages.profile);
  const recentDocument = documentFor(pages.recent);
  const pumbilityDocument = documentFor(pages.pumbility);
  const normalizedUsername = clean(username);
  const normalizedExpectedDisplayName = identityKey(expectedDisplayName);
  const normalizedInstallationId = clean(installationId);
  const displayName = canonicalDisplayName(profileDocument.querySelector(".profile_name .name_w .t2")?.textContent);
  if (!normalizedUsername || !normalizedExpectedDisplayName || !normalizedInstallationId || !displayName) {
    throw new Error("MyPIU could not identify the linked PIUGAME account.");
  }
  if (identityKey(displayName) !== normalizedExpectedDisplayName) {
    throw new Error("The PIUGAME browser session belongs to a different linked player.");
  }

  return {
    schemaVersion: 1,
    idempotencyKey: `browser-extension:${normalizedInstallationId}:${generatedAt}`,
    installationId: normalizedInstallationId,
    source: "browser-extension",
    appVersion: clean(appVersion),
    piuVersion: pages.version,
    generatedAt,
    profile: {
      username: normalizedUsername,
      displayName,
      titleName: clean(profileDocument.querySelector(".profile_name .name_w .t1")?.textContent),
      gameId: null,
      pumpTag: displayName,
      avatarUrl: backgroundImageURL(profileDocument.querySelector(".profile_img .re")?.getAttribute("style")),
      pumbilityScore: decimal(pumbilityDocument.querySelector(".pumbility_total_wrap .t2")?.textContent),
      pp: decimal(profileDocument.querySelector(".profile_etc .tt")?.textContent),
      rating: integer(profileDocument.querySelector(".play_data_wrap .my_w .num")?.textContent),
      playCount: integer(profileDocument.querySelector(".board_search .total .t2, .board_search .total_wrap .t2")?.textContent),
      clearCount: integer(profileDocument.querySelector(".clear_w .l_con .t1")?.textContent?.split("/")[0]),
      totalCharts: integer(profileDocument.querySelector(".clear_w .l_con .t1")?.textContent?.split("/")[1]),
      progressPercent: integer(profileDocument.querySelector(".clear_w .graph .num")?.textContent),
      plateCounts: Object.fromEntries(
        [...profileDocument.querySelectorAll(".plate_w .list li")].flatMap((item) => {
          const code = item.querySelector("[data-type]")?.getAttribute("data-type")?.toLowerCase();
          const count = integer(item.querySelector(".t_num")?.textContent);
          return code && count !== null ? [[code, count]] : [];
        })
      ),
      recentArcade: timeValue(profileDocument, "recently access games"),
      lastAccess: timeValue(profileDocument, "last access date")
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
  const playedAt = clean(item.querySelector(".recently_date_tt")?.textContent);
  if (!mode || !level || !playedAt) return [];
  const assetCode = (path) => {
    const source = [...item.querySelectorAll("img")].map((image) => image.getAttribute("src") ?? "").find((value) => value.includes(path));
    return source?.split("/").pop()?.replace(/\.[^.]+$/, "").toLowerCase() ?? null;
  };
  const judgment = (name) => integer(
    [...item.querySelectorAll("table.recently_play td")]
      .find((cell) => cell.getAttribute("data-th")?.toLowerCase() === name)
      ?.querySelector(".tx")?.textContent
  );

  return [{
    songName,
    mode,
    level,
    score: stageBreak ? null : integer(scoreText),
    grade: assetCode("/grade/"),
    plate: assetCode("/plate/"),
    stageBreak,
    judgments: {
      perfect: judgment("perfect"),
      great: judgment("great"),
      good: judgment("good"),
      bad: judgment("bad"),
      miss: judgment("miss")
    },
    playedAt
  }];
}

function backgroundImageURL(style) {
  return style?.match(/url\(['"]?([^'")]+)/i)?.[1] ?? null;
}

function timeValue(document, prefix) {
  const text = [...document.querySelectorAll(".time_w .tt")]
    .map((element) => clean(element.textContent))
    .find((value) => value?.toLowerCase().startsWith(prefix));
  if (!text) return null;
  return clean(text.slice(text.indexOf(":") + 1));
}

function documentFor(html) {
  return new DOMParser().parseFromString(html, "text/html");
}

function clean(value) {
  const result = value?.replace(/\s+/g, " ").trim();
  return result || null;
}

function identityKey(value) {
  return canonicalDisplayName(value)?.toLocaleLowerCase("en-US") ?? null;
}

function canonicalDisplayName(value) {
  return clean(value)?.replace(/\s*#\s*/g, "#") ?? null;
}

function integer(value) {
  const digits = String(value ?? "").replace(/\D/g, "");
  return digits ? Number.parseInt(digits, 10) : null;
}

function decimal(value) {
  const normalized = String(value ?? "").replace(/[^\d.]/g, "");
  return normalized ? Number.parseFloat(normalized) : null;
}
