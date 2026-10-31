#!/usr/bin/env bash
# Песочница: отдельный новый симулятор с пустым Keychain и контейнерами (нет ключа, нет контактов),
# чтобы /first-time-user и verifier не трогали симулятор разработчика.
#   scripts/sandbox.sh start   — создать, загрузить, поставить и открыть приложение; печатает UDID
#   scripts/sandbox.sh stop    — выключить и удалить все песочницы
source "$(dirname "$0")/common.sh"

case "${1:-start}" in
    start)
        build_app
        UDID="$(xcrun simctl create "$SANDBOX_NAME" "$DEVICE")"
        install_and_launch "$UDID"
        echo "Песочница запущена: «$SANDBOX_NAME» ($UDID). Удалить: scripts/sandbox.sh stop"
        ;;
    stop)
        xcrun simctl list devices -j | python3 -c '
import json, sys
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if d["name"] == sys.argv[1]:
            print(d["udid"])
' "$SANDBOX_NAME" | while read -r udid; do
            xcrun simctl shutdown "$udid" 2>/dev/null || true
            xcrun simctl delete "$udid"
            echo "Удалена песочница $udid"
        done
        ;;
    *)
        echo "Использование: scripts/sandbox.sh start|stop" >&2
        exit 2
        ;;
esac
