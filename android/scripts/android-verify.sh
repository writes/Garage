#!/usr/bin/env bash
# Android verification gate: build, unit tests, lint. Run from anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."

# Prefer JDK 21 from Homebrew when JAVA_HOME is not already set (macOS dev machines).
if [[ -z "${JAVA_HOME:-}" && -d /opt/homebrew/opt/openjdk@21 ]]; then
  export JAVA_HOME=/opt/homebrew/opt/openjdk@21
fi

cleanup() { ./gradlew --stop >/dev/null 2>&1 || true; }
trap cleanup EXIT

./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
