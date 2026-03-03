#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/Package.swift"
NOTICES="$ROOT_DIR/THIRD_PARTY_NOTICES.md"

if [[ ! -f "$NOTICES" ]]; then
  echo "error: THIRD_PARTY_NOTICES.md is missing" >&2
  exit 1
fi

if ! command -v awk >/dev/null 2>&1; then
  echo "error: awk is required" >&2
  exit 1
fi

BINARY_TARGETS=()
while IFS= read -r target; do
  [[ -n "$target" ]] || continue
  BINARY_TARGETS+=("$target")
done < <(
  awk '
    /\.binaryTarget\(/ { in_binary = 1; next }
    in_binary && /name:[[:space:]]*"/ {
      line = $0
      sub(/.*name:[[:space:]]*"/, "", line)
      sub(/".*/, "", line)
      print line
      in_binary = 0
    }
  ' "$MANIFEST"
)

if [[ "${#BINARY_TARGETS[@]}" -eq 0 ]]; then
  echo "error: no binary targets found in Package.swift" >&2
  exit 1
fi

missing=0
for target in "${BINARY_TARGETS[@]}"; do
  if ! rg -q "^## ${target}$" "$NOTICES"; then
    echo "error: THIRD_PARTY_NOTICES.md is missing a section for binary target '${target}'" >&2
    missing=1
  fi
done

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

echo "Verified third-party notice sections for ${#BINARY_TARGETS[@]} binary target(s)."
