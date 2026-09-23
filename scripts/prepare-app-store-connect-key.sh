#!/bin/sh
set -eu

key_path=${1:?"Usage: prepare-app-store-connect-key.sh KEY_PATH"}

require_value() {
  variable_name=$1
  eval "variable_value=\${$variable_name-}"
  if test -z "$variable_value"; then
    echo "Required iOS release credential $variable_name is missing." >&2
    exit 1
  fi
}

require_value APPLE_TEAM_ID
require_value APP_STORE_CONNECT_KEY_ID
require_value APP_STORE_CONNECT_ISSUER_ID
require_value APP_STORE_CONNECT_PRIVATE_KEY

case "$APPLE_TEAM_ID" in
  *[!A-Z0-9]* | ????????? | ???????????*)
    echo "APPLE_TEAM_ID must contain exactly 10 uppercase letters or digits." >&2
    exit 1
    ;;
esac

case "$APP_STORE_CONNECT_KEY_ID" in
  *[!A-Z0-9]* | ????????? | ???????????*)
    echo "APP_STORE_CONNECT_KEY_ID must contain exactly 10 uppercase letters or digits." >&2
    exit 1
    ;;
esac

if ! printf '%s\n' "$APP_STORE_CONNECT_ISSUER_ID" \
  | grep -Eq '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'; then
  echo "APP_STORE_CONNECT_ISSUER_ID must be a UUID." >&2
  exit 1
fi

key_directory=$(dirname "$key_path")
mkdir -p "$key_directory"
temporary_key="$key_path.tmp"
trap 'rm -f "$temporary_key"' EXIT HUP INT TERM

umask 077
printf '%s\n' "$APP_STORE_CONNECT_PRIVATE_KEY" > "$temporary_key"
if ! openssl ec -in "$temporary_key" -check -noout >/dev/null 2>&1; then
  echo "APP_STORE_CONNECT_PRIVATE_KEY is not a valid EC private key." >&2
  exit 1
fi

mv "$temporary_key" "$key_path"
chmod 600 "$key_path"
trap - EXIT HUP INT TERM

printf 'Prepared App Store Connect key %s for team %s.\n' \
  "$APP_STORE_CONNECT_KEY_ID" "$APPLE_TEAM_ID"
