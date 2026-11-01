#!/usr/bin/env bash
# Unhosted UI tests do not install their app build dependency. Install it explicitly.
source "$(dirname "$0")/common.sh"
: "${TYPING_SIMULATOR:?Set the disposable simulator UDID}"
name="$(xcrun simctl list devices -j | python3 -c 'import json,sys; print(next(d["name"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["udid"] == sys.argv[1]))' "$TYPING_SIMULATOR")"
[[ "$name" == CipherKeyboard-Typing-* ]] || { echo 'Disposable typing simulator required' >&2; exit 2; }
result="${TYPING_RESULT:-$ROOT/.build/TestResults/typing-$(date +%Y%m%d-%H%M%S).xcresult}"
args=(-project "$PROJECT" -scheme TypingIntegration -destination "platform=iOS Simulator,id=$TYPING_SIMULATOR" -derivedDataPath "$DERIVED" "CURRENT_PROJECT_VERSION=$(typing_revision)" -parallel-testing-enabled NO)
xcodebuild build-for-testing "${args[@]}" "$@"
xcrun simctl terminate "$TYPING_SIMULATOR" dev.cipherkeyboard.typinghost 2>/dev/null || true
xcrun simctl terminate "$TYPING_SIMULATOR" dev.cipherkeyboard.app.keyboard 2>/dev/null || true
xcrun simctl install "$TYPING_SIMULATOR" "$APP_PATH"
installed="$(xcrun simctl get_app_container "$TYPING_SIMULATOR" dev.cipherkeyboard.app app)"
relative='PlugIns/CipherKeyboardExtension.appex/CipherKeyboardExtension.debug.dylib'
cmp "$APP_PATH/$relative" "$installed/$relative"
echo "Verified installed extension SHA256: $(shasum -a 256 "$installed/$relative")"
xcodebuild test-without-building "${args[@]}" -resultBundlePath "$result" "$@"
