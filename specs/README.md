# specs/ — фичи проекта

Каждая фича — папка `NN-name/` (номер задаёт порядок). Папки на `_` фичами не считаются.

| Файл | Кто пишет | Что это |
|---|---|---|
| `requirements.md` | `/kickoff`, `/write-evals` | требования + статус и риск во frontmatter |
| `evals.md` | `/write-evals`; статусы — только агент verifier | контракт приёмки: фича готова, когда все evals `pass` |
| `mockup.html` | `/write-evals` | эталон дизайна: все состояния экрана, десктоп и мобильный |
| `state.md` | `/review-loop` | раунды цикла, открытые проблемы, журнал |
| `ftue-report.md` | `/first-time-user` | отчёт «первого пользователя» |
| `evidence/` | verifier | доказательства (скриншоты, выводы) — в git не попадают |

`_design/design.md` — общий дизайн (палитра, шрифты, компоненты), его создаёт первый макет.

Статусы: `draft → in-review → approved → building → verified → done`.
Таблица всех фич: `python3 .claude/scripts/pipeline.py` или `/pipeline`.
