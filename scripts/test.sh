#!/usr/bin/env bash
# Тесты.
#   scripts/test.sh        — ядро (swift test на Mac) + UI-тесты в симуляторе
#   scripts/test.sh core   — только ядро, секунды
#   scripts/test.sh ui     — только UI-тесты
#   scripts/test.sh ui -only-testing:CipherKeyboardUITests/LaunchSmokeTests   — дополнительные флаги xcodebuild
source "$(dirname "$0")/common.sh"

what="${1:-all}"
[ $# -gt 0 ] && shift

if [ "$what" = all ] || [ "$what" = core ]; then
    echo "== CipherCore: swift test"
    swift test --package-path "$CORE_PACKAGE" --scratch-path "$ROOT/.build/core" "$@"
fi
if [ "$what" = all ] || [ "$what" = ui ]; then
    echo "== Приложение: xcodebuild test на «${DEVICE}»"
    RESULT="$ROOT/.build/TestResults/ui-$(date +%Y%m%d-%H%M%S).xcresult"
    status=0
    xcodebuild test -project "$PROJECT" -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,name=$DEVICE" \
        -derivedDataPath "$DERIVED" "CURRENT_PROJECT_VERSION=$(typing_revision)" -resultBundlePath "$RESULT" -quiet "$@" || status=$?
    if [ -d "$RESULT" ]; then
        xcrun xcresulttool get test-results summary --path "$RESULT" | python3 -c '
import json, sys
s = json.load(sys.stdin)
print("UI-тесты: %s — пройдено %d, упало %d, пропущено %d" % (s["result"], s["passedTests"], s["failedTests"], s["skippedTests"]))
for f in s.get("testFailures", []):
    print("  ✗ %s: %s" % (f.get("testName"), f.get("failureText")))
'
        echo "Отчёт: ${RESULT#$ROOT/}"
    fi
    exit "$status"
fi
