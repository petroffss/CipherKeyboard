# Evals: Шифрование и вставка в сообщение

> Контракт приёмки. Все статусы сейчас pending; pass/fail и доказательства ставит только независимый verifier. Имена новых тестов ниже — требования к реализации, сейчас этих тестов нет. Одобрение контракта не является приёмкой реализации.

## E1 · Выбор контакта сохраняет черновик и курсор 
- **Тип:** ui
- **Шаги:** Настоящее расширение в Debug-хозяине, Full Access, личный ключ и 20 синтетических контактов с известными UUID/ключами. Ввести «Привет, Анна!», поставить внутренний курсор после «Привет», открыть keyboard.recipient, прокрутить к последнему контакту, выбрать его; снова открыть и нажать «Назад».
- **Ожидается:** Порядок совпадает с ContactBook, в строках имя и короткий отпечаток; выбранная строка отмечена. Выбор закрывает список, имя обновляется. Назад не меняет выбор. Черновик и курсор неизменны; поле хозяина/выделение не менялись. Первоначально получатель не выбран даже при одном контакте. AC1, AC14.
- **Почему провалит плохую работу:** Ловит декоративный список, потерю черновика и автоматический выбор первого контакта.
- **Статус:** pass
- **Доказательство:** Independent frozen74cbb522/rev101101654 actual fresh extension E1 PASS1/1,0skip: initial unselected, exact «Привет, Анна!» and cursor6 preserved,20 ordered rows with valid UUID/fingerprint labels, last selected trait and Back, owner text/selection unchanged. All14 installed app/extension files plus host3 match independent Live build before/after. See [R2 E1 log](evidence/verifier-round2-functional/e1.log), [summary](evidence/verifier-round2-functional/e1-summary.json), [byteproof](evidence/verifier-round2-functional/e1-after-byteproof.json).

## E2 · Восстановление только актуального id [security]
- **Тип:** test
- **Шаги:** Написать Packages/CipherCore/Tests/KeyboardTypingTests/EncryptInsertTests.swift: rememberedRecipientID. Выбрать B, закрыть и открыть новую сессию; переименовать B с тем же ключом и снова открыть. Удалить B, добавить другой контакт с таким же именем и новым UUID; открыть. Проверить записи spy preferences.
- **Ожидается:** Восстанавливается только B по UUID; переименование обновляет имя. После удаления выбор пуст, одноимённый контакт не подставляется, сохранённый id сброшен. Единственная записанная величина — UUID; нет имени/ключа/черновика/шифротекста. AC2.
- **Почему провалит плохую работу:** Ловит выбор по имени, индексу или устаревшему объекту и лишнее постоянное хранение.
- **Статус:** pass
- **Доказательство:** Independent frozen74cbb522/rev101101654 core169=34+135 PASS: rememberedRecipientID verifies UUID-only write, rename, deletion and same-name replacement. See [R2 core log](evidence/verifier-round2-functional/core.log).

## E3 · Пустой и пробельный текст не шифруется [negative]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: eligibility. Матрица текстов "", " ", "\n\t ", "\u{00A0}", " а\n "; с получателем и без, с готовыми хранилищами и с unavailable/missing. Попытаться вызвать действие напрямую, обходя disabled UI.
- **Ожидается:** Пустые/whitespacesAndNewlines: 0 seal, 0 proxy. Без получателя/ключа тоже 0. Непустой « а\n » зашифровывается без trim и нормализации. UI disabled совпадает с координатором. AC3.
- **Почему провалит плохую работу:** Ловит защиту только цветом кнопки, проверку isEmpty и незаметное изменение сообщения.
- **Статус:** pass
- **Доказательство:** Independent core169 PASS: eligibility text/access/selection matrix; direct action and exact non-trimmed whitespace UTF-8 roundtrip. See [R2 core log](evidence/verifier-round2-functional/core.log).

## E4 · Настоящее расширение вставляет одну строку в курсор [security]
- **Тип:** ui
- **Шаги:** Установить замороженную Debug-сборку, сопоставить SHA/хеш встроенного и установленного extension и runtime revision. Debug-хозяин: «До |встречи!» с пустым выделением. Набрать внутри «Привет, Анна!», выбрать Анну, нажать «Зашифровать». Записать proxy trace и итог хозяина. Повторить короткий сценарий в обычном поле приложения симулятора, например поиске Настроек.
- **Ожидается:** Единственная вставка C начинается ckmsg1:, является полной строкой без пробелов/CR/LF/многоточия и открывается ядром. Итог «До »+C+«встречи!»; префикс/суффикс сохранены. Нет deleteBackward/adjustTextPosition/первоначальной вставки открытого текста, автоматической отправки или clipboard. Сначала поле хозяина неизменно при наборе. Черновик пуст после возврата insertText. AC5, AC6.
- **Почему провалит плохую работу:** Ловит успех только в учебном превью/spy, старую установленную сборку и перезапись поля.
- **Статус:** pass
- **Доказательство:** Actual frozen full native10/10 plus exact15-C proof PASS: literal Привет, Анна! kept out of owner until single canonical C at cursor3, exact До +C+встречи! retained, traceinsert1/delete0/replacement0; ordinary real Settings separately retained exact C and actualA/B/third proof. Shipping-controller fullUI spy proves insert1/context0/delete0/adjust0; audit clipboard unchanged. Installed14 app/extension+host3 match own source101101654 before/after. See [15 proof](evidence/verifier-round2-functional/native-fifteen-proof-manifest.json), [B/third](evidence/verifier-round2-functional/native-fifteen-B-third.log), [fullUI33](evidence/verifier-round2-functional/fresh-full-ui-summary.json), [final byteproof](evidence/verifier-round2-functional/audit-final-byteproof.json).

## E5 · Вставленное сообщение открывают только нужные ключи [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: insertedCiphertextRoundTrip. Взять именно аргумент proxy из интеграции координатора с настоящим CipherMessage.seal, а также строку из E4. Открыть как B (выбранный), A (отправитель), C (посторонний); у B проверить contacts с A и без A. Повторить с пробелами, переносами и Unicode.
- **Ожидается:** A и B получают точные исходные байты UTF-8, полный senderKey равен A. У B sender.contact соответствует A, без контакта sender.unknown; у A sender.me. C: CipherError.notARecipient. Нет использования фиктивного sealer в этом тесте. AC10.
- **Почему провалит плохую работу:** Ловит шифрование статичного текста, не тому контакту или без добавления себя.
- **Статус:** pass
- **Доказательство:** Independent frozen74cbb522 core real-sealer roundtrip PASS and15 exact canonical retained actual-native C:10 cycles +4 native cases +ordinary Settings. Every same C self-opened by actual KeychainA with exact UTF-8/full sender/sender.me; independent offline B opens exact bytes as known-contact and unknown sender/fullAkey, third key gives notARecipient. Includes literal phrase, whitespace/decomposed Unicode and4096;5 actualA negative controls reject wrong/unknown/empty/malformed/tampered. Expected plaintext/private keys are not transported to app: only C+closed public case ID. See [15 native proof manifest](evidence/verifier-round2-functional/native-fifteen-proof-manifest.json), [offline B/third](evidence/verifier-round2-functional/native-fifteen-B-third.log), [native full10](evidence/verifier-round2-functional/encrypt-runtime-summary.json).

## E6 · Непустое выделение хозяина сохраняется [negative]
- **Тип:** ui
- **Шаги:** В Debug-хозяине выделить «встречи» в «До встречи!», ввести приватный черновик, выбрать контакт и нажать «Зашифровать». Снять выделение и повторить. Отдельно начать шифрование без выделения с управляемой задержкой и создать выделение до commit; эта попытка тоже не должна заменять текст.
- **Ожидается:** Первая попытка: 0 вставок/удалений/сдвигов, исходные текст и выделение хозяина сохранены, черновик/курсор сохранены, «Снимите выделение в поле сообщения». После снятия выделения новая явная попытка вставляет один шифротекст. AC5.
- **Почему провалит плохую работу:** Ловит стандартную замену выделенного текста через insertText и тихую потерю текста хозяина.
- **Статус:** pass
- **Доказательство:** Independent core selectionRechecked + frozen actual full EncryptRuntimeTests10/10 PASS,0skip. Initial and delayed owner selection refused without owner/draft mutation; explicit retry after removal inserts once. Native testSelectionAndSuccessGeometry and testDoubleTapDelayedSelectionAndCancellation retained. See [R2 native summary](evidence/verifier-round2-functional/encrypt-runtime-summary.json) and [log](evidence/verifier-round2-functional/encrypt-runtime.log).

## E7 · Два нажатия дают одну вставку [negative]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: singleFlight. Управляемый sealer задержать, нажать дважды; попытаться набрать/удалить/сменить получателя, завершить sealer, снова нажать без ввода; затем ввести новый текст и нажать ещё раз. Параллельный UI-сценарий двойного касания в Debug-хозяине.
- **Ожидается:** В задержке «Шифруем…», кнопка/ввод/выбор заблокированы. До завершения 1 seal, после него ровно 1 insertText исходного снимка. Повтор без текста: 0 новых вставок. Новый непустой черновик шифруется один раз новым действием. AC7.
- **Почему провалит плохую работу:** Ловит debounce только на времени, гонку двух задач и навсегда заблокированную кнопку.
- **Статус:** pass
- **Доказательство:** Independent core169 singleFlight PASS; actual frozen extension testDoubleTapDelayedSelectionAndCancellation completed PASS34.539s on382F5C37/rev101101654: delayed busy/input/recipient disabled, single host insertion, cancellation/no replay. Full native class is tracked separately, not yet counted as complete here. See [R2 core](evidence/verifier-round2-functional/core.log) and [native log](evidence/verifier-round2-functional/encrypt-runtime.log).

## E8 · Ошибка не теряет текст и допускает повтор [negative]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: failurePreservesDraft. По отдельности identity missing, unavailable и sealer throws; полный доступ есть, текст и внутренний курсор известны. Для unavailable убрать сбой и повторить. Проверить missing также в настоящем расширении чистой песочницы; ошибки — через Debug-only dependency, затем проверить её отсутствие в Release.
- **Ожидается:** До вставки 0 proxy. Текст/курсор прежние. missing: «Откройте приложение CipherKeyboard, чтобы создать ключ»; unavailable: «Ключ недоступен — откройте приложение CipherKeyboard»; seal failure: «Не удалось зашифровать сообщение. Повторите попытку». Повтор после восстановления даёт одну вставку. Ключ не создаётся/не пересоздаётся. AC8.
- **Почему провалит плохую работу:** Ловит очистку в defer, молчаливую ошибку, plaintext fallback и генерацию нового ключа.
- **Статус:** pass
- **Доказательство:** Independent core failurePreservesDraft/missing/unavailable/throw/retry PASS and actual native fault recovery PASS in full10. Real NoKeyC7 clean extension PASS1/1: actualFullAccessON, metadata rows0 before/install/after, container app never launched, typing enabled/encrypt disabled, exact missing message and unchanged owner. All installed14 app/extension+host3 bytes match own Live frozen101101654; C7shutdown. Release hooks absent. See [NoKey summary](evidence/verifier-round2-functional/nokey-summary.json), [metadata after](evidence/verifier-round2-functional/nokey-after-identity-metadata.json), [byteproof](evidence/verifier-round2-functional/nokey-after-byteproof.json).

## E9 · Границы UTF-8 и независимая проверка длины [negative]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: utf8Boundaries. 3500/3501/4096/4097 байт ASCII и кириллица/emoji с известным utf8.count; счётчик проверить в настоящем расширении. 4096 байт зашифровать настоящим ядром. Ввод ещё одного символа отвергнуть; отдельно тестовым входом передать координатору 4097 байт, не меняя Release-лимит модели ввода.
- **Ожидается:** Счётчик только N>3500: «N / 4096 байт». 4096 байт открываются точно; сверхлимитный ввод целиком отклонён: «Сообщение не должно превышать 4096 байт». Защитный вход 4097: 0 proxy, неизменные текст/курсор, «Слишком длинное сообщение: 4097 из 4096 байт». AC9.
- **Почему провалит плохую работу:** Ловит подсчёт Character вместо байтов и отсутствие проверки длины вне UI.
- **Статус:** pass
- **Доказательство:** Independent core169 UTF-8 3500/3501/4096/4097 ASCII/Cyrillic/emoji and defensive4097 PASS; actual native4096 ciphertext self-opens exactly as real KeychainA; external normal-input test PASS13.830s proves4096 counter, unchanged cursor/text and whole extra Cyrillic insertion rejected with exact limit message. See [core](evidence/verifier-round2-functional/core.log), [native](evidence/verifier-round2-functional/encrypt-runtime-summary.json), [supplemental log](evidence/verifier-round2-functional/supplemental.log).

## E10 · Удалённый или подменённый контакт не получает сообщение [negative] [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: recipientRevalidation. Выбрать B; после показа панели удалить его, заменить ключ под прежним UUID, вернуть unreadable; повторить каждую мутацию после начала задержанного seal до commit. Отдельно переименовать при неизменных UUID и обеих частях полного ключа. Проверить refresh при открытии списка.
- **Ожидается:** Удаление/замена ключа: 0 вставок, выбор и remembered id сброшены, «Данные изменились — выберите получателя заново»; до старта также нельзя молча принять новый ключ. Unreadable: 0 вставок, «Не удалось прочитать контакты», Повторить; повторное чтение восстанавливает доступность только для проверенного контакта. Переименование обновляет имя, адресат прежний. AC2, AC4.
- **Почему провалит плохую работу:** Ловит TOCTOU между выбором и вставкой, равенство только short fingerprint и доверие старому списку.
- **Статус:** pass
- **Доказательство:** Independent core169 PASS: recipientRevalidation covers pre/during seal remove, full agreement/signing replacement, unreadable/retry and rename. See [R2 core log](evidence/verifier-round2-functional/core.log).

## E11 · Смена личного ключа отменяет операцию [negative] [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: identityRevalidation. Начать seal как A, перед завершением заменить identity на A2 с другим полным public key либо сделать чтение unavailable/missing.
- **Ожидается:** 0 proxy. При A2 выбор сброшен и «Данные изменились — выберите получателя заново». При unavailable/missing соответствующая ошибка AC8. В активной сессии текст/курсор сохранены. Нет подписи неожиданной новой личностью. AC4, AC8.
- **Почему провалит плохую работу:** Ловит использование старого key snapshot без проверки и тихую смену отправителя.
- **Статус:** pass
- **Доказательство:** Independent core169 PASS: direct identity mutations plus identityRecoveryRequiresExplicitSelection (30 combinations), same-key recovery, commit failure baseline, session reset and metadata; A2/signing-only recovery clears selected+remembered UUID, changed message, zero seal/proxy, draft/cursor preserved; same A retry succeeds. See [R2 core log](evidence/verifier-round2-functional/core.log).

## E12 · Полный доступ проверяется в момент действия [negative] [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: accessGate. При hasFullAccess=false вызвать open/select/encrypt с reader/storage spies. Затем начать операцию с true, отозвать доступ до commit. В настоящем расширении отдельно включить и выключить Full Access в Settings; после возврата проверить панель и возможность набора.
- **Ожидается:** Без доступа 0 чтений/записей общих хранилищ и remembered preferences, выбор/шифрование disabled, баннер «Включите «Полный доступ» в Настройках, чтобы шифровать»; набор работает. После отзыва 0 вставок и больше нет обращений к защищённым хранилищам. AC11.
- **Почему провалит плохую работу:** Ловит guard только при запуске и debug fixture вместо настоящего системного разрешения.
- **Статус:** pass
- **Доказательство:** Independent accessGate/noAccessNeverConstructsSharedReaders core PASS; actual SettingsOFF/ON plus external testActualDeniedTypingAndBanner PASS96.940s: system/model false, correct exact banner in keyboard.encrypt.status, approved unavailable metadata, recipient/encrypt disabled; full old input sequence works for empty/nonempty owner selection with owner unchanged and hide/reopen clear. Original legacy6/7 old identityStatus-channel assertion remains E19fail and is not replaced by this diagnostic. See [supplemental log](evidence/verifier-round2-functional/supplemental.log), [core](evidence/verifier-round2-functional/core.log), [legacy failure](evidence/verifier-round2-functional/typing-runtime-summary.json).

## E13 · Закрытие и смена документа не переносят результат [negative] [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: sessionAndDocumentCancellation. Задержать seal и по отдельности: hide, background, globe, смена documentIdentifier, поворот. Завершить старую задачу после открытия новой сессии/поля. Проверить также закрытие сразу после уже выполненного insertText. В реальном расширении пройти hide/reopen и переключение между двумя полями Debug-хозяина.
- **Ожидается:** Hide/background/globe: черновик очищен, отложенный результат 0 proxy в старом/новом поле, новая сессия пустая. Смена документа при активной сессии: 0 вставок, текст сохранён, «Поле сообщения изменилось — повторите попытку». Поворот: текст/получатель сохраняются, ≤1 вставки. Закрытие после вставки не вызывает повтор при открытии. AC12.
- **Почему провалит плохую работу:** Ловит поздний completion в чужой документ и повторную отправку после reopen.
- **Статус:** pass
- **Доказательство:** Independent core sessionAndDocumentCancellation PASS; actual full native10 and complete legacy execution cover hide/reopen/background/globe/rotation/two fields/no replay (legacy OFF observer failure is separately E19fail). External transient A-to-B-to-A PASS: Bvisible=true, Areturned=true at1.049/1.772sec before2sec delayed completion; owner unchanged, trace empty, draft preserved and document-changed message. See [transient proof](evidence/verifier-round2-functional/transient-document-probe.txt), [supplemental7](evidence/verifier-round2-functional/supplemental-summary.json), [native10](evidence/verifier-round2-functional/encrypt-runtime-summary.json).

## E14 · Успех и полоса статуса без скачка 
- **Тип:** ui
- **Шаги:** В реальном расширении зашифровать короткий текст для Анны; снять кадр и геометрию до, после и через 2 секунды (допуск наблюдения 0,3 секунды). Начать новый ввод. Длинное имя отдельно.
- **Ожидается:** После возврата вставки пустой черновик/нулевой курсор, выбранная Анна остаётся, «Зашифровано для Анна» показывается 2 секунды, затем обычный статус. Геометрия редактора/клавиш/поля хозяина не меняется из-за смены статуса. Новый ввод работает. Полное длинное имя доступно VoiceOver. AC6.
- **Почему провалит плохую работу:** Ловит toast поверх клавиш, исчезающий layout slot и очистку до успешной передачи.
- **Статус:** pass
- **Доказательство:** Actual native success geometry/cursor reset PASS and external full40-Character name AX PASS. Production SystemKeyboardClock observer PASS: positive-to-negative1.9523sec, conservative lifetime bounds1.903..2.274sec within1.7..2.3; source activity/action boundaries retained rather than assuming tap return equals insert. Before/success/ordinary frame arrays equal; new input works, recipient remains. See [clock bounds](evidence/verifier-round2-functional/success-clock-bounds.json), [observation](evidence/verifier-round2-functional/success-clock-observation.txt), [supplemental7](evidence/verifier-round2-functional/supplemental-summary.json).

## E15 · Приватность доказана до и после успеха и ошибки [security]
- **Тип:** command
- **Шаги:** На одном замороженном SHA расширить/использовать scripts/typing-audit.sh для сценариев 06. До прогона подтвердить установленный синтетический clipboard sentinel, известную непустую identity и видимость её Keychain metadata; задать уникальный синтетический черновик. Пройти набор, выбор, успех, сбой и закрытие. Сравнить clipboard, файлы App Group/контейнеров, UserDefaults, Keychain metadata и логи. Проанализировать все новые insertText/deleteBackward/adjustTextPosition/UIPasteboard/print/Logger/os_log/NSLog/UserDefaults/FileManager и reader/writer зависимости.
- **Ожидается:** Exit 0, audit prerequisites pass. Sentinel неизменен, нет сохранённого черновика/шифротекста/приватных ключей или новых Keychain items, кроме заранее созданной identity. Разрешён только UUID выбора в локальных preferences и существующий setup marker 04. Spy доказывает единственный выход шифротекста через insertText и отсутствие plaintext proxy; поиск строки дополняет проверку, не заменяет её. Никаких сетевых API/новых permissions. AC2, AC5, AC11.
- **Почему провалит плохую работу:** Ловит ложное «утечки не нашли» с пустым Keychain/clipboard и хранение plaintext вне проверяемой модели.
- **Статус:** pass
- **Доказательство:** Isolated frozen74 audit exit0/PASS; setup3/3 and canary1/1 separately. Actual clipboard sentinel before/after true/unchanged; known real identity1 equals native trustedA fullpublickey and metadatahashes unchanged. setupFailures[],failures[],unexpectedChanges[],canaryMatches[]; only existing group/keyboard-access.v1.json receipt changed. UUID-only preference/core gate/source boundary audit, shipping-controller proxy1/context0/delete0/adjust0 and Release/permissions checks complement runtime scan. See [audit result](evidence/verifier-round2-functional/audit-result.json), [before](evidence/verifier-round2-functional/audit-before.json), [after](evidence/verifier-round2-functional/audit-after.json), [known identity](evidence/verifier-round2-functional/audit-known-identity-proof.json), [privacy audit](evidence/verifier-round2-functional/privacy-sites.md).

## E16 · Подмена сообщения и отправителя отклоняется [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: tamperedInsertedMessage и существующие adversarial tests CipherCore. Для реального результата координатора изменить байт ciphertext, подпись, заменить sender key; при необходимости переподписать подменённым ключом, как в тестах ядра. Ввести недопустимый публичный ключ через недоверенный источник контактов.
- **Ожидается:** Ни один изменённый вариант не открывается как исходное доверенное сообщение; malformed/tampered/invalidKey согласно границе проверки. Недопустимый ключ не ведёт к вставке или plaintext fallback. Факт подписи привязан к полному senderKey. AC4, AC10.
- **Почему провалит плохую работу:** Ловит обход проверок ядра или собственный несовместимый формат в адаптере клавиатуры.
- **Статус:** pass
- **Доказательство:** Independent core169 PASS: tamperedInsertedMessage + full135 CipherCore adversarial cases reject changed bytes/signature/sender/invalid public keys. See [R2 core log](evidence/verifier-round2-functional/core.log).

## E17 · Все состояния совпадают с макетом [design]
- **Тип:** design
- **Шаги:** Сравнить каждый из 126 кадров с specs/06-encrypt-insert/mockup.html: все 17 state-* в портрете 375/402/440 обе темы (102); ready/picker/limit/long-name в альбоме 667/874/956 обе темы (24). Состояния fixture только Debug; реальная панель extension и системные safe areas. Дать manifest ожидаемых/полученных кадров и индивидуальный результат просмотра каждого.
- **Ожидается:** 126 уникальных кадров, ни одного missing. Все состояния/точные тексты из AC1–AC14, порядок и цвета соответствуют макету; допустимы различия SF/сглаживания до 2 pt. Panel ≤420/240 pt без safe area, поле хозяина видно. Нет обрезанных ошибок/наложений/переполнения; строки/управляющие действия ≥44×44 pt, клавиши в пределах исключений AC13. Нет подмены ошибок одним общим кадром.
- **Почему провалит плохую работу:** Ловит удобный частичный набор скриншотов и UI, существующий только в HTML.
- **Статус:** pending
- **Доказательство:** R2 remains pending: per root, complete126-frame design/live accessibility checks move to final R3 frozen source after correcting the stale legacy observer. No design pass/waiver or reduction of contract; R1 history is retained in [R1 report](evidence/verifier-round1-functional/report.md).

## E18 · Живые переходы и доступность [design] [regression]
- **Тип:** ui
- **Шаги:** 375×667 обе темы: настоящими клавишами пройти пусто → строка → четыре строки с Return → счётчик >3500; открыть/прокрутить/закрыть список, выбрать самое длинное имя (40 Character), выполнить ошибку/повтор/успех. Границы 402/440 и все три альбомных размера: ready↔picker, поворот с черновиком. VoiceOver: выбрать контакт, проверить выбранность, disabled/busy, ошибки и полное имя. Снять геометрию и последовательность действий.
- **Ожидается:** Каждый переход доступен, курсор виден, все четыре ряда и поле хозяина остаются на экране, нет второй клавиатуры, скрытого управления или обрезанной инструкции. Области касаний и высоты AC13 соблюдены; статус не меняет геометрию. Labels русские, ids AC14 сохранены, полное имя доступно без эллипсиса в accessibility. Статические 126 кадров не заменяют эту проверку.
- **Почему провалит плохую работу:** Ловит класс дефекта 05 D5: при обычном вводе контент обрезается, хотя статичные fixtures зелёные.
- **Статус:** pending
- **Доказательство:** R2 remains pending: per root, complete126-frame design/live accessibility checks move to final R3 frozen source after correcting the stale legacy observer. No design pass/waiver or reduction of contract; R1 history is retained in [R1 report](evidence/verifier-round1-functional/report.md).

## E19 · Регрессия, Release и стабильность расширения [regression] [security]
- **Тип:** command
- **Шаги:** На финальном SHA выполнить scripts/test.sh core, scripts/lint.sh, scripts/build.sh, сборку Release через scripts/build.sh -configuration Release, полный scripts/test.sh ui без фильтра и существующие typing runtime checks. В настоящем расширении 10 циклов выбора/шифрования/закрытия, один 4096-байтовый текст; сохранить host trace и crash/jetsam evidence. Проверить Release бинарники/entitlements и работающее превью набора 05.
- **Ожидается:** Все команды exit 0, полный UI suite без skip/скрытых failures; число и имена тестов записаны отдельно от focused reruns. Новый функционал не ослабил регрессии 01–05. Превью read-only, «До встречи!» неизменно, без новых действий шифрования. Нет freeze/crash/jetsam/подмены клавиатуры, debug seed/delay/fault hooks отсутствуют в Release. Сеть/RequestsOpenAccess/App Group/Keychain entitlements без незаявленных расширений. AC14.
- **Почему провалит плохую работу:** Ловит только локальные тесты модели, неполный UI suite и Debug-only работоспособность.
- **Статус:** fail
- **Доказательство:** Independent frozen74cbb522/rev101101654: core169/lint79/Python4/Debug/Release PASS; fresh full unfiltered UI33/33 PASS and native full10/10 PASS. Full legacy KeyboardRuntimeTests FAIL6/7,0skip: testEditingMatrixWithoutFullAccess at line57 expects AC11 banner in keyboard.identityStatus; actual metadata is Общие данные недоступны while real system/model access=false and keyboard.encrypt.status contains exact required banner. No product/test edits; actual OFFtyping contract diagnostic is separate and cannot replace full7. All installed app/extension/host bytes matched independent builds. E19 remains fail until the complete legacy suite is green on the accepted frozen source. See [legacy summary](evidence/verifier-round2-functional/typing-runtime-summary.json), [legacy log](evidence/verifier-round2-functional/typing-runtime.log), [fresh fullUI](evidence/verifier-round2-functional/fresh-full-ui-summary.json), [full native](evidence/verifier-round2-functional/encrypt-runtime-summary.json).

## E20 · Независимая приёмка высокого риска [security]
- **Тип:** ui
- **Шаги:** После зелёных технических evals отдельные verifier/reviewer в свежих контекстах проверяют замороженный SHA, reviewer выполняет глубокое security review по REVIEW.md. Затем first-time-user без доступа к коду: в готовой песочнице с синтетической личностью/контактами выбрать получателя, набрать текст и вставить шифротекст, убедиться, что отправка ручная; отдельно восстановиться после отсутствия выбора. Сохранить отчёты и замечания, передать пользователю для приёмки.
- **Ожидается:** Независимые отчёты относятся к проверенному установленному SHA; нет открытых важных находок. First-time-user достигает целей по UI без подсказок о внутренних механизмах, не отправляет реальных сообщений. Отчёт фиксирует помощь координатора/ограничения инструментов, если были. Слияние и done только после явной приёмки пользователя; до неё verified. Все AC.
- **Почему провалит плохую работу:** Ловит самоприёмку builder, скрытую помощь и преждевременный merge high-risk фичи.
- **Статус:** pending
- **Доказательство:** R2 acceptance pending: E19 full legacy6/7 remains fail due stale metadata/banner assertion; complete E17/E18 design evaluation, first-time-user, fresh independent final reports and explicit human acceptance remain required. No merge/done/20-of20 claim. See [R2 report](evidence/verifier-round2-functional/report.md).
