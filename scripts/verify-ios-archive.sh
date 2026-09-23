#!/bin/sh
set -eu

archive_path=${1:?"Usage: verify-ios-archive.sh ARCHIVE_PATH MARKETING_VERSION BUILD_NUMBER"}
expected_marketing_version=${2:?"Expected marketing version is required"}
expected_build_number=${3:?"Expected build number is required"}

app="$archive_path/Products/Applications/MyPIU.app"
extension="$app/PlugIns/MyPIU Sync Extension.appex"
manifest="$extension/manifest.json"
privacy_manifest="$app/PrivacyInfo.xcprivacy"

test -d "$app"
test -f "$app/Info.plist"
test -x "$app/MyPIU"
test -f "$app/Assets.car"
test -n "$(find "$app" -maxdepth 1 -name 'AppIcon*.png' -size +0c -print -quit)"
test -f "$privacy_manifest"
test -d "$extension"
test -f "$extension/Info.plist"
test -x "$extension/MyPIU Sync Extension"
test -f "$manifest"
test -f "$extension/src/service-worker.js"
test -d "$archive_path/dSYMs/MyPIU.app.dSYM"
test -d "$archive_path/dSYMs/MyPIU Sync Extension.appex.dSYM"

python3 - \
  "$archive_path/Info.plist" \
  "$app/Info.plist" \
  "$extension/Info.plist" \
  "$privacy_manifest" \
  "$manifest" \
  "$expected_marketing_version" \
  "$expected_build_number" <<'PY'
import json
import pathlib
import plistlib
import sys


def read_plist(path: str) -> dict:
    with pathlib.Path(path).open("rb") as plist_file:
        return plistlib.load(plist_file)


archive_info = read_plist(sys.argv[1])
app_info = read_plist(sys.argv[2])
extension_info = read_plist(sys.argv[3])
privacy = read_plist(sys.argv[4])
manifest = json.loads(pathlib.Path(sys.argv[5]).read_text())
expected_marketing_version = sys.argv[6]
expected_build_number = sys.argv[7]

assert app_info["CFBundleIdentifier"] == "com.austinkimchi.mypiu"
assert app_info["CFBundlePackageType"] == "APPL"
assert app_info["CFBundleShortVersionString"] == expected_marketing_version
assert app_info["CFBundleVersion"] == expected_build_number
assert app_info["ITSAppUsesNonExemptEncryption"] is False
assert "fetch" in app_info["UIBackgroundModes"]
assert any(
    "mypiu" in url_type.get("CFBundleURLSchemes", [])
    for url_type in app_info["CFBundleURLTypes"]
)

assert extension_info["CFBundleIdentifier"] == "com.austinkimchi.mypiu.safari"
assert extension_info["CFBundlePackageType"] == "XPC!"
assert extension_info["CFBundleShortVersionString"] == expected_marketing_version
assert extension_info["CFBundleVersion"] == expected_build_number
assert extension_info["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.Safari.web-extension"
assert extension_info["NSExtension"]["NSExtensionPrincipalClass"].endswith(".SafariWebExtensionHandler")

application_properties = archive_info["ApplicationProperties"]
assert application_properties["ApplicationPath"] == "Applications/MyPIU.app"
assert application_properties["CFBundleIdentifier"] == "com.austinkimchi.mypiu"
assert application_properties["CFBundleShortVersionString"] == expected_marketing_version
assert application_properties["CFBundleVersion"] == expected_build_number

assert privacy["NSPrivacyTracking"] is False
assert privacy["NSPrivacyTrackingDomains"] == []
collected_types = {
    entry["NSPrivacyCollectedDataType"]
    for entry in privacy["NSPrivacyCollectedDataTypes"]
}
assert collected_types == {
    "NSPrivacyCollectedDataTypeName",
    "NSPrivacyCollectedDataTypeEmailAddress",
    "NSPrivacyCollectedDataTypeUserID",
    "NSPrivacyCollectedDataTypeDeviceID",
    "NSPrivacyCollectedDataTypeGameplayContent",
    "NSPrivacyCollectedDataTypeCoarseLocation",
}
assert all(
    entry["NSPrivacyCollectedDataTypeLinked"] is True
    and entry["NSPrivacyCollectedDataTypeTracking"] is False
    for entry in privacy["NSPrivacyCollectedDataTypes"]
)
accessed_api_reasons = {
    entry["NSPrivacyAccessedAPIType"]: set(entry["NSPrivacyAccessedAPITypeReasons"])
    for entry in privacy["NSPrivacyAccessedAPITypes"]
}
assert accessed_api_reasons == {
    "NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1"},
}

assert manifest["manifest_version"] == 3
assert manifest["background"] == {"service_worker": "src/service-worker.js"}
PY

if grep -Eq '^[[:space:]]*import[[:space:]]' "$extension/src/service-worker.js"; then
  echo "Safari service worker must remain a classic script without import statements." >&2
  exit 1
fi

printf 'Verified MyPIU iOS archive %s (%s).\n' "$expected_marketing_version" "$expected_build_number"
