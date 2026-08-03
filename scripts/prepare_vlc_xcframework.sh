#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FRAMEWORKS_DIR="$ROOT_DIR/Frameworks"
OUTPUT_XCFRAMEWORK="$FRAMEWORKS_DIR/VLCKit.xcframework"

IOS_VLCKIT_URL="https://github.com/jakhongir97/PlayerKit/releases/download/1.0.7/VLCKit.xcframework.zip"
IOS_VLCKIT_SHA256="2bb6de2ccd80a972cec24f19a2e1ecd3829eb87c6ea972cb39ca8c7c3968d997"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/playerkit-vlckit.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

for command in curl shasum ditto plutil; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "error: $command is required" >&2
    exit 1
  fi
done

info() {
  echo "[prepare_vlc_xcframework] $1"
}

download_verified() {
  local url="$1"
  local expected_sha256="$2"
  local destination="$3"
  local actual_sha256

  curl --fail --location --silent --show-error --retry 3 \
    --proto '=https' --tlsv1.2 "$url" --output "$destination"
  actual_sha256="$(shasum -a 256 "$destination" | awk '{ print $1 }')"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "error: SHA-256 mismatch for $url" >&2
    echo "expected: $expected_sha256" >&2
    echo "actual:   $actual_sha256" >&2
    exit 1
  fi
}

framework_slices() {
  local xcframework="$1"
  find "$xcframework" -mindepth 2 -maxdepth 2 -type d -name 'VLCKit.framework' -print | sort
}

validate_xcframework() {
  local xcframework="$1"
  local expected_platform="$2"

  if [[ ! -f "$xcframework/Info.plist" ]]; then
    echo "error: missing XCFramework Info.plist at $xcframework" >&2
    exit 1
  fi
  if ! plutil -p "$xcframework/Info.plist" | grep -q "SupportedPlatform\" => \"$expected_platform\""; then
    echo "error: $xcframework has no $expected_platform slice" >&2
    exit 1
  fi
  if [[ -z "$(framework_slices "$xcframework")" ]]; then
    echo "error: $xcframework contains no VLCKit.framework slices" >&2
    exit 1
  fi
}

info "Downloading pinned iOS VLCKit artifact."
ios_zip="$tmp_dir/VLCKit-ios.zip"
ios_extract="$tmp_dir/ios"
download_verified "$IOS_VLCKIT_URL" "$IOS_VLCKIT_SHA256" "$ios_zip"
mkdir -p "$ios_extract"
ditto -x -k "$ios_zip" "$ios_extract"
ios_xcframework="$(find "$ios_extract" -path '*/__MACOSX/*' -prune -o -type d -name 'VLCKit.xcframework' -print | head -n 1)"
validate_xcframework "$ios_xcframework" ios

mkdir -p "$FRAMEWORKS_DIR"
rm -rf "$OUTPUT_XCFRAMEWORK"
ditto "$ios_xcframework" "$OUTPUT_XCFRAMEWORK"
info "Prepared verified iOS framework at $OUTPUT_XCFRAMEWORK."
