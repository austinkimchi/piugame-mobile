#!/bin/sh
set -eu

output_path=${1:?"Usage: create-ios-export-options.sh OUTPUT_PATH TEAM_ID [export|upload]"}
team_id=${2:?"Apple Developer team ID is required"}
destination=${3:-export}

case "$team_id" in
  ??????????) ;;
  *)
    echo "Apple Developer team ID must contain exactly 10 uppercase letters or digits." >&2
    exit 1
    ;;
esac

case "$team_id" in
  *[!A-Z0-9]*)
    echo "Apple Developer team ID must contain exactly 10 uppercase letters or digits." >&2
    exit 1
    ;;
esac

case "$destination" in
  export | upload) ;;
  *)
    echo "iOS export destination must be export or upload." >&2
    exit 1
    ;;
esac

cat > "$output_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>$destination</string>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
  <key>method</key>
  <string>app-store-connect</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>$team_id</string>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
EOF

printf 'Created App Store Connect %s options for team %s.\n' \
  "$destination" "$team_id"
