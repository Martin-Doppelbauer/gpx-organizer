#!/bin/zsh
# Builds, signs (Developer ID), notarizes and zips GPX Organizer for distribution outside the App Store.
#
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="gpx-organizer" ./release.sh
#
# Needs a paid Apple Developer account; see RELEASING.md for the one-time setup.
set -euo pipefail
cd "$(dirname "$0")"

if [[ -z "${SIGN_ID:-}" || -z "${NOTARY_PROFILE:-}" ]]; then
  echo "Set SIGN_ID (your 'Developer ID Application: …' certificate) and NOTARY_PROFILE (notarytool keychain profile)."
  echo "See RELEASING.md. Available signing identities:"
  security find-identity -v -p codesigning || true
  exit 1
fi

VERSION="$(cat VERSION)"
APP="dist/GPX Organizer.app"
ZIP="dist/GPX-Organizer-$VERSION.zip"

./build_app.sh
# replace the ad-hoc signature by the Developer ID signature with the hardened runtime
codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# notarize (Apple scans the app), then attach the ticket so it also opens offline
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

spctl --assess --type execute --verbose "$APP"
echo "Done: $ZIP"
echo "Publish it on GitHub, e.g.: gh release create v$VERSION \"$ZIP\" --title \"GPX Organizer $VERSION\" --notes \"…\""
