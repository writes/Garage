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

if rg -n '\bTODO\b|\bFIXME\b' Garage Tests CloudFunctions/src docs Configuration .github project.yml scripts >/dev/null 2>&1; then
  echo "Task markers are not allowed without issue linkage"
  exit 1
fi

if rg -n 'print\(' Garage Tests >/dev/null 2>&1; then
  echo "print() calls are not allowed"
  exit 1
fi

# Force-unwrap enforcement moved to SwiftLint (operator-approved 2026-07-30): the regex that
# lived here only matched `x!.y`, so bare `x!`, `as!`, and `try!` all passed silently — false
# confidence, not a gate. SwiftLint's force_unwrapping (opt-in, enabled in .swiftlint.yml) plus
# its default-on force_cast/force_try cover every form, run under --strict in verify-ios.sh.

echo "Policy checks passed"
