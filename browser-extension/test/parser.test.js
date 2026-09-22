import assert from "node:assert/strict";
import test from "node:test";
import { DOMParser } from "linkedom";

import { parseSyncPayload } from "../src/parser.js";

globalThis.DOMParser = DOMParser;

test("normalizes profile and recent plays without exporting raw HTML", () => {
  const payload = parseSyncPayload({
    version: "phoenix2",
    profile: `
      <div class="subProfile_wrap">
        <div class="profile_name"><div class="name_w"><span class="t1">CONRAD FOLLOWER</span><span class="t2">PKIMCHI # 7501</span></div></div>
        <div class="profile_img"><div class="re" style="background-image:url('https://www.piugame.com/avatar.png')"></div></div>
        <div class="profile_etc"><span class="tt">1,034</span></div>
        <ul class="time_w"><li><span class="tt">last access date : 2026-09-21 12:37:31</span></li><li><span class="tt">recently access games : ROUND1</span></li></ul>
      </div>
      <div class="board_search"><div class="total"><span class="t2">215</span></div></div>
      <div class="play_data_wrap"><div class="my_w"><span class="num">18318</span></div></div>
      <div class="clear_w"><div class="l_con"><span class="t1">125 / 3,646</span></div><div class="graph"><span class="num">3%</span></div></div>
      <div class="plate_w"><ul class="list"><li><a data-type="rg"></a><span class="t_num">12</span></li></ul></div>`,
    recent: `
      <ul class="recently_playeList"><li>
        <div class="song_name"><p>BATTLE NO.1</p></div>
        <div class="stepBall_in"><div class="tw"><img src="https://www.piugame.com/l_img/stepball/full/s_text.png"></div><div class="numw"><img src="https://www.piugame.com/l_img/stepball/full/s_num_1.png"><img src="https://www.piugame.com/l_img/stepball/full/s_num_9.png"></div></div>
        <div class="con2"><ul class="list"><li></li><li><div class="tx">954,848</div><img src="https://www.piugame.com/l_img/grade/s.png"></li><li><img src="https://www.piugame.com/l_img/plate/rg.png"></li></ul></div>
        <table class="recently_play"><tr><td data-th="Perfect"><span class="tx">1,234</span></td><td data-th="Miss"><span class="tx">1</span></td></tr></table>
        <div class="recently_date_tt">2026-09-21 12:30:00 (GMT+9)</div>
      </li></ul>`,
    pumbility: `<div class="pumbility_total_wrap"><div class="t2">15,770.43</div></div>`
  }, {
    generatedAt: "2026-09-21T22:30:00.000Z",
    username: "pkimchi",
    expectedDisplayName: "PKIMCHI#7501",
    installationId: "fixture-install",
    appVersion: "0.1.0"
  });

  assert.equal(payload.idempotencyKey, "browser-extension:fixture-install:2026-09-21T22:30:00.000Z");
  assert.equal(payload.profile.username, "pkimchi");
  assert.equal(payload.profile.displayName, "PKIMCHI#7501");
  assert.equal(payload.profile.pp, 1_034);
  assert.equal(payload.profile.rating, 18_318);
  assert.equal(payload.profile.plateCounts.rg, 12);
  assert.equal(payload.profile.pumbilityScore, 15_770.43);
  assert.equal(payload.profile.clearCount, 125);
  assert.equal(payload.recentPlays[0].songName, "BATTLE NO.1");
  assert.equal(payload.recentPlays[0].mode, "S");
  assert.equal(payload.recentPlays[0].level, "19");
  assert.equal(payload.recentPlays[0].score, 954_848);
  assert.equal(payload.recentPlays[0].judgments.perfect, 1_234);
  assert.equal(JSON.stringify(payload).includes("recently_playeList"), false);
});

test("rejects a PIUGAME session for another linked player", () => {
  assert.throws(
    () => parseSyncPayload({
      version: "phoenix2",
      profile: `<div class="profile_name"><div class="name_w"><span class="t2">OTHER#1234</span></div></div>`,
      recent: "",
      pumbility: ""
    }, {
      username: "pkimchi",
      expectedDisplayName: "PKIMCHI#7501",
      installationId: "fixture-install"
    }),
    /different linked player/
  );
});

test("skips recent plays without a complete chart token", () => {
  const payload = parseSyncPayload({
    version: "phoenix2",
    profile: `<div class="profile_name"><div class="name_w"><span class="t2">PKIMCHI#7501</span></div></div>`,
    recent: `
      <ul class="recently_playeList">
        <li>
          <div class="song_name"><p>INCOMPLETE</p></div>
          <div class="stepBall_in"><div class="numw"><img src="/l_img/stepball/full/s_num_1.png"></div></div>
        </li>
        <li>
          <div class="song_name"><p>NO TIMESTAMP</p></div>
          <div class="stepBall_in"><div class="tw"><img src="/l_img/stepball/full/s_text.png"></div><div class="numw"><img src="/l_img/stepball/full/s_num_1.png"><img src="/l_img/stepball/full/s_num_5.png"></div></div>
        </li>
        <li>
          <div class="song_name"><p>COMPLETE</p></div>
          <div class="stepBall_in"><div class="tw"><img src="/l_img/stepball/full/s_text.png"></div><div class="numw"><img src="/l_img/stepball/full/s_num_1.png"><img src="/l_img/stepball/full/s_num_6.png"></div></div>
          <div class="recently_date_tt">2026-09-21 12:30:00 (GMT+9)</div>
        </li>
      </ul>`,
    pumbility: ""
  }, {
    username: "pkimchi",
    expectedDisplayName: "PKIMCHI#7501",
    installationId: "fixture-install"
  });

  assert.equal(payload.recentPlays.length, 1);
  assert.equal(payload.recentPlays[0].songName, "COMPLETE");
  assert.equal(payload.recentPlays[0].mode, "S");
  assert.equal(payload.recentPlays[0].level, "16");
});
