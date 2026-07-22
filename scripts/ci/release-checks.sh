#!/usr/bin/env bash
set -euo pipefail

# Release-only gate. Run before archiving for TestFlight / App Store submission — NOT on every
# dev/CI build (these fail while operator-only prerequisites are still placeholders). See
# docs/DEPLOY_RUNBOOK.md.
cd "$(dirname "$0")/../.."

fail=0

# 1. Placeholder Privacy/Terms URLs must never ship: live `.invalid` Links in the
#    auto-renewable-subscription sheet are a guaranteed App Store 3.1.2 rejection.
if rg -n 'OPERATOR-REPLACE|\.invalid\b' Garage Configuration 2>/dev/null; then
  echo "❌ Placeholder URLs (.invalid / OPERATOR-REPLACE) must be replaced with real, resolvable HTTPS URLs."
  fail=1
fi

# 2. Export-compliance key must be declared or every upload lands in 'Missing Compliance'.
if ! rg -q 'ITSAppUsesNonExemptEncryption' project.yml Garage/Resources/Info.plist 2>/dev/null; then
  echo "❌ ITSAppUsesNonExemptEncryption is not set (add it to project.yml Info.plist properties)."
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "Release checks FAILED — see docs/DEPLOY_RUNBOOK.md."
  exit 1
fi

echo "Release checks passed"
