# Evals: Шифрование и вставка в сообщение

> Контракт приёмки. Все статусы сейчас pending; pass/fail и доказательства ставит только независимый verifier. Имена новых тестов ниже — требования к реализации, сейчас этих тестов нет. Одобрение контракта не является приёмкой реализации.

## E1 · Выбор контакта сохраняет черновик и курсор 
- **Тип:** ui
- **Шаги:** Настоящее расширение в Debug-хозяине, Full Access, личный ключ и 20 синтетических контактов с известными UUID/ключами. Ввести «Привет, Анна!», поставить внутренний курсор после «Привет», открыть keyboard.recipient, прокрутить к последнему контакту, выбрать его; снова открыть и нажать «Назад».
- **Ожидается:** Порядок совпадает с ContactBook, в строках имя и короткий отпечаток; выбранная строка отмечена. Выбор закрывает список, имя обновляется. Назад не меняет выбор. Черновик и курсор неизменны; поле хозяина/выделение не менялись. Первоначально получатель не выбран даже при одном контакте. AC1, AC14.
- **Почему провалит плохую работу:** Ловит декоративный список, потерю черновика и автоматический выбор первого контакта.
- **Статус:** pass
- **Доказательство:** Independent frozen d1df3f1 / runtime527240558 fresh actual extension E1 PASS1/1,0skip,32.850s: initial unselected, exact «Привет, Анна!» and actual cursor6 preserved;20 ordered UUID/fingerprint labels, last40-Character-name selected trait and Back; owner text/selection unchanged. All14 installed app/ext+host3 match own Live before/after. See [R3 E1](evidence/verifier-round3-functional/e1-summary.json), [retained actual AX/PNG](evidence/verifier-round3-functional/e1-attachments/manifest.json), [byteproof](evidence/verifier-round3-functional/e1-after-byteproof.json).

## E2 · Восстановление только актуального id [security]
- **Тип:** test
- **Шаги:** Написать Packages/CipherCore/Tests/KeyboardTypingTests/EncryptInsertTests.swift: rememberedRecipientID. Выбрать B, закрыть и открыть новую сессию; переименовать B с тем же ключом и снова открыть. Удалить B, добавить другой контакт с таким же именем и новым UUID; открыть. Проверить записи spy preferences.
- **Ожидается:** Восстанавливается только B по UUID; переименование обновляет имя. После удаления выбор пуст, одноимённый контакт не подставляется, сохранённый id сброшен. Единственная записанная величина — UUID; нет имени/ключа/черновика/шифротекста. AC2.
- **Почему провалит плохую работу:** Ловит выбор по имени, индексу или устаревшему объекту и лишнее постоянное хранение.
- **Статус:** pass
- **Доказательство:** Independent frozen d1df3f1 / runtime527240558 core169 (34+135) PASS,0fail. rememberedRecipientID verifies UUID-only write, rename, deletion and same-name new UUID replacement. See [R3 core](evidence/verifier-round3-functional/core.log), [own recovery replay](evidence/verifier-round3-functional/independent-r1-replay.log).

## E3 · Пустой и пробельный текст не шифруется [negative]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: eligibility. Матрица текстов "", " ", "\n\t ", "\u{00A0}", " а\n "; с получателем и без, с готовыми хранилищами и с unavailable/missing. Попытаться вызвать действие напрямую, обходя disabled UI.
- **Ожидается:** Пустые/whitespacesAndNewlines: 0 seal, 0 proxy. Без получателя/ключа тоже 0. Непустой « а\n » зашифровывается без trim и нормализации. UI disabled совпадает с координатором. AC3.
- **Почему провалит плохую работу:** Ловит защиту только цветом кнопки, проверку isEmpty и незаметное изменение сообщения.
- **Статус:** pass
- **Доказательство:** Independent frozen d1df3f1 / runtime527240558 core169 (34+135) PASS,0fail. eligibility direct actions, whitespace/newline/NBSP, no trim exact UTF8 and unavailable/missing access matrix. See [R3 core](evidence/verifier-round3-functional/core.log), [own recovery replay](evidence/verifier-round3-functional/independent-r1-replay.log).

## E4 · Настоящее расширение вставляет одну строку в курсор [security]
- **Тип:** ui
- **Шаги:** Установить замороженную Debug-сборку, сопоставить SHA/хеш встроенного и установленного extension и runtime revision. Debug-хозяин: «До |встречи!» с пустым выделением. Набрать внутри «Привет, Анна!», выбрать Анну, нажать «Зашифровать». Записать proxy trace и итог хозяина. Повторить короткий сценарий в обычном поле приложения симулятора, например поиске Настроек.
- **Ожидается:** Единственная вставка C начинается ckmsg1:, является полной строкой без пробелов/CR/LF/многоточия и открывается ядром. Итог «До »+C+«встречи!»; префикс/суффикс сохранены. Нет deleteBackward/adjustTextPosition/первоначальной вставки открытого текста, автоматической отправки или clipboard. Сначала поле хозяина неизменно при наборе. Черновик пуст после возврата insertText. AC5, AC6.
- **Почему провалит плохую работу:** Ловит успех только в учебном превью/spy, старую установленную сборку и перезапись поля.
- **Статус:** pass
- **Доказательство:** Independent frozen d1df3f1 / runtime527240558. FULL native10/10 PASS: testNativeLiteralAndUnicodeActualSenderProof uses real keys for «Привет, Анна!», chosen Anna, empty cursor3, host unchanged while typing, one insert with exact preserved prefix/suffix and cleared draft. Its SAME native-literal-anna retained C is canonical and actualA/offlineB self-opened. Ordinary Settings separately passes and its exact C retained by external replay. See [native14 records](evidence/verifier-round3-functional/native-fourteen-proof-manifest.json), [15sameC proof](evidence/verifier-round3-functional/native-fifteen-B-third.log), [Settings retained manifest](evidence/verifier-round3-functional/ordinary-settings-attachments/manifest.json), [native10](evidence/verifier-round3-functional/encrypt-runtime-summary.json).

## E5 · Вставленное сообщение открывают только нужные ключи [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: insertedCiphertextRoundTrip. Взять именно аргумент proxy из интеграции координатора с настоящим CipherMessage.seal, а также строку из E4. Открыть как B (выбранный), A (отправитель), C (посторонний); у B проверить contacts с A и без A. Повторить с пробелами, переносами и Unicode.
- **Ожидается:** A и B получают точные исходные байты UTF-8, полный senderKey равен A. У B sender.contact соответствует A, без контакта sender.unknown; у A sender.me. C: CipherError.notARecipient. Нет использования фиктивного sealer в этом тесте. AC10.
- **Почему провалит плохую работу:** Ловит шифрование статичного текста, не тому контакту или без добавления себя.
- **Статус:** pass
- **Доказательство:** Independent frozen d1df3f1 / runtime527240558. Core real-sealer PASS plus15 exact canonical retained actual C (10cycles+4nativecases+ordinarySettings): every same C actual KeychainA exactUTF8/fullsender/sender.me; offlineB known+unknown exactUTF8/fullsender, third notARecipient. Additional own external proof explicitly checks text/fullsender also in unknown path;5actualA negatives rejected. No actual privateA/expected plaintext transported to app. See [15manifest](evidence/verifier-round3-functional/native-fifteen-proof-manifest.json), [frozenBproof](evidence/verifier-round3-functional/native-fifteen-B-third.log), [explicitunknown](evidence/verifier-round3-functional/native-fifteen-explicit-unknown-proof.log).

## E6 · Непустое выделение хозяина сохраняется [negative]
- **Тип:** ui
- **Шаги:** В Debug-хозяине выделить «встречи» в «До встречи!», ввести приватный черновик, выбрать контакт и нажать «Зашифровать». Снять выделение и повторить. Отдельно начать шифрование без выделения с управляемой задержкой и создать выделение до commit; эта попытка тоже не должна заменять текст.
- **Ожидается:** Первая попытка: 0 вставок/удалений/сдвигов, исходные текст и выделение хозяина сохранены, черновик/курсор сохранены, «Снимите выделение в поле сообщения». После снятия выделения новая явная попытка вставляет один шифротекст. AC5.
- **Почему провалит плохую работу:** Ловит стандартную замену выделенного текста через insertText и тихую потерю текста хозяина.
- **Статус:** pass
- **Доказательство:** Independent frozen d1df3f1 / runtime527240558 core169 selectionRechecked plus FULL native10/10 PASS,0skip: testSelectionAndSuccessGeometry and testDoubleTapDelayedSelectionAndCancellation refuse initial/delayed owner selection with zero mutation, preserve draft/cursor and allow explicit retry. See [native10](evidence/verifier-round3-functional/encrypt-runtime-summary.json), [full log](evidence/verifier-round3-functional/encrypt-runtime.log).

## E7 · Два нажатия дают одну вставку [negative]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: singleFlight. Управляемый sealer задержать, нажать дважды; попытаться набрать/удалить/сменить получателя, завершить sealer, снова нажать без ввода; затем ввести новый текст и нажать ещё раз. Параллельный UI-сценарий двойного касания в Debug-хозяине.
- **Ожидается:** В задержке «Шифруем…», кнопка/ввод/выбор заблокированы. До завершения 1 seal, после него ровно 1 insertText исходного снимка. Повтор без текста: 0 новых вставок. Новый непустой черновик шифруется один раз новым действием. AC7.
- **Почему провалит плохую работу:** Ловит debounce только на времени, гонку двух задач и навсегда заблокированную кнопку.
- **Статус:** pass
- **Доказательство:** Independent core169 singleFlight and FULL native10/10 PASS,0skip on frozen d1df3f1 / runtime527240558. testDoubleTapDelayedSelectionAndCancellation PASS35.270s verifies delayed busy/input/recipient disabled, one captured insertion and no replay; core verifies second new draft normal retry. See [core](evidence/verifier-round3-functional/core.log), [native10](evidence/verifier-round3-functional/encrypt-runtime-summary.json).

## E8 · Ошибка не теряет текст и допускает повтор [negative]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: failurePreservesDraft. По отдельности identity missing, unavailable и sealer throws; полный доступ есть, текст и внутренний курсор известны. Для unavailable убрать сбой и повторить. Проверить missing также в настоящем расширении чистой песочницы; ошибки — через Debug-only dependency, затем проверить её отсутствие в Release.
- **Ожидается:** До вставки 0 proxy. Текст/курсор прежние. missing: «Откройте приложение CipherKeyboard, чтобы создать ключ»; unavailable: «Ключ недоступен — откройте приложение CipherKeyboard»; seal failure: «Не удалось зашифровать сообщение. Повторите попытку». Повтор после восстановления даёт одну вставку. Ключ не создаётся/не пересоздаётся. AC8.
- **Почему провалит плохую работу:** Ловит очистку в defer, молчаливую ошибку, plaintext fallback и генерацию нового ключа.
- **Статус:** pass
- **Доказательство:** Independent frozen d1df3f1 / runtime527240558 core169 failurePreservesDraft/missing/unavailable/throw/retry and FULL native10 fault recovery PASS. Real clean NoKeyC7 PASS1/1,37.064s,actual Settings FullAccessON, exact missing-key message, typing enabled/encrypt disabled/owner unchanged; metadata rows0 before/install/after, container app never launched and no key generated. All14 installed app/ext+host3 matched own Live;C7shutdown. Releasehooks absent. See [NoKey](evidence/verifier-round3-functional/nokey-summary.json), [metadata](evidence/verifier-round3-functional/nokey-after-identity-metadata.json), [byteproof](evidence/verifier-round3-functional/nokey-after-byteproof.json).

## E9 · Границы UTF-8 и независимая проверка длины [negative]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: utf8Boundaries. 3500/3501/4096/4097 байт ASCII и кириллица/emoji с известным utf8.count; счётчик проверить в настоящем расширении. 4096 байт зашифровать настоящим ядром. Ввод ещё одного символа отвергнуть; отдельно тестовым входом передать координатору 4097 байт, не меняя Release-лимит модели ввода.
- **Ожидается:** Счётчик только N>3500: «N / 4096 байт». 4096 байт открываются точно; сверхлимитный ввод целиком отклонён: «Сообщение не должно превышать 4096 байт». Защитный вход 4097: 0 proxy, неизменные текст/курсор, «Слишком длинное сообщение: 4097 из 4096 байт». AC9.
- **Почему провалит плохую работу:** Ловит подсчёт Character вместо байтов и отсутствие проверки длины вне UI.
- **Статус:** pass
- **Доказательство:** Independent frozen d1df3f1 / runtime527240558. Core169 UTF8 3500/3501/4096/4097 ASCII/Cyrillic/emoji and defensive4097 PASS; native4096 exact actualA/B proof PASS. External normal-input limit PASS14.270s: 4096 counter, whole extra Cyrillic insertion rejected with exact old limit message, cursor/text unchanged. See [core](evidence/verifier-round3-functional/core.log), [native15](evidence/verifier-round3-functional/native-fifteen-proof-manifest.json), [supplement original6/7 log](evidence/verifier-round3-functional/supplemental.log).

## E10 · Удалённый или подменённый контакт не получает сообщение [negative] [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: recipientRevalidation. Выбрать B; после показа панели удалить его, заменить ключ под прежним UUID, вернуть unreadable; повторить каждую мутацию после начала задержанного seal до commit. Отдельно переименовать при неизменных UUID и обеих частях полного ключа. Проверить refresh при открытии списка.
- **Ожидается:** Удаление/замена ключа: 0 вставок, выбор и remembered id сброшены, «Данные изменились — выберите получателя заново»; до старта также нельзя молча принять новый ключ. Unreadable: 0 вставок, «Не удалось прочитать контакты», Повторить; повторное чтение восстанавливает доступность только для проверенного контакта. Переименование обновляет имя, адресат прежний. AC2, AC4.
- **Почему провалит плохую работу:** Ловит TOCTOU между выбором и вставкой, равенство только short fingerprint и доверие старому списку.
- **Статус:** pass
- **Доказательство:** Independent frozen d1df3f1 / runtime527240558 core169 (34+135) PASS,0fail. recipientRevalidation pre/during removal, both full-key parts, unreadable/retry and rename. See [R3 core](evidence/verifier-round3-functional/core.log), [own recovery replay](evidence/verifier-round3-functional/independent-r1-replay.log).

## E11 · Смена личного ключа отменяет операцию [negative] [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: identityRevalidation. Начать seal как A, перед завершением заменить identity на A2 с другим полным public key либо сделать чтение unavailable/missing.
- **Ожидается:** 0 proxy. При A2 выбор сброшен и «Данные изменились — выберите получателя заново». При unavailable/missing соответствующая ошибка AC8. В активной сессии текст/курсор сохранены. Нет подписи неожиданной новой личностью. AC4, AC8.
- **Почему провалит плохую работу:** Ловит использование старого key snapshot без проверки и тихую смену отправителя.
- **Статус:** pass
- **Доказательство:** Independent frozen d1df3f1 / runtime527240558 core169 (34+135) PASS,0fail. identityRevalidation/recovery30 combinations, sameA, full/signing-only A2, commit read failure and session reset; own historical missing/unavailable→A2 CLI asserts selected=false/canEncrypt=false/changed=true/zero insert/draft preserved. See [R3 core](evidence/verifier-round3-functional/core.log), [own recovery replay](evidence/verifier-round3-functional/independent-r1-replay.log).

## E12 · Полный доступ проверяется в момент действия [negative] [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: accessGate. При hasFullAccess=false вызвать open/select/encrypt с reader/storage spies. Затем начать операцию с true, отозвать доступ до commit. В настоящем расширении отдельно включить и выключить Full Access в Settings; после возврата проверить панель и возможность набора.
- **Ожидается:** Без доступа 0 чтений/записей общих хранилищ и remembered preferences, выбор/шифрование disabled, баннер «Включите «Полный доступ» в Настройках, чтобы шифровать»; набор работает. После отзыва 0 вставок и больше нет обращений к защищённым хранилищам. AC11.
- **Почему провалит плохую работу:** Ловит guard только при запуске и debug fixture вместо настоящего системного разрешения.
- **Статус:** pass
- **Доказательство:** Independent frozen d1df3f1 / runtime527240558. Core accessGate/noAccessNeverConstructsSharedReaders PASS; FULL legacy7/7 strict OFFmatrix PASS68.273s, both exact texts and all prior input/host/lifecycle. External actualDenied PASS97.531s independently proves real SettingsOFF, system+model false, both exact channels, disabledrecipient/encrypt, typing/owner invariant and ON restoration. Other supplemental test failed before row activation and is separate. See [legacy7](evidence/verifier-round3-functional/typing-runtime-summary.json), [actualOFFlog](evidence/verifier-round3-functional/supplemental.log).

## E13 · Закрытие и смена документа не переносят результат [negative] [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: sessionAndDocumentCancellation. Задержать seal и по отдельности: hide, background, globe, смена documentIdentifier, поворот. Завершить старую задачу после открытия новой сессии/поля. Проверить также закрытие сразу после уже выполненного insertText. В реальном расширении пройти hide/reopen и переключение между двумя полями Debug-хозяина.
- **Ожидается:** Hide/background/globe: черновик очищен, отложенный результат 0 proxy в старом/новом поле, новая сессия пустая. Смена документа при активной сессии: 0 вставок, текст сохранён, «Поле сообщения изменилось — повторите попытку». Поворот: текст/получатель сохраняются, ≤1 вставки. Закрытие после вставки не вызывает повтор при открытии. AC12.
- **Почему провалит плохую работу:** Ловит поздний completion в чужой документ и повторную отправку после reopen.
- **Статус:** pass
- **Доказательство:** Independent frozen d1df3f1 / runtime527240558. Core session/document cancellation, FULL native10 and FULL legacy7 PASS hide/reopen/background/globe/rotations/two-host-fields/no replay. External actual A→B→A: Bvisible=true,Areturned=true at1.052/1.779sec before2sec delayed completion; unchanged owner,trace empty,draft preserved,document-changed message. See [transient](evidence/verifier-round3-functional/transient-document-probe.txt), [native10](evidence/verifier-round3-functional/encrypt-runtime-summary.json), [legacy7](evidence/verifier-round3-functional/typing-runtime-summary.json).

## E14 · Успех и полоса статуса без скачка 
- **Тип:** ui
- **Шаги:** В реальном расширении зашифровать короткий текст для Анны; снять кадр и геометрию до, после и через 2 секунды (допуск наблюдения 0,3 секунды). Начать новый ввод. Длинное имя отдельно.
- **Ожидается:** После возврата вставки пустой черновик/нулевой курсор, выбранная Анна остаётся, «Зашифровано для Анна» показывается 2 секунды, затем обычный статус. Геометрия редактора/клавиш/поля хозяина не меняется из-за смены статуса. Новый ввод работает. Полное длинное имя доступно VoiceOver. AC6.
- **Почему провалит плохую работу:** Ловит toast поверх клавиш, исчезающий layout slot и очистку до успешной передачи.
- **Статус:** pass
- **Доказательство:** Independent frozen d1df3f1 / runtime527240558. Native success geometry/reset and production clock observer PASS: positive-to-negative1.825s, conservative lifetime1.766..2.156sec within1.7..2.3; before/success/ordinary frames equal. Original supplemental6/7 failed long-name BEFORE encryption because picker remained open after AXtap on partially clipped row; cause not proved. One strengthened own observer focused1/1PASS35.418s establishes fully-visible stable40Я row, coordinate activation, picker closed, exact selected full label BEFORE typing and exact full40Я successAX. Original6/7 retained separately; no fake full7 claim. See [clockbounds](evidence/verifier-round3-functional/success-clock-bounds.json), [focused1](evidence/verifier-round3-functional/long-name-focused-summary.json), [actualAX](evidence/verifier-round3-functional/long-name-focused-attachments/DF7200A5-121B-4619-86E5-5C178318DD4C.txt).

## E15 · Приватность доказана до и после успеха и ошибки [security]
- **Тип:** command
- **Шаги:** На одном замороженном SHA расширить/использовать scripts/typing-audit.sh для сценариев 06. До прогона подтвердить установленный синтетический clipboard sentinel, известную непустую identity и видимость её Keychain metadata; задать уникальный синтетический черновик. Пройти набор, выбор, успех, сбой и закрытие. Сравнить clipboard, файлы App Group/контейнеров, UserDefaults, Keychain metadata и логи. Проанализировать все новые insertText/deleteBackward/adjustTextPosition/UIPasteboard/print/Logger/os_log/NSLog/UserDefaults/FileManager и reader/writer зависимости.
- **Ожидается:** Exit 0, audit prerequisites pass. Sentinel неизменен, нет сохранённого черновика/шифротекста/приватных ключей или новых Keychain items, кроме заранее созданной identity. Разрешён только UUID выбора в локальных preferences и существующий setup marker 04. Spy доказывает единственный выход шифротекста через insertText и отсутствие plaintext proxy; поиск строки дополняет проверку, не заменяет её. Никаких сетевых API/новых permissions. AC2, AC5, AC11.
- **Почему провалит плохую работу:** Ловит ложное «утечки не нашли» с пустым Keychain/clipboard и хранение plaintext вне проверяемой модели.
- **Статус:** pass
- **Доказательство:** Independent frozen d1df3f1/rev527240558 isolated encrypt-audit LAST exit0/PASS: setup3/3,canary1/1,real sentinel installed/readback,known identity metadata1 before/after and full publicA matches15nativeC; metadata hashes/clipboard equal,failures/unexpectedChanges/canaryMatches empty. Only UUID preference and version/date receipt changed, both validated. Source boundary audit + shipping controller spy insert1/context0/delete0/adjust0;no new permissions/network. See [audit](evidence/verifier-round3-functional/audit-result.json), [knownA](evidence/verifier-round3-functional/audit-known-identity-proof.json), [sites](evidence/verifier-round3-functional/privacy-sites.md).

## E16 · Подмена сообщения и отправителя отклоняется [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: tamperedInsertedMessage и существующие adversarial tests CipherCore. Для реального результата координатора изменить байт ciphertext, подпись, заменить sender key; при необходимости переподписать подменённым ключом, как в тестах ядра. Ввести недопустимый публичный ключ через недоверенный источник контактов.
- **Ожидается:** Ни один изменённый вариант не открывается как исходное доверенное сообщение; malformed/tampered/invalidKey согласно границе проверки. Недопустимый ключ не ведёт к вставке или plaintext fallback. Факт подписи привязан к полному senderKey. AC4, AC10.
- **Почему провалит плохую работу:** Ловит обход проверок ядра или собственный несовместимый формат в адаптере клавиатуры.
- **Статус:** pass
- **Доказательство:** Independent frozen d1df3f1 / runtime527240558 core169 (34+135) PASS,0fail. tamperedInsertedMessage plus complete CipherCore135 adversarial tests reject ciphertext/signature/sender/public-key substitutions. See [R3 core](evidence/verifier-round3-functional/core.log), [own recovery replay](evidence/verifier-round3-functional/independent-r1-replay.log).

## E17 · Все состояния совпадают с макетом [design]
- **Тип:** design
- **Шаги:** Сравнить каждый из 126 кадров с specs/06-encrypt-insert/mockup.html: все 17 state-* в портрете 375/402/440 обе темы (102); ready/picker/limit/long-name в альбоме 667/874/956 обе темы (24). Состояния fixture только Debug; реальная панель extension и системные safe areas. Дать manifest ожидаемых/полученных кадров и индивидуальный результат просмотра каждого.
- **Ожидается:** 126 уникальных кадров, ни одного missing. Все состояния/точные тексты из AC1–AC14, порядок и цвета соответствуют макету; допустимы различия SF/сглаживания до 2 pt. Panel ≤420/240 pt без safe area, поле хозяина видно. Нет обрезанных ошибок/наложений/переполнения; строки/управляющие действия ≥44×44 pt, клавиши в пределах исключений AC13. Нет подмены ошибок одним общим кадром.
- **Почему провалит плохую работу:** Ловит удобный частичный набор скриншотов и UI, существующий только в HTML.
- **Статус:** fail
- **Доказательство:** Независимый final DESIGN R3 на frozen d1df3f133ea839450c4d50003e1e7b16a2532f1e / runtime527240558: все126 уникальных original full-screen PNG лично просмотрены, missing0; state/content126pass, fullVisual54pass/72fail по подтверждённому D12 disabled Encrypt foreground. Raw RGB не соответствует approved CSS white+opacity.42; функциональный/криптографический дефект не заявляется. Прежние375 glyph-кандидаты отозваны как ошибки визуального чтения, оригиналы сохранены. См. [E17](evidence/verifier-round3-design/E17-126-review.md), [findings](evidence/verifier-round3-design/findings.md), [final handoff](evidence/verifier-round3-design/handoff.json).

## E18 · Живые переходы и доступность [design] [regression]
- **Тип:** ui
- **Шаги:** 375×667 обе темы: настоящими клавишами пройти пусто → строка → четыре строки с Return → счётчик >3500; открыть/прокрутить/закрыть список, выбрать самое длинное имя (40 Character), выполнить ошибку/повтор/успех. Границы 402/440 и все три альбомных размера: ready↔picker, поворот с черновиком. VoiceOver: выбрать контакт, проверить выбранность, disabled/busy, ошибки и полное имя. Снять геометрию и последовательность действий.
- **Ожидается:** Каждый переход доступен, курсор виден, все четыре ряда и поле хозяина остаются на экране, нет второй клавиатуры, скрытого управления или обрезанной инструкции. Области касаний и высоты AC13 соблюдены; статус не меняет геометрию. Labels русские, ids AC14 сохранены, полное имя доступно без эллипсиса в accessibility. Статические 126 кадров не заменяют эту проверку.
- **Почему провалит плохую работу:** Ловит класс дефекта 05 D5: при обычном вводе контент обрезается, хотя статичные fixtures зелёные.
- **Статус:** pending
- **Доказательство:** Независимый final DESIGN R3 на frozen d1df3f133ea839450c4d50003e1e7b16a2532f1e / runtime527240558: все6 ordinary live series завершены,116 original full-screen PNG лично просмотрены;375 обе темы1751ordinary taps→3502UTF8, переходы/повороты/picker/error/retry/busy/success и actual VoiceOver speech/navigation проверены. Полный pass не принят: post-loop landscape final-glyph display402/440 unresolved при сохранённых AX/model/caret; один bounded402light burst воспроизводит те же пиксели через XCUIScreen+simctl, причина не доказана и product/text-loss defect не заявлен. Native AX activation с host positive control блокирован Mac locked; physical VoiceOver gesture отдельно не выполнен. Все owned UI shutdown/runners0/VO false, UI+clipboardALLCLEAR. См. [E18](evidence/verifier-round3-design/E18-live-review.md), [findings](evidence/verifier-round3-design/findings.md), [final handoff](evidence/verifier-round3-design/handoff.json).

## E19 · Регрессия, Release и стабильность расширения [regression] [security]
- **Тип:** command
- **Шаги:** На финальном SHA выполнить scripts/test.sh core, scripts/lint.sh, scripts/build.sh, сборку Release через scripts/build.sh -configuration Release, полный scripts/test.sh ui без фильтра и существующие typing runtime checks. В настоящем расширении 10 циклов выбора/шифрования/закрытия, один 4096-байтовый текст; сохранить host trace и crash/jetsam evidence. Проверить Release бинарники/entitlements и работающее превью набора 05.
- **Ожидается:** Все команды exit 0, полный UI suite без skip/скрытых failures; число и имена тестов записаны отдельно от focused reruns. Новый функционал не ослабил регрессии 01–05. Превью read-only, «До встречи!» неизменно, без новых действий шифрования. Нет freeze/crash/jetsam/подмены клавиатуры, debug seed/delay/fault hooks отсутствуют в Release. Сеть/RequestsOpenAccess/App Group/Keychain entitlements без незаявленных расширений. AC14.
- **Почему провалит плохую работу:** Ловит только локальные тесты модели, неполный UI suite и Debug-only работоспособность.
- **Статус:** pass
- **Доказательство:** Independent final d1df3f1/rev527240558 core169/lint79/Python4/Debug/actualRelease PASS; fresh FULL unfiltered UI33/33, FULL native10/10, FULL original legacy7/7,all names reconcile,0skip. Correct strict OFF case68.273s. Native10cycles+4096+old preview/lifecycle pass;Releasehooks absent/permissions unchanged;all installed14+host3 match own builds and before/after pairs unchanged;source79+100inventory frozen;no new target crashes,Simulator not physicaljetsam proof. Extra observer original6/7 retained separately plus one strengthened focused longname1/1,not claimed full7. Final isolatedauditPASS,all own shutdown/runners0/main+FTUEuntouched. See [fullUI](evidence/verifier-round3-functional/fresh-full-ui-summary.json), [native10](evidence/verifier-round3-functional/encrypt-runtime-summary.json), [legacy7](evidence/verifier-round3-functional/typing-runtime-summary.json), [release](evidence/verifier-round3-functional/release-inspection.json), [ALLCLEAR](evidence/verifier-round3-functional/shutdown-allclear.json).

## E20 · Независимая приёмка высокого риска [security]
- **Тип:** ui
- **Шаги:** После зелёных технических evals отдельные verifier/reviewer в свежих контекстах проверяют замороженный SHA, reviewer выполняет глубокое security review по REVIEW.md. Затем first-time-user без доступа к коду: в готовой песочнице с синтетической личностью/контактами выбрать получателя, набрать текст и вставить шифротекст, убедиться, что отправка ручная; отдельно восстановиться после отсутствия выбора. Сохранить отчёты и замечания, передать пользователю для приёмки.
- **Ожидается:** Независимые отчёты относятся к проверенному установленному SHA; нет открытых важных находок. First-time-user достигает целей по UI без подсказок о внутренних механизмах, не отправляет реальных сообщений. Отчёт фиксирует помощь координатора/ограничения инструментов, если были. Слияние и done только после явной приёмки пользователя; до неё verified. Все AC.
- **Почему провалит плохую работу:** Ловит самоприёмку builder, скрытую помощь и преждевременный merge high-risk фичи.
- **Статус:** pending
- **Доказательство:** Frozen R3 d1df3f133ea839450c4d50003e1e7b16a2532f1e / runtime527240558: независимый functional E1–E16/E19 pass17 и reviewer/security Important0 относятся к этому SHA; final design E17fail(D12),E18pending(unresolved display/native AX Mac locked). Технические evals ещё не все зелёные; отдельный first-time-user и явная приёмка высокого риска пользователем не выполнены. Mac unlock ожидается, lock не обходится. Нет all-pass/verified/merge/done вывода. См. [functional](evidence/verifier-round3-functional/report.md), [reviewer](evidence/reviewer-round3/report.md), [design handoff](evidence/verifier-round3-design/handoff.json).
