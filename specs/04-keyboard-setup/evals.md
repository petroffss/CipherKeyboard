# Evals: Подключение клавиатуры

Все статусы pending до независимой проверки. Имена новых тестов задают контракт для реализации.

## E1 · Модель состояний [negative, security]
- **Тип:** test
- **Шаги:** SetupStateTests.swift › resolvesStates: absent/present/unknown список × missing/valid/corrupt/future отметка; exact id и похожий id.
- **Ожидается:** Absent → инструкции; present+valid и unknown+valid → проверено ранее; present+missing → нужен показ; unknown+missing → неопределённость; corrupt/future не дают успех (уточнение 2026-11-04: список клавиатур недоступен, отметка расширения — единственный источник).
- **Почему провалит плохую работу:** Ловит ложное подтверждение и совпадения по подстроке.
- **Статус:** pass
- **Доказательство:** SetupStateTests: independent 5/5 pass, including 3x5 presence/record matrix, exact/prefix/suffix IDs and both durable-cutoff failure regressions; evidence/verifier/cipher-setup-verifier-core-final.log. Core unchanged in final 65f4865.

## E2 · Отметка разрешения [negative, security]
- **Тип:** test
- **Шаги:** SetupStateTests.swift › recordsOnlySuccessfulAccess: fake writer, hasFullAccess false/true, ошибка записи.
- **Ожидается:** При false нет обращения к контейнеру; true пишет только version/date; сбой не меняет ключи/контакты и не подтверждает запись.
- **Почему провалит плохую работу:** Ловит запись без доступа и лишние данные.
- **Статус:** pass
- **Доказательство:** recordsOnlySuccessfulAccess + fileRoundTripAndRemoval pass: false factoryCalls=0; true JSON keys exactly version/date; failed write preserves bytes, no reads/removes; evidence/verifier/cipher-setup-verifier-core-final.log. Real App Group evidence also in E8.

## E3 · Настройка и переход с Мой ключ
- **Тип:** test
- **Шаги:** UITests/SetupUITests.swift › testStatesAndBanner: debug absent/present-unconfirmed/confirmed/unknown; нажать баннер, раскрыть шаги.
- **Ожидается:** Точные тексты AC1–6/8, баннер ведёт на Настройка; подтверждение явно историческое, шаги доступны.
- **Почему провалит плохую работу:** Ловит заглушку вкладки и неверный переход.
- **Статус:** pass
- **Доказательство:** Final 65f4865 testStatesAndBanner PASS in /tmp/cipher-setup-f1f2-402-light.xcresult (2/2 with design); all four states, banner navigation, historical note, expanded steps including approved steps 1/4. Screens: evidence/verifier/final-402-light/.

## E4 · Возврат из настроек [negative]
- **Тип:** test
- **Шаги:** SetupUITests.swift › testRefreshOnForeground: изменить fake reader между background/foreground, включая удаление и повторное добавление.
- **Ожидается:** Состояние обновляется без перезапуска; удаление сбрасывает отметку, повторное добавление не даёт успех.
- **Почему провалит плохую работу:** Ловит кеширование навсегда.
- **Статус:** pass
- **Доказательство:** testRefreshOnForeground PASS: .build/TestResults/ui-20261101-133214.xcresult (Setup+Smoke 4/4, zero skipped). Real remove/readd foreground transitions also PASS /tmp/cipher-setup-real-revoke.xcresult; evidence/verifier/real-revoke/.

## E5 · Открытие настроек и отказ [negative]
- **Тип:** test
- **Шаги:** SetupUITests.swift › testOpenSettingsFailure: injected opener success/false; нажать Открыть Настройки.
- **Ожидается:** Вызывается только UIApplication.openSettingsURLString; false показывает текст и ручной путь AC10.
- **Почему провалит плохую работу:** Ловит неработающую кнопку и молчаливый отказ.
- **Статус:** pass
- **Доказательство:** testOpenSettingsFailure PASS in targeted 402 3/3 and final 375 4/4; injected true validates UIApplication.openSettingsURLString, false shows exact error/manual path. Actual public Settings launch: evidence/verifier/real-entry/; final error layouts: evidence/verifier/final-375-light/ and final-402-dark/.

## E6 · Настоящее подключение [security]
- **Тип:** ui
- **Шаги:** Чистый временный симулятор: создать ключ; открыть Настройка, перейти в системные настройки, включить расширение, открыть в Settings search без полного доступа; затем включить доступ и открыть снова; вернуться в приложение.
- **Ожидается:** Без доступа точный баннер AC7 и рабочая 🌐; с доступом расширение записывает отметку, приложение показывает AC3 и пояснение о последней проверке.
- **Почему провалит плохую работу:** Инъекции не доказывают обмен между процессами.
- **Статус:** pass
- **Доказательство:** Real temporary 402: initially 3 system keyboards/no mark; add extension with Full Access=0, exact denial banner and working globe; enable actual switch+Allow, extension shows key 94A0 0DCF and writes mark, app foreground shows confirmed+historical note. evidence/verifier/real-add/, real-globe/, real-full-access/; /tmp/cipher-setup-real-access.xcresult PASS.

## E7 · Отзыв и удаление [negative, security]
- **Тип:** ui
- **Шаги:** После E6 отключить Full Access, открыть расширение, затем приложение; удалить клавиатуру, вернуться, добавить заново.
- **Ожидается:** Расширение показывает запрет; приложение не заявляет текущее разрешение по старой отметке. При доступном списке удаление/повторное добавление выполняют AC8; при недоступном списке явная неопределённость.
- **Почему провалит плохую работу:** Ловит ложный зелёный статус после отзыва.
- **Статус:** pass
- **Доказательство:** Real revoke/remove/readd 2/2 PASS: denial after access=0, app keeps explicit historical note; deletion returns to instructions and removes mark; readd needs new opening. Fingerprint unchanged. /tmp/cipher-setup-real-revoke.xcresult; evidence/verifier/real-revoke/ and after-remove-readd.json.

## E8 · Содержимое App Group [security]
- **Тип:** command
- **Шаги:** После E6 прочитать запись проверки в контейнере временного устройства; сравнить файлы личности/контактов до и после.
- **Ожидается:** Только version/date; ключи и контакты неизменны; ввод/буфер не сохранены; нет новых сетевых API, scripts/lint.sh успешен.
- **Почему провалит плохую работу:** Ловит утечки и побочные изменения.
- **Статус:** pass
- **Доказательство:** Real record only {version:1,date:815221674.514603}; contacts SHA256 ad0a8e1924109b70d5631ea12d2803af39bc06291922eb82cb3a8a89a32ee5f9 unchanged, full fingerprint unchanged, no input/clipboard files. Final lint OK 48 files. evidence/verifier/keyboard-access-after-full.json, cipher-setup-e8-baseline.json, cipher-setup-e8-after-full.json and cipher-setup-f1f2-lint.log.

## E9 · Все состояния дизайна [design]
- **Тип:** design
- **Шаги:** Снять все state-* макета на 375×667 и 402×874 в светлой/тёмной теме; прокрутить до конца, раскрыть шаги.
- **Ожидается:** Точные тексты, порядок блоков, системная палитра; кнопки ≥44 pt, отсутствие обрезки/перекрытия; пояснение о последней проверке видно.
- **Почему провалит плохую работу:** Ловит потерю важных предупреждений на узком экране.
- **Статус:** pass
- **Доказательство:** All 7 mockup states inspected at 375x667/402x874, light/dark: original 52 app captures + real keyboard captures; final 65f4865 changed-step matrix 28 captures (absent, confirmed collapsed/expanded, error), all four app runs PASS. Controls >=44, scroll reveals all text, historical note readable. evidence/verifier/design-*/, final-*/, keyboard-375-real/, keyboard-375-light-final/, 402-*-keyboard-no-access.png.

## E10 · Регрессии и Release [security]
- **Тип:** command
- **Шаги:** scripts/test.sh core; scripts/test.sh ui; scripts/lint.sh; scripts/build.sh; Release build и strings по именам новых debug flags.
- **Ожидается:** Все проверки успешны, debug flags и fake storage отсутствуют в Release; 02/03 продолжают работать.
- **Почему провалит плохую работу:** Ловит сломанные предыдущие сценарии и тестовые обходы в релизе.
- **Статус:** pass
- **Доказательство:** Core 135/135; final Debug build and lint48 PASS; independent final65f4865 Release build exit0 and all 5 debug markers absent in app+extension. Full402:25 old+2 new PASS, sole ancestor-ID failure fixed and Setup3/3 rerun PASS; final375 Setup+Smoke4/4, updatedE3 PASS. Extra legacy toast375 FAILED (cause not fully established), separately documented in evidence/verifier/README.md; not claimed all375UI green. Logs/scans in evidence/verifier/.

## E11 · Отметка расширения при недоступном списке клавиатур [regression, security]
- **Тип:** test
- **Шаги:** `scripts/test.sh core --filter 'SetupStateTests'` — resolvesStates (матрица unknown × отметка) и unknownListTrustsExtensionRecordButNotOldEvidence; затем `scripts/test.sh ui -only-testing:CipherKeyboardUITests/SetupUITests` и реальная проверка: включить клавиатуру с полным доступом, открыть её, вернуться в приложение.
- **Ожидается:** При `presence == .unknown` действительная отметка даёт `.confirmed(date)`, отсутствие отметки — `.unknown`; отметка старше сохранённой или сеансовой отсечки удаления даёт `.needsOpening`, нечитаемая отсечка — `.unknown`; удаление в сеансе с последующим unknown не оживляет отметку. В production (без чтения `AppleKeyboards`) приложение после реального показа расширения с полным доступом показывает «Подключение проверено» с исторической пометкой; до показа — «Не удалось проверить подключение». SetupUITests testRefreshOnForeground по-прежнему проходит.
- **Почему провалит плохую работу:** ловит возврат раннего `return .unknown`, из-за которого одобренное состояние «Подключение проверено» было недостижимо после правок 2026-11-04, и ловит оживление удалённой отметки отсечками.
- **Статус:** pending
- **Доказательство:** —
