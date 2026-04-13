#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

plutil -lint Garage/Resources/Info.plist
plutil -lint Garage/Resources/PrivacyInfo.xcprivacy
plutil -lint Garage.entitlements
test -f firebase.firestore.rules
test -f firebase.storage.rules
test -f Configuration/FirestoreIndexes.json

if rg -n "NSAllowsArbitraryLoads</key>[[:space:]]*<true/>" Garage/Resources/Info.plist >/dev/null 2>&1; then
  echo "ATS arbitrary loads must remain disabled"
  exit 1
fi

if rg -n "GoogleService-Info.plist|Secrets.swift" .gitignore >/dev/null 2>&1; then
  echo "Secret ignore rules present"
else
  echo "Missing ignore rules for secrets"
  exit 1
fi

echo "Security checks passed"

