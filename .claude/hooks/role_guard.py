#!/usr/bin/env python3
"""PreToolUse-хук ролей цикла /review-loop. Подключается во frontmatter агентов: role_guard.py <роль>.

builder  — строит приложение, но не может менять контракт: specs/**, REVIEW.md, CLAUDE.md, IDEA.md, .claude/**.
           (Иначе проще всего «пройти» evals, ослабив их.)
verifier — проверяет, но не чинит: пишет только строки **Статус:** / **Доказательство:** в
           specs/<фича>/evals.md и файлы в specs/<фича>/evidence/.
"""
import difflib
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import specslib as sl  # noqa: E402

BUILDER_PROTECTED = re.compile(r"^(specs/|REVIEW\.md$|CLAUDE\.md$|IDEA\.md$|\.claude/)")
SHELL_PROTECTED = re.compile(r"(specs/|REVIEW\.md|CLAUDE\.md|IDEA\.md|\.claude/)")
SHELL_WRITES = re.compile(
    r"((^|[^0-9&>])>{1,2}[ \t]*(?!&|/dev/null)\S|\btee\b|\bsed\b[^|;&]*\s-i|\bperl\b[^|;&]*\s-i|"
    r"\b(mv|cp|rm|truncate|touch)\b|\bgit\s+(checkout|restore|rm|mv)\b|pipeline\.py\s+set)"
)
VERIFIER_LINE = re.compile(r"^[ \t]*[-*][ \t]*\*\*(Статус|Status|Доказательство|Evidence)\*\*[ \t]*:?|"
                           r"^[ \t]*[-*][ \t]*\*\*(Статус|Status|Доказательство|Evidence):\*\*")


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}, ensure_ascii=False))
    sys.exit(0)


def rel_path(root, path):
    try:
        return Path(path).resolve().relative_to(root).as_posix()
    except (ValueError, OSError, TypeError):
        return None


def changed_lines(old, new):
    return [line[2:] for line in difflib.ndiff(old.splitlines(), new.splitlines()) if line[:2] in ("- ", "+ ")]


def verifier_edit_ok(tool, tool_input, path):
    old_text = sl.read_text(path)
    if tool == "Write":
        pairs = [(old_text, tool_input.get("content", ""))]
    elif tool == "Edit":
        pairs = [(tool_input.get("old_string", ""), tool_input.get("new_string", ""))]
    elif tool == "MultiEdit":
        pairs = [(e.get("old_string", ""), e.get("new_string", "")) for e in tool_input.get("edits") or []]
    else:
        return False
    return all(VERIFIER_LINE.match(line) for old, new in pairs for line in changed_lines(old, new) if line.strip())


def main():
    role = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    root = Path(os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or ".").resolve()
    tool = data.get("tool_name", "")
    tool_input = data.get("tool_input") or {}

    if tool == "Bash":
        command = tool_input.get("command", "")
        if role == "builder" and SHELL_PROTECTED.search(command) and SHELL_WRITES.search(command):
            deny("Строитель не меняет спецификации, правила и настройки (specs/, REVIEW.md, CLAUDE.md, .claude/) — "
                 "ни инструментами, ни через терминал. Если требование или eval кажется неверным, верни это "
                 "оркестратору как вопрос.")
        return

    path = tool_input.get("file_path") or tool_input.get("notebook_path")
    rel = rel_path(root, path)
    if rel is None:
        return  # вне проекта (временные файлы) — не наше дело

    if role == "builder" and BUILDER_PROTECTED.match(rel):
        deny("Строитель не меняет %s: это контракт фичи и правила проекта. Evals должны пройти как есть. "
             "Если требование кажется неверным или невыполнимым — верни это оркестратору как вопрос." % rel)

    if role == "verifier":
        if re.match(r"^specs/[^/_.][^/]*/evidence/", rel):
            return
        if re.match(r"^specs/[^/_.][^/]*/evals\.md$", rel):
            if verifier_edit_ok(tool, tool_input, path):
                return
            deny("Verifier меняет в evals.md только строки `- **Статус:**` и `- **Доказательство:**` "
                 "(доказательство — одной строкой). Формулировки, шаги и ожидания трогать нельзя.")
        deny("Verifier не меняет код и файлы проекта (%s) — только статусы в evals.md и файлы в evidence/. "
             "Причину провала опиши в ответе оркестратору." % rel)


if __name__ == "__main__":
    main()
