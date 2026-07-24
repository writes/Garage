#!/bin/zsh
# Build, sign, export and (optionally) upload a TestFlight build of Garage.
#
# This is the second half of the QA pipeline. `scripts/release/asc.py` talks to App Store
# Connect (app record, signing assets, TestFlight groups); this script turns the repo into a
# signed .ipa and hands it to Apple.
#
# It deliberately does NOT edit project.yml (a PROTECTED surface). Signing identity, team and
# provisioning profile are passed as xcodebuild build-setting overrides, so a QA build needs no
# change to the protected build definition. When the signing setup is settled, folding
# DEVELOPMENT_TEAM / CODE_SIGN_STYLE into project.yml is an operator-gated follow-up.
#
# Usage:
#   scripts/release/testflight_build.sh --team-id ABCDE12345 --profile "Garage App Store" [--upload]
#
# Prerequisites (checked below, with actionable errors):
#   * a Distribution signing identity in the keychain   -> asc.py create-cert
#   * an App Store provisioning profile installed        -> asc.py create-profile
#   * an ASC API key at ~/.appstoreconnect/private_keys  -> only for --upload

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"
PATH="$ROOT_DIR/.tools/bin:$PATH"   # pinned xcodegen / swiftlint, same as the CI gate

TEAM_ID=""
PROFILE_NAME=""
DO_UPLOAD=0
ALLOW_PLACEHOLDER_URLS=0
BUILD_DIR="$ROOT_DIR/build/testflight"

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team-id) TEAM_ID="${2:-}"; shift 2 ;;
    --profile) PROFILE_NAME="${2:-}"; shift 2 ;;
    --upload) DO_UPLOAD=1; shift ;;
    --allow-placeholder-urls) ALLOW_PLACEHOLDER_URLS=1; shift ;;
    --build-dir) BUILD_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown flag: $1" >&2; usage ;;
  esac
done

fail() { echo "ERROR: $*" >&2; exit 1; }

[[ -n "$TEAM_ID" ]] || fail "--team-id is required (Apple Developer Team ID, e.g. ABCDE12345).
       Find it with: python3 scripts/release/asc.py signing"
[[ -n "$PROFILE_NAME" ]] || fail "--profile is required (the provisioning profile NAME).
       Create/list one with: python3 scripts/release/asc.py signing"

echo "==> Preflight"

# 1. An app icon is mandatory; the App Store rejects uploads without one, and an empty
#    AppIcon.appiconset compiles cleanly, so this fails silently at upload time otherwise.
ICON_DIR="Garage/Resources/Assets.xcassets/AppIcon.appiconset"
if ! grep -q '"filename"' "$ICON_DIR/Contents.json" 2>/dev/null; then
  fail "no app icon declared in $ICON_DIR/Contents.json — the upload will be rejected."
fi
ICON_FILE="$(python3 -c "
import json,sys
d=json.load(open('$ICON_DIR/Contents.json'))
names=[i.get('filename') for i in d.get('images',[]) if i.get('filename')]
print(names[0] if names else '')
")"
[[ -n "$ICON_FILE" && -f "$ICON_DIR/$ICON_FILE" ]] || fail "icon declared but file missing: $ICON_DIR/$ICON_FILE"
python3 - "$ICON_DIR/$ICON_FILE" <<'PY'
import struct, sys
path = sys.argv[1]
data = open(path, 'rb').read()
if data[:8] != b'\x89PNG\r\n\x1a\n':
    raise SystemExit(f"ERROR: {path} is not a PNG")
width, height = struct.unpack('>II', data[16:24])
colour_type = data[25]
if (width, height) != (1024, 1024):
    raise SystemExit(f"ERROR: app icon must be 1024x1024, got {width}x{height}")
if colour_type in (4, 6) or b'tRNS' in data:
    raise SystemExit("ERROR: app icon has an alpha channel — App Store upload will reject it")
print(f"    icon OK: {width}x{height}, no alpha")
PY

# 2. Placeholder legal URLs ship a broken Settings screen to testers.
if grep -rq "OPERATOR-REPLACE\|\.invalid" Garage/Core/Utilities/Constants.swift 2>/dev/null; then
  if [[ "$ALLOW_PLACEHOLDER_URLS" -eq 1 ]]; then
    echo "    WARNING: Constants.swift still has placeholder Privacy/Terms URLs."
    echo "             Testers will hit dead links in Settings. Proceeding (--allow-placeholder-urls)."
  else
    fail "Constants.swift still has placeholder Privacy/Terms URLs.
       Publish the legal pages first:  python3 scripts/release/legal_site.py render
       or pass --allow-placeholder-urls for an internal-only smoke build."
  fi
fi

# 2b. The bundled Firebase config must be registered to the bundle ID we are actually shipping.
#     There is one GoogleService-Info.plist and project.yml copies it into every configuration,
#     so a Release build silently ships whatever that file says. Verified 2026-07-24: the last
#     green Release archive carried BUNDLE_ID com.writes.harrysplayhouse.debug. The failure mode
#     is invisible at build time and total at runtime — Google Sign-In rejects the OAuth client
#     for a mismatched bundle ID, and App Check/App Attest tokens are refused for an
#     unregistered one, failing every Firestore/Storage/Functions call under enforcement.
RELEASE_BUNDLE_ID="$(python3 -c "
import re
text = open('project.yml').read()
match = re.search(r'Release:.*?PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)', text, re.S)
print(match.group(1) if match else '')
")"
python3 - "$RELEASE_BUNDLE_ID" <<'PY'
import plistlib, sys
expected = sys.argv[1]
path = "Garage/Resources/GoogleService-Info.plist"
try:
    config = plistlib.load(open(path, "rb"))
except OSError:
    raise SystemExit(f"ERROR: {path} is missing — the app cannot reach Firebase.")
actual = config.get("BUNDLE_ID")
project = config.get("PROJECT_ID")
if actual != expected:
    raise SystemExit(
        f"ERROR: Firebase config mismatch.\n"
        f"       {path}\n"
        f"         PROJECT_ID = {project}\n"
        f"         BUNDLE_ID  = {actual}\n"
        f"       but this build ships bundle ID {expected}.\n"
        f"       Testers would fail sign-in and every App Check'd backend call.\n"
        f"       Fix: add an iOS app for {expected} in the Firebase project QA should hit,\n"
        f"       register it under App Check, and replace {path} with that download."
    )
print(f"    Firebase config OK: {project} / {actual}")
PY

# 3. Real secrets, not the CI template — a build with template secrets is useless for QA.
if [[ ! -f Configuration/Secrets.swift ]]; then
  fail "Configuration/Secrets.swift is missing (PROTECTED, operator-provided)."
fi
if diff -q Configuration/Secrets.swift Configuration/Secrets.template.swift >/dev/null 2>&1; then
  fail "Configuration/Secrets.swift is still the placeholder template — RevenueCat/Firebase
       will not work in the QA build. Provide the real file before building."
fi

# 4. Signing assets must actually exist locally.
SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -nE 's/.*"((Apple|iPhone) Distribution[^"]*)".*/\1/p' | head -1)"
if [[ -z "$SIGN_IDENTITY" ]]; then
  fail "no valid distribution signing identity in the keychain.
       Create one:  python3 scripts/release/asc.py create-cert --type IOS_DISTRIBUTION \\
                      --generate-key ~/.appstoreconnect/signing/garage_distribution.key \\
                      --out ~/.appstoreconnect/signing/garage_distribution.cer
       If an identity exists but shows as INVALID, the Apple WWDR intermediate is missing or
       the wrong generation: certificates issued by 'WWDR ... OU=G3' need AppleWWDRCAG3.cer
       from https://www.apple.com/certificateauthority/ imported into the same keychain."
fi
# IOS_DISTRIBUTION certificates carry the legacy CN 'iPhone Distribution: ...'; the newer
# DISTRIBUTION type carries 'Apple Distribution: ...'. xcodebuild matches on a CN prefix, so
# hardcoding either one breaks half the time — derive it from the keychain instead.
echo "    signing identity: $SIGN_IDENTITY"
if ! ls ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision >/dev/null 2>&1; then
  fail "no provisioning profiles installed.
       Create one:  python3 scripts/release/asc.py create-profile --name '$PROFILE_NAME' ..."
fi

echo "==> Generating project"
command -v xcodegen >/dev/null 2>&1 || fail "xcodegen not found (expected .tools/bin or PATH)"
xcodegen generate

mkdir -p "$BUILD_DIR"
ARCHIVE_PATH="$BUILD_DIR/Garage.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

echo "==> Archiving (Release, signed)"
xcodebuild \
  -project Garage.xcodeproj \
  -scheme Garage \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  archive \
  -archivePath "$ARCHIVE_PATH"

BUNDLE_ID="$(python3 -c "
import re
text = open('project.yml').read()
match = re.search(r'Release:.*?PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)', text, re.S)
print(match.group(1) if match else '')
")"
[[ -n "$BUNDLE_ID" ]] || fail "could not parse the Release PRODUCT_BUNDLE_IDENTIFIER from project.yml"
echo "    bundle id: $BUNDLE_ID"

EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>manual</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>${BUNDLE_ID}</key><string>${PROFILE_NAME}</string>
  </dict>
</dict>
</plist>
PLIST

echo "==> Exporting .ipa"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

IPA_PATH="$(ls "$EXPORT_PATH"/*.ipa 2>/dev/null | head -1)"
[[ -n "$IPA_PATH" ]] || fail "export produced no .ipa in $EXPORT_PATH"
echo "    exported: $IPA_PATH"

if [[ "$DO_UPLOAD" -eq 1 ]]; then
  echo "==> Validating with App Store Connect"
  python3 scripts/release/asc.py upload --ipa "$IPA_PATH" --validate
  echo "==> Uploading to App Store Connect"
  python3 scripts/release/asc.py upload --ipa "$IPA_PATH"
  echo
  echo "Uploaded. Processing takes a few minutes; then:"
  echo "  python3 scripts/release/asc.py app --bundle-id $BUNDLE_ID    # watch processingState"
else
  echo
  echo "Not uploaded (pass --upload). To upload manually:"
  echo "  python3 scripts/release/asc.py upload --ipa '$IPA_PATH'"
fi
