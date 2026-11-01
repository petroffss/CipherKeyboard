# Общие настройки для скриптов scripts/*.sh (подключается через source).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT="CipherKeyboard.xcodeproj"
SCHEME="CipherKeyboard"
BUNDLE_ID="dev.cipherkeyboard.app"
DEVICE="${DEVICE:-iPhone 17}"                  # симулятор по умолчанию; другой: DEVICE="iPhone 18 Pro" scripts/run.sh
DERIVED="${DERIVED:-$ROOT/.build/DerivedData}"
APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/CipherKeyboard.app"
CORE_PACKAGE="Packages/CipherCore"
SANDBOX_NAME="CipherKeyboard-Sandbox"

# Все .swift-файлы проекта (без сборочных папок).
swift_files() {
    find App Keyboard UITests DebugHost DebugHostTests "$CORE_PACKAGE" -name '*.swift' -not -path '*/.build/*' -not -path '*/.swiftpm/*' | sort
}

# Hash every Swift source, including untracked work, so cached extension binaries are observable.
typing_revision() {
    local source_hash
    source_hash="$(swift_files | xargs shasum -a 256 | shasum -a 256 | cut -c1-8)"
    echo "$((16#$source_hash % 2000000000 + 2))"
}

# UDID доступного симулятора по имени (первый с таким именем).
device_udid() {
    xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if "iOS" in runtime:
        for d in devices:
            if d["name"] == name:
                print(d["udid"]); sys.exit(0)
sys.exit("Симулятор «%s» не найден: xcrun simctl list devices available" % name)
' "$1"
}

# Собрать приложение с клавиатурой для симулятора.
build_app() {
    xcodebuild build -project "$PROJECT" -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,name=$DEVICE" \
        -derivedDataPath "$DERIVED" "CURRENT_PROJECT_VERSION=$(typing_revision)" -quiet "$@"
}

# Загрузить симулятор (если ещё не загружен), поставить и открыть приложение.
install_and_launch() {
    local udid="$1"
    xcrun simctl bootstatus "$udid" -b >/dev/null
    [ "${HEADLESS:-0}" = 1 ] || open -a Simulator --args -CurrentDeviceUDID "$udid"
    xcrun simctl install "$udid" "$APP_PATH"
    xcrun simctl launch "$udid" "$BUNDLE_ID" >/dev/null
}
