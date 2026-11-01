# Evals: Набор текста внутри клавиатуры

> Все проверки pending до независимого verifier. Имена новых тестов — контракт для builder; файлы чистой модели размещаются в тестовом таргете выбранного локального модуля.

## E1 · Редактор и курсор
- **Тип:** test
- **Шаги:** KeyboardInputTests.swift › insertsAtGraphemeBoundary: вставить «Привет», поставить курсор после «При», вставить «X», Enter, пробел; удалить перед курсором.
- **Ожидается:** Текст точно соответствует последовательности; курсор всегда на границе Character, поле хозяина не требуется.
- **Почему провалит плохую работу:** ловит редактор, который всегда дописывает в конец.
- **Статус:** pass
- **Доказательство:** Round5 1db6b7e/source248220564 insertsAtGraphemeBoundary exact text/cursor; independent core15typing+135core exit0; core.log. evidence/verifier-round5/.

## E2 · Точные страницы
- **Тип:** test
- **Шаги:** KeyboardInputTests.swift › layoutsAndTransitions: сравнить массивы всех четырёх страниц с таблицей требований; переключить язык и страницы с непустым текстом и курсором в середине.
- **Ожидается:** Ряды совпадают полностью; курсор и текст сохранены; возврат по АБВ/ABC и смена языка соответствуют AC2.
- **Почему провалит плохую работу:** ловит отсутствующие символы и потерю текста.
- **Статус:** pass
- **Доказательство:** Round5 1db6b7e/source248220564 layoutsAndTransitions all4exactpages/transitions, text+cursor preserved; core150 exit0; core.log. evidence/verifier-round5/.

## E3 · Регистр
- **Тип:** test
- **Шаги:** KeyboardInputTests.swift › shiftStateMachine: начало, после newline/. /! /? , середина слова; Shift off, цифра, пробел, буква; двойное нажатие 299 и 301 мс; Caps через смену языка.
- **Ожидается:** Автоматический и одноразовый регистры соответствуют AC3; 299 включает Caps, 301 не включает; буква расходует one-shot, цифра и пробел нет.
- **Почему провалит плохую работу:** ловит декоративный Shift и всегда заглавную букву.
- **Статус:** pass
- **Доказательство:** Round5 1db6b7e/source248220564 shiftStateMachine auto/one-shot/Caps,299/301ms,explicitoff/page transitions; core150 exit0; core.log. evidence/verifier-round5/.

## E4 · Альтернативы и отмена [negative]
- **Тип:** test
- **Шаги:** KeyboardGestureTests.swift › alternateTimingAndCancellation: управляемые часы 449/450 мс для е/ь в обоих регистрах; отпускание внутри/снаружи, скрытие и поворот.
- **Ожидается:** 449 даёт основную букву; 450 и отпускание внутри — только ё/ъ; отмена ничего не вставляет и не оставляет активный таймер.
- **Почему провалит плохую работу:** ловит двойной ввод основной и альтернативной буквы.
- **Статус:** pass
- **Доказательство:** Round5 1db6b7e/source248220564 alternateTimingAndCancellation449/450ms,bothcases,inside/outside/hide/rotate/zero timers; core.log exit0. evidence/verifier-round5/.

## E5 · Удаление целых символов [negative]
- **Тип:** test
- **Шаги:** KeyboardInputTests.swift › deletesCharacters: по одному удалить e+combining acute, 👍🏽, 🇷🇺, 👨‍👩‍👧‍👦; повторить в начале непустого поля и в пустом.
- **Ожидается:** Каждый пример удаляется целиком за одно действие, текст справа от курсора сохраняется, в начале нет изменений.
- **Почему провалит плохую работу:** ловит удаление UTF-16 единиц и порчу emoji.
- **Статус:** pass
- **Доказательство:** Round5 1db6b7e/source248220564 deletesCharacters whole composed/skin-tone/flag/ZWJ, beginning unchanged; core.log exit0. evidence/verifier-round5/.

## E6 · Повтор удаления
- **Тип:** test
- **Шаги:** KeyboardGestureTests.swift › repeatStops: удержать на 399/400/480 мс; отпустить, отменить, скрыть; продвинуть часы ещё на секунду.
- **Ожидается:** Удалений соответственно 1/2/3; после остановки ни одного нового; удержание прочих обычных клавиш не повторяет ввод.
- **Почему провалит плохую работу:** ловит неотменённый таймер.
- **Статус:** pass
- **Доказательство:** Round5 1db6b7e/source248220564 repeatStops399/400/480ms counts1/2/3, cancellation/hide stop, ordinarykeys no repeat; core.log exit0. evidence/verifier-round5/.

## E7 · Байтовая граница [negative]
- **Тип:** test
- **Шаги:** KeyboardInputTests.swift › utf8Limit: ASCII и кириллица на 3500/3501/4096 байтах; попытаться добавить букву, Enter, ё и emoji сверх4096 с курсором в середине; удалить.
- **Ожидается:** Счётчик только >3500; 4096 допустимы; переполнение отклонено целиком с точным текстом AC11 и неизменным курсором; удаление снимает ошибку.
- **Почему провалит плохую работу:** ловит подсчёт букв вместо байтов и частичное принятие.
- **Статус:** pass
- **Доказательство:** Round5 1db6b7e/source248220564 utf8Limit3500/3501/4096 atomic rejection/cursor unchanged/exacterror/deletion reset; core.log exit0. evidence/verifier-round5/.

## E8 · Изоляция от хозяина [security]
- **Тип:** test
- **Шаги:** KeyboardIsolationTests.swift › noHostProxyCalls: spy всех чтений контекста, insertText/deleteBackward/adjustTextPosition; выполнить все действия модели и UI adapter, включая пустое удаление и Enter.
- **Ожидается:** Ноль чтений контекста и ноль перечисленных вызовов; проверен production adapter, а не отдельная заглушка.
- **Почему провалит плохую работу:** ловит скрытые вызовы proxy при Backspace.
- **Статус:** pass
- **Доказательство:** Round5 1db6b7e/source248220564 Actual production controller/panel/adapter proxy-spy UI passed in unfiltered clean30;0calls; full-ui-case-results.json. evidence/verifier-round5/.

## E9 · Превью общим компонентом
- **Тип:** ui
- **Шаги:** UITests/KeyboardTypingTests.swift › testPreviewTyping: открыть через кнопку в подключении; нажать реальные клавиши «Привет», Enter, сменить язык; закрыть и открыть снова. Не применять typeText вместо клавиш.
- **Ожидается:** Тексты AC10, поле «До встречи!» неизменно; набор работает, повторное открытие пустое; нет второй клавиатуры и глобуса, статус подключения не изменён.
- **Почему провалит плохую работу:** ловит картинку вместо общей клавиатуры.
- **Статус:** pass
- **Доказательство:** Round5 1db6b7e/source248220564 Real previewkeys/Back/tab/background/reset/status/fingerprint/host invariance passed full unfiltered30 on BRANDNEW clean E0F7device, extensionneverenabled; full-ui-summary.json. evidence/verifier-round5/.

## E10 · Настоящее расширение [security]
- **Тип:** ui
- **Шаги:** В чистом временном симуляторе включить расширение; Debug-хозяин: пустое поле, затем «До встречи!» с выделением; полный доступ on/off. В каждом варианте набрать, удалить, Enter, сменить страницы, удержать е/ь; повторить набор в обычном приложении.
- **Ожидается:** Черновик меняется внутри панели, текст и диапазон выделения хозяина неизменны; работает и без доступа; подтверждение подключения не содержит черновик.
- **Почему провалит плохую работу:** ловит успех только внутри preview.
- **Статус:** pass
- **Доказательство:** Round5 1db6b7e/source248220564 Runtime7/7 exit0; actualSettingsFullAccessON/OFF xempty/selectedhost, sequence/ordinarySettings, unchangedhost text+selection; receipt onlydate/version; runtime-summary.json,receipt-schema.json. evidence/verifier-round5/.

## E11 · Стирание и поворот [negative] [security]
- **Тип:** ui
- **Шаги:** В расширении набрать уникальную синтетическую строку. По отдельности скрыть, уйти в фон, переключить глобусом; открыть вновь. Повторить preview: назад, другая вкладка, фон. Отдельно повернуть хозяина при активном черновике.
- **Ожидается:** После закрытий пусто, русский и auto Shift; поворот сохраняет текст/курсор и отменяет незавершённые жесты; отложенный ввод не появляется.
- **Почему провалит плохую работу:** ловит сохранение состояния живущего процесса.
- **Статус:** pass
- **Доказательство:** Round5 1db6b7e/source248220564 Actual hide focus=false/panelabsent/reopen,rotation,background/globe andpreviewBack/tab/background resets passed; corecancel/zero timers; runtime-summary.json,full-ui-case-results.json,core.log. evidence/verifier-round5/.

## E12 · Нет экспорта или записи [security]
- **Тип:** ui
- **Шаги:** Задать синтетический clipboard sentinel; набрать другой уникальный canary; долго нажать поле, попробовать копирование/drag. Сравнить app/extension/group files, defaults, keychain metadata и логи до/после. Проверить пути записи кодом.
- **Ожидается:** Нет меню экспорта/вставки и drag-export, clipboard неизменен; canary нигде не записан. Ключи/контакты неизменны; допустима только штатная запись даты/версии подключения04 без текста.
- **Почему провалит плохую работу:** ловит утечку через стандартный UITextView и логи.
- **Статус:** pass
- **Доказательство:** Round5 1db6b7e/source248220564 IsolatedauditPASS setup2/2+canary1/1: actualsentineltrueboth, exactknown1identityattribute-onlyproof,15files/defaults/metadata/clipboard unchanged exceptdate/versionreceipt, no canary/logmatches,no reinstall between; audit/result.json. evidence/verifier-round5/.

## E13 · Статусы не блокируют набор [negative]
- **Тип:** ui
- **Шаги:** Debug fixtures: нет доступа, нет ключа, ошибка ключа, ошибка контактов, обычный доступ. В каждом ввести и удалить текст; spies фабрик хранилища при no-access.
- **Ожидается:** Точные предупреждения AC9; набор во всех случаях; no-access не создаёт фабрик чтения общих хранилищ; расширение не создаёт ключ.
- **Почему провалит плохую работу:** ловит регрессию защит02–04.
- **Статус:** pass
- **Доказательство:** Round5 1db6b7e/source248220564 Runtimefive-status typed/deleted each, exactwarnings/no-accessreaders0, hostunchanged; lazyfactorycorepass; runtime-summary.json,core.log. evidence/verifier-round5/.

## E14 · Все состояния и размеры [design]
- **Тип:** design
- **Шаги:** Скриншоты всех16 якорей mockup.html на375/402/440 в обеих темах; расширение также667/874/956 landscape. Сравнить с каждой соответствующей рамкой. Проверить popup, четыре строки, прокрутку и ошибку лимита.
- **Ожидается:** Блоки/тексты/цвета совпадают; четыре ряда целиком, safe area учтена, ограничения размеров AC8 выполнены; буквы≥26pt, высоты≥44/32; нет переполнения или скачка счётчика. Preview только портрет.
- **Почему провалит плохую работу:** ловит проверку лишь одного удобного размера.
- **Статус:** fail
- **Доказательство:** Round5 1db6b7e/source248220564 FAIL D5:186/186freshuniqueactualpairs andall186individuallyreviewedpass, actualtheme/host48pt/caret/style checks pass; actualscroll/caretpass. Normal375preview real5lineinputclipsAC10instruction,2settledframes gui20/gui21; design-review.json,fix-list.md. evidence/verifier-round5/.

## E15 · Доступность и системный глобус
- **Тип:** ui
- **Шаги:** Accessibility Inspector/XCUITest: пройти управляющие клавиши, Shift/Caps, альтернативы; сравнить needsInputModeSwitchKey true/false; нажать/удержать собственный глобус.
- **Ожидается:** Имена/состояния/IDs из AC12 доступны; собственный глобус только при true, вызывает стандартное переключение/список; двойного глобуса нет.
- **Почему провалит плохую работу:** ловит недоступные символы и тупиковый переключатель.
- **Статус:** pass
- **Доказательство:** Round5 1db6b7e/source248220564 Actual production labels/ShiftCaps/hints/IDs/needsInputModeSwitchKeytruefalse probe passed full30; realglobehold/list/switch runtimepass;375owntrue,402/440systemonly,previewfalse; runtime-summary.json,matrix-integrity.json. evidence/verifier-round5/.

## E16 · Нагрузка и жизненный цикл
- **Тип:** test
- **Шаги:** KeyboardLifecycleTests.swift › stressAndReset: 500 фиксированных операций сравнить с эталонной строкой; 10 show/hide, удержание delete с отменой. Ту же короткую последовательность прогнать preview/extension.
- **Ожидается:** Результаты точно совпадают, нет crash/hang; после закрытия активных повторов0; одинаковый ввод даёт одинаковый черновик в обеих оболочках.
- **Почему провалит плохую работу:** ловит гонки и различающиеся реализации.
- **Статус:** pass
- **Доказательство:** Round5 1db6b7e/source248220564 stressAndReset500actions/10resets/0timers+overlappingtouchtests passed; actualpreview/extension parity runtimepass; core.log,runtime-summary.json. evidence/verifier-round5/.

## E17 · Регрессии и Release
- **Тип:** command
- **Шаги:** scripts/test.sh core; scripts/test.sh ui; scripts/lint.sh; scripts/build.sh. Собрать Release и проверить отсутствие Debug host/seed/diagnostics и запрещённых сетевых API; сохранить команды и результаты.
- **Ожидается:** Все тесты и команды завершаются0; Debug/Release собираются, новые тесты реально выполнены; Release не открывает тестовые пути.
- **Почему провалит плохую работу:** ловит непроверенные тесты и диагностический доступ в релизе.
- **Статус:** pass
- **Доказательство:** Round5 1db6b7e/source248220564 PASS fullUNFILTERED30pass0fail0skip exit0 onBRANDNEW E0F7 cleanneverextensionenabled; exact30uniqueIDs. Core150/lint67/explicitDebugRelease exit0, Release0of24Debugmarkers/network0,actual4entitlementslices; full-ui-contract-coverage.json,release-binary-audit.json. evidence/verifier-round5/.

## Покрытие
AC1: E1,E9,E14; AC2: E2,E10; AC3: E3; AC4: E4,E10; AC5: E5,E6; AC6: E8,E10,E12; AC7: E11,E12,E16; AC8: E14; AC9: E10,E13,E15; AC10: E9; AC11: E7,E14; AC12: E15,E16.
