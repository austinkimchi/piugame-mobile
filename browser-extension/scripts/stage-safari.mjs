import { readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

import {
  extensionDirectory,
  normalizeRuntimeFile,
  readExtensionMetadata,
  stageExtensionRuntime,
  validateExtensionMetadata
} from "./runtime-files.mjs";

export async function stageSafariExtension(
  stagingDirectory = join(extensionDirectory, "dist", "safari-mv3")
) {
  const { manifest, packageMetadata } = readExtensionMetadata();
  validateExtensionMetadata(manifest, packageMetadata);

  stageExtensionRuntime(stagingDirectory);
  const stagedManifestPath = join(stagingDirectory, "manifest.json");
  const stagedManifest = JSON.parse(readFileSync(stagedManifestPath, "utf8"));
  delete stagedManifest.background.type;
  writeFileSync(stagedManifestPath, `${JSON.stringify(stagedManifest, null, 2)}\n`);
  normalizeRuntimeFile(stagedManifestPath);

  const stagedServiceWorkerPath = join(stagingDirectory, stagedManifest.background.service_worker);
  await build({
    entryPoints: [join(extensionDirectory, manifest.background.service_worker)],
    outfile: stagedServiceWorkerPath,
    bundle: true,
    format: "iife",
    platform: "browser",
    target: "safari15.4",
    legalComments: "none",
    logLevel: "silent"
  });
  normalizeRuntimeFile(stagedServiceWorkerPath);
  process.stdout.write(`${stagingDirectory}\n`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (args.length !== 0 && (args.length !== 2 || args[0] !== "--output" || !args[1])) {
    throw new Error("Usage: node scripts/stage-safari.mjs [--output <directory>]");
  }
  await stageSafariExtension(args[1] ? resolve(args[1]) : undefined);
}
