#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Packaging below uses the native SwiftPM resource layout.
sh scripts/swift-check.sh build --build-system native -c release --product omp-ui
APP_DIR="$PWD/dist/omp-ui.app"
# Start clean so obsolete resources cannot leak into a release.
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp .build/release/omp-ui "$APP_DIR/Contents/MacOS/omp-ui"
VERSION=$(cat VERSION)
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>omp-ui</string>
<key>CFBundleIdentifier</key><string>sh.omp.ui</string>
<key>CFBundleName</key><string>omp-ui</string>
<key>CFBundleDisplayName</key><string>omp-ui</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP_DIR"
printf '%s\n' "$APP_DIR"
