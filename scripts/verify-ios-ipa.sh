#!/bin/sh
set -eu

ipa_path=${1:?"Usage: verify-ios-ipa.sh IPA_PATH MARKETING_VERSION BUILD_NUMBER TEAM_ID"}
expected_marketing_version=${2:?"Expected marketing version is required"}
expected_build_number=${3:?"Expected build number is required"}
expected_team_id=${4:?"Expected Apple Developer team ID is required"}

for command_name in codesign ditto security; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name is required to verify an iOS distribution." >&2
    exit 1
  fi
done

test -s "$ipa_path"
verification_directory=$(mktemp -d "${TMPDIR:-/tmp}/mypiu-ipa.XXXXXX")
trap 'rm -rf "$verification_directory"' EXIT HUP INT TERM

ditto -x -k "$ipa_path" "$verification_directory"
app="$verification_directory/Payload/MyPIU.app"
extension="$app/PlugIns/MyPIU Sync Extension.appex"
test -d "$app"
test -d "$extension"
test -f "$app/embedded.mobileprovision"
test -f "$extension/embedded.mobileprovision"

codesign --verify --strict --verbose=2 "$extension"
codesign --verify --strict --verbose=2 "$app"

security cms -D -i "$app/embedded.mobileprovision" \
  > "$verification_directory/app-profile.plist"
security cms -D -i "$extension/embedded.mobileprovision" \
  > "$verification_directory/extension-profile.plist"
codesign -d --entitlements :- "$app" \
  > "$verification_directory/app-entitlements.plist" 2>/dev/null
codesign -d --entitlements :- "$extension" \
  > "$verification_directory/extension-entitlements.plist" 2>/dev/null
codesign -d --extract-certificates "$verification_directory/app-signing-" \
  "$app" >/dev/null 2>&1
codesign -d --extract-certificates "$verification_directory/extension-signing-" \
  "$extension" >/dev/null 2>&1
test -s "$verification_directory/app-signing-0"
test -s "$verification_directory/extension-signing-0"

python3 - \
  "$app/Info.plist" \
  "$extension/Info.plist" \
  "$verification_directory/app-profile.plist" \
  "$verification_directory/extension-profile.plist" \
  "$verification_directory/app-entitlements.plist" \
  "$verification_directory/extension-entitlements.plist" \
  "$verification_directory/app-signing-0" \
  "$verification_directory/extension-signing-0" \
  "$expected_marketing_version" \
  "$expected_build_number" \
  "$expected_team_id" <<'PY'
import datetime
import pathlib
import plistlib
import sys


def read_plist(path: str) -> dict:
    with pathlib.Path(path).open("rb") as plist_file:
        return plistlib.load(plist_file)


app_info = read_plist(sys.argv[1])
extension_info = read_plist(sys.argv[2])
app_profile = read_plist(sys.argv[3])
extension_profile = read_plist(sys.argv[4])
app_entitlements = read_plist(sys.argv[5])
extension_entitlements = read_plist(sys.argv[6])
app_signing_certificate = pathlib.Path(sys.argv[7]).read_bytes()
extension_signing_certificate = pathlib.Path(sys.argv[8]).read_bytes()
expected_version = sys.argv[9]
expected_build = sys.argv[10]
expected_team = sys.argv[11]

bundles = (
    (
        app_info,
        app_profile,
        app_entitlements,
        app_signing_certificate,
        "com.austinkimchi.mypiu",
    ),
    (
        extension_info,
        extension_profile,
        extension_entitlements,
        extension_signing_certificate,
        "com.austinkimchi.mypiu.safari",
    ),
)
now = datetime.datetime.now(datetime.timezone.utc)

for info, profile, signed_entitlements, signing_certificate, expected_bundle_id in bundles:
    assert info["CFBundleIdentifier"] == expected_bundle_id
    assert info["CFBundleShortVersionString"] == expected_version
    assert info["CFBundleVersion"] == expected_build
    assert expected_team in profile["TeamIdentifier"]
    assert profile["ExpirationDate"].replace(tzinfo=datetime.timezone.utc) > now
    assert "ProvisionedDevices" not in profile
    assert profile.get("ProvisionsAllDevices") is not True
    assert signing_certificate in profile["DeveloperCertificates"]

    entitlements = profile["Entitlements"]
    assert entitlements["application-identifier"] == f"{expected_team}.{expected_bundle_id}"
    assert entitlements["com.apple.developer.team-identifier"] == expected_team
    assert entitlements.get("get-task-allow") is not True
    assert signed_entitlements["application-identifier"] == entitlements["application-identifier"]
    assert signed_entitlements["com.apple.developer.team-identifier"] == expected_team
    assert signed_entitlements.get("get-task-allow") is not True
PY

printf 'Verified signed MyPIU IPA %s (%s) for team %s.\n' \
  "$expected_marketing_version" "$expected_build_number" "$expected_team_id"
