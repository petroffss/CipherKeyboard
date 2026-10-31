#!/usr/bin/env bash
# Форматирование всех .swift-файлов по .swift-format (после правок это делает хук автоматически).
source "$(dirname "$0")/common.sh"

swift_files | xargs xcrun swift-format format --in-place --parallel
echo "Форматирование: OK"
