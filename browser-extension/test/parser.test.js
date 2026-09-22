import assert from "node:assert/strict";
import test from "node:test";
import { DOMParser } from "linkedom";

import { parseSyncPayload } from "../src/parser.js";

globalThis.DOMParser = DOMParser;

test("normalizes profile and recent plays without exporting raw HTML", () => {
  const payload = parseSyncPayload({
    version: "phoenix2",
    profile: `
      <div class="subProfile_wrap"><div class="profile_name"><div class="name_w"><span class="t2">PKIMCHI#7501</span></div></div></div>
      <div class="board_search"><div class="total"><span class="t2">215</span></div></div>
      <div class="clear_w"><div class="l_con"><span class="t1">125 / 3,646</span></div></div>`,
    recent: `
      <ul class="recently_playeList"><li>
        <div class="song_name"><p>BATTLE NO.1</p></div>
        <div class="stepBall_in"><div class="tw"><img src="https://www.piugame.com/l_img/stepball/full/s_text.png"></div><div class="numw"><img src="https://www.piugame.com/l_img/stepball/full/s_num_1.png"><img src="https://www.piugame.com/l_img/stepball/full/s_num_9.png"></div></div>
        <div class="con2"><ul class="list"><li></li><li><div class="tx">954,848</div><img src="https://www.piugame.com/l_img/grade/s.png"></li><li><img src="https://www.piugame.com/l_img/plate/rg.png"></li></ul></div>
        <div class="recently_date_tt">2026-09-21 12:30:00 (GMT+9)</div>
      </li></ul>`,
    pumbility: `<div class="pumbility_total_wrap"><div class="t2">15,770.43</div></div>`
  }, {
    generatedAt: "2026-09-21T22:30:00.000Z",
    username: "pkimchi"
  });

  assert.equal(payload.profile.username, "pkimchi");
  assert.equal(payload.profile.displayName, "PKIMCHI#7501");
  assert.equal(payload.profile.pumbilityScore, 15_770.43);
  assert.equal(payload.profile.clearCount, 125);
  assert.equal(payload.recentPlays[0].songName, "BATTLE NO.1");
  assert.equal(payload.recentPlays[0].mode, "S");
  assert.equal(payload.recentPlays[0].level, "19");
  assert.equal(payload.recentPlays[0].score, 954_848);
  assert.equal(JSON.stringify(payload).includes("recently_playeList"), false);
});
