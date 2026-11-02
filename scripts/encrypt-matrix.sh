#!/usr/bin/env bash
# Three explicit disposable UDIDs: native 375, 402 and 440 pt profiles, in any order.
source "$(dirname "$0")/common.sh"
[ "$#" = 3 ] || { echo 'Usage: scripts/typing-matrix.sh UDID375 UDID402 UDID440' >&2; exit 2; }
output="${TYPING_MATRIX_OUTPUT:-$ROOT/.build/EncryptMatrix/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$output"
results=()
for udid in "$@"; do
    xcrun simctl bootstatus "$udid" -b >/dev/null
    TYPING_SIMULATOR="$udid" scripts/typing-host.sh
    # Settings and actual extension activation are a separate, retained preflight.
    TYPING_SIMULATOR="$udid" TYPING_RESULT="$output/$udid-preflight.xcresult" scripts/typing-integration.sh \
        -only-testing:TypingIntegrationTests/KeyboardRuntimeTests/testFullAccessPreflight > "$output/$udid-preflight.log" 2>&1
    for theme in light dark; do
        method=Light
        [ "$theme" = dark ] && method=Dark
        result="$output/$udid-$theme.xcresult"
        TYPING_SIMULATOR="$udid" TYPING_APPEARANCE="$theme" TYPING_RESULT="$result" scripts/typing-integration.sh \
            "-only-testing:TypingIntegrationTests/EncryptMatrixTests/testCapture${method}CurrentProfile" > "$output/$udid-$theme.log" 2>&1
        results+=("$result")
    done
    xcrun simctl shutdown "$udid"
done
python3 scripts/typing-matrix-export.py "$output/frames" "${results[@]}" --complete --encrypt
xcrun swiftc -D DEBUG -parse-as-library DebugHost/MatrixMontage.swift -o "$output/montage"
"$output/montage" "$output/frames/manifest.json" "$output/montages"
echo "Matrix manifest: $output/frames/manifest.json"
