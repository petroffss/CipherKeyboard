#!/usr/bin/env python3
"""Хуки спецификаций: PreToolUse и PostToolUse для Edit|Write|MultiEdit.

PreToolUse не даёт сделать «на словах» то, что требует доказательств или решения человека:
  • status: approved   — только пользователь, через /approve;
  • status: building   — только у одобренной фичи (без одобренных evals ничего не строим);
  • status: verified / done — только когда все evals в статусе pass;
    done для medium/high — только через /approve (результат принимает человек);
  • статус eval → pass — только агент verifier.
PostToolUse проверяет формат requirements.md и evals.md и говорит Claude, что исправить.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import specslib as sl  # noqa: E402


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}, ensure_ascii=False))
    sys.exit(0)


def apply_edit(text, old, new, replace_all):
    if not old:
        return text
    return text.replace(old, new) if replace_all else text.replace(old, new, 1)


def text_after(tool, tool_input, old_text):
    if tool == "Write":
        return tool_input.get("content", "")
    if tool == "Edit":
        return apply_edit(old_text, tool_input.get("old_string", ""), tool_input.get("new_string", ""),
                          tool_input.get("replace_all", False))
    if tool == "MultiEdit":
        text = old_text
        for edit in tool_input.get("edits") or []:
            text = apply_edit(text, edit.get("old_string", ""), edit.get("new_string", ""),
                              edit.get("replace_all", False))
        return text
    return None


def guard_status(fdir, old_text, new_text):
    fid = fdir.name
    old_status = sl.parse_frontmatter(old_text).get("status", "")
    new_fm = sl.parse_frontmatter(new_text)
    new_status = new_fm.get("status", "")
    if new_status == old_status:
        return
    feature = sl.load_feature(fdir)

    if new_status == "approved":
        deny("Одобрить фичу может только пользователь. Покажи ему requirements.md, evals.md и макет "
             "и попроси выполнить /approve %s." % fid)
    if new_status == "building" and old_status not in ("approved", "building", "verified", "done"):
        deny("Нельзя строить %s без одобренных evals (статус сейчас: %s). Порядок: /write-evals → "
             "пользователь проверяет → /approve → /review-loop." % (fid, old_status or "нет"))
    if new_status in ("verified", "done"):
        failing = sl.failing_evals(feature)
        if not feature["evals"] or failing:
            ids = ", ".join(e["id"] for e in failing) or "evals.md пуст"
            deny("Нельзя ставить %s: не пройдены evals (%s). Фича готова, только когда все evals в статусе pass "
                 "по результатам агента verifier." % (new_status, ids))
        risk = new_fm.get("risk") or feature["risk"]
        if new_status == "done" and risk != "low":
            deny("Фичу с риском %s принимает пользователь: поставь verified и попроси его выполнить /approve %s."
                 % (risk, fid))


def guard_eval_passes(agent_type, old_text, new_text):
    if agent_type == "verifier":
        return
    before = {e["id"]: e["status"] for e in sl.parse_evals(old_text)}
    newly = [e["id"] for e in sl.parse_evals(new_text) if e["status"] == "pass" and before.get(e["id"]) != "pass"]
    if newly:
        deny("Статус pass ставит только агент verifier, с доказательством (%s). Новые evals добавляй со статусом "
             "pending, затем запусти Agent(subagent_type: \"verifier\") на эти evals." % ", ".join(newly))


def pre(data, root):
    tool_input = data.get("tool_input") or {}
    path = tool_input.get("file_path")
    fdir, name = sl.feature_of_path(root, path)
    if name not in ("requirements.md", "evals.md"):
        return
    old_text = sl.read_text(path)
    new_text = text_after(data.get("tool_name"), tool_input, old_text)
    if new_text is None:
        return
    if name == "requirements.md":
        guard_status(fdir, old_text, new_text)
    else:
        guard_eval_passes(data.get("agent_type") or "", old_text, new_text)


def post(data, root):
    fdir, name = sl.feature_of_path(root, (data.get("tool_input") or {}).get("file_path"))
    if name not in ("requirements.md", "evals.md"):
        return
    feature = sl.load_feature(fdir)
    strict = feature["status"] not in ("draft", "—")
    problems = []
    if name == "requirements.md":
        problems += sl.lint_requirements(feature["fm"], feature["req_text"], strict)
    if name == "evals.md" or strict:
        problems += sl.lint_evals(feature["evals"], feature["risk"], feature["ui"], strict)
    if feature["status"] in ("verified", "done") and sl.failing_evals(feature):
        problems.append("статус %s, но не все evals pass — верни статус building" % feature["status"])
    if problems:
        print("Проверка specs/%s/%s — исправь:\n- %s" % (fdir.name, name, "\n- ".join(problems)), file=sys.stderr)
        sys.exit(2)


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    root = sl.project_root(data)
    event = data.get("hook_event_name")
    try:
        if event == "PreToolUse":
            pre(data, root)
        elif event == "PostToolUse":
            post(data, root)
    except (OSError, ValueError, KeyError) as exc:
        print("spec_hooks: %s" % exc, file=sys.stderr)


if __name__ == "__main__":
    main()
