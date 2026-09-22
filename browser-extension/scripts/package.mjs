import { createHash } from "node:crypto";
import {
  readFileSync,
  rmSync,
  writeFileSync
} from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

import {
  extensionDirectory,
  readExtensionMetadata,
  runtimeFiles,
  stageExtensionRuntime,
  validateExtensionMetadata
} from "./runtime-files.mjs";

export { isValidChromiumVersion } from "./runtime-files.mjs";

export function packageChromiumExtension() {
  const { manifest, packageMetadata } = readExtensionMetadata();
  validateExtensionMetadata(manifest, packageMetadata);

  const distDirectory = join(extensionDirectory, "dist");
  const stagingDirectory = join(distDirectory, ".chromium-stage");
  const archiveName = `mypiu-sync-chromium-v${manifest.version}.zip`;
  const archivePath = join(distDirectory, archiveName);
  const checksumPath = `${archivePath}.sha256`;

  rmSync(distDirectory, { recursive: true, force: true });
  stageExtensionRuntime(stagingDirectory);

  try {
    const zip = spawnSync("zip", ["-X", "-q", archivePath, "-@"], {
      cwd: stagingDirectory,
      encoding: "utf8",
      env: { ...process.env, TZ: "UTC" },
      input: `${runtimeFiles.join("\n")}\n`
    });
    if (zip.error) throw zip.error;
    if (zip.status !== 0) {
      throw new Error(zip.stderr.trim() || `zip exited with status ${zip.status}`);
    }

    const digest = createHash("sha256").update(readFileSync(archivePath)).digest("hex");
    writeFileSync(checksumPath, `${digest}  ${archiveName}\n`);
    process.stdout.write(`${archivePath}\n${checksumPath}\n`);
  } finally {
    rmSync(stagingDirectory, { recursive: true, force: true });
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  packageChromiumExtension();
}
