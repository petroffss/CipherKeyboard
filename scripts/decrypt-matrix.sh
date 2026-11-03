#!/usr/bin/env bash
# Capture the 94 approved native frames on three explicitly supplied disposable simulators.
source "$(dirname "$0")/common.sh"
[ "$#" = 3 ] || { echo 'Usage: scripts/decrypt-matrix.sh UDID375 UDID402 UDID440' >&2; exit 2; }
output="${DECRYPT_MATRIX_OUTPUT:-$ROOT/.build/DecryptMatrix/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$output"
for udid in "$@"; do
    xcrun simctl bootstatus "$udid" -b >/dev/null
    TYPING_SIMULATOR="$udid" scripts/typing-host.sh
    TYPING_SIMULATOR="$udid" TYPING_RESULT="$output/$udid-preflight.xcresult" scripts/typing-integration.sh \
        -only-testing:TypingIntegrationTests/KeyboardRuntimeTests/testFullAccessPreflight > "$output/$udid-preflight.log" 2>&1
    for theme in light dark; do
        TYPING_SIMULATOR="$udid" TYPING_APPEARANCE="$theme" TYPING_RESULT="$output/$udid-$theme.xcresult" scripts/typing-integration.sh \
            -only-testing:TypingIntegrationTests/DecryptMatrixTests/testCaptureCurrentProfile > "$output/$udid-$theme.log" 2>&1
    done
    xcrun simctl shutdown "$udid"
done
echo "Native decrypt matrix result bundles: $output"
