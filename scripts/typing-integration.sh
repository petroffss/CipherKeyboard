#!/usr/bin/env bash
# Unhosted UI tests do not install their app build dependency. Install it explicitly.
source "$(dirname "$0")/common.sh"
: "${TYPING_SIMULATOR:?Set the disposable simulator UDID}"
name="$(xcrun simctl list devices -j | python3 -c 'import json,sys; print(next(d["name"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["udid"] == sys.argv[1]))' "$TYPING_SIMULATOR")"
[[ "$name" == CipherKeyboard-Typing-* ]] || { echo 'Disposable typing simulator required' >&2; exit 2; }
# A CoreDevice hardware-keyboard reconnect can otherwise minimize the real keyboard mid-capture.
# This is an iOS preference on this disposable UDID, never a host/global Simulator preference.
xcrun simctl spawn "$TYPING_SIMULATOR" defaults write com.apple.keyboard.preferences AutomaticMinimizationEnabled -bool false
keyboard_minimization="$(xcrun simctl spawn "$TYPING_SIMULATOR" defaults read com.apple.keyboard.preferences AutomaticMinimizationEnabled)"
[[ "$keyboard_minimization" == 0 ]] || { echo 'Disposable software-keyboard precondition failed' >&2; exit 1; }
echo "Disposable automatic keyboard minimization: $keyboard_minimization (off)"
if [ -n "${TYPING_APPEARANCE:-}" ]; then
    [[ "$TYPING_APPEARANCE" == light || "$TYPING_APPEARANCE" == dark ]] || exit 2
    xcrun simctl ui "$TYPING_SIMULATOR" appearance "$TYPING_APPEARANCE"
    actual_appearance="$(xcrun simctl ui "$TYPING_SIMULATOR" appearance)"
    [[ "$actual_appearance" == "$TYPING_APPEARANCE" ]] || { echo 'OS appearance readback mismatch' >&2; exit 1; }
    echo "Actual Simulator OS appearance: $actual_appearance"
fi
result="${TYPING_RESULT:-$ROOT/.build/TestResults/typing-$(date +%Y%m%d-%H%M%S).xcresult}"
revision="$(typing_revision)"
args=(-project "$PROJECT" -scheme TypingIntegration -destination "platform=iOS Simulator,id=$TYPING_SIMULATOR" -derivedDataPath "$DERIVED" "CURRENT_PROJECT_VERSION=$revision" -parallel-testing-enabled NO)
xcodebuild build-for-testing "${args[@]}" "$@"
xcrun simctl terminate "$TYPING_SIMULATOR" dev.cipherkeyboard.typinghost 2>/dev/null || true
xcrun simctl terminate "$TYPING_SIMULATOR" dev.cipherkeyboard.app.keyboard 2>/dev/null || true
xcrun simctl install "$TYPING_SIMULATOR" "$APP_PATH"
installed="$(xcrun simctl get_app_container "$TYPING_SIMULATOR" dev.cipherkeyboard.app app)"
relative='PlugIns/CipherKeyboardExtension.appex/CipherKeyboardExtension.debug.dylib'
cmp "$APP_PATH/$relative" "$installed/$relative"
echo "Verified installed extension SHA256: $(shasum -a 256 "$installed/$relative")"
installed_revision="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$installed/Info.plist")"
[[ "$installed_revision" == "$revision" ]] || { echo 'Installed source revision mismatch' >&2; exit 1; }
echo "Runtime source revision: $revision; simulator: $TYPING_SIMULATOR; installed: $installed"
xcodebuild test-without-building "${args[@]}" -resultBundlePath "$result" "$@"
