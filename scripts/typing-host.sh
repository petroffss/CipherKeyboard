#!/usr/bin/env bash
# Build/install the separate rotating Debug host on an explicitly supplied disposable simulator.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TYPING_SIMULATOR:?Set TYPING_SIMULATOR to the disposable simulator UDID}"
output="$PWD/.build/TypingHost.app"
mkdir -p "$output"
xcrun --sdk iphonesimulator swiftc -D DEBUG -parse-as-library -target arm64-apple-ios18.0-simulator \
    -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" DebugHost/TypingHost.swift -o "$output/TypingHost"
cat > "$output/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.cipherkeyboard.typinghost</string>
<key>CFBundleExecutable</key><string>TypingHost</string><key>CFBundleName</key><string>TypingHost</string>
<key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string><key>MinimumOSVersion</key><string>18.0</string>
<key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/><key>UISceneConfigurations</key><dict/></dict>
<key>UIDeviceFamily</key><array><integer>1</integer></array><key>UILaunchScreen</key><dict/>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
</dict></plist>
PLIST
xattr -cr "$output"
codesign --force --sign - "$output"
xcrun simctl install "$TYPING_SIMULATOR" "$output"
xcrun simctl launch "$TYPING_SIMULATOR" dev.cipherkeyboard.typinghost
