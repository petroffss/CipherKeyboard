---
name: approve
description: Одобрение пользователем. Фича в in-review → approved (evals и макет одобрены, можно строить). Фича в verified → done (результат принят, ветка вливается в main). Вызывает только пользователь.
argument-hint: "<фича>"
disable-model-invocation: true
---

# /approve — решение пользователя

Фича: $ARGUMENTS

Пользователь сам вызвал эту команду — это и есть его одобрение. Сначала `python3 .claude/scripts/pipeline.py show <фича>`, дальше по статусу.

## in-review → approved (контракт одобрен)
1. `python3 .claude/scripts/pipeline.py check <фича>`. Есть проблемы — покажи их и остановись: битый контракт не одобряем.
2. Если в requirements.md остались «Открытые вопросы» — перечисли их и спроси, одобрять ли так (AskUserQuestion).
3. `python3 .claude/scripts/pipeline.py set-status <фича> approved`.
4. Коммит в текущую ветку: `git add specs/<фича> && git commit -m "[ok] specs(<фича>): evals одобрены"`.
5. Следующий шаг: `/review-loop <фича>`.

## verified → done (результат принят)
1. Убедись, что все evals `pass`, а в `specs/<фича>/state.md` стоит `loop: done`.
2. Риск high и нет `specs/<фича>/ftue-report.md` → напомни, что для high тест первого пользователя обязателен, и спроси: сначала `/first-time-user <фича>` или принять так.
3. Влей ветку: `git switch main && git merge --no-ff feature/<фича> -m "[ok] feature(<фича>): <название>"`. Конфликт — остановись и покажи, что конфликтует.
4. `python3 .claude/scripts/pipeline.py set-status <фича> done` и коммит `[ok] <фича>: принята`.
5. Сообщи sha merge-коммита и как откатить всю фичу: `git revert -m 1 <sha>`.
6. Если в state.md остались неразобранные «Кандидаты в выученные правила» — предложи их (по одной строке) для REVIEW.md и добавь только одобренные.
7. Следующий шаг — из `python3 .claude/scripts/pipeline.py`.

## Другие статусы
Ничего не меняй. Объясни, чего не хватает, и назови следующий шаг из `pipeline.py show`.
