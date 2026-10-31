#!/usr/bin/env python3
"""PreToolUse-хук агента first-time-user: агент видит приложение только так, как его видит человек.

Разрешено: браузерные MCP-инструменты (встроенный браузер, Claude in Chrome, Playwright и т.п.)
и ToolSearch для их загрузки. Запрещено всё остальное: чтение файлов, поиск, терминал, правки,
а внутри браузера — выполнение JavaScript, консоль/сеть/логи, загрузка файлов и адреса file:// / view-source:.
Работает по белому списку, поэтому обойти его «через терминал» нельзя.
"""
import json
import os
import re
import sys

ALLOWED_BUILTIN = {"ToolSearch", "TodoWrite"}
BROWSER_SERVER = re.compile(r"(browser|chrome|playwright|puppeteer)", re.I)
FORBIDDEN_IN_BROWSER = re.compile(r"(javascript|evaluate|run_code|console|network|logs|upload|preview_start|preview_stop)", re.I)
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
    is_browser = len(parts) >= 3 and parts[0] == "mcp" and BROWSER_SERVER.search(parts[1])
    if not is_browser:
        deny("Ты первый пользователь: у тебя есть только браузер. Код, файлы и терминал недоступны (%s)." % tool)
    if FORBIDDEN_IN_BROWSER.search(parts[-1]):
        deny("Обычный пользователь не запускает JavaScript и не смотрит консоль, сеть или логи (%s). "
             "Пользуйся только тем, что видно на экране." % tool)
    for value in strings(tool_input):
        if FORBIDDEN_URL.match(value) or (project and project in value):
            deny("Этот адрес недоступен первому пользователю: открывай только адрес приложения, который тебе дали.")


if __name__ == "__main__":
    main()
