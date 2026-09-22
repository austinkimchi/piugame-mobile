import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { isValidChromiumVersion } from "../scripts/package.mjs";
import { runtimeFiles } from "../scripts/runtime-files.mjs";

const extensionDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(join(extensionDirectory, "manifest.json"), "utf8"));
const archiveName = `mypiu-sync-chromium-v${manifest.version}.zip`;
const archivePath = join(extensionDirectory, "dist", archiveName);
const expectedFiles = [...runtimeFiles];

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
  const archiveMetadata = execFileSync("zipinfo", ["-v", archivePath], { encoding: "utf8" });
  const archivedModes = [...archiveMetadata.matchAll(/Unix file attributes \((\d+) octal\)/g)]
    .map((match) => match[1]);
  assert.equal(archivedModes.length, expectedFiles.length);
  assert.deepEqual(new Set(archivedModes), new Set(["100644"]));

  const expectedDigest = readFileSync(`${archivePath}.sha256`, "utf8").split(/\s+/, 1)[0];
  const actualDigest = createHash("sha256").update(readFileSync(archivePath)).digest("hex");
  assert.equal(actualDigest, expectedDigest);

  execFileSync(process.execPath, ["scripts/package.mjs"], { cwd: extensionDirectory });
  const repeatedDigest = createHash("sha256").update(readFileSync(archivePath)).digest("hex");
  assert.equal(repeatedDigest, actualDigest);
});

test("stages the same allowlisted runtime for Safari", () => {
  execFileSync(process.execPath, ["scripts/stage-safari.mjs"], { cwd: extensionDirectory });

  const stagingDirectory = join(extensionDirectory, "dist", "safari-mv3");
  for (const relativePath of expectedFiles) {
    assert.equal(statSync(join(stagingDirectory, relativePath)).mode & 0o777, 0o644);
    if (relativePath !== "manifest.json" && relativePath !== "src/service-worker.js") {
      const source = readFileSync(join(extensionDirectory, relativePath));
      const staged = readFileSync(join(stagingDirectory, relativePath));
      assert.deepEqual(staged, source, `${relativePath} differs from its shared source`);
    }
  }

  const stagedManifest = JSON.parse(readFileSync(join(stagingDirectory, "manifest.json"), "utf8"));
  assert.equal(stagedManifest.background.type, undefined);
  assert.equal(stagedManifest.background.service_worker, "src/service-worker.js");
  const stagedWorker = readFileSync(join(stagingDirectory, "src/service-worker.js"), "utf8");
  assert.doesNotMatch(stagedWorker, /^\s*import\s/m);
  assert.match(stagedWorker, /chrome\.runtime\.onMessage\.addListener/);
  assert.match(stagedWorker, /https:\/\/phoenix\.piugame\.com/);

  const stagedFiles = execFileSync("find", [".", "-type", "f"], {
    cwd: stagingDirectory,
    encoding: "utf8"
  })
    .trim()
    .split("\n")
    .map((entry) => entry.replace(/^\.\//, ""))
    .sort();
  assert.deepEqual(stagedFiles, expectedFiles.toSorted());
});
