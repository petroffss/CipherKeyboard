#!/usr/bin/env python3
"""SessionStart-хук: в начале каждой сессии даёт Claude короткую сводку — где проект в конвейере
и какой следующий шаг. Всё, что печатается в stdout, попадает в контекст сессии."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import specslib as sl  # noqa: E402


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        data = {}
    root = sl.project_root(data)

    if "⟨" in sl.read_text(root / "CLAUDE.md"):
        print("Проект ещё не инициализирован (в CLAUDE.md остались пометки ⟨…⟩). Когда пользователь опишет "
              "задумку — запусти скилл kickoff. Задумка может лежать в IDEA.md, раздел «Задумка».")
        return

    features = sl.list_features(root)
    if not features:
        print("Фич в specs/ пока нет. Новую фичу заводит /write-evals <имя> <описание>.")
        return

    lines = ["Конвейер фич (specs/): статус · риск · evals pass → следующий шаг"]
    for f in features:
        loop = f["state"].get("loop")
        loop_note = " · цикл: %s, раунд %s" % (loop, f["state"].get("round", "?")) if loop and f["status"] == "building" else ""
        lines.append("- %s: %s · %s · %s%s → %s" % (
            f["id"], f["status"], f["risk"], sl.evals_summary(f), loop_note, sl.next_step(f, features)))
    lines.append("Полная таблица: /pipeline. Работаем по конвейеру из CLAUDE.md, раздел «Как мы работаем».")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
