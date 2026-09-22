import {
  chmodSync,
  copyFileSync,
  mkdirSync,
  readFileSync,
  rmSync,
  utimesSync
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const runtimeFiles = Object.freeze([
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

export const extensionDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");

const fixedTimestamp = new Date("2000-01-01T00:00:00.000Z");

export function readExtensionMetadata() {
  return {
    manifest: JSON.parse(readFileSync(join(extensionDirectory, "manifest.json"), "utf8")),
    packageMetadata: JSON.parse(readFileSync(join(extensionDirectory, "package.json"), "utf8"))
  };
}

export function stageExtensionRuntime(destinationDirectory) {
  rmSync(destinationDirectory, { recursive: true, force: true });
  mkdirSync(destinationDirectory, { recursive: true });

  for (const relativePath of runtimeFiles) {
    const source = join(extensionDirectory, relativePath);
    const destination = join(destinationDirectory, relativePath);
    mkdirSync(dirname(destination), { recursive: true });
    copyFileSync(source, destination);
    normalizeRuntimeFile(destination);
  }
}

export function normalizeRuntimeFile(path) {
  chmodSync(path, 0o644);
  utimesSync(path, fixedTimestamp, fixedTimestamp);
}

export function validateExtensionMetadata(extensionManifest, npmPackage) {
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
  const omittedFiles = referencedFiles.filter((path) => !runtimeFiles.includes(path));
  if (omittedFiles.length > 0) {
    throw new Error(`Manifest files are missing from the package allowlist: ${omittedFiles.join(", ")}`);
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
