#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTICES="$ROOT_DIR/THIRD_PARTY_NOTICES.md"

for command in swift python3 awk grep; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "error: $command is required" >&2
    exit 1
  fi
done

if [[ ! -f "$NOTICES" ]]; then
  echo "error: THIRD_PARTY_NOTICES.md is missing" >&2
  exit 1
fi

package_json="$(swift package --package-path "$ROOT_DIR" dump-package)"
binary_targets="$({ printf '%s' "$package_json" | python3 -c '
import json, sys
package = json.load(sys.stdin)
for target in package.get("targets", []):
    if target.get("type") != "binary" or not target.get("url"):
        continue
    print("\t".join((target["name"], target["url"], target.get("checksum", ""))))
'; } || true)"

if [[ -z "$binary_targets" ]]; then
  echo "error: no resolved remote binary targets found" >&2
  exit 1
fi

missing=0
count=0
while IFS=$'\t' read -r target url checksum; do
  [[ -n "$target" ]] || continue
  count=$((count + 1))

  section="$(awk -v heading="## $target" '
    $0 == heading { found = 1 }
    found && $0 ~ /^## / && $0 != heading { exit }
    found { print }
  ' "$NOTICES")"

  if [[ -z "$section" ]]; then
    echo "error: missing notice section for binary target '$target'" >&2
    missing=1
    continue
  fi

  for expected in \
    "- Artifact URL: \`$url\`" \
    "- SwiftPM checksum: \`$checksum\`" \
    "- Resolved version/build:" \
    "- Upstream and license:" \
    "- Privacy manifest:" \
    "- Code signature and provenance:" \
    "- Release status:"; do
    if ! grep -Fqx -- "$expected" <<<"$section" && [[ "$expected" == *":" ]]; then
      if ! grep -Fq -- "$expected" <<<"$section"; then
        echo "error: '$target' notice is missing field: $expected" >&2
        missing=1
      fi
    elif ! grep -Fqx -- "$expected" <<<"$section"; then
      echo "error: '$target' notice does not match resolved package value: $expected" >&2
      missing=1
    fi
  done
done <<<"$binary_targets"

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

echo "Verified structured notices for $count resolved binary target(s)."
