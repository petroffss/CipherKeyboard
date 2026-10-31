#!/usr/bin/env bash
# Запуск (dev): собрать, загрузить симулятор $DEVICE, поставить и открыть приложение.
# HEADLESS=1 — не открывать окно Simulator (для агентов).
source "$(dirname "$0")/common.sh"

build_app
UDID="$(device_udid "$DEVICE")"
install_and_launch "$UDID"
echo "Запущено: $BUNDLE_ID на «$DEVICE» ($UDID)"
