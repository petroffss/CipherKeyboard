"""Общий разбор спецификаций для хуков и .claude/scripts/pipeline.py.

Фича — это папка specs/NN-name/:
  requirements.md  frontmatter (status, risk, ui, …) + требования
  evals.md         проверки: заголовок `## E1 · Название [теги]` и поля `- **Ключ:** значение`
  mockup.html      эталон дизайна (если ui: yes)
  state.md         состояние цикла /review-loop (frontmatter: loop, round, …)
Папки, начинающиеся с `_` или `.`, фичами не считаются (например specs/_design).
"""
import os
import re
from pathlib import Path

STATUSES = ["draft", "in-review", "approved", "building", "verified", "done"]
RISKS = ["low", "medium", "high"]
PLATFORMS = ["web", "ios", "android", "desktop", "cli", "api"]
# ui — сценарий в интерфейсе: браузер для web, симулятор/эмулятор для мобильных, окно для desktop
EVAL_TYPES = ["ui", "test", "command", "design", "api"]
EVAL_TYPE_ALIASES = {"browser": "ui", "simulator": "ui", "emulator": "ui", "e2e": "ui"}
EVAL_STATUSES = ["pending", "pass", "fail"]

# Минимум evals и обязательных тегов по риску: чем дороже ошибка, тем строже контракт.
MINIMUMS = {
    "low": {"total": 3, "negative": 0, "security": 0},
    "medium": {"total": 5, "negative": 1, "security": 0},
    "high": {"total": 8, "negative": 2, "security": 1},
}

FIELD_ALIASES = {
    "тип": "type", "type": "type",
    "шаги": "steps", "steps": "steps", "команда": "steps", "command": "steps",
    "ожидается": "expected", "ожидаемый результат": "expected", "expected": "expected",
    "почему провалит плохую работу": "why", "why": "why",
    "статус": "status", "status": "status",
    "доказательство": "evidence", "evidence": "evidence",
    "теги": "tags", "tags": "tags",
}
REQUIRED_FIELDS = [
    ("type", "Тип"),
    ("steps", "Шаги"),
    ("expected", "Ожидается"),
    ("why", "Почему провалит плохую работу"),
    ("status", "Статус"),
]

PLATFORM_RE = re.compile(r"^[ \t>*-]*\**Платформа\**[ \t]*:?\**[ \t]*:?[ \t]*`?([A-Za-z]+)", re.M)
FRONTMATTER_RE = re.compile(r"\A---[ \t]*\n(.*?)\n---[ \t]*(?:\n|\Z)", re.S)
EVAL_HEAD_RE = re.compile(r"^##[ \t]+(E\d+)\b(.*)$", re.M)
FIELD_RE = re.compile(r"^[ \t]*[-*][ \t]*\*\*([^*]+?)\*\*[ \t]*:?[ \t]*(.*)$")
TAG_RE = re.compile(r"\[([A-Za-z0-9_-]+)\]")


def project_root(hook_input=None):
    root = os.environ.get("CLAUDE_PROJECT_DIR") or (hook_input or {}).get("cwd") or os.getcwd()
    return Path(root).resolve()


def read_text(path):
    try:
        return Path(path).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return ""


def project_platform(root):
    """Платформа из строки `Платформа: ios` в CLAUDE.md; web, если не указана."""
    m = PLATFORM_RE.search(read_text(Path(root) / "CLAUDE.md"))
    platform = m.group(1).lower() if m else ""
    return platform if platform in PLATFORMS else "web"


# ---------- frontmatter ----------

def parse_frontmatter(text):
    m = FRONTMATTER_RE.match(text or "")
    if not m:
        return {}
    fm = {}
    for line in m.group(1).splitlines():
        if not line.strip() or line.lstrip().startswith("#") or ":" not in line:
            continue
        key, value = line.split(":", 1)
        value = re.sub(r"\s+#.*$", "", value).strip().strip("\"'")
        fm[key.strip()] = value
    return fm


def set_frontmatter_field(text, key, value):
    """Меняет (или добавляет) `key: value` во frontmatter, сохраняя комментарий в конце строки."""
    m = FRONTMATTER_RE.match(text)
    if not m:
        return "---\n%s: %s\n---\n%s" % (key, value, text)
    body = m.group(1)
    line_re = re.compile(r"^(%s:[ \t]*)([^#\n]*?)([ \t]+#.*)?$" % re.escape(key), re.M)
    if line_re.search(body):
        body = line_re.sub(lambda mm: mm.group(1) + value + (mm.group(3) or ""), body, count=1)
    else:
        body += "\n%s: %s" % (key, value)
    return text[:m.start(1)] + body + text[m.end(1):]


def parse_list(value):
    value = (value or "").strip().strip("[]")
    return [v.strip().strip("\"'") for v in value.split(",") if v.strip()]


# ---------- evals ----------

def _first_word(value):
    words = re.findall(r"[A-Za-zА-Яа-яЁё-]+", value or "")
    return words[0].lower() if words else ""


def parse_evals(text):
    evals = []
    heads = list(EVAL_HEAD_RE.finditer(text or ""))
    for i, head in enumerate(heads):
        end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        body = text[head.end():end]
        other_heading = re.search(r"^#{1,2}[ \t]", body, re.M)
        if other_heading:
            body = body[:other_heading.start()]

        fields, current = {}, None
        for line in body.splitlines():
            m = FIELD_RE.match(line)
            if m:
                current = FIELD_ALIASES.get(m.group(1).strip().rstrip(":").strip().lower())
                if current and current not in fields:
                    fields[current] = m.group(2).strip()
                elif current:
                    current = None
            elif current and line[:1] in (" ", "\t") and line.strip():
                fields[current] = (fields[current] + " " + line.strip()).strip()

        tags = {t.lower() for t in TAG_RE.findall(head.group(2))}
        tags |= {t.lower() for t in TAG_RE.findall(fields.get("tags", ""))}
        tags |= {t.strip().lower() for t in re.split(r"[,\s]+", fields.get("tags", "")) if re.fullmatch(r"[A-Za-z_-]+", t.strip())}
        eval_type = _first_word(fields.get("type"))
        evals.append({
            "id": head.group(1),
            "title": TAG_RE.sub("", head.group(2)).strip(" ·-—:\t"),
            "fields": fields,
            "tags": tags,
            "type": EVAL_TYPE_ALIASES.get(eval_type, eval_type),
            "status": _first_word(fields.get("status")),
        })
    return evals


def lint_evals(evals, risk=None, ui=False, strict=True, platform="web"):
    """Список проблем evals.md. strict=False — только структура (пока фича в draft).
    [mobile] обязателен только для web: там одна вёрстка на два размера экрана."""
    if not evals:
        return ["нет ни одного eval — заголовок каждого должен выглядеть так: `## E1 · Название [теги]`"]
    problems, seen = [], set()
    for e in evals:
        eid = e["id"]
        if eid in seen:
            problems.append("%s: номер повторяется" % eid)
        seen.add(eid)
        for key, label in REQUIRED_FIELDS:
            if not e["fields"].get(key):
                problems.append("%s: нет поля `- **%s:** …`" % (eid, label))
        if e["type"] and e["type"] not in EVAL_TYPES:
            problems.append("%s: тип «%s», допустимо: %s" % (eid, e["type"], ", ".join(EVAL_TYPES)))
        if e["fields"].get("status") and e["status"] not in EVAL_STATUSES:
            problems.append("%s: статус «%s», допустимо: %s" % (eid, e["status"], ", ".join(EVAL_STATUSES)))
    if not strict:
        return problems

    if risk not in MINIMUMS:
        problems.append("риск фичи не определён (risk: %s) — сначала оцени его скиллом classify-risk" % (risk or "—"))
    else:
        need = MINIMUMS[risk]
        if len(evals) < need["total"]:
            problems.append("для риска %s нужно минимум %d evals, сейчас %d" % (risk, need["total"], len(evals)))
        for tag in ("negative", "security"):
            have = sum(1 for e in evals if tag in e["tags"])
            if have < need[tag]:
                problems.append("для риска %s нужно минимум %d eval(s) с тегом [%s], сейчас %d" % (risk, need[tag], tag, have))
    if ui:
        if not any("design" in e["tags"] or e["type"] == "design" for e in evals):
            problems.append("у фичи есть интерфейс (ui: yes) — нужен eval сравнения с макетом: тег [design]")
        if platform == "web" and not any("mobile" in e["tags"] for e in evals):
            problems.append("веб-фича с интерфейсом — нужен eval мобильного вида: тег [mobile]")
    return problems


# ---------- requirements ----------

def lint_requirements(fm, text, strict=True):
    problems = []
    if not fm:
        return ["нет frontmatter (блок между `---` в начале файла) — возьми его из шаблона requirements.md"]
    for key in ("feature", "title", "status", "risk", "ui"):
        if key not in fm:
            problems.append("frontmatter: нет поля `%s`" % key)
    if fm.get("status") and fm["status"] not in STATUSES:
        problems.append("status «%s», допустимо: %s" % (fm["status"], " → ".join(STATUSES)))
    if fm.get("risk") and fm["risk"] not in RISKS + ["unknown"]:
        problems.append("risk «%s», допустимо: low, medium, high (или unknown до оценки)" % fm["risk"])
    if fm.get("ui") and fm["ui"].lower() not in ("yes", "no"):
        problems.append("ui «%s», допустимо: yes или no" % fm["ui"])
    if strict:
        if fm.get("risk") not in RISKS:
            problems.append("риск не определён — оцени его скиллом classify-risk")
        section = re.search(r"^##[ \t]+Критерии приёмки[^\n]*\n(.*?)(?=^##[ \t]|\Z)", text, re.S | re.M)
        if not section or not re.search(r"^[ \t]*[-*]", section.group(1), re.M):
            problems.append("раздел `## Критерии приёмки` пуст или отсутствует")
    return problems


# ---------- фичи ----------

def load_feature(fdir):
    fdir = Path(fdir)
    req_text = read_text(fdir / "requirements.md")
    fm = parse_frontmatter(req_text)
    evals_text = read_text(fdir / "evals.md")
    return {
        "id": fdir.name,
        "dir": fdir,
        "title": fm.get("title") or fdir.name,
        "status": fm.get("status") or ("draft" if req_text else "—"),
        "risk": fm.get("risk") or "unknown",
        "ui": (fm.get("ui") or "no").lower() in ("yes", "true", "да"),
        "depends_on": parse_list(fm.get("depends_on")),
        "fm": fm,
        "req_text": req_text,
        "has_requirements": bool(req_text),
        "has_evals": bool(evals_text.strip()),
        "evals": parse_evals(evals_text),
        "state": parse_frontmatter(read_text(fdir / "state.md")),
        "has_mockup": (fdir / "mockup.html").exists(),
    }


def list_features(root):
    specs = Path(root) / "specs"
    if not specs.is_dir():
        return []
    dirs = [d for d in sorted(specs.iterdir()) if d.is_dir() and not d.name.startswith(("_", "."))]
    return [load_feature(d) for d in dirs]


def find_feature(root, name):
    name = (name or "").strip().strip("/")
    if name.startswith("specs/"):
        name = name[len("specs/"):]
    feats = list_features(root)
    for pick in (
        lambda f: f["id"] == name,
        lambda f: re.sub(r"^\d+-", "", f["id"]) == name,
        lambda f: name and name in f["id"],
    ):
        found = [f for f in feats if pick(f)]
        if len(found) == 1:
            return found[0]
    return None


def feature_of_path(root, path):
    """specs/<id>/<file> → (папка фичи, имя файла); иначе (None, None)."""
    if not path:
        return None, None
    try:
        rel = Path(path).resolve().relative_to(Path(root).resolve())
    except ValueError:
        return None, None
    parts = rel.parts
    if len(parts) == 3 and parts[0] == "specs" and not parts[1].startswith(("_", ".")):
        return Path(root) / "specs" / parts[1], parts[2]
    return None, None


def failing_evals(feature):
    return [e for e in feature["evals"] if e["status"] != "pass"]


def check_feature(feature, platform="web"):
    """Полная проверка перед ревью/одобрением."""
    problems = lint_requirements(feature["fm"], feature["req_text"], strict=True)
    problems += lint_evals(feature["evals"], feature["risk"], feature["ui"], strict=True, platform=platform)
    if feature["ui"] and not feature["has_mockup"]:
        problems.append("ui: yes, но нет mockup.html — эталона дизайна")
    return problems


def next_step(feature, all_features=None):
    fid, status, risk = feature["id"], feature["status"], feature["risk"]
    if not feature["has_requirements"]:
        return "/write-evals %s" % fid
    if status == "draft":
        return "/write-evals %s" % fid
    if status == "in-review":
        return "посмотри requirements, evals и макет → /approve %s (или напиши правки)" % fid
    if status == "approved":
        waiting = [d for d in feature["depends_on"]
                   if all_features and any(f["id"] == d and f["status"] != "done" for f in all_features)]
        if waiting:
            return "сначала закончи %s, потом /review-loop %s" % (", ".join(waiting), fid)
        return "/review-loop %s" % fid
    if status == "building":
        loop = feature["state"].get("loop")
        if loop in ("needs-human", "stopped"):
            return "цикл ждёт твоего решения — specs/%s/state.md, затем /review-loop %s" % (fid, fid)
        return "/review-loop %s (продолжить)" % fid
    if status == "verified":
        if risk == "high":
            return "/first-time-user %s, затем /approve %s" % (fid, fid)
        return "проверь руками → /approve %s" % fid
    if status == "done":
        return "готово"
    return "/pipeline"


def evals_summary(feature):
    total = len(feature["evals"])
    passed = sum(1 for e in feature["evals"] if e["status"] == "pass")
    return "%d/%d" % (passed, total) if total else "—"
