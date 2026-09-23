#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/mypiu-release-test.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

private_key=$(openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null)
export APPLE_TEAM_ID=ABCDE12345
export APP_STORE_CONNECT_KEY_ID=12345ABCDE
export APP_STORE_CONNECT_ISSUER_ID=01234567-89ab-cdef-0123-456789abcdef
export APP_STORE_CONNECT_PRIVATE_KEY="$private_key"

key_path="$test_directory/private_keys/AuthKey_$APP_STORE_CONNECT_KEY_ID.p8"
"$repository_root/scripts/prepare-app-store-connect-key.sh" "$key_path"
test -s "$key_path"
openssl ec -in "$key_path" -check -noout >/dev/null 2>&1

python3 - "$key_path" <<'PY'
import pathlib
import stat
import sys

mode = stat.S_IMODE(pathlib.Path(sys.argv[1]).stat().st_mode)
assert mode == 0o600, oct(mode)
PY

export_options="$test_directory/ExportOptions.plist"
"$repository_root/scripts/create-ios-export-options.sh" \
  "$export_options" "$APPLE_TEAM_ID"
upload_options="$test_directory/UploadOptions.plist"
"$repository_root/scripts/create-ios-export-options.sh" \
  "$upload_options" "$APPLE_TEAM_ID" upload

python3 - "$export_options" "$upload_options" <<'PY'
import pathlib
import plistlib
import sys

with pathlib.Path(sys.argv[1]).open("rb") as plist_file:
    options = plistlib.load(plist_file)

assert options == {
    "destination": "export",
    "manageAppVersionAndBuildNumber": False,
    "method": "app-store-connect",
    "signingStyle": "automatic",
    "stripSwiftSymbols": True,
    "teamID": "ABCDE12345",
    "uploadSymbols": True,
}

with pathlib.Path(sys.argv[2]).open("rb") as plist_file:
    upload_options = plistlib.load(plist_file)
assert upload_options == {**options, "destination": "upload"}
PY

if APP_STORE_CONNECT_PRIVATE_KEY=not-a-key \
  "$repository_root/scripts/prepare-app-store-connect-key.sh" \
  "$test_directory/invalid.p8" >/dev/null 2>&1; then
  echo "Malformed App Store Connect private key was accepted." >&2
  exit 1
fi

if "$repository_root/scripts/create-ios-export-options.sh" \
  "$test_directory/invalid.plist" lowercase1 >/dev/null 2>&1; then
  echo "Malformed Apple Developer team ID was accepted." >&2
  exit 1
fi

if "$repository_root/scripts/create-ios-export-options.sh" \
  "$test_directory/short.plist" SHORT >/dev/null 2>&1; then
  echo "Short Apple Developer team ID was accepted." >&2
  exit 1
fi

if APPLE_TEAM_ID=SHORT \
  "$repository_root/scripts/prepare-app-store-connect-key.sh" \
  "$test_directory/short-team.p8" >/dev/null 2>&1; then
  echo "Short Apple Developer team ID was accepted by credential preflight." >&2
  exit 1
fi

if APP_STORE_CONNECT_KEY_ID=SHORT \
  "$repository_root/scripts/prepare-app-store-connect-key.sh" \
  "$test_directory/short-key.p8" >/dev/null 2>&1; then
  echo "Short App Store Connect key ID was accepted." >&2
  exit 1
fi

if "$repository_root/scripts/create-ios-export-options.sh" \
  "$test_directory/invalid-destination.plist" "$APPLE_TEAM_ID" invalid \
  >/dev/null 2>&1; then
  echo "Invalid iOS export destination was accepted." >&2
  exit 1
fi

for script in \
  "$repository_root/scripts/prepare-app-store-connect-key.sh" \
  "$repository_root/scripts/create-ios-export-options.sh" \
  "$repository_root/scripts/verify-ios-ipa.sh"; do
  sh -n "$script"
done

printf 'iOS release helper tests passed.\n'
