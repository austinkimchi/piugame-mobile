import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { isValidChromiumVersion } from "../scripts/package.mjs";

const extensionDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(join(extensionDirectory, "manifest.json"), "utf8"));
const archiveName = `mypiu-sync-chromium-v${manifest.version}.zip`;
const archivePath = join(extensionDirectory, "dist", archiveName);
const expectedFiles = [
  "manifest.json",
  "assets/icon-16.png",
  "assets/icon-32.png",
  "assets/icon-48.png",
  "assets/icon-128.png",
  "src/content-script.js",
  "src/import-client.js",
  "src/parser.js",
  "src/piugame-session.js",
  "src/popup.html",
  "src/popup.js",
  "src/service-worker.js",
  "src/sync-client.js"
];

test("accepts only Chromium-compatible extension versions", () => {
  assert.equal(isValidChromiumVersion("0.2.1"), true);
  assert.equal(isValidChromiumVersion("65535.0.1.9"), true);
  assert.equal(isValidChromiumVersion("0.0.0"), false);
  assert.equal(isValidChromiumVersion("1.65536"), false);
  assert.equal(isValidChromiumVersion("1.032"), false);
  assert.equal(isValidChromiumVersion("1.2.3.4.5"), false);
  assert.equal(isValidChromiumVersion("1.2-beta"), false);
});

test("builds an allowlisted Chromium package with a valid checksum", () => {
  execFileSync(process.execPath, ["scripts/package.mjs"], { cwd: extensionDirectory });

  const archiveEntries = execFileSync("unzip", ["-Z1", archivePath], { encoding: "utf8" })
    .trim()
    .split("\n");
  assert.deepEqual(archiveEntries, expectedFiles);
  assert.equal(archiveEntries.some((entry) => /(?:node_modules|test|package\.json)/.test(entry)), false);

  const expectedDigest = readFileSync(`${archivePath}.sha256`, "utf8").split(/\s+/, 1)[0];
  const actualDigest = createHash("sha256").update(readFileSync(archivePath)).digest("hex");
  assert.equal(actualDigest, expectedDigest);

  execFileSync(process.execPath, ["scripts/package.mjs"], { cwd: extensionDirectory });
  const repeatedDigest = createHash("sha256").update(readFileSync(archivePath)).digest("hex");
  assert.equal(repeatedDigest, actualDigest);
});
