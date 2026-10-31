#!/usr/bin/env python3
"""PostToolUse-хук: после правки .swift-файла форматирует его swift-format (правила — .swift-format в корне).
Ошибки форматтера не блокируют правку — их покажет scripts/lint.sh."""
import json
import subprocess
import sys


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    path = (data.get("tool_input") or {}).get("file_path") or ""
    if not path.endswith(".swift"):
        return
    try:
        subprocess.run(["xcrun", "swift-format", "format", "--in-place", path], capture_output=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        pass


if __name__ == "__main__":
    main()
