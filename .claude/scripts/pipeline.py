#!/usr/bin/env python3
"""Конвейер фич: статусы, проверки и переходы.

  python3 .claude/scripts/pipeline.py                     таблица всех фич и следующий шаг
  python3 .claude/scripts/pipeline.py show <фича>         подробности: evals, цикл, следующий шаг
  python3 .claude/scripts/pipeline.py check <фича>        полная проверка requirements/evals/макета (код 1 — есть проблемы)
  python3 .claude/scripts/pipeline.py set-status <фича> <статус>
                                                          переход статуса с проверками:
      in-review  — требования и evals проходят check
      approved   — только из in-review и только по команде пользователя (/approve)
      building   — только из approved / verified / done
      verified, done — только если все evals pass

Статусы: draft → in-review → approved → building → verified → done
"""
import datetime
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))
import specslib as sl  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]


def fail(message, code=1):
    print(message, file=sys.stderr)
    sys.exit(code)


def get_feature(name):
    feature = sl.find_feature(ROOT, name)
    if not feature:
        known = ", ".join(f["id"] for f in sl.list_features(ROOT)) or "нет ни одной"
        fail("Фича «%s» не найдена в specs/. Есть: %s" % (name, known))
    return feature


def cmd_table():
    features = sl.list_features(ROOT)
    if not features:
        print("В specs/ пока нет фич. Начни с /kickoff <идея> или /write-evals <имя> <описание>.")
        return
    rows = [("Фича", "Статус", "Риск", "Evals", "Цикл", "Следующий шаг")]
    for f in features:
        loop = ""
        if f["state"].get("loop"):
            loop = "%s r%s" % (f["state"]["loop"], f["state"].get("round", "?"))
        rows.append((f["id"], f["status"], f["risk"], sl.evals_summary(f), loop, sl.next_step(f, features)))
    widths = [max(len(r[i]) for r in rows) for i in range(len(rows[0]) - 1)]
    for i, row in enumerate(rows):
        print("  ".join(cell.ljust(widths[j]) for j, cell in enumerate(row[:-1])) + "  " + row[-1])
        if i == 0:
            print("  ".join("-" * w for w in widths) + "  " + "-" * 14)
    pending = [f for f in features if f["status"] != "done"]
    if pending:
        print("\nДальше: %s" % sl.next_step(pending[0], features))
    else:
        print("\nВсе фичи готовы.")


def cmd_show(name):
    f = get_feature(name)
    print("%s — %s" % (f["id"], f["title"]))
    print("статус: %s · риск: %s%s · ui: %s · макет: %s" % (
        f["status"], f["risk"],
        " (%s)" % f["fm"]["risk_reason"] if f["fm"].get("risk_reason") else "",
        "yes" if f["ui"] else "no", "есть" if f["has_mockup"] else "нет"))
    if f["depends_on"]:
        print("зависит от: %s" % ", ".join(f["depends_on"]))
    if f["evals"]:
        print("\nevals (%s pass):" % sl.evals_summary(f))
        for e in f["evals"]:
            tags = " [%s]" % ", ".join(sorted(e["tags"])) if e["tags"] else ""
            print("  %-4s %-7s %-8s %s%s" % (e["id"], e["status"] or "?", e["type"] or "?", e["title"], tags))
    else:
        print("\nevals: ещё нет")
    if f["state"]:
        s = f["state"]
        print("\nцикл: %s · раунд %s из %s · база %s" % (
            s.get("loop", "?"), s.get("round", "?"), s.get("max_rounds", "5"), s.get("base_commit", "?")))
    print("\nследующий шаг: %s" % sl.next_step(f, sl.list_features(ROOT)))


def cmd_check(name):
    f = get_feature(name)
    problems = sl.check_feature(f, sl.project_platform(ROOT))
    if problems:
        fail("%s: %d проблем(ы):\n- %s" % (f["id"], len(problems), "\n- ".join(problems)))
    print("%s: проверка пройдена (%d evals, риск %s)." % (f["id"], len(f["evals"]), f["risk"]))


def cmd_set_status(name, status):
    if status not in sl.STATUSES:
        fail("Неизвестный статус «%s». Допустимо: %s" % (status, " → ".join(sl.STATUSES)))
    f = get_feature(name)
    current = f["status"]
    if status in ("in-review", "approved"):
        problems = sl.check_feature(f, sl.project_platform(ROOT))
        if problems:
            fail("Нельзя перевести %s в %s — сначала исправь:\n- %s" % (f["id"], status, "\n- ".join(problems)))
    if status == "approved" and current != "in-review":
        fail("Одобрить можно только фичу в статусе in-review (сейчас %s)." % current)
    if status == "building" and current not in ("approved", "building", "verified", "done"):
        fail("Нельзя строить %s без одобренных evals (сейчас %s): /write-evals → /approve → /review-loop."
             % (f["id"], current))
    if status in ("verified", "done"):
        failing = sl.failing_evals(f)
        if not f["evals"] or failing:
            fail("Нельзя ставить %s: не пройдены evals %s." % (status, ", ".join(e["id"] for e in failing) or "(нет evals)"))

    path = f["dir"] / "requirements.md"
    text = sl.set_frontmatter_field(sl.read_text(path), "status", status)
    if status in ("approved", "done"):
        text = sl.set_frontmatter_field(text, "%s_at" % status, datetime.date.today().isoformat())
    path.write_text(text, encoding="utf-8")
    print("%s: %s → %s" % (f["id"], current, status))


def main(argv):
    if not argv or argv[0] in ("status", "table"):
        return cmd_table()
    cmd, args = argv[0], argv[1:]
    if cmd == "show" and len(args) == 1:
        return cmd_show(args[0])
    if cmd == "check" and len(args) == 1:
        return cmd_check(args[0])
    if cmd == "set-status" and len(args) == 2:
        return cmd_set_status(args[0], args[1])
    fail(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
