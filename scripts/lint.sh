#!/usr/bin/env bash
# Линтер: swift-format (правила — .swift-format) + обещание «без сети»: сетевые API в коде запрещены.
source "$(dirname "$0")/common.sh"

swift_files | xargs xcrun swift-format lint --strict --parallel

NETWORK_API='\b(URLSession|URLRequest|NWConnection|NWListener|NWPathMonitor|CFNetwork|CFStream|WKWebView|SFSafariViewController|MultipeerConnectivity)\b|^[[:space:]]*import[[:space:]]+(Network|WebKit|MultipeerConnectivity)\b'
if swift_files | xargs grep -nE "$NETWORK_API"; then
    echo "lint: найден сетевой код — CipherKeyboard обещает работу без сети (CLAUDE.md, REVIEW.md)" >&2
    exit 1
fi
echo "Линтер: OK ($(swift_files | wc -l | tr -d ' ') файлов)"
