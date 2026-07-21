#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

PATH="$ROOT_DIR/.tools/bin:$PATH"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required"
  exit 1
fi

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "swiftlint is required"
  exit 1
fi

SIMULATOR_NAME="$(
  xcrun simctl list devices available |
    awk -F ' \\(' '/^[[:space:]]+[A-Za-z0-9].*\\((Shutdown|Booted)\\)$/ {
      gsub(/^[[:space:]]+/, "", $1)
      print $1
      exit
    }'
)"

./scripts/ci/policy-checks.sh
xcodegen generate

# Regenerate-equality gate (DECISION_LEDGER group ea4de5ac0c6fb564, 2026-07-21): Garage.xcodeproj/
# is a generated ALLOWED-candidate surface; project.yml is the PROTECTED source of truth. The
# committed project.pbxproj MUST equal `xcodegen generate` output — fail loudly on any drift so
# nothing non-derivable from the protected project.yml can be promoted.
if ! git diff --quiet -- Garage.xcodeproj/project.pbxproj; then
  echo "ERROR: committed Garage.xcodeproj/project.pbxproj differs from 'xcodegen generate' output."
  echo "       Run '.tools/bin/xcodegen generate' and commit the regenerated project (or reconcile project.yml)."
  git --no-pager diff --stat -- Garage.xcodeproj/project.pbxproj
  exit 1
fi

swiftlint lint --strict
xcodebuild -project Garage.xcodeproj -scheme Garage -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

if [[ -n "${SIMULATOR_NAME}" ]]; then
  xcodebuild -project Garage.xcodeproj -scheme Garage -destination "platform=iOS Simulator,name=${SIMULATOR_NAME}" test
else
  echo "No available iOS simulator found; skipping simulator tests"
fi

xcodebuild \
  -project Garage.xcodeproj \
  -scheme Garage \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  archive \
  -archivePath build/Garage.xcarchive
