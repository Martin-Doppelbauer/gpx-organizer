#!/bin/zsh
# Builds GPX Organizer.app (Apple Silicon, ad-hoc signed) into ./dist
set -e
cd "$(dirname "$0")"
VERSION="$(cat VERSION 2>/dev/null || echo 0.1.0)"
swift build -c release --arch arm64
APP="dist/GPX Organizer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --show-bin-path)/GPXOrganizer" "$APP/Contents/MacOS/GPXOrganizer"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"
# texts per language: Resources/Localization/<language>.lproj/ (Localizable.strings, and README.md / UserGuide.md in that language)
LANGS=("en")
for d in Resources/Localization/*.lproj(N); do
  l="${d:t:r}"
  cp -R "$d" "$APP/Contents/Resources/"
  [[ "$l" != "en" ]] && LANGS+=("$l")
done
# English: the help texts of the project are the English ones
mkdir -p "$APP/Contents/Resources/en.lproj"
cp README.md Resources/UserGuide.md "$APP/Contents/Resources/en.lproj/"
LOCALIZATIONS=""
for l in $LANGS; do LOCALIZATIONS="$LOCALIZATIONS<string>$l</string>"; done
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
 <key>CFBundleDevelopmentRegion</key><string>en</string>
 <key>CFBundleLocalizations</key><array>$LOCALIZATIONS</array>
 <key>CFBundleName</key><string>GPX Organizer</string>
 <key>CFBundleDisplayName</key><string>GPX Organizer</string>
 <key>CFBundleIdentifier</key><string>org.gpxorganizer.GPXOrganizer</string>
 <key>CFBundleIconFile</key><string>AppIcon</string>
 <key>CFBundleExecutable</key><string>GPXOrganizer</string>
 <key>CFBundlePackageType</key><string>APPL</string>
 <key>CFBundleShortVersionString</key><string>$VERSION</string>
 <key>CFBundleVersion</key><string>1</string>
 <key>LSMinimumSystemVersion</key><string>14.0</string>
 <key>NSHighResolutionCapable</key><true/>
 <key>NSPrincipalClass</key><string>NSApplication</string>
 <key>CFBundleDocumentTypes</key><array><dict>
   <key>CFBundleTypeName</key><string>GPX</string><key>CFBundleTypeRole</key><string>Viewer</string>
   <key>CFBundleTypeExtensions</key><array><string>gpx</string></array></dict></array>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
# make Finder / Launch Services pick up the (new) icon instead of a cached generic one
touch "$APP/Contents/Resources/AppIcon.icns" "$APP/Contents/Info.plist" "$APP"
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$LSR" ] && "$LSR" -f -R -trusted "$APP" >/dev/null 2>&1
echo "Built: $APP"
