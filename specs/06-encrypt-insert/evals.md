# Evals: Шифрование и вставка в сообщение

> Контракт приёмки. Все статусы сейчас pending; pass/fail и доказательства ставит только независимый verifier. Имена новых тестов ниже — требования к реализации, сейчас этих тестов нет. Одобрение контракта не является приёмкой реализации.

## E1 · Выбор контакта сохраняет черновик и курсор 
- **Тип:** ui
- **Шаги:** Настоящее расширение в Debug-хозяине, Full Access, личный ключ и 20 синтетических контактов с известными UUID/ключами. Ввести «Привет, Анна!», поставить внутренний курсор после «Привет», открыть keyboard.recipient, прокрутить к последнему контакту, выбрать его; снова открыть и нажать «Назад».
- **Ожидается:** Порядок совпадает с ContactBook, в строках имя и короткий отпечаток; выбранная строка отмечена. Выбор закрывает список, имя обновляется. Назад не меняет выбор. Черновик и курсор неизменны; поле хозяина/выделение не менялись. Первоначально получатель не выбран даже при одном контакте. AC1, AC14.
- **Почему провалит плохую работу:** Ловит декоративный список, потерю черновика и автоматический выбор первого контакта.
- **Статус:** pass
- **Доказательство:** Independent actual extension rev1531367603: first unselected screenshot/AX retained from e1-live partial (observer queried removed row after tap); corrected e1-replay completed 1/1 PASS with exact draft, cursor6, all20 ContactBook rows/order, last UUID/selected, Back and unchanged host selection. See specs/06-encrypt-insert/evidence/verifier-round1-functional/e1-first-unselected.png and .build/IndependentEncryptR1/Functional/e1-replay.log; full installed app/extension/host bytes matched in runtime-e1-byteproof.json.

## E2 · Восстановление только актуального id [security]
- **Тип:** test
- **Шаги:** Написать Packages/CipherCore/Tests/KeyboardTypingTests/EncryptInsertTests.swift: rememberedRecipientID. Выбрать B, закрыть и открыть новую сессию; переименовать B с тем же ключом и снова открыть. Удалить B, добавить другой контакт с таким же именем и новым UUID; открыть. Проверить записи spy preferences.
- **Ожидается:** Восстанавливается только B по UUID; переименование обновляет имя. После удаления выбор пуст, одноимённый контакт не подставляется, сохранённый id сброшен. Единственная записанная величина — UUID; нет имени/ключа/черновика/шифротекста. AC2.
- **Почему провалит плохую работу:** Ловит выбор по имени, индексу или устаревшему объекту и лишнее постоянное хранение.
- **Статус:** pass
- **Доказательство:** Independent SHA6aa22f9/rev1531367603: EncryptInsertTests.rememberedRecipientID PASS; UUID/nil only, rename and removal; .build/IndependentEncryptR1/Functional/core.log (162=27+135 PASS).

## E3 · Пустой и пробельный текст не шифруется [negative]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: eligibility. Матрица текстов "", " ", "\n\t ", "\u{00A0}", " а\n "; с получателем и без, с готовыми хранилищами и с unavailable/missing. Попытаться вызвать действие напрямую, обходя disabled UI.
- **Ожидается:** Пустые/whitespacesAndNewlines: 0 seal, 0 proxy. Без получателя/ключа тоже 0. Непустой « а\n » зашифровывается без trim и нормализации. UI disabled совпадает с координатором. AC3.
- **Почему провалит плохую работу:** Ловит защиту только цветом кнопки, проверку isEmpty и незаметное изменение сообщения.
- **Статус:** pass
- **Доказательство:** Independent EncryptInsertTests.eligibility PASS: 30 text/selection/identity combinations, direct action, exact whitespace UTF-8 round-trip; .build/IndependentEncryptR1/Functional/core.log.

## E4 · Настоящее расширение вставляет одну строку в курсор [security]
- **Тип:** ui
- **Шаги:** Установить замороженную Debug-сборку, сопоставить SHA/хеш встроенного и установленного extension и runtime revision. Debug-хозяин: «До |встречи!» с пустым выделением. Набрать внутри «Привет, Анна!», выбрать Анну, нажать «Зашифровать». Записать proxy trace и итог хозяина. Повторить короткий сценарий в обычном поле приложения симулятора, например поиске Настроек.
- **Ожидается:** Единственная вставка C начинается ckmsg1:, является полной строкой без пробелов/CR/LF/многоточия и открывается ядром. Итог «До »+C+«встречи!»; префикс/суффикс сохранены. Нет deleteBackward/adjustTextPosition/первоначальной вставки открытого текста, автоматической отправки или clipboard. Сначала поле хозяина неизменно при наборе. Черновик пуст после возврата insertText. AC5, AC6.
- **Почему провалит плохую работу:** Ловит успех только в учебном превью/spy, старую установленную сборку и перезапись поля.
- **Статус:** pass
- **Доказательство:** Actual frozen extension8/8 + supplemental literal4/4 PASS: exact literal draft kept out of host until one canonical ASCII C, host prefix/suffix preserved at cursor3, insertions1/deletions0/replacements0; ordinary Settings C separately self-opens as real Keychain A. 11 canonical native C open as B. Clipboard audit PASS. See evidence/verifier-round1-functional/literal-inserted-host.txt; evidence/verifier-round1-functional/roundtrip-proof-scope.json; evidence/verifier-round1-functional/canonical-roundtrip.log; evidence/verifier-round1-functional/runtime-final-byteproof.json; A coverage limitation remains E5 fail.

## E5 · Вставленное сообщение открывают только нужные ключи [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: insertedCiphertextRoundTrip. Взять именно аргумент proxy из интеграции координатора с настоящим CipherMessage.seal, а также строку из E4. Открыть как B (выбранный), A (отправитель), C (посторонний); у B проверить contacts с A и без A. Повторить с пробелами, переносами и Unicode.
- **Ожидается:** A и B получают точные исходные байты UTF-8, полный senderKey равен A. У B sender.contact соответствует A, без контакта sender.unknown; у A sender.me. C: CipherError.notARecipient. Нет использования фиктивного sealer в этом тесте. AC10.
- **Почему провалит плохую работу:** Ловит шифрование статичного текста, не тому контакту или без добавления себя.
- **Статус:** fail
- **Доказательство:** Coverage gap on frozen SHA6aa22f9: actual Keychain sender A self-open is retained only for the separate Settings ciphertext with fixed text Cyrillic A. DEBUG openInserted rejects every other expected plaintext by its fixed guard; it cannot prove actual A opens native host hello/4096/literal E4 ciphertexts. Unit fixture A and app-controller proxy roundtrip are separate evidence, not substitutes. B/known-unknown/C checks are retained independently. This is missing contract proof, not a demonstrated decryption vulnerability. See .build/IndependentEncryptR1/Functional/encrypt-runtime.log, App/KeyboardEncryptProbe.swift openInserted, and evidence/verifier-round1-functional/report.md.

## E6 · Непустое выделение хозяина сохраняется [negative]
- **Тип:** ui
- **Шаги:** В Debug-хозяине выделить «встречи» в «До встречи!», ввести приватный черновик, выбрать контакт и нажать «Зашифровать». Снять выделение и повторить. Отдельно начать шифрование без выделения с управляемой задержкой и создать выделение до commit; эта попытка тоже не должна заменять текст.
- **Ожидается:** Первая попытка: 0 вставок/удалений/сдвигов, исходные текст и выделение хозяина сохранены, черновик/курсор сохранены, «Снимите выделение в поле сообщения». После снятия выделения новая явная попытка вставляет один шифротекст. AC5.
- **Почему провалит плохую работу:** Ловит стандартную замену выделенного текста через insertText и тихую потерю текста хозяина.
- **Статус:** pass
- **Доказательство:** Independent core selectionRechecked + actual extension testSelectionAndSuccessGeometry/testDoubleTapDelayedSelectionAndCancellation PASS in completed runtime8/8; selection refusal preserves host/draft, new explicit action inserts once; .build/IndependentEncryptR1/Functional/encrypt-runtime-summary.json and encrypt-runtime.log.

## E7 · Два нажатия дают одну вставку [negative]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: singleFlight. Управляемый sealer задержать, нажать дважды; попытаться набрать/удалить/сменить получателя, завершить sealer, снова нажать без ввода; затем ввести новый текст и нажать ещё раз. Параллельный UI-сценарий двойного касания в Debug-хозяине.
- **Ожидается:** В задержке «Шифруем…», кнопка/ввод/выбор заблокированы. До завершения 1 seal, после него ровно 1 insertText исходного снимка. Повтор без текста: 0 новых вставок. Новый непустой черновик шифруется один раз новым действием. AC7.
- **Почему провалит плохую работу:** Ловит debounce только на времени, гонку двух задач и навсегда заблокированную кнопку.
- **Статус:** pass
- **Доказательство:** Independent core singleFlight PASS and completed actual extension delayed double-tap/cancellation runtime PASS8/8: busy/input/recipient disabled, one actual host trace insertion, no hidden replay; .build/IndependentEncryptR1/Functional/core.log and encrypt-runtime.log.

## E8 · Ошибка не теряет текст и допускает повтор [negative]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: failurePreservesDraft. По отдельности identity missing, unavailable и sealer throws; полный доступ есть, текст и внутренний курсор известны. Для unavailable убрать сбой и повторить. Проверить missing также в настоящем расширении чистой песочницы; ошибки — через Debug-only dependency, затем проверить её отсутствие в Release.
- **Ожидается:** До вставки 0 proxy. Текст/курсор прежние. missing: «Откройте приложение CipherKeyboard, чтобы создать ключ»; unavailable: «Ключ недоступен — откройте приложение CipherKeyboard»; seal failure: «Не удалось зашифровать сообщение. Повторите попытку». Повтор после восстановления даёт одну вставку. Ключ не создаётся/не пересоздаётся. AC8.
- **Почему провалит плохую работу:** Ловит очистку в defer, молчаливую ошибку, plaintext fallback и генерацию нового ключа.
- **Статус:** pass
- **Доказательство:** Core failurePreservesDraft PASS for missing/unavailable/throw with cursor preserved/retry; actual native fault recovery in runtime8/8. Truly clean extension NoKey1/1 PASS with real Full Access, no container-app launch, missing-key message, typing enabled/encrypt disabled, host unchanged; Keychain identity metadata0 before/after. Release hooks absent. See evidence/verifier-round1-functional/nokey-after-identity-byteproof.json, nokey-real.png, core.log, release-inspection.json.

## E9 · Границы UTF-8 и независимая проверка длины [negative]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: utf8Boundaries. 3500/3501/4096/4097 байт ASCII и кириллица/emoji с известным utf8.count; счётчик проверить в настоящем расширении. 4096 байт зашифровать настоящим ядром. Ввод ещё одного символа отвергнуть; отдельно тестовым входом передать координатору 4097 байт, не меняя Release-лимит модели ввода.
- **Ожидается:** Счётчик только N>3500: «N / 4096 байт». 4096 байт открываются точно; сверхлимитный ввод целиком отклонён: «Сообщение не должно превышать 4096 байт». Защитный вход 4097: 0 proxy, неизменные текст/курсор, «Слишком длинное сообщение: 4097 из 4096 байт». AC9.
- **Почему провалит плохую работу:** Ловит подсчёт Character вместо байтов и отсутствие проверки длины вне UI.
- **Статус:** pass
- **Доказательство:** Core UTF-8 ASCII/Cyrillic/emoji3500/3501/4096/4097 and defensive4097 PASS; actual normal4096 input+counter retained, whole extra Cyrillic insertion rejected with exact limit message/cursor unchanged in supplemental4/4. Actual4096 C opens exactly in independent canonical B proof11/11. See evidence/verifier-round1-functional/core.log; evidence/verifier-round1-functional/normal-4096-rejection.png; evidence/verifier-round1-functional/live-additional.log; evidence/verifier-round1-functional/canonical-roundtrip.log.

## E10 · Удалённый или подменённый контакт не получает сообщение [negative] [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: recipientRevalidation. Выбрать B; после показа панели удалить его, заменить ключ под прежним UUID, вернуть unreadable; повторить каждую мутацию после начала задержанного seal до commit. Отдельно переименовать при неизменных UUID и обеих частях полного ключа. Проверить refresh при открытии списка.
- **Ожидается:** Удаление/замена ключа: 0 вставок, выбор и remembered id сброшены, «Данные изменились — выберите получателя заново»; до старта также нельзя молча принять новый ключ. Unreadable: 0 вставок, «Не удалось прочитать контакты», Повторить; повторное чтение восстанавливает доступность только для проверенного контакта. Переименование обновляет имя, адресат прежний. AC2, AC4.
- **Почему провалит плохую работу:** Ловит TOCTOU между выбором и вставкой, равенство только short fingerprint и доверие старому списку.
- **Статус:** pass
- **Доказательство:** Independent EncryptInsertTests.recipientRevalidation PASS: pre/during-seal removal, agreement/signing full-key mutation, unreadable/retry, rename; .build/IndependentEncryptR1/Functional/core.log.

## E11 · Смена личного ключа отменяет операцию [negative] [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: identityRevalidation. Начать seal как A, перед завершением заменить identity на A2 с другим полным public key либо сделать чтение unavailable/missing.
- **Ожидается:** 0 proxy. При A2 выбор сброшен и «Данные изменились — выберите получателя заново». При unavailable/missing соответствующая ошибка AC8. В активной сессии текст/курсор сохранены. Нет подписи неожиданной новой личностью. AC4, AC8.
- **Почему провалит плохую работу:** Ловит использование старого key snapshot без проверки и тихую смену отправителя.
- **Статус:** pass
- **Доказательство:** Direct contract mutations EncryptInsertTests.identityRevalidation PASS (A2/missing/unavailable/signing-only), 0 proxy; .build/IndependentEncryptR1/Functional/core.log. Supplemental recovery A-to-missing/unavailable-to-A2 violates AC4: .build/IndependentEncryptR1/Functional/identity-recovery-repro.log; important R1 remains open and blocks E20.

## E12 · Полный доступ проверяется в момент действия [negative] [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: accessGate. При hasFullAccess=false вызвать open/select/encrypt с reader/storage spies. Затем начать операцию с true, отозвать доступ до commit. В настоящем расширении отдельно включить и выключить Full Access в Settings; после возврата проверить панель и возможность набора.
- **Ожидается:** Без доступа 0 чтений/записей общих хранилищ и remembered preferences, выбор/шифрование disabled, баннер «Включите «Полный доступ» в Настройках, чтобы шифровать»; набор работает. После отзыва 0 вставок и больше нет обращений к защищённым хранилищам. AC11.
- **Почему провалит плохую работу:** Ловит guard только при запуске и debug fixture вместо настоящего системного разрешения.
- **Статус:** pass
- **Доказательство:** Independent core accessGate/noAccessNeverConstructsSharedReaders PASS; complete real KeyboardRuntimeTests7/7 PASS on rev1531367603, actual Settings Full Access OFF/ON switch+editing scenarios, real denied banner and typing preserved. See .build/IndependentEncryptR1/Functional/typing-runtime-summary.json and specs/06-encrypt-insert/evidence/verifier-round1-functional/actual-full-access-OFF.png plus actual-extension-access-OFF.png; runtime OS appearance readback light.

## E13 · Закрытие и смена документа не переносят результат [negative] [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: sessionAndDocumentCancellation. Задержать seal и по отдельности: hide, background, globe, смена documentIdentifier, поворот. Завершить старую задачу после открытия новой сессии/поля. Проверить также закрытие сразу после уже выполненного insertText. В реальном расширении пройти hide/reopen и переключение между двумя полями Debug-хозяина.
- **Ожидается:** Hide/background/globe: черновик очищен, отложенный результат 0 proxy в старом/новом поле, новая сессия пустая. Смена документа при активной сессии: 0 вставок, текст сохранён, «Поле сообщения изменилось — повторите попытку». Поворот: текст/получатель сохраняются, ≤1 вставки. Закрытие после вставки не вызывает повтор при открытии. AC12.
- **Почему провалит плохую работу:** Ловит поздний completion в чужой документ и повторную отправку после reopen.
- **Статус:** pass
- **Доказательство:** Independent core cancellation PASS; actual runtime8/8 and typing7/7 cover hide/reopen, background, globe, rotation, two fields and no automatic replay. Supplemental actual A-to-B-to-A: B visible, A returned, switches1.087/1.807s within2s delay; original host unchanged, document-changed error, no trace mutation. See evidence/verifier-round1-functional/transient-document-probe.txt and runtime/typing logs.

## E14 · Успех и полоса статуса без скачка 
- **Тип:** ui
- **Шаги:** В реальном расширении зашифровать короткий текст для Анны; снять кадр и геометрию до, после и через 2 секунды (допуск наблюдения 0,3 секунды). Начать новый ввод. Длинное имя отдельно.
- **Ожидается:** После возврата вставки пустой черновик/нулевой курсор, выбранная Анна остаётся, «Зашифровано для Анна» показывается 2 секунды, затем обычный статус. Геометрия редактора/клавиш/поля хозяина не меняется из-за смены статуса. Новый ввод работает. Полное длинное имя доступно VoiceOver. AC6.
- **Почему провалит плохую работу:** Ловит toast поверх клавиш, исчезающий layout slot и очистку до успешной передачи.
- **Статус:** pass
- **Доказательство:** Actual runtime success geometry PASS; supplemental full40-character recipient success AX/cursor0 PASS. Corrected production-clock observer1/1 PASS: observed positive-to-negative1.8164s, conservative lifetime bounds incl snapshot/activity rounding1.749..2.148s within1.7..2.3; all frame arrays equal before/success/ordinary. Failed tap-origin observer retained separately. See evidence/verifier-round1-functional/success-clock-bounds.json; evidence/verifier-round1-functional/success-clock-observation.txt; evidence/verifier-round1-functional/success-full-long-name-AX.txt; evidence/verifier-round1-functional/live-clock-replay.log.

## E15 · Приватность доказана до и после успеха и ошибки [security]
- **Тип:** command
- **Шаги:** На одном замороженном SHA расширить/использовать scripts/typing-audit.sh для сценариев 06. До прогона подтвердить установленный синтетический clipboard sentinel, известную непустую identity и видимость её Keychain metadata; задать уникальный синтетический черновик. Пройти набор, выбор, успех, сбой и закрытие. Сравнить clipboard, файлы App Group/контейнеров, UserDefaults, Keychain metadata и логи. Проанализировать все новые insertText/deleteBackward/adjustTextPosition/UIPasteboard/print/Logger/os_log/NSLog/UserDefaults/FileManager и reader/writer зависимости.
- **Ожидается:** Exit 0, audit prerequisites pass. Sentinel неизменен, нет сохранённого черновика/шифротекста/приватных ключей или новых Keychain items, кроме заранее созданной identity. Разрешён только UUID выбора в локальных preferences и существующий setup marker 04. Spy доказывает единственный выход шифротекста через insertText и отсутствие plaintext proxy; поиск строки дополняет проверку, не заменяет её. Никаких сетевых API/новых permissions. AC2, AC5, AC11.
- **Почему провалит плохую работу:** Ловит ложное «утечки не нашли» с пустым Keychain/clipboard и хранение plaintext вне проверяемой модели.
- **Статус:** pass
- **Доказательство:** Strictly isolated encrypt-audit exit0/PASS: actual sentinel before/after unchanged, real nonempty identity metadata1 before/after, setupFailures[], failures[], unexpectedChanges[], canaryMatches[]; only existing group/keyboard-access.v1.json changed. Shipping-controller spy33-test suite proves insertText1/context0/delete0/adjust0; source boundary/UUID audit retained. See evidence/verifier-round1-functional/audit-result.json; evidence/verifier-round1-functional/audit-before.json; evidence/verifier-round1-functional/audit-after.json; evidence/verifier-round1-functional/privacy-sites.md.

## E16 · Подмена сообщения и отправителя отклоняется [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: tamperedInsertedMessage и существующие adversarial tests CipherCore. Для реального результата координатора изменить байт ciphertext, подпись, заменить sender key; при необходимости переподписать подменённым ключом, как в тестах ядра. Ввести недопустимый публичный ключ через недоверенный источник контактов.
- **Ожидается:** Ни один изменённый вариант не открывается как исходное доверенное сообщение; malformed/tampered/invalidKey согласно границе проверки. Недопустимый ключ не ведёт к вставке или plaintext fallback. Факт подписи привязан к полному senderKey. AC4, AC10.
- **Почему провалит плохую работу:** Ловит обход проверок ядра или собственный несовместимый формат в адаптере клавиатуры.
- **Статус:** pass
- **Доказательство:** Independent tamperedInsertedMessage and adversarial CipherCore PASS; both executables 162/162=27+135; altered bytes/signature/sender and invalid public key rejected; .build/IndependentEncryptR1/Functional/core.log.

## E17 · Все состояния совпадают с макетом [design]
- **Тип:** design
- **Шаги:** Сравнить каждый из 126 кадров с specs/06-encrypt-insert/mockup.html: все 17 state-* в портрете 375/402/440 обе темы (102); ready/picker/limit/long-name в альбоме 667/874/956 обе темы (24). Состояния fixture только Debug; реальная панель extension и системные safe areas. Дать manifest ожидаемых/полученных кадров и индивидуальный результат просмотра каждого.
- **Ожидается:** 126 уникальных кадров, ни одного missing. Все состояния/точные тексты из AC1–AC14, порядок и цвета соответствуют макету; допустимы различия SF/сглаживания до 2 pt. Panel ≤420/240 pt без safe area, поле хозяина видно. Нет обрезанных ошибок/наложений/переполнения; строки/управляющие действия ≥44×44 pt, клавиши в пределах исключений AC13. Нет подмены ошибок одним общим кадром.
- **Почему провалит плохую работу:** Ловит удобный частичный набор скриншотов и UI, существующий только в HTML.
- **Статус:** fail
- **Доказательство:** Independent design verifier final frozen6aa22f9/rev1531367603:126/126 screenshot+geometry pairs,126/126 originals individually reviewed, missing0, byte-crosschecked. D1-D7/D9/D10 remain mismatches; D8 is approved automatic-Shift/reference conflict, not a product defect. Exact individual evidence: [E17-126-review.md](evidence/verifier-round1-design/E17-126-review.md); [handoff.json](evidence/verifier-round1-design/handoff.json); [README.md](evidence/verifier-round1-design/README.md).

## E18 · Живые переходы и доступность [design] [regression]
- **Тип:** ui
- **Шаги:** 375×667 обе темы: настоящими клавишами пройти пусто → строка → четыре строки с Return → счётчик >3500; открыть/прокрутить/закрыть список, выбрать самое длинное имя (40 Character), выполнить ошибку/повтор/успех. Границы 402/440 и все три альбомных размера: ready↔picker, поворот с черновиком. VoiceOver: выбрать контакт, проверить выбранность, disabled/busy, ошибки и полное имя. Снять геометрию и последовательность действий.
- **Ожидается:** Каждый переход доступен, курсор виден, все четыре ряда и поле хозяина остаются на экране, нет второй клавиатуры, скрытого управления или обрезанной инструкции. Области касаний и высоты AC13 соблюдены; статус не меняет геометрию. Labels русские, ids AC14 сохранены, полное имя доступно без эллипсиса в accessibility. Статические 126 кадров не заменяют эту проверку.
- **Почему провалит плохую работу:** Ловит класс дефекта 05 D5: при обычном вводе контент обрезается, хотя статичные fixtures зелёные.
- **Статус:** fail
- **Доказательство:** Independent design verifier final: D11, actual four-line draft rotation loses visible caret in all6 profile/theme runs (cursor9,15 UTF-8 bytes);74 live geometry phases. Both375 themes used1751 ordinary taps to3502bytes. Actual VoiceOver speech/navigation retained; physical activation remains unverified after native-host positive-control failure, not an extension-specific defect. Exact evidence: [E18-live-review.md](evidence/verifier-round1-design/E18-live-review.md); [handoff.json](evidence/verifier-round1-design/handoff.json).

## E19 · Регрессия, Release и стабильность расширения [regression] [security]
- **Тип:** command
- **Шаги:** На финальном SHA выполнить scripts/test.sh core, scripts/lint.sh, scripts/build.sh, сборку Release через scripts/build.sh -configuration Release, полный scripts/test.sh ui без фильтра и существующие typing runtime checks. В настоящем расширении 10 циклов выбора/шифрования/закрытия, один 4096-байтовый текст; сохранить host trace и crash/jetsam evidence. Проверить Release бинарники/entitlements и работающее превью набора 05.
- **Ожидается:** Все команды exit 0, полный UI suite без skip/скрытых failures; число и имена тестов записаны отдельно от focused reruns. Новый функционал не ослабил регрессии 01–05. Превью read-only, «До встречи!» неизменно, без новых действий шифрования. Нет freeze/crash/jetsam/подмены клавиатуры, debug seed/delay/fault hooks отсутствуют в Release. Сеть/RequestsOpenAccess/App Group/Keychain entitlements без незаявленных расширений. AC14.
- **Почему провалит плохую работу:** Ловит только локальные тесты модели, неполный UI suite и Debug-only работоспособность.
- **Статус:** pass
- **Доказательство:** Independent frozen SHA6aa22f9/rev1531367603: core162=27+135, lint79, Debug+actual Release exit0; complete unfiltered UI33/33 no skip/missing, runtime8/8, old typing7/7, ten actual cycles incl4096, preview unchanged/read-only, full installed app/extension/host byte matches. No new crash reports or observed substitution. Simulator log explicitly says not jetsam managed: no physical-device memory-budget claim. Initial UI minimization0/final1 retained separately. See evidence/verifier-round1-functional/full-ui-discovery-reconciliation.json; evidence/verifier-round1-functional/release-inspection.json; evidence/verifier-round1-functional/runtime-final-byteproof.json; evidence/verifier-round1-functional/crash-inventory-final.json; evidence/verifier-round1-functional/scoped-crash-jetsam.log; evidence/verifier-round1-functional/report.md.

## E20 · Независимая приёмка высокого риска [security]
- **Тип:** ui
- **Шаги:** После зелёных технических evals отдельные verifier/reviewer в свежих контекстах проверяют замороженный SHA, reviewer выполняет глубокое security review по REVIEW.md. Затем first-time-user без доступа к коду: в готовой песочнице с синтетической личностью/контактами выбрать получателя, набрать текст и вставить шифротекст, убедиться, что отправка ручная; отдельно восстановиться после отсутствия выбора. Сохранить отчёты и замечания, передать пользователю для приёмки.
- **Ожидается:** Независимые отчёты относятся к проверенному установленному SHA; нет открытых важных находок. First-time-user достигает целей по UI без подсказок о внутренних механизмах, не отправляет реальных сообщений. Отчёт фиксирует помощь координатора/ограничения инструментов, если были. Слияние и done только после явной приёмки пользователя; до неё verified. Все AC.
- **Почему провалит плохую работу:** Ловит самоприёмку builder, скрытую помощь и преждевременный merge high-risk фичи.
- **Статус:** pending
- **Доказательство:** R1 acceptance remains blocked: important AC4 identity-recovery security finding is open; technical E5/E17/E18 fail; first-time-user has not run and human acceptance is absent. Independent reports: [security reviewer](evidence/reviewer-round1/report.md); [functional report](evidence/verifier-round1-functional/report.md); [design final report](evidence/verifier-round1-design/README.md). No merge/done acceptance is claimed.
