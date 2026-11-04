#!/usr/bin/env bash
# Линтер: swift-format (правила — .swift-format), запрет сетевых API и контроль границ расширения.
source "$(dirname "$0")/common.sh"

swift_files | xargs xcrun swift-format lint --strict --parallel

python3 scripts/check-network-boundaries.py
python3 scripts/check-keyboard-boundaries.py
echo "Линтер: OK ($(swift_files | wc -l | tr -d ' ') файлов)"
