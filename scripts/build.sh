#!/usr/bin/env bash
# Сборка: приложение + клавиатура для iOS Simulator (без подписи командой).
source "$(dirname "$0")/common.sh"

build_app "$@"
echo "Сборка: OK → ${APP_PATH#$ROOT/}"
