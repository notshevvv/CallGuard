#!/bin/zsh
# Builds CallGuard.app into ./dist   (usage: ./build.sh)
set -euo pipefail
cd "${0:A:h}"
VERSION="${VERSION:-2.0.0}"
BUNDLE_ID="${BUNDLE_ID:-app.callguard.CallGuard}"

swift build -c release --arch arm64 --arch x86_64 2>/dev/null || swift build -c release
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path 2>/dev/null || swift build -c release --show-bin-path)

APP=dist/CallGuard.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/CallGuard" "$APP/Contents/MacOS/CallGuard"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>CallGuard</string>
  <key>CFBundleDisplayName</key><string>CallGuard</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>CallGuard</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.4</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <key>NSAudioCaptureUsageDescription</key><string>CallGuard routes your Mac's sound through its own engine to stop call ducking, boost volume and bass, and fade media on a sleep timer. Nothing is recorded, saved or sent anywhere.</string>
  <key>NSMicrophoneUsageDescription</key><string>CallGuard only mutes and unmutes your microphones. It never listens.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $PWD/$APP"
