#!/bin/sh
# Incremental compile only: never boot, install, or launch a Simulator app.
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
derived_data="$repository_root/.build/ios-dev"
cache_limit_kib=2097152 # 2 GiB; checked between builds, not a filesystem quota.
minimum_free_kib=5242880 # Leave at least 5 GiB before starting a build.

fail() { printf '%s\n' "$*" >&2; exit 1; }
usage() {
  printf 'Usage: %s [build|check] [existing-simulator-udid]\n' "$0"
  printf 'build: incremental unsigned Debug compile; check: inspect without building.\n'
  printf 'Cache: %s (2 GiB between-build guard). See docs/native-development.md.\n' "$derived_data"
}

action=${1:-build}
case "$action" in
  -h|--help|help) usage; exit 0 ;;
  build|check) ;;
  *) usage >&2; exit 2 ;;
esac
[ "$#" -le 2 ] || { usage >&2; exit 2; }

project="$repository_root/ios/MyPIU.xcodeproj"
[ -f "$project/project.pbxproj" ] || fail "Missing Xcode project: $project"
[ -f "$project/xcshareddata/xcschemes/MyPIU.xcscheme" ] || fail 'Missing shared MyPIU scheme.'
for command in node xcrun xcodebuild; do
  command -v "$command" >/dev/null 2>&1 || fail "Required command is unavailable: $command"
done
[ ! -L "$repository_root/.build" ] && [ ! -L "$derived_data" ] || fail 'The development cache must not be a symlink.'

simulator_id=$(xcrun simctl list devices available -j | node -e '
  let input = "";
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", chunk => input += chunk);
  process.stdin.on("end", () => {
    try {
      const devices = Object.entries(JSON.parse(input).devices)
        .filter(([runtime]) => runtime.includes(".iOS-"))
        .flatMap(([, devices]) => devices)
        .filter(device => device.isAvailable === true);
      const requested = process.argv[1];
      const phones = devices.filter(device => device.name.startsWith("iPhone"));
      const device = requested ? devices.find(device => device.udid === requested)
        : phones.find(device => device.state === "Booted") ?? phones[0] ?? devices[0];
      if (!device) throw new Error(requested
        ? "Requested Simulator is not an available, installed iOS device."
        : "No installed iOS Simulator device is available. Select an existing runtime in Xcode.");
      process.stdout.write(device.udid);
    } catch (error) {
      console.error(error.message);
      process.exitCode = 1;
    }
  });
' "${2:-}")

cache_size_kib=0
if [ -d "$derived_data" ]; then
  cache_size_kib=$(du -sk "$derived_data" | awk '{print $1}')
fi
[ "$cache_size_kib" -lt "$cache_limit_kib" ] || fail "Cache reached 2 GiB. Stop builds, then clean only $derived_data as documented."
free_kib=$(df -Pk "$repository_root" | awk 'END {print $4}')
[ "$free_kib" -ge "$minimum_free_kib" ] || fail 'Less than 5 GiB free. Free space before starting another build.'

printf 'Project: %s\nScheme: MyPIU (Debug)\nSimulator destination: %s\nCache: %s (%s KiB)\n' \
  "$project" "$simulator_id" "$derived_data" "$cache_size_kib"
[ "$action" = build ] || exit 0

# Reuse this path after pulls; a clean build discards the incremental benefit.
# Signing is disabled only for this compile command, not in the project.
xcodebuild \
  -project "$project" \
  -scheme MyPIU \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath "$derived_data" \
  -jobs 2 \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=YES \
  build

cache_size_kib=$(du -sk "$derived_data" | awk '{print $1}')
printf 'Development cache: %s KiB.\n' "$cache_size_kib"
if [ "$cache_size_kib" -ge "$cache_limit_kib" ]; then
  printf 'Build finished; cache reached 2 GiB. Clean it before the next build (docs/native-development.md).\n' >&2
fi
