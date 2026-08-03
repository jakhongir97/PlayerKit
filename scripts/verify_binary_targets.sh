#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/playerkit-binary-audit.XXXXXX")"
STRICT_COMPLIANCE="${PLAYERKIT_STRICT_BINARY_COMPLIANCE:-0}"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

for command in swift python3 curl ditto plutil codesign lipo; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "error: $command is required" >&2
    exit 1
  fi
done

package_json="$(swift package --package-path "$ROOT_DIR" dump-package)"
binary_targets="$(printf '%s' "$package_json" | python3 -c '
import json, sys
package = json.load(sys.stdin)
for target in package.get("targets", []):
    if target.get("type") != "binary" or not target.get("url"):
        continue
    print("\t".join((target["name"], target["url"], target.get("checksum", ""))))
')"

if [[ -z "$binary_targets" ]]; then
  echo "error: no resolved remote binary targets found" >&2
  exit 1
fi

target_count=0
compliance_issues=0

compliance_issue() {
  compliance_issues=$((compliance_issues + 1))
  echo "  compliance warning: $1" >&2
}

while IFS=$'\t' read -r name url expected_checksum; do
  [[ -n "$name" ]] || continue
  target_count=$((target_count + 1))
  artifact_path="$TMP_DIR/$name.zip"
  extract_dir="$TMP_DIR/$name"

  echo "- $name"
  echo "  downloading $url"
  curl --fail --location --silent --show-error --retry 3 \
    --proto '=https' --tlsv1.2 "$url" --output "$artifact_path"

  actual_checksum="$(swift package compute-checksum "$artifact_path")"
  if [[ "$actual_checksum" != "$expected_checksum" ]]; then
    echo "error: checksum mismatch for $name" >&2
    echo "expected: $expected_checksum" >&2
    echo "actual:   $actual_checksum" >&2
    exit 1
  fi
  echo "  checksum OK"

  mkdir -p "$extract_dir"
  ditto -x -k "$artifact_path" "$extract_dir"
  xcframework="$(find "$extract_dir" -path '*/__MACOSX/*' -prune -o -type d -name "$name.xcframework" -print | head -n 1)"
  if [[ -z "$xcframework" || ! -f "$xcframework/Info.plist" ]]; then
    echo "error: $name archive does not contain $name.xcframework/Info.plist" >&2
    exit 1
  fi

  device_frameworks="$(plutil -convert json -o - "$xcframework/Info.plist" | python3 -c '
import json, pathlib, sys
info = json.load(sys.stdin)
root = pathlib.Path(sys.argv[1])
libraries = info.get("AvailableLibraries", [])
if not libraries:
    raise SystemExit("XCFramework has no AvailableLibraries")
seen = set()
has_ios_device = False
has_ios_simulator = False
for library in libraries:
    identifier = library.get("LibraryIdentifier")
    path = library.get("LibraryPath")
    architectures = library.get("SupportedArchitectures") or []
    platform = library.get("SupportedPlatform")
    if not identifier or identifier in seen or not path or not architectures or not platform:
        raise SystemExit("XCFramework contains an incomplete or duplicate library record")
    seen.add(identifier)
    if not (root / identifier / path).is_dir():
        raise SystemExit(f"XCFramework references missing library: {identifier}/{path}")
    if platform == "ios" and library.get("SupportedPlatformVariant") is None:
        has_ios_device = True
        print(str(pathlib.Path(identifier) / path))
    if platform == "ios" and library.get("SupportedPlatformVariant") == "simulator":
        has_ios_simulator = True
if not has_ios_device or not has_ios_simulator:
    raise SystemExit("XCFramework must contain iOS device and simulator slices")
' "$xcframework")"

  if [[ -z "$device_frameworks" ]]; then
    echo "error: $name has no valid iOS device framework slice" >&2
    exit 1
  fi

  while IFS= read -r relative_framework; do
    framework="$xcframework/$relative_framework"
    if [[ ! -d "$framework" ]]; then
      echo "error: $name Info.plist references missing framework: $relative_framework" >&2
      exit 1
    fi

    executable="$(plutil -extract CFBundleExecutable raw -o - "$framework/Info.plist" 2>/dev/null || true)"
    identifier="$(plutil -extract CFBundleIdentifier raw -o - "$framework/Info.plist" 2>/dev/null || true)"
    version="$(plutil -extract CFBundleShortVersionString raw -o - "$framework/Info.plist" 2>/dev/null || true)"
    if [[ -z "$executable" || ! -f "$framework/$executable" ]]; then
      echo "error: $relative_framework has no valid CFBundleExecutable" >&2
      exit 1
    fi
    if ! lipo -archs "$framework/$executable" | grep -qw arm64; then
      echo "error: $relative_framework does not contain arm64" >&2
      exit 1
    fi
    echo "  bundle ${identifier:-unknown} version ${version:-unknown}"

    expected_signing_requirement=""
    case "$name" in
      VLCKit)
        expected_signing_requirement='=anchor apple generic and certificate leaf[subject.OU] = "75GAHG3SZQ"'
        ;;
      # Google has not published a signing identity for this archive. Keep a
      # future signed replacement blocked until that identity is documented.
      GoogleCast) expected_signing_requirement="" ;;
    esac

    if codesign --verify --strict "$framework" >/dev/null 2>&1; then
      if [[ -z "$expected_signing_requirement" ]]; then
        compliance_issue "$relative_framework has no pinned vendor signing identity"
      elif ! codesign --verify --strict \
          --test-requirement "$expected_signing_requirement" \
          "$framework" >/dev/null 2>&1; then
        compliance_issue "$relative_framework does not satisfy its pinned vendor requirement"
      fi
    else
      compliance_issue "$relative_framework has no valid code signature"
    fi

    privacy_manifest="$(find "$framework" -type f -name PrivacyInfo.xcprivacy -size +0c -print -quit)"
    if [[ -z "$privacy_manifest" ]]; then
      compliance_issue "$relative_framework contains no PrivacyInfo.xcprivacy"
    elif ! plutil -lint "$privacy_manifest" >/dev/null 2>&1; then
      compliance_issue "$relative_framework contains an invalid PrivacyInfo.xcprivacy"
    fi
  done <<<"$device_frameworks"

  license_file="$(find "$extract_dir" -type f -size +0c \
      \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname 'NOTICE*' -o -iname 'oss_licenses*' \) \
      -print -quit)"
  if [[ -z "$license_file" ]]; then
    compliance_issue "$name archive contains no license or notice file"
  fi
done <<<"$binary_targets"

echo "Verified checksum and XCFramework structure for $target_count binary target artifact(s)."

if [[ "$compliance_issues" -gt 0 ]]; then
  if [[ "$STRICT_COMPLIANCE" == "1" ]]; then
    echo "error: $compliance_issues binary compliance issue(s) block release" >&2
    exit 1
  fi
  echo "$compliance_issues compliance issue(s) remain; set PLAYERKIT_STRICT_BINARY_COMPLIANCE=1 for the release gate." >&2
fi
