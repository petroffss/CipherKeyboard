#!/usr/bin/env bash
# Isolated E12 run. No clipboard-consuming UI suites may run concurrently.
source "$(dirname "$0")/common.sh"
: "${TYPING_SIMULATOR:?Set an explicitly disposable simulator UDID}"
output="${TYPING_AUDIT_OUTPUT:-$ROOT/.build/TypingAudit/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$output"
# A production Keychain identity, real Full Access, current installed bytes and closed draft.
TYPING_RESULT="$output/setup.xcresult" scripts/typing-integration.sh \
    -only-testing:TypingIntegrationTests/KeyboardRuntimeTests/testFullAccessPreflight \
    -only-testing:TypingIntegrationTests/KeyboardRuntimeTests/testClipboardSentinelSetup > "$output/setup.log" 2>&1
# In-process setup writes a fixed synthetic sentinel. The following read-only snapshot
# must observe that actual sentinel AND exactly one real identity metadata entry.
# Failed setup snapshots remain on disk and stop the run before canary UI.
python3 scripts/typing-audit.py snapshot "$TYPING_SIMULATOR" "$output/before.json"
ui_status=0
# Do not rebuild/reinstall between snapshots: installation itself re-keys OS
# SplashBoard snapshot filenames. Setup already verified installed bytes/revision.
xcodebuild test-without-building -project "$PROJECT" -scheme TypingIntegration \
    -destination "platform=iOS Simulator,id=$TYPING_SIMULATOR" -derivedDataPath "$DERIVED" \
    "CURRENT_PROJECT_VERSION=$(typing_revision)" -parallel-testing-enabled NO \
    -resultBundlePath "$output/canary.xcresult" \
    -only-testing:TypingIntegrationTests/KeyboardRuntimeTests/testNoExportCanary > "$output/canary.log" 2>&1 || ui_status=$?
after_status=0
python3 scripts/typing-audit.py snapshot "$TYPING_SIMULATOR" "$output/after.json" || after_status=$?
compare_status=0
python3 scripts/typing-audit.py compare "$output/before.json" "$output/after.json" "$output/result.json" || compare_status=$?
[ "$ui_status" = 0 ] && [ "$after_status" = 0 ] && [ "$compare_status" = 0 ]
