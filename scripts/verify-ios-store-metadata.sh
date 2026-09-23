#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
metadata_root=${1:-"$repo_root/ios/AppStore"}

python3 - "$metadata_root" <<'PY'
import pathlib
import sys
import urllib.parse


root = pathlib.Path(sys.argv[1])
store = root / "metadata" / "en-US"
testflight = root / "testflight" / "en-US"


def read(directory: pathlib.Path, filename: str) -> str:
    path = directory / filename
    if not path.is_file():
        raise AssertionError(f"Missing metadata file: {path}")
    value = path.read_text(encoding="utf-8").strip()
    if not value:
        raise AssertionError(f"Metadata file is empty: {path}")
    lowered = value.lower()
    if "todo" in lowered or "placeholder" in lowered or "example.com" in lowered:
        raise AssertionError(f"Metadata contains a placeholder: {path}")
    return value


def require_length(label: str, value: str, maximum: int, minimum: int = 1) -> None:
    length = len(value)
    if not minimum <= length <= maximum:
        raise AssertionError(
            f"{label} must contain {minimum}-{maximum} characters; found {length}"
        )


name = read(store, "name.txt")
subtitle = read(store, "subtitle.txt")
promotional_text = read(store, "promotional_text.txt")
description = read(store, "description.txt")
keywords = read(store, "keywords.txt")

require_length("Name", name, 30, 2)
require_length("Subtitle", subtitle, 30)
require_length("Promotional text", promotional_text, 170)
require_length("Description", description, 4000)

keyword_bytes = len(keywords.encode("utf-8"))
if keyword_bytes > 100:
    raise AssertionError(f"Keywords must not exceed 100 UTF-8 bytes; found {keyword_bytes}")
keyword_values = [keyword.strip() for keyword in keywords.split(",")]
if any(len(keyword) <= 2 for keyword in keyword_values):
    raise AssertionError("Every keyword must contain more than two characters")
if len(set(keyword.casefold() for keyword in keyword_values)) != len(keyword_values):
    raise AssertionError("Keywords must not contain duplicates")

for filename in ("support_url.txt", "marketing_url.txt", "privacy_url.txt"):
    value = read(store, filename)
    parsed = urllib.parse.urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc or parsed.query or parsed.fragment:
        raise AssertionError(f"{filename} must contain one clean HTTPS URL")

beta_description = read(testflight, "beta_description.txt")
what_to_test = read(testflight, "what_to_test.txt")
require_length("Beta app description", beta_description, 4000)
require_length("What to Test", what_to_test, 4000)

print(
    "Verified iOS App Store metadata: "
    f"description={len(description)} characters, keywords={keyword_bytes} bytes."
)
PY
