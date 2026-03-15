#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FRAMEWORKS_DIR="$ROOT_DIR/Frameworks"
OUTPUT_XCFRAMEWORK="$FRAMEWORKS_DIR/VLCKit.xcframework"

IOS_VLCKIT_URL="https://github.com/jakhongir97/PlayerKit/releases/download/1.0.7/VLCKit.xcframework.zip"
MACOS_VLCKIT_URL="https://download.videolan.org/pub/cocoapods/prod/VLCKit-3.7.2-3e42ae47-79128878.tar.xz"
MACOS_VLCKIT_ARCHIVE_NAME="VLCKit-3.7.2-3e42ae47-79128878.tar.xz"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

info() {
  echo "[prepare_vlc_xcframework] $1"
}

has_platform_slice() {
  local xcframework_path="$1"
  local platform="$2"

  plutil -p "$xcframework_path/Info.plist" | grep -q "SupportedPlatform\" => \"$platform\""
}

find_existing_ios_xcframework() {
  local candidate=""

  if [[ -d "$ROOT_DIR/.build/artifacts/playerkit/VLCKit/VLCKit.xcframework" ]]; then
    candidate="$ROOT_DIR/.build/artifacts/playerkit/VLCKit/VLCKit.xcframework"
  else
    candidate="$(find "$ROOT_DIR/.." -path '*/SourcePackages/artifacts/playerkit/VLCKit/VLCKit.xcframework' -o -path '*/.build/artifacts/playerkit/VLCKit/VLCKit.xcframework' | head -n 1 || true)"
  fi

  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate"
  fi
}

download_ios_xcframework() {
  local zip_path="$tmp_dir/VLCKit-ios.zip"
  local extract_dir="$tmp_dir/ios"

  mkdir -p "$extract_dir"
  info "Downloading iOS VLCKit artifact."
  curl -L --fail --continue-at - -o "$zip_path" "$IOS_VLCKIT_URL"
  ditto -x -k "$zip_path" "$extract_dir"
  printf '%s\n' "$extract_dir/VLCKit.xcframework"
}

extract_macos_xcframework() {
  local archive_path="/tmp/$MACOS_VLCKIT_ARCHIVE_NAME"
  local extract_dir="$tmp_dir/macos"

  mkdir -p "$extract_dir"
  if [[ ! -f "$archive_path" ]]; then
    info "Downloading macOS VLCKit artifact."
    curl -L --fail --continue-at - -o "$archive_path" "$MACOS_VLCKIT_URL"
  else
    info "Using cached macOS VLCKit archive at $archive_path."
  fi
  xz -dc "$archive_path" | tar -xf - -C "$extract_dir"
  find "$extract_dir" -type d -name 'VLCKit.xcframework' | head -n 1
}

build_merged_xcframework() {
  local ios_xcframework="$1"
  local macos_xcframework="$2"
  local output_dir="$3"
  local framework_args=()

  while IFS= read -r framework_path; do
    framework_args+=(-framework "$framework_path")
  done < <(find "$ios_xcframework" "$macos_xcframework" -mindepth 2 -maxdepth 2 -type d -name 'VLCKit.framework')

  if [[ "${#framework_args[@]}" -eq 0 ]]; then
    echo "Failed to locate VLCKit.framework slices for xcframework creation." >&2
    exit 1
  fi

  xcodebuild -create-xcframework "${framework_args[@]}" -output "$output_dir"
}

if [[ -d "$OUTPUT_XCFRAMEWORK" ]] && has_platform_slice "$OUTPUT_XCFRAMEWORK" ios && has_platform_slice "$OUTPUT_XCFRAMEWORK" macos; then
  info "Using existing merged VLCKit.xcframework."
  exit 0
fi

mkdir -p "$FRAMEWORKS_DIR"

ios_xcframework_path="$(find_existing_ios_xcframework || true)"
if [[ -z "$ios_xcframework_path" ]]; then
  ios_xcframework_path="$(download_ios_xcframework)"
else
  info "Using cached iOS VLCKit artifact at $ios_xcframework_path."
fi

macos_xcframework_path="$(extract_macos_xcframework)"
if [[ -z "$macos_xcframework_path" ]]; then
  echo "Failed to locate the extracted macOS VLCKit.xcframework." >&2
  exit 1
fi

build_merged_xcframework "$ios_xcframework_path" "$macos_xcframework_path" "$tmp_dir/VLCKit.xcframework"

rm -rf "$OUTPUT_XCFRAMEWORK"
ditto "$tmp_dir/VLCKit.xcframework" "$OUTPUT_XCFRAMEWORK"
info "Prepared $OUTPUT_XCFRAMEWORK."
