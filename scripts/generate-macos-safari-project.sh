#!/bin/sh
set -eu

repository_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
extension_root="$repository_root/browser-extension"
project_root="${1:-$extension_root/dist/safari-project}"
staged_extension="$extension_root/dist/safari-mv3"
packager_log="$(mktemp "${TMPDIR:-/tmp}/mypiu-safari-packager.XXXXXX")"

command -v npm >/dev/null 2>&1 || {
  echo "npm is required to stage the Safari extension resources." >&2
  exit 1
}
command -v xcrun >/dev/null 2>&1 || {
  echo "Xcode command-line tools are required to package the Safari extension." >&2
  exit 1
}

if [ "${SKIP_NPM_CI:-0}" != "1" ]; then
  npm --prefix "$extension_root" ci
fi
npm --prefix "$extension_root" run stage:safari

xcrun --find safari-web-extension-packager >/dev/null
xcrun safari-web-extension-packager "$staged_extension" \
  --project-location "$project_root" \
  --app-name "MyPIU Sync" \
  --bundle-identifier com.austinkimchi.mypiu.sync \
  --swift \
  --copy-resources \
  --no-open \
  --no-prompt \
  --force 2>&1 | tee "$packager_log"

if grep -q "not supported by your current version of Safari" "$packager_log"; then
  echo "Safari packager reported unsupported manifest keys." >&2
  exit 1
fi

project="$(find "$project_root" -name '*.xcodeproj' -print -quit)"
test -n "$project"
test -f "$project/project.pbxproj"
printf '%s\n' "$project"
