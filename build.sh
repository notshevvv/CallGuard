#!/bin/zsh
# Builds CallGuard.app into ./dist   (usage: ./build.sh)
set -euo pipefail
cd "${0:A:h}"
VERSION="${VERSION:-3.3.1}"
BUNDLE_ID="${BUNDLE_ID:-app.callguard.CallGuard}"

# Build each chip separately (own build folder each) and join them; no Xcode build system needed.
for A in arm64 x86_64; do
  swift build -c release --triple $A-apple-macosx14.4 --build-path .build/$A
done
mkdir -p .build/universal
lipo -create .build/arm64/release/CallGuard .build/x86_64/release/CallGuard -output .build/universal/CallGuard
BIN=.build/universal

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
# Sign with a stable local identity when there is one, so macOS keeps CallGuard's
# System Audio Recording permission across updates. Ad-hoc otherwise.
IDENTITY="${SIGN_IDENTITY:-CallGuard Local Signing}"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "Built $PWD/$APP"
