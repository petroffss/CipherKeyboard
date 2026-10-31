#!/usr/bin/env python3
"""PreToolUse-хук агента first-time-user: агент видит приложение только так, как его видит человек.

Разрешено: MCP-инструменты интерфейса — браузер (встроенный, Claude in Chrome, Playwright…),
iOS Simulator, Android-эмулятор — и ToolSearch для их загрузки. Запрещено всё остальное: чтение файлов,
поиск, терминал, правки. Внутри инструментов интерфейса запрещены JavaScript, консоль/сеть/логи,
загрузка файлов, сборка и установка приложения, адреса file:// / view-source:.
Работает по белому списку, поэтому обойти его «через терминал» нельзя.
"""
import json
import os
import re
import sys

ALLOWED_BUILTIN = {"ToolSearch", "TodoWrite"}
UI_SERVER = re.compile(r"(browser|chrome|playwright|puppeteer|simulator|emulator)", re.I)
FORBIDDEN_TOOL = re.compile(r"(javascript|evaluate|run_code|console|network|logs|upload|preview_start|preview_stop|build|install)", re.I)
FORBIDDEN_ACTION = {"launch", "build", "install"}  # приложение запускает оркестратор, а не «пользователь»
FORBIDDEN_URL = re.compile(r"^\s*(file:|view-source:|chrome:|about:|devtools:)", re.I)


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}, ensure_ascii=False))
    sys.exit(0)


def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for v in value.values():
            yield from strings(v)
    elif isinstance(value, list):
        for v in value:
            yield from strings(v)


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    tool = data.get("tool_name", "")
    tool_input = data.get("tool_input") or {}
    project = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or ""

    if tool in ALLOWED_BUILTIN:
        return
    parts = tool.split("__")
    is_ui = len(parts) >= 3 and parts[0] == "mcp" and UI_SERVER.search(parts[1])
    if not is_ui:
        deny("Ты первый пользователь: у тебя есть только экран приложения (браузер или симулятор). "
             "Код, файлы и терминал недоступны (%s)." % tool)
    if FORBIDDEN_TOOL.search(parts[-1]) or str(tool_input.get("action", "")).lower() in FORBIDDEN_ACTION:
        deny("Обычный пользователь не запускает JavaScript, не смотрит консоль, сеть или логи и не собирает "
             "приложение (%s). Пользуйся только тем, что видно на экране." % tool)
    for value in strings(tool_input):
        if FORBIDDEN_URL.match(value) or (project and project in value):
            deny("Этот адрес недоступен первому пользователю: открывай только адрес приложения, который тебе дали.")


if __name__ == "__main__":
    main()
