import assert from "node:assert/strict";
import test from "node:test";

import {
  isAuthenticatedProfilePage,
  normalizePIUGameVersion,
  piuSignInURL
} from "../src/piugame-session.js";

test("recognizes an authenticated PIUGAME profile response", () => {
  assert.equal(isAuthenticatedProfilePage({
    url: "https://www.piugame.com/my_page/play_data.php",
    html: '<div class="subProfile_wrap"><div class="profile_name"></div></div>'
  }), true);
});

test("detects redirected and embedded PIUGAME login pages", () => {
  assert.equal(isAuthenticatedProfilePage({
    url: "https://www.piugame.com/bbs/login.php",
    html: '<div class="profile_name"></div>'
  }), false);
  assert.equal(isAuthenticatedProfilePage({
    url: "https://www.piugame.com/my_page/play_data.php",
    html: '<form action="/bbs/login_check.php"></form>'
  }), false);
});

test("builds version-specific recovery URLs with a safe default", () => {
  assert.equal(normalizePIUGameVersion("phoenix"), "phoenix");
  assert.equal(normalizePIUGameVersion("unexpected"), "phoenix2");
  assert.equal(piuSignInURL("phoenix"), "https://phoenix.piugame.com/bbs/login.php");
  assert.equal(piuSignInURL("phoenix2"), "https://www.piugame.com/bbs/login.php");
});
