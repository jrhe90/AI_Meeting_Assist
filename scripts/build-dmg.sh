#!/usr/bin/env bash
#
# Build a signed, notarised, stapled AI Note Taker .dmg ready for GitHub
# Releases. See README → "Publishing a release" for prerequisites.
#
# Required environment:
#   DEV_TEAM_ID         10-character Apple Developer Team ID.
#   APP_BUNDLE_ID       e.g. com.ainotetaker.app
#   APP_VERSION         e.g. 1.0.0 (written into Info.plist as CFBundleShortVersionString)
#
# Notarization credentials — either:
#   NOTARY_PROFILE      name of a `notarytool store-credentials` keychain entry, OR
#   APPLE_ID + TEAM_ID + APP_PASSWORD  (app-specific password from appleid.apple.com)
#
# Optional:
#   OUTPUT_DIR          where to drop the .dmg (default: ./build/dist)
#   CREATE_DMG_BIN      override the create-dmg binary (default: PATH lookup)

set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────
# Setup
# ────────────────────────────────────────────────────────────────────────────

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/AINoteTaker.xcodeproj"
SCHEME="AINoteTaker"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/build/dist}"
ARCHIVE_PATH="$OUTPUT_DIR/AINoteTaker.xcarchive"
EXPORT_PATH="$OUTPUT_DIR/export"
DMG_PATH="$OUTPUT_DIR/AINoteTaker-${APP_VERSION:?APP_VERSION required}.dmg"

require_env() {
  for var in "$@"; do
    [[ -n "${!var:-}" ]] || { echo "Missing env: $var"; exit 1; }
  done
}

require_env DEV_TEAM_ID APP_BUNDLE_ID APP_VERSION

# Notarization can use either a stored profile or inline credentials.
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${APPLE_ID:-}" && -n "${APP_PASSWORD:-}" ]]; then
  NOTARY_AUTH=(--apple-id "$APPLE_ID" --team-id "$DEV_TEAM_ID" --password "$APP_PASSWORD")
else
  echo "Either NOTARY_PROFILE or APPLE_ID+APP_PASSWORD must be set."
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$DMG_PATH"

if ! command -v xcodegen >/dev/null; then
  echo "xcodegen is required (brew install xcodegen)" ; exit 1
fi
xcodegen generate --spec "$ROOT/project.yml"

CREATE_DMG="${CREATE_DMG_BIN:-$(command -v create-dmg || true)}"
if [[ -z "$CREATE_DMG" ]]; then
  echo "create-dmg is required (brew install create-dmg)" ; exit 1
fi

# ────────────────────────────────────────────────────────────────────────────
# Archive
# ────────────────────────────────────────────────────────────────────────────

echo "▶ Archiving…"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=macOS' \
  DEVELOPMENT_TEAM="$DEV_TEAM_ID" \
  MARKETING_VERSION="$APP_VERSION" \
  CODE_SIGN_STYLE=Automatic \
  | tail -20

# ────────────────────────────────────────────────────────────────────────────
# Export (Developer ID, ad-hoc distribution)
# ────────────────────────────────────────────────────────────────────────────

EXPORT_PLIST="$OUTPUT_DIR/ExportOptions.plist"
cat >"$EXPORT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$DEV_TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

echo "▶ Exporting…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -exportPath "$EXPORT_PATH" \
  | tail -20

APP_PATH="$EXPORT_PATH/AINoteTaker.app"
[[ -d "$APP_PATH" ]] || { echo "Expected $APP_PATH not found"; exit 1; }

# ────────────────────────────────────────────────────────────────────────────
# Notarize the .app first (faster feedback than DMG round-trip)
# ────────────────────────────────────────────────────────────────────────────

echo "▶ Notarizing .app…"
NOTARY_ZIP="$OUTPUT_DIR/AINoteTaker.zip"
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" "${NOTARY_AUTH[@]}" --wait
xcrun stapler staple "$APP_PATH"
rm "$NOTARY_ZIP"

# ────────────────────────────────────────────────────────────────────────────
# Wrap into a .dmg
# ────────────────────────────────────────────────────────────────────────────

echo "▶ Building DMG…"
"$CREATE_DMG" \
  --volname "AI Note Taker" \
  --window-size 540 360 \
  --icon-size 96 \
  --icon "AINoteTaker.app" 140 180 \
  --app-drop-link 400 180 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$APP_PATH"

# ────────────────────────────────────────────────────────────────────────────
# Sign + notarize the DMG so Gatekeeper trusts it even offline.
# ────────────────────────────────────────────────────────────────────────────

echo "▶ Signing DMG…"
codesign --sign "Developer ID Application: $DEV_TEAM_ID" \
         --timestamp "$DMG_PATH"

echo "▶ Notarizing DMG…"
xcrun notarytool submit "$DMG_PATH" "${NOTARY_AUTH[@]}" --wait
xcrun stapler staple "$DMG_PATH"

echo "▶ Done: $DMG_PATH"
