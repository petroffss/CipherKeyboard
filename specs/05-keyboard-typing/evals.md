# Evals: Набор текста внутри клавиатуры

> Все проверки pending до независимого verifier. Имена новых тестов — контракт для builder; файлы чистой модели размещаются в тестовом таргете выбранного локального модуля.

## E1 · Редактор и курсор
- **Тип:** test
- **Шаги:** KeyboardInputTests.swift › insertsAtGraphemeBoundary: вставить «Привет», поставить курсор после «При», вставить «X», Enter, пробел; удалить перед курсором.
- **Ожидается:** Текст точно соответствует последовательности; курсор всегда на границе Character, поле хозяина не требуется.
- **Почему провалит плохую работу:** ловит редактор, который всегда дописывает в конец.
- **Статус:** pass
- **Доказательство:** Round4 2c7726e/source956018778 insertsAtGraphemeBoundary: exact text/cursor; current independent core15typing+135core,exit0; evidence/verifier-round4/core.log.

## E2 · Точные страницы
- **Тип:** test
- **Шаги:** KeyboardInputTests.swift › layoutsAndTransitions: сравнить массивы всех четырёх страниц с таблицей требований; переключить язык и страницы с непустым текстом и курсором в середине.
- **Ожидается:** Ряды совпадают полностью; курсор и текст сохранены; возврат по АБВ/ABC и смена языка соответствуют AC2.
- **Почему провалит плохую работу:** ловит отсутствующие символы и потерю текста.
- **Статус:** pass
- **Доказательство:** Round4 2c7726e/source956018778 layoutsAndTransitions: all4exactpages/transitions,text+cursor preserved; core15+135,exit0; evidence/verifier-round4/core.log.

## E3 · Регистр
- **Тип:** test
- **Шаги:** KeyboardInputTests.swift › shiftStateMachine: начало, после newline/. /! /? , середина слова; Shift off, цифра, пробел, буква; двойное нажатие 299 и 301 мс; Caps через смену языка.
- **Ожидается:** Автоматический и одноразовый регистры соответствуют AC3; 299 включает Caps, 301 не включает; буква расходует one-shot, цифра и пробел нет.
- **Почему провалит плохую работу:** ловит декоративный Shift и всегда заглавную букву.
- **Статус:** pass
- **Доказательство:** Round4 2c7726e/source956018778 shiftStateMachine: auto/one-shot/Caps,299/301ms,explicitoff andpage transitions; core15+135,exit0; evidence/verifier-round4/core.log.

## E4 · Альтернативы и отмена [negative]
- **Тип:** test
- **Шаги:** KeyboardGestureTests.swift › alternateTimingAndCancellation: управляемые часы 449/450 мс для е/ь в обоих регистрах; отпускание внутри/снаружи, скрытие и поворот.
- **Ожидается:** 449 даёт основную букву; 450 и отпускание внутри — только ё/ъ; отмена ничего не вставляет и не оставляет активный таймер.
- **Почему провалит плохую работу:** ловит двойной ввод основной и альтернативной буквы.
- **Статус:** pass
- **Доказательство:** Round4 2c7726e/source956018778 alternateTimingAndCancellation:449/450ms,е/ь,bothcases,inside/outside/hide/rotate,zero timers; core15+135,exit0; evidence/verifier-round4/core.log.

## E5 · Удаление целых символов [negative]
- **Тип:** test
- **Шаги:** KeyboardInputTests.swift › deletesCharacters: по одному удалить e+combining acute, 👍🏽, 🇷🇺, 👨‍👩‍👧‍👦; повторить в начале непустого поля и в пустом.
- **Ожидается:** Каждый пример удаляется целиком за одно действие, текст справа от курсора сохраняется, в начале нет изменений.
- **Почему провалит плохую работу:** ловит удаление UTF-16 единиц и порчу emoji.
- **Статус:** pass
- **Доказательство:** Round4 2c7726e/source956018778 deletesCharacters: composed/skin-tone/flag/ZWJ whole Character,beginning unchanged; core15+135,exit0; evidence/verifier-round4/core.log.

## E6 · Повтор удаления
- **Тип:** test
- **Шаги:** KeyboardGestureTests.swift › repeatStops: удержать на 399/400/480 мс; отпустить, отменить, скрыть; продвинуть часы ещё на секунду.
- **Ожидается:** Удалений соответственно 1/2/3; после остановки ни одного нового; удержание прочих обычных клавиш не повторяет ввод.
- **Почему провалит плохую работу:** ловит неотменённый таймер.
- **Статус:** pass
- **Доказательство:** Round4 2c7726e/source956018778 repeatStops:399/400/480ms counts1/2/3,cancellation/hide stop timers,ordinarykeys no repeat; evidence/verifier-round4/core.log,exit0.

## E7 · Байтовая граница [negative]
- **Тип:** test
- **Шаги:** KeyboardInputTests.swift › utf8Limit: ASCII и кириллица на 3500/3501/4096 байтах; попытаться добавить букву, Enter, ё и emoji сверх4096 с курсором в середине; удалить.
- **Ожидается:** Счётчик только >3500; 4096 допустимы; переполнение отклонено целиком с точным текстом AC11 и неизменным курсором; удаление снимает ошибку.
- **Почему провалит плохую работу:** ловит подсчёт букв вместо байтов и частичное принятие.
- **Статус:** pass
- **Доказательство:** Round4 2c7726e/source956018778 utf8Limit:3500/3501/4096 boundaries,atomic rejection/cursor unchanged,exacterror,deletion reset; evidence/verifier-round4/core.log,exit0.

## E8 · Изоляция от хозяина [security]
- **Тип:** test
- **Шаги:** KeyboardIsolationTests.swift › noHostProxyCalls: spy всех чтений контекста, insertText/deleteBackward/adjustTextPosition; выполнить все действия модели и UI adapter, включая пустое удаление и Enter.
- **Ожидается:** Ноль чтений контекста и ноль перечисленных вызовов; проверен production adapter, а не отдельная заглушка.
- **Почему провалит плохую работу:** ловит скрытые вызовы proxy при Backspace.
- **Статус:** pass
- **Доказательство:** Round4 2c7726e/source956018778 Production controller/panel/adapter proxy-spy UI passed in full suite andclean3/3;0calls; evidence/verifier-round4/full-ui-first-case-results.json,clean-supplement-tests.json.

## E9 · Превью общим компонентом
- **Тип:** ui
- **Шаги:** UITests/KeyboardTypingTests.swift › testPreviewTyping: открыть через кнопку в подключении; нажать реальные клавиши «Привет», Enter, сменить язык; закрыть и открыть снова. Не применять typeText вместо клавиш.
- **Ожидается:** Тексты AC10, поле «До встречи!» неизменно; набор работает, повторное открытие пустое; нет второй клавиатуры и глобуса, статус подключения не изменён.
- **Почему провалит плохую работу:** ловит картинку вместо общей клавиатуры.
- **Статус:** pass
- **Доказательство:** Round4 2c7726e/source956018778 Real preview-key typing/reset/status/fingerprint/proxy-host invariance passed full UI andclean3/3 onfresh device withkeyboardneverenabled; evidence/verifier-round4/clean-supplement-summary.json.

## E10 · Настоящее расширение [security]
- **Тип:** ui
- **Шаги:** В чистом временном симуляторе включить расширение; Debug-хозяин: пустое поле, затем «До встречи!» с выделением; полный доступ on/off. В каждом варианте набрать, удалить, Enter, сменить страницы, удержать е/ь; повторить набор в обычном приложении.
- **Ожидается:** Черновик меняется внутри панели, текст и диапазон выделения хозяина неизменны; работает и без доступа; подтверждение подключения не содержит черновик.
- **Почему провалит плохую работу:** ловит успех только внутри preview.
- **Статус:** pass
- **Доказательство:** Round4 2c7726e/source956018778 Independent runtime7/7,exit0: actualFullAccessON/OFF×empty/selected host,full sequence,unchangedhost text+selection,ordinarySettings; receipt onlydate/version; evidence/verifier-round4/runtime-summary.json,receipt-schema.json.

## E11 · Стирание и поворот [negative] [security]
- **Тип:** ui
- **Шаги:** В расширении набрать уникальную синтетическую строку. По отдельности скрыть, уйти в фон, переключить глобусом; открыть вновь. Повторить preview: назад, другая вкладка, фон. Отдельно повернуть хозяина при активном черновике.
- **Ожидается:** После закрытий пусто, русский и auto Shift; поворот сохраняет текст/курсор и отменяет незавершённые жесты; отложенный ввод не появляется.
- **Почему провалит плохую работу:** ловит сохранение состояния живущего процесса.
- **Статус:** pass
- **Доказательство:** Round4 2c7726e/source956018778 Runtime actualhide/focusfalse/panelabsence/reopen,rotation,background/globe reset; realpreviewback/tab/background andcoretimercancel passed; evidence/verifier-round4/runtime-summary.json,clean-supplement-summary.json,core.log.

## E12 · Нет экспорта или записи [security]
- **Тип:** ui
- **Шаги:** Задать синтетический clipboard sentinel; набрать другой уникальный canary; долго нажать поле, попробовать копирование/drag. Сравнить app/extension/group files, defaults, keychain metadata и логи до/после. Проверить пути записи кодом.
- **Ожидается:** Нет меню экспорта/вставки и drag-export, clipboard неизменен; canary нигде не записан. Ключи/контакты неизменны; допустима только штатная запись даты/версии подключения04 без текста.
- **Почему провалит плохую работу:** ловит утечку через стандартный UITextView и логи.
- **Статус:** pass
- **Доказательство:** Round4 2c7726e/source956018778 Finalsource isolatedauditPASS:setup2/2+canary1/1,actualsentineltrueboth,knownidentity1rowboth withattributes-only proof,15files/metadata/defaults/clipboard unchanged exceptdate/versionreceipt,no canary/logmatches; evidence/verifier-round4/audit/result.json.

## E13 · Статусы не блокируют набор [negative]
- **Тип:** ui
- **Шаги:** Debug fixtures: нет доступа, нет ключа, ошибка ключа, ошибка контактов, обычный доступ. В каждом ввести и удалить текст; spies фабрик хранилища при no-access.
- **Ожидается:** Точные предупреждения AC9; набор во всех случаях; no-access не создаёт фабрик чтения общих хранилищ; расширение не создаёт ключ.
- **Почему провалит плохую работу:** ловит регрессию защит02–04.
- **Статус:** pass
- **Доказательство:** Round4 2c7726e/source956018778 Runtime five-status scenario passed;typed/deleted each,host unchanged,no-accessreaders0; lazyfactory coretest passed; evidence/verifier-round4/runtime-summary.json,core.log.

## E14 · Все состояния и размеры [design]
- **Тип:** design
- **Шаги:** Скриншоты всех16 якорей mockup.html на375/402/440 в обеих темах; расширение также667/874/956 landscape. Сравнить с каждой соответствующей рамкой. Проверить popup, четыре строки, прокрутку и ошибку лимита.
- **Ожидается:** Блоки/тексты/цвета совпадают; четыре ряда целиком, safe area учтена, ограничения размеров AC8 выполнены; буквы≥26pt, высоты≥44/32; нет переполнения или скачка счётчика. Preview только портрет.
- **Почему провалит плохую работу:** ловит проверку лишь одного удобного размера.
- **Статус:** fail
- **Доказательство:** Round4 2c7726e/source956018778 FAIL:78/186unique pairs(all78reviewed),108missing;375completed62,402coordinator-canceled16,440notcaptured. D1uppercase multiline/limit,D2mutedwarnings,D3darkpreviewactuallylight,D4hostfieldhiddenlandscape. Strictexport1,matrix75; evidence/verifier-round4/design-review.json,fix-list.md.

## E15 · Доступность и системный глобус
- **Тип:** ui
- **Шаги:** Accessibility Inspector/XCUITest: пройти управляющие клавиши, Shift/Caps, альтернативы; сравнить needsInputModeSwitchKey true/false; нажать/удержать собственный глобус.
- **Ожидается:** Имена/состояния/IDs из AC12 доступны; собственный глобус только при true, вызывает стандартное переключение/список; двойного глобуса нет.
- **Почему провалит плохую работу:** ловит недоступные символы и тупиковый переключатель.
- **Статус:** pass
- **Доказательство:** Round4 2c7726e/source956018778 Actual controller labels/ShiftCaps/hints/customactions/needsInputModeSwitchKey probe passed; real375globe hold/list/switch passed; metadata375own=true,402own=false,previewfalse; evidence/verifier-round4/accessibility-frame-metadata.json,runtime-summary.json,clean-supplement-summary.json.

## E16 · Нагрузка и жизненный цикл
- **Тип:** test
- **Шаги:** KeyboardLifecycleTests.swift › stressAndReset: 500 фиксированных операций сравнить с эталонной строкой; 10 show/hide, удержание delete с отменой. Ту же короткую последовательность прогнать preview/extension.
- **Ожидается:** Результаты точно совпадают, нет crash/hang; после закрытия активных повторов0; одинаковый ввод даёт одинаковый черновик в обеих оболочках.
- **Почему провалит плохую работу:** ловит гонки и различающиеся реализации.
- **Статус:** pass
- **Доказательство:** Round4 2c7726e/source956018778 stressAndReset500actions/10resets/0timers plusindependent overlappingtouch tests passed; actualpreview/extension parity passed; evidence/verifier-round4/core.log,runtime-summary.json.

## E17 · Регрессии и Release
- **Тип:** command
- **Шаги:** scripts/test.sh core; scripts/test.sh ui; scripts/lint.sh; scripts/build.sh. Собрать Release и проверить отсутствие Debug host/seed/diagnostics и запрещённых сетевых API; сохранить команды и результаты.
- **Ожидается:** Все тесты и команды завершаются0; Debug/Release собираются, новые тесты реально выполнены; Release не открывает тестовые пути.
- **Почему провалит плохую работу:** ловит непроверенные тесты и диагностический доступ в релизе.
- **Статус:** fail
- **Доказательство:** Round4 2c7726e/source956018778 FAIL:fullunfilteredUI29pass/1fail/0skip,exit65(Contactstestexpectsapp.keyboards whileCipherpanelpresent). Cleancontrol3/3 doesNOTreplacefullsuite;canceledcleanfullretry0tests/75. Core150/lint67/Debug+Release+binaryaudit pass; evidence/verifier-round4/report.md.

## Покрытие
AC1: E1,E9,E14; AC2: E2,E10; AC3: E3; AC4: E4,E10; AC5: E5,E6; AC6: E8,E10,E12; AC7: E11,E12,E16; AC8: E14; AC9: E10,E13,E15; AC10: E9; AC11: E7,E14; AC12: E15,E16.
