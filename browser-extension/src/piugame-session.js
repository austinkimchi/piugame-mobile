export const PIUGAME_ORIGINS = Object.freeze({
  phoenix: "https://phoenix.piugame.com",
  phoenix2: "https://www.piugame.com"
});

export function normalizePIUGameVersion(value) {
  return value === "phoenix" ? "phoenix" : "phoenix2";
}

export function piuSignInURL(version) {
  return `${PIUGAME_ORIGINS[normalizePIUGameVersion(version)]}/bbs/login.php`;
}

export function isAuthenticatedProfilePage(page) {
  const url = String(page?.url ?? "");
  const html = String(page?.html ?? "");
  if (/\/(?:bbs\/)?login\.php(?:[?#]|$)/i.test(url)) return false;
  if (/form[^>]+action=["'][^"']*login_check\.php/i.test(html)) return false;
  return /subProfile_wrap|play_data_wrap|profile_name/i.test(html);
}
