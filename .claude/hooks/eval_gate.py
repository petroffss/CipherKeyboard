#!/usr/bin/env python3
"""Stop-хук «нельзя сказать готово, пока evals не пройдены».

Если какая-то фича в статусе building и не все её evals в статусе pass, Claude не может закончить
ход — хук возвращает его в цикл /review-loop. Отпускает, когда:
  • все evals pass, или
  • в specs/<фича>/state.md стоит loop: needs-human | stopped | done
    (цикл сам остановился по правилам: нужен ответ человека, застряли, лимит раундов, пауза по просьбе).
Предохранитель: после 5 блокировок подряд в одной сессии хук отпускает с предупреждением,
чтобы не жечь лимиты. Отключить полностью: переменная окружения EVAL_GATE=off.
"""
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import specslib as sl  # noqa: E402

MAX_CONSECUTIVE_BLOCKS = 5


def load_counter(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save_counter(path, counter):
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(counter), encoding="utf-8")
    except OSError:
        pass


def main():
    if os.environ.get("EVAL_GATE", "").lower() == "off":
        return
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    root = sl.project_root(data)

    blocking = []
    for feature in sl.list_features(root):
        if feature["status"] != "building":
            continue
        if feature["state"].get("loop") in ("needs-human", "stopped", "done"):
            continue
        failing = sl.failing_evals(feature)
        if failing or not feature["evals"]:
            blocking.append((feature, failing))

    counter_path = root / ".claude" / ".cache" / "eval_gate.json"
    counter = load_counter(counter_path)
    session = data.get("session_id") or "default"
    if not blocking:
        if counter.pop(session, None) is not None:
            save_counter(counter_path, counter)
        return

    count = counter.get(session, 0) + 1
    if count > MAX_CONSECUTIVE_BLOCKS:
        counter.pop(session, None)
        save_counter(counter_path, counter)
        print(json.dumps({"systemMessage": "eval-gate: фича в статусе building всё ещё не проходит evals, "
                                           "но хук отпустил после %d попыток подряд. Посмотри /pipeline."
                                           % MAX_CONSECUTIVE_BLOCKS}, ensure_ascii=False))
        return
    counter[session] = count
    save_counter(counter_path, counter)

    lines = []
    for feature, failing in blocking:
        ids = ", ".join(e["id"] for e in failing) or "нет evals.md"
        lines.append("• %s: не пройдены %s (pass %s)" % (feature["id"], ids, sl.evals_summary(feature)))
    reason = (
        "Рано заканчивать: есть фича в статусе building с непройденными evals.\n%s\n"
        "Продолжи цикл /review-loop: следующий раунд builder → verifier → reviewer, статусы evals ставит только verifier.\n"
        "Остановиться можно только по правилам цикла: нужен ответ человека, проблема не уходит 2 раунда исправлений, "
        "достигнут лимит раундов или пользователь сам попросил паузу. Тогда запиши отчёт в specs/<фича>/state.md, "
        "поставь там `loop: needs-human` (или `stopped` при лимите) и только потом заканчивай."
        % "\n".join(lines)
    )
    print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))


if __name__ == "__main__":
    main()
