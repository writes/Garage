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
    sed -nE 's/^[[:space:]]+(.+) \([0-9A-Fa-f-]+\) \((Shutdown|Booted)\)[[:space:]]*$/\1/p' |
    head -1
)"

./scripts/ci/policy-checks.sh

# Bootstrap Secrets.swift from the committed template if absent (CI / fresh clones) so the app
# compiles and pbxproj generation is deterministic (project.yml lists Configuration/Secrets.swift
# as a source). The template carries placeholder values only; real secrets are injected for
# signed/release builds (operator-gated), never here.
[ -f Configuration/Secrets.swift ] || cp Configuration/Secrets.template.swift Configuration/Secrets.swift

xcodegen generate

# Regenerate-equality gate (DECISION_LEDGER group ea4de5ac0c6fb564, 2026-07-21): Garage.xcodeproj/
# is a generated ALLOWED-candidate surface; project.yml is the PROTECTED source of truth. The
# committed project.pbxproj MUST equal `xcodegen generate` output — fail loudly on any drift so
# nothing non-derivable from the protected project.yml can be promoted.
if ! diff -q \
  <(git show HEAD:Garage.xcodeproj/project.pbxproj | python3 scripts/ci/pbxproj_canon.py) \
  <(python3 scripts/ci/pbxproj_canon.py < Garage.xcodeproj/project.pbxproj) >/dev/null 2>&1; then
  echo "ERROR: committed Garage.xcodeproj/project.pbxproj differs from 'xcodegen generate' output (beyond SwiftPM placeholders)."
  echo "       Run '.tools/bin/xcodegen generate' and commit the regenerated project (or reconcile project.yml)."
  exit 1
fi
# pbxproj_canon.py normalizes xcodegen's non-deterministic TEMP_ SwiftPM placeholder ids and sorts
# ONLY the XCSwiftPackageProductDependency section; every other line stays order-checked, so a moved
# or permuted build setting / entitlement (a poisoned Release config) is still caught by the diff.

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
