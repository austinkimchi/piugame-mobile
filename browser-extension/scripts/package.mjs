import { createHash } from "node:crypto";
import {
  chmodSync,
  copyFileSync,
  mkdirSync,
  readFileSync,
  rmSync,
  utimesSync,
  writeFileSync
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

export const packageFiles = Object.freeze([
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
]);

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const extensionDirectory = resolve(scriptDirectory, "..");
const fixedTimestamp = new Date("2000-01-01T00:00:00.000Z");

export function packageChromiumExtension() {
  const manifest = JSON.parse(readFileSync(join(extensionDirectory, "manifest.json"), "utf8"));
  const packageMetadata = JSON.parse(readFileSync(join(extensionDirectory, "package.json"), "utf8"));
  validateMetadata(manifest, packageMetadata);

  const distDirectory = join(extensionDirectory, "dist");
  const stagingDirectory = join(distDirectory, ".chromium-stage");
  const archiveName = `mypiu-sync-chromium-v${manifest.version}.zip`;
  const archivePath = join(distDirectory, archiveName);
  const checksumPath = `${archivePath}.sha256`;

  rmSync(distDirectory, { recursive: true, force: true });
  mkdirSync(stagingDirectory, { recursive: true });

  try {
    for (const relativePath of packageFiles) {
      const source = join(extensionDirectory, relativePath);
      const destination = join(stagingDirectory, relativePath);
      mkdirSync(dirname(destination), { recursive: true });
      copyFileSync(source, destination);
      chmodSync(destination, 0o644);
      utimesSync(destination, fixedTimestamp, fixedTimestamp);
    }

    const zip = spawnSync("zip", ["-X", "-q", archivePath, "-@"], {
      cwd: stagingDirectory,
      encoding: "utf8",
      env: { ...process.env, TZ: "UTC" },
      input: `${packageFiles.join("\n")}\n`
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

export function isValidChromiumVersion(value) {
  if (typeof value !== "string" || !/^\d+(?:\.\d+){0,3}$/.test(value)) return false;
  const rawComponents = value.split(".");
  if (rawComponents.some((component) => component.length > 1 && component.startsWith("0"))) {
    return false;
  }
  const components = rawComponents.map(Number);
  return components.some((component) => component !== 0)
    && components.every((component) => Number.isInteger(component) && component <= 65_535);
}

function validateMetadata(extensionManifest, npmPackage) {
  if (extensionManifest.manifest_version !== 3) {
    throw new Error("Only a Manifest V3 extension can be packaged.");
  }
  if (extensionManifest.version !== npmPackage.version) {
    throw new Error(
      `manifest version ${extensionManifest.version} does not match package version ${npmPackage.version}.`
    );
  }
  if (!isValidChromiumVersion(extensionManifest.version)) {
    throw new Error(`Invalid Chromium extension version: ${extensionManifest.version}`);
  }

  const referencedFiles = [
    ...Object.values(extensionManifest.icons ?? {}),
    ...Object.values(extensionManifest.action?.default_icon ?? {}),
    extensionManifest.action?.default_popup,
    extensionManifest.background?.service_worker,
    ...(extensionManifest.content_scripts ?? []).flatMap((entry) => entry.js ?? []),
    ...(extensionManifest.web_accessible_resources ?? []).flatMap((entry) => entry.resources ?? [])
  ].filter(Boolean);
  const omittedFiles = referencedFiles.filter((path) => !packageFiles.includes(path));
  if (omittedFiles.length > 0) {
    throw new Error(`Manifest files are missing from the package allowlist: ${omittedFiles.join(", ")}`);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  packageChromiumExtension();
}
