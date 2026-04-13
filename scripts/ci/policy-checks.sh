#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

SWIFT_FILES=("${(@f)$(find Garage Tests -type f -name '*.swift' | sort)}")

for file in "${SWIFT_FILES[@]}"; do
  line_count="$(wc -l < "$file" | tr -d ' ')"
  if [[ "$line_count" -gt 300 ]]; then
    echo "File exceeds 300 lines: $file ($line_count)"
    exit 1
  fi
done

if rg -n '\bTODO\b|\bFIXME\b' Garage Tests CloudFunctions docs Configuration >/dev/null 2>&1; then
  echo "TODO/FIXME markers are not allowed without issue linkage"
  exit 1
fi

if rg -n 'print\(' Garage Tests >/dev/null 2>&1; then
  echo "print() calls are not allowed"
  exit 1
fi

if rg -n '\w+!\.' Garage Tests >/dev/null 2>&1; then
  echo "Potential force unwrap usage detected"
  exit 1
fi

echo "Policy checks passed"

