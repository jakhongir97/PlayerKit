#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="PlayerKit"

destinations="$(xcodebuild -scheme "$SCHEME" -showdestinations 2>/dev/null || true)"

if [[ -z "$destinations" ]]; then
  echo "error: unable to resolve simulator destinations for scheme '$SCHEME'" >&2
  exit 1
fi

pick_destination() {
  local preferred_name="$1"
  local line os

  line="$(printf '%s\n' "$destinations" | awk -v target="$preferred_name" '
    $0 ~ /platform:iOS Simulator/ && $0 ~ ("name:" target) { print; exit }
  ')"

  [[ -n "$line" ]] || return 1

  os="$(printf '%s\n' "$line" | sed -n 's/.*OS:\([^,}]*\).*/\1/p' | tr -d ' ')"
  [[ -n "$os" ]] || return 1

  printf 'platform=iOS Simulator,name=%s,OS=%s\n' "$preferred_name" "$os"
  return 0
}

destination=""

for preferred in "iPhone 16" "iPhone 15" "iPhone 14"; do
  if destination="$(pick_destination "$preferred")"; then
    break
  fi
done

if [[ -z "$destination" ]]; then
  line="$(printf '%s\n' "$destinations" | awk '
    $0 ~ /platform:iOS Simulator/ && $0 ~ /name:iPhone/ { print; exit }
  ')"
  if [[ -z "$line" ]]; then
    echo "error: no iPhone simulator destination found for scheme '$SCHEME'" >&2
    exit 1
  fi

  name="$(printf '%s\n' "$line" | sed -n 's/.*name:\([^,}]*\).*/\1/p' | sed 's/^ *//; s/ *$//')"
  os="$(printf '%s\n' "$line" | sed -n 's/.*OS:\([^,}]*\).*/\1/p' | tr -d ' ')"

  if [[ -z "$name" || -z "$os" ]]; then
    echo "error: failed to parse fallback simulator destination" >&2
    exit 1
  fi

  destination="platform=iOS Simulator,name=$name,OS=$os"
fi

echo "Running tests on destination: $destination"
xcodebuild test -scheme "$SCHEME" -destination "$destination" -quiet
