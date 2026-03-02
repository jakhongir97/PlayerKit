#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/Package.swift"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if ! command -v swift >/dev/null 2>&1; then
  echo "error: swift is required to compute checksums" >&2
  exit 1
fi

TARGET_COUNT=0

while IFS=' ' read -r url expected_checksum; do
  [[ -z "$url" || -z "$expected_checksum" ]] && continue
  TARGET_COUNT=$((TARGET_COUNT + 1))
  artifact_path="$TMP_DIR/$(basename "$url")"

  echo "- Downloading: $url"
  curl --fail --location --silent --show-error "$url" --output "$artifact_path"

  actual_checksum="$(swift package compute-checksum "$artifact_path")"
  if [[ "$actual_checksum" != "$expected_checksum" ]]; then
    echo "error: checksum mismatch for $url" >&2
    echo "expected: $expected_checksum" >&2
    echo "actual:   $actual_checksum" >&2
    exit 1
  fi

  echo "  checksum OK"
done < <(
  awk '
    $1 == "url:" {
      url = $2
      gsub(/[\",]/, "", url)
    }
    $1 == "checksum:" {
      checksum = $2
      gsub(/[\",]/, "", checksum)
      if (url != "" && checksum != "") {
        print url " " checksum
      }
      url = ""
      checksum = ""
    }
  ' "$MANIFEST"
)

if [[ "$TARGET_COUNT" -eq 0 ]]; then
  echo "error: no binary targets with url/checksum were found in Package.swift" >&2
  exit 1
fi

echo "Verified $TARGET_COUNT binary target artifact(s)."
echo "All binary target artifacts are valid."
