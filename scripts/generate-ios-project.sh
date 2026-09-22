#!/bin/sh
set -eu

repository_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
extension_root="$repository_root/browser-extension"
extension_resources="$repository_root/ios/MyPIUSafariExtension/Resources"

command -v npm >/dev/null 2>&1 || {
  echo "npm is required to stage the Safari extension resources." >&2
  exit 1
}
command -v xcodegen >/dev/null 2>&1 || {
  echo "XcodeGen is required to generate the MyPIU project." >&2
  exit 1
}

npm --prefix "$extension_root" ci
npm --prefix "$extension_root" run stage:safari -- --output "$extension_resources"

cd "$repository_root/ios"
xcodegen generate
