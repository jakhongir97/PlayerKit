#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="PlayerKit"
DERIVED_DATA_PATH="${PLAYERKIT_DERIVED_DATA_PATH:-$ROOT_DIR/.build/xcode-tests}"
cd "$ROOT_DIR"

destinations="$(xcodebuild -scheme "$SCHEME" -showdestinations 2>/dev/null || true)"

if [[ -z "$destinations" ]]; then
  echo "error: unable to resolve simulator destinations for scheme '$SCHEME'" >&2
  exit 1
fi

pick_destination() {
  local preferred_name="$1"
  local line id

  line="$(printf '%s\n' "$destinations" | awk -v target="$preferred_name" '
    $0 ~ /platform:iOS Simulator/ {
      name = $0
      sub(/.*name:/, "", name)
      sub(/[,}].*/, "", name)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
      if (name == target) { print; exit }
    }
  ')"

  [[ -n "$line" ]] || return 1

  id="$(printf '%s\n' "$line" | sed -n 's/.*id:\([^,}]*\).*/\1/p' | tr -d ' ')"
  [[ -n "$id" ]] || return 1

  printf 'platform=iOS Simulator,id=%s\n' "$id"
  return 0
}

destination="${PLAYERKIT_TEST_DESTINATION:-}"

if [[ -z "$destination" ]]; then
  for preferred in "iPhone 17" "iPhone 16" "iPhone 15" "iPhone 14"; do
    if destination="$(pick_destination "$preferred")"; then
      break
    fi
  done
fi

if [[ -z "$destination" ]]; then
  line="$(printf '%s\n' "$destinations" | awk '
    $0 ~ /platform:iOS Simulator/ && $0 ~ /name:iPhone/ { print; exit }
  ')"
  if [[ -z "$line" ]]; then
    line="$(printf '%s\n' "$destinations" | awk '
      $0 ~ /platform:macOS/ && $0 !~ /variant:/ { print; exit }
    ')"
    if [[ -z "$line" ]]; then
      echo "error: no iPhone simulator or macOS destination found for scheme '$SCHEME'" >&2
      exit 1
    fi
    destination="platform=macOS"
  else
    id="$(printf '%s\n' "$line" | sed -n 's/.*id:\([^,}]*\).*/\1/p' | tr -d ' ')"

    if [[ -z "$id" ]]; then
      echo "error: failed to parse fallback simulator destination" >&2
      exit 1
    fi

    destination="platform=iOS Simulator,id=$id"
  fi
fi

echo "Running tests on destination: $destination"
case "$destination" in
  platform=macOS*)
    # ponytail: the package has unit tests only; SwiftPM avoids Xcode's flaky
    # headless macOS test host. Use xcodebuild again if a UI-test bundle is added.
    swift test
    exit 0
    ;;
esac

xcodebuild test \
  -scheme "$SCHEME" \
  -destination "$destination" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -quiet
