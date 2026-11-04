# Evals: Шифрование и вставка в сообщение

> Контракт приёмки. Все статусы сейчас pending; pass/fail и доказательства ставит только независимый verifier. Имена новых тестов ниже — требования к реализации, сейчас этих тестов нет. Одобрение контракта не является приёмкой реализации.

## E1 · Выбор контакта сохраняет черновик и курсор 
- **Тип:** ui
- **Шаги:** Настоящее расширение в Debug-хозяине, Full Access, личный ключ и 20 синтетических контактов с известными UUID/ключами. Ввести «Привет, Анна!», поставить внутренний курсор после «Привет», открыть keyboard.recipient, прокрутить к последнему контакту, выбрать его; снова открыть и нажать «Назад».
- **Ожидается:** Порядок совпадает с ContactBook, в строках имя и короткий отпечаток; выбранная строка отмечена. Выбор закрывает список, имя обновляется. Назад не меняет выбор. Черновик и курсор неизменны; поле хозяина/выделение не менялись. Первоначально получатель не выбран даже при одном контакте. AC1, AC14.
- **Почему провалит плохую работу:** Ловит декоративный список, потерю черновика и автоматический выбор первого контакта.
- **Статус:** pass
- **Доказательство:** R5 frozen19abc786/runtime442244589; NEWruntime125BB922 first-unselected before explicitchoice/nativeinsert. Independent E1 1/1,0fail/skip/warnings,36.292s: literal Привет, Анна!/cursor6,20orderedUUID/fingerprints, sharedfully2Drow+viewportstable>=.25s bounded5s/oneordinarytap, pickerclosed/exact40Яselected/editorexists, selectedtrait/Back/draftcursor/hosttext+selection unchanged. all14app/ext+host3 beforeafterbytes; actualUIKitVO=false x3. Three originalPNGs personallyopened. evidence/verifier-round5-functional/{e1-summary.json,e1-reconciliation.json,e1-before-byteproof.json,e1-after-byteproof.json,e1-personal-original-review.json}.

## E2 · Восстановление только актуального id [security]
- **Тип:** test
- **Шаги:** Написать Packages/CipherCore/Tests/KeyboardTypingTests/EncryptInsertTests.swift: rememberedRecipientID. Выбрать B, закрыть и открыть новую сессию; переименовать B с тем же ключом и снова открыть. Удалить B, добавить другой контакт с таким же именем и новым UUID; открыть. Проверить записи spy preferences.
- **Ожидается:** Восстанавливается только B по UUID; переименование обновляет имя. После удаления выбор пуст, одноимённый контакт не подставляется, сохранённый id сброшен. Единственная записанная величина — UUID; нет имени/ключа/черновика/шифротекста. AC2.
- **Почему провалит плохую работу:** Ловит выбор по имени, индексу или устаревшему объекту и лишнее постоянное хранение.
- **Статус:** pass
- **Доказательство:** R5 frozen19abc786/runtime442244589; independent core169/169(34KeyboardTyping+135CipherCore), lint79, Python4/4, own Debug/Release/signatures4/Releasehooks0. rememberedRecipientID PASS: UUID only, rename/reopen/delete/same-name/newUUID, spy values. Fresh coverage/core.log and source inspection recorded in evidence/verifier-round5-functional/core-encryption-coverage.json.

## E3 · Пустой и пробельный текст не шифруется [negative]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: eligibility. Матрица текстов "", " ", "\n\t ", "\u{00A0}", " а\n "; с получателем и без, с готовыми хранилищами и с unavailable/missing. Попытаться вызвать действие напрямую, обходя disabled UI.
- **Ожидается:** Пустые/whitespacesAndNewlines: 0 seal, 0 proxy. Без получателя/ключа тоже 0. Непустой « а\n » зашифровывается без trim и нормализации. UI disabled совпадает с координатором. AC3.
- **Почему провалит плохую работу:** Ловит защиту только цветом кнопки, проверку isEmpty и незаметное изменение сообщения.
- **Статус:** pass
- **Доказательство:** R5 frozen19abc786/runtime442244589; independent core169/169(34KeyboardTyping+135CipherCore), lint79, Python4/4, own Debug/Release/signatures4/Releasehooks0. eligibility PASS: all whitespace matrices including NBSP, direct disabled-boundary calls 0seal/0proxy, exact nontrimmed nonempty text; source coordinator guards independently inspected. evidence/verifier-round5-functional/core-encryption-coverage.json.

## E4 · Настоящее расширение вставляет одну строку в курсор [security]
- **Тип:** ui
- **Шаги:** Установить замороженную Debug-сборку, сопоставить SHA/хеш встроенного и установленного extension и runtime revision. Debug-хозяин: «До |встречи!» с пустым выделением. Набрать внутри «Привет, Анна!», выбрать Анну, нажать «Зашифровать». Записать proxy trace и итог хозяина. Повторить короткий сценарий в обычном поле приложения симулятора, например поиске Настроек.
- **Ожидается:** Единственная вставка C начинается ckmsg2:, является полной строкой без пробелов/CR/LF/многоточия и открывается ядром. Итог «До »+C+«встречи!»; префикс/суффикс сохранены. Нет deleteBackward/adjustTextPosition/первоначальной вставки открытого текста, автоматической отправки или clipboard. Сначала поле хозяина неизменно при наборе. Черновик пуст после возврата insertText. AC5, AC6.
- **Почему провалит плохую работу:** Ловит успех только в учебном превью/spy, старую установленную сборку и перезапись поля.
- **Статус:** pass
- **Доказательство:** R5 frozen19abc786/runtime442244589; FULLnative10/10,FULLlegacy7/7,FULLsupplement7/7,0fail/skip/warnings; all14app/ext+host3beforeafterbytes. Actualextension literalinsertion at hostcursor gives exactly До +C+встречи!, hosttrace1insert/0delete/0replace/no contextreads/no plaintext attyping; emptydraftafterreturn. Separately actualSettings C15 retainedcanonical/opened byactualKeychainA+B. evidence/verifier-round5-functional/{encrypt-runtime-reconciliation.json,supplemental-reconciliation.json,native-fifteen-proof-manifest.json}.

## E5 · Вставленное сообщение открывают только нужные ключи [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: insertedCiphertextRoundTrip. Взять именно аргумент proxy из интеграции координатора с настоящим CipherMessage.seal, а также строку из E4. Открыть как B (выбранный), A (отправитель), C (посторонний); у B проверить contacts с A и без A. Повторить с пробелами, переносами и Unicode.
- **Ожидается:** A и B получают точные исходные байты UTF-8, полный senderKey равен A. У B sender.contact соответствует A, без контакта sender.unknown; у A sender.me. C: CipherError.notARecipient. Нет использования фиктивного sealer в этом тесте. AC10.
- **Почему провалит плохую работу:** Ловит шифрование статичного текста, не тому контакту или без добавления себя.
- **Статус:** pass
- **Доказательство:** R5 frozen19abc786/runtime442244589; FULLnative10/10,FULLlegacy7/7,FULLsupplement7/7,0fail/skip/warnings; all14app/ext+host3beforeafterbytes. SAME15 unique exactcanonical native/SettingsC: actualKeychainA selfopen15 exactUTF8/fullsender.me +offlineBknown/unknown15 exactUTF8/fullsenderKey +third15notARecipient. Includesliteral/whitespace/newline/decomposedUnicode/4096/10cycles andseparateSettingsC;5negativeactualAcontrols. evidence/verifier-round5-functional/{native-fifteen-proof-manifest.json,native-fifteen-B-third.log,native-fifteen-explicit-unknown-proof.log}.

## E6 · Непустое выделение хозяина сохраняется [negative]
- **Тип:** ui
- **Шаги:** В Debug-хозяине выделить «встречи» в «До встречи!», ввести приватный черновик, выбрать контакт и нажать «Зашифровать». Снять выделение и повторить. Отдельно начать шифрование без выделения с управляемой задержкой и создать выделение до commit; эта попытка тоже не должна заменять текст.
- **Ожидается:** Первая попытка: 0 вставок/удалений/сдвигов, исходные текст и выделение хозяина сохранены, черновик/курсор сохранены, «Снимите выделение в поле сообщения». После снятия выделения новая явная попытка вставляет один шифротекст. AC5.
- **Почему провалит плохую работу:** Ловит стандартную замену выделенного текста через insertText и тихую потерю текста хозяина.
- **Статус:** pass
- **Доказательство:** R5 frozen19abc786/runtime442244589; fresh independent core169/169 and FULLnative10/10/0fail/0skip/warnings[],634.438s on actualRuntime125BB922; all14app/ext+host3beforeaftermatched. selectionRechecked + native testSelectionAndSuccessGeometry/testDoubleTapDelayedSelectionAndCancellation PASS: nonempty hostselection preserved,0proxy then newexplicitretry singleC; selection createdduringdelay also0. evidence/verifier-round5-functional/{core-encryption-coverage.json,encrypt-runtime-reconciliation.json}.

## E7 · Два нажатия дают одну вставку [negative]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: singleFlight. Управляемый sealer задержать, нажать дважды; попытаться набрать/удалить/сменить получателя, завершить sealer, снова нажать без ввода; затем ввести новый текст и нажать ещё раз. Параллельный UI-сценарий двойного касания в Debug-хозяине.
- **Ожидается:** В задержке «Шифруем…», кнопка/ввод/выбор заблокированы. До завершения 1 seal, после него ровно 1 insertText исходного снимка. Повтор без текста: 0 новых вставок. Новый непустой черновик шифруется один раз новым действием. AC7.
- **Почему провалит плохую работу:** Ловит debounce только на времени, гонку двух задач и навсегда заблокированную кнопку.
- **Статус:** pass
- **Доказательство:** R5 frozen19abc786/runtime442244589; fresh independent core169/169 and FULLnative10/10/0fail/0skip/warnings[],634.438s on actualRuntime125BB922; all14app/ext+host3beforeaftermatched. singleFlight + native testDoubleTapDelayedSelectionAndCancellation PASS: actualdelayedbusy/disabledinput+recipient, doubletap1seal/1insert, immutable snapshot, noemptyretry, newnonemptydraft newoperation. evidence/verifier-round5-functional/{core-encryption-coverage.json,encrypt-runtime-reconciliation.json}.

## E8 · Ошибка не теряет текст и допускает повтор [negative]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: failurePreservesDraft. По отдельности identity missing, unavailable и sealer throws; полный доступ есть, текст и внутренний курсор известны. Для unavailable убрать сбой и повторить. Проверить missing также в настоящем расширении чистой песочницы; ошибки — через Debug-only dependency, затем проверить её отсутствие в Release.
- **Ожидается:** До вставки 0 proxy. Текст/курсор прежние. missing: «Откройте приложение CipherKeyboard, чтобы создать ключ»; unavailable: «Ключ недоступен — откройте приложение CipherKeyboard»; seal failure: «Не удалось зашифровать сообщение. Повторите попытку». Повтор после восстановления даёт одну вставку. Ключ не создаётся/не пересоздаётся. AC8.
- **Почему провалит плохую работу:** Ловит очистку в defer, молчаливую ошибку, plaintext fallback и генерацию нового ключа.
- **Статус:** pass
- **Доказательство:** R5 frozen19abc786/runtime442244589; FULLnative10/10,FULLlegacy7/7,FULLsupplement7/7,0fail/skip/warnings; all14app/ext+host3beforeafterbytes. Freshcore failurePreservesDraft/unavailable/missing/sealerthrow and actualnativefault/retry PASS. CleanNoKeyC7 1/1/0fail/skip,46.837s; actualSettingsON,identitymetadata0 beforeinstall/afterinstall/aftertest,containerappneverlaunched/seednever,internaltypingА+hostunchanged/encryptdisabled/exactmissingmessage;all14+host3bytes. ActualReleasehooks0. evidence/verifier-round5-functional/{nokey-summary.json,nokey-after-identity-metadata.json,nokey-container-app-not-launched.json,nokey-long-success-personal-original-review.json}.

## E9 · Границы UTF-8 и независимая проверка длины [negative]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: utf8Boundaries. 3500/3501/4096/4097 байт ASCII и кириллица/emoji с известным utf8.count; счётчик проверить в настоящем расширении. 4096 байт зашифровать настоящим ядром. Ввод ещё одного символа отвергнуть; отдельно тестовым входом передать координатору 4097 байт, не меняя Release-лимит модели ввода.
- **Ожидается:** Счётчик только N>3500: «N / 4096 байт». 4096 байт открываются точно; сверхлимитный ввод целиком отклонён: «Сообщение не должно превышать 4096 байт». Защитный вход 4097: 0 proxy, неизменные текст/курсор, «Слишком длинное сообщение: 4097 из 4096 байт». AC9.
- **Почему провалит плохую работу:** Ловит подсчёт Character вместо байтов и отсутствие проверки длины вне UI.
- **Статус:** pass
- **Доказательство:** R5 frozen19abc786/runtime442244589; FULLnative10/10,FULLlegacy7/7,FULLsupplement7/7,0fail/skip/warnings; all14app/ext+host3beforeafterbytes. Freshutf8Boundaries/defensive4097 tests; nativeactual4096ciphertextsopenexactly; ordinary UIkeyattempt above4096rejectedwhole/counter4096/draftcursorpreserved. Defensivefixtureactual4097 rejects0newproxy/exactNerror distinct fromnormalinputlimit. evidence/verifier-round5-functional/{core-encryption-coverage.json,supplemental-reconciliation.json,native-fifteen-proof-manifest.json}.

## E10 · Удалённый или подменённый контакт не получает сообщение [negative] [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: recipientRevalidation. Выбрать B; после показа панели удалить его, заменить ключ под прежним UUID, вернуть unreadable; повторить каждую мутацию после начала задержанного seal до commit. Отдельно переименовать при неизменных UUID и обеих частях полного ключа. Проверить refresh при открытии списка.
- **Ожидается:** Удаление/замена ключа: 0 вставок, выбор и remembered id сброшены, «Данные изменились — выберите получателя заново»; до старта также нельзя молча принять новый ключ. Unreadable: 0 вставок, «Не удалось прочитать контакты», Повторить; повторное чтение восстанавливает доступность только для проверенного контакта. Переименование обновляет имя, адресат прежний. AC2, AC4.
- **Почему провалит плохую работу:** Ловит TOCTOU между выбором и вставкой, равенство только short fingerprint и доверие старому списку.
- **Статус:** pass
- **Доказательство:** R5 frozen19abc786/runtime442244589; independent core169/169(34KeyboardTyping+135CipherCore), lint79, Python4/4, own Debug/Release/signatures4/Releasehooks0. recipientRevalidation PASS before/after suspension: removal, fullkey/signing-only replacement, unreadable/recovery, sameid/fullkey rename; source refresh/readContacts inspected. evidence/verifier-round5-functional/core-encryption-coverage.json.

## E11 · Смена личного ключа отменяет операцию [negative] [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: identityRevalidation. Начать seal как A, перед завершением заменить identity на A2 с другим полным public key либо сделать чтение unavailable/missing.
- **Ожидается:** 0 proxy. При A2 выбор сброшен и «Данные изменились — выберите получателя заново». При unavailable/missing соответствующая ошибка AC8. В активной сессии текст/курсор сохранены. Нет подписи неожиданной новой личностью. AC4, AC8.
- **Почему провалит плохую работу:** Ловит использование старого key snapshot без проверки и тихую смену отправителя.
- **Статус:** pass
- **Доказательство:** R5 frozen19abc786/runtime442244589; independent core169/169(34KeyboardTyping+135CipherCore), lint79, Python4/4, own Debug/Release/signatures4/Releasehooks0. identityRevalidation and six recovery/baseline cases PASS; independent oldR1 replay missing/unavailable→A2 now changed/reselect/0insert, draft preserved. evidence/verifier-round5-functional/{core-encryption-coverage.json,independent-r1-replay.log}.

## E12 · Полный доступ проверяется в момент действия [negative] [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: accessGate. При hasFullAccess=false вызвать open/select/encrypt с reader/storage spies. Затем начать операцию с true, отозвать доступ до commit. В настоящем расширении отдельно включить и выключить Full Access в Settings; после возврата проверить панель и возможность набора.
- **Ожидается:** Без доступа 0 чтений/записей общих хранилищ и remembered preferences, выбор/шифрование disabled, баннер «Включите «Полный доступ» в Настройках, чтобы шифровать»; набор работает. После отзыва 0 вставок и больше нет обращений к защищённым хранилищам. AC11.
- **Почему провалит плохую работу:** Ловит guard только при запуске и debug fixture вместо настоящего системного разрешения.
- **Статус:** pass
- **Доказательство:** R5 frozen19abc786/runtime442244589; FULLnative10/10,FULLlegacy7/7,FULLsupplement7/7,0fail/skip/warnings; all14app/ext+host3beforeafterbytes. FreshaccessGate spies0identity/contact/preferencescalls withoutaccess andafterrevocationbeforecommit0proxy. ActualSettingsOFF/ON/nativelegacyOFF+suppactualdenied twice withbothselectedpreconditions; system/modelFullAccessfalse/exactAC11banner/typingworks/hostunchanged/recipient+encryptdisabled. evidence/verifier-round5-functional/{core-encryption-coverage.json,typing-runtime-reconciliation.json,supplemental-reconciliation.json,actual-UIKit-VoiceOver-readbacks.json}.

## E13 · Закрытие и смена документа не переносят результат [negative] [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: sessionAndDocumentCancellation. Задержать seal и по отдельности: hide, background, globe, смена documentIdentifier, поворот. Завершить старую задачу после открытия новой сессии/поля. Проверить также закрытие сразу после уже выполненного insertText. В реальном расширении пройти hide/reopen и переключение между двумя полями Debug-хозяина.
- **Ожидается:** Hide/background/globe: черновик очищен, отложенный результат 0 proxy в старом/новом поле, новая сессия пустая. Смена документа при активной сессии: 0 вставок, текст сохранён, «Поле сообщения изменилось — повторите попытку». Поворот: текст/получатель сохраняются, ≤1 вставки. Закрытие после вставки не вызывает повтор при открытии. AC12.
- **Почему провалит плохую работу:** Ловит поздний completion в чужой документ и повторную отправку после reopen.
- **Статус:** pass
- **Доказательство:** R5 frozen19abc786/runtime442244589; fresh core169/169 sessionAndDocumentCancellation PASS, FULLnative10/10 inclactualdelayedhide/reopen+TwoHostDocumentsRejectLateCompletion+bothdirection/theme rotations, FULLlegacy7/7 inclactualbackground/globe/lifecycleclear. Delayedcompletion0insert in wrong/newfield, activesessiondraft preservedon documentchange, hide/reopenempty/no replay. exactall14app/ext+host3beforeafterbytes. evidence/verifier-round5-functional/{core-encryption-coverage.json,encrypt-runtime-reconciliation.json,typing-runtime-reconciliation.json,native-caret-geometry-summary.json}.

## E14 · Успех и полоса статуса без скачка 
- **Тип:** ui
- **Шаги:** В реальном расширении зашифровать короткий текст для Анны; снять кадр и геометрию до, после и через 2 секунды (допуск наблюдения 0,3 секунды). Начать новый ввод. Длинное имя отдельно.
- **Ожидается:** После возврата вставки пустой черновик/нулевой курсор, выбранная Анна остаётся, «Зашифровано для Анна» показывается 2 секунды, затем обычный статус. Геометрия редактора/клавиш/поля хозяина не меняется из-за смены статуса. Новый ввод работает. Полное длинное имя доступно VoiceOver. AC6.
- **Почему провалит плохую работу:** Ловит toast поверх клавиш, исчезающий layout slot и очистку до успешной передачи.
- **Статус:** pass
- **Доказательство:** R5 frozen19abc786/runtime442244589; FULLnative10/10,FULLlegacy7/7,FULLsupplement7/7,0fail/skip/warnings; all14app/ext+host3beforeafterbytes. Actualsuccesscleartext/cursor0/recipientretained; before-success-ordinaryframearraysexactequal. Productionclock conservativeoriginalactivitybounds1.791563–2.164102s within1.7–2.3,notclaimedexact2.000. Real40Яselected via shared2Dstableordinarytouch,exactfullstatusAX,newtypingworks. OriginalPNGs personallyopened;fullVOlabelavailable,actualspeech/activationreservedE18. evidence/verifier-round5-functional/{success-clock-bounds.json,success-clock-observation.txt,nokey-long-success-personal-original-review.json}.

## E15 · Приватность доказана до и после успеха и ошибки [security]
- **Тип:** command
- **Шаги:** На одном замороженном SHA расширить/использовать scripts/typing-audit.sh для сценариев 06. До прогона подтвердить установленный синтетический clipboard sentinel, известную непустую identity и видимость её Keychain metadata; задать уникальный синтетический черновик. Пройти набор, выбор, успех, сбой и закрытие. Сравнить clipboard, файлы App Group/контейнеров, UserDefaults, Keychain metadata и логи. Проанализировать все новые insertText/deleteBackward/adjustTextPosition/UIPasteboard/print/Logger/os_log/NSLog/UserDefaults/FileManager и reader/writer зависимости.
- **Ожидается:** Exit 0, audit prerequisites pass. Sentinel неизменен, нет сохранённого черновика/шифротекста/приватных ключей или новых Keychain items, кроме заранее созданной identity. Разрешён только UUID выбора в локальных preferences и существующий setup marker 04. Spy доказывает единственный выход шифротекста через insertText и отсутствие plaintext proxy; поиск строки дополняет проверку, не заменяет её. Никаких сетевых API/новых permissions. AC2, AC5, AC11.
- **Почему провалит плохую работу:** Ловит ложное «утечки не нашли» с пустым Keychain/clipboard и хранение plaintext вне проверяемой модели.
- **Статус:** pass
- **Доказательство:** R5 frozen19abc786/runtime442244589; LASTisolatedaudit setup3/canary1 PASS/exit0, actualsynthetic sentinel confirmedbefore+after unchanged; realidentitymetadata1→1/hashesequal, prerequisites[]/failures[]/unexpected[]/canaryMatches[]. Actualchangedfiles EXACTONLY group/keyboard-access.v1.json receipt04(37bytes); UUIDpref wasUNCHANGED, notclaimedasactualdiff. LASTaudit retained full publicA EXACTmatches trustednativeA and all15actualC fullsender keys; no metadata-only/shortfingerprint inference, see audit-known-public-identity-proof.json. Sourceprivacy boundaryreview+core spies,Releasehooks0,lint79. NoUI/clipboardconsumeraftercanary. evidence/verifier-round5-functional/{audit-final-comparison.json,audit-setup-reconciliation.json,audit-canary-reconciliation.json,privacy-sites.md,shutdown-allclear.json}.

## E16 · Подмена сообщения и отправителя отклоняется [security]
- **Тип:** test
- **Шаги:** EncryptInsertTests.swift: tamperedInsertedMessage и существующие adversarial tests CipherCore. Для реального результата координатора изменить байт ciphertext, подпись, заменить sender key; при необходимости переподписать подменённым ключом, как в тестах ядра. Ввести недопустимый публичный ключ через недоверенный источник контактов.
- **Ожидается:** Ни один изменённый вариант не открывается как исходное доверенное сообщение; malformed/tampered/invalidKey согласно границе проверки. Недопустимый ключ не ведёт к вставке или plaintext fallback. Факт подписи привязан к полному senderKey. AC4, AC10.
- **Почему провалит плохую работу:** Ловит обход проверок ядра или собственный несовместимый формат в адаптере клавиатуры.
- **Статус:** pass
- **Доказательство:** R5 frozen19abc786/runtime442244589; independent core169/169(34KeyboardTyping+135CipherCore), lint79, Python4/4, own Debug/Release/signatures4/Releasehooks0. tamperedInsertedMessage and full CipherCore adversarial tests PASS: payload/signature/sender replacement and noncanonical/loworder publickey negatives; trusted sender tied to fullkey. evidence/verifier-round5-functional/{core.log,core-encryption-coverage.json}.

## E17 · Все состояния совпадают с макетом [design]
- **Тип:** design
- **Шаги:** Сравнить каждый из 126 кадров с specs/06-encrypt-insert/mockup.html: все 17 state-* в портрете 375/402/440 обе темы (102); ready/picker/limit/long-name в альбоме 667/874/956 обе темы (24). Состояния fixture только Debug; реальная панель extension и системные safe areas. Дать manifest ожидаемых/полученных кадров и индивидуальный результат просмотра каждого.
- **Ожидается:** 126 уникальных кадров, ни одного missing. Все состояния/точные тексты из AC1–AC14, порядок и цвета соответствуют макету; допустимы различия SF/сглаживания до 2 pt. Panel ≤420/240 pt без safe area, поле хозяина видно. Нет обрезанных ошибок/наложений/переполнения; строки/управляющие действия ≥44×44 pt, клавиши в пределах исключений AC13. Нет подмены ошибок одним общим кадром.
- **Почему провалит плохую работу:** Ловит удобный частичный набор скриншотов и UI, существующий только в HTML.
- **Статус:** pass
- **Доказательство:** R5 frozen19abc786/runtime442244589; fresh independentdesign ALL126unique/personallyindividuallyopened/0missing/0duplicate:102portrait17states×3sizes×2themes+24landscape4states×3sizes×2themes. 126state/content/geometry/surfacepalettePASS;114scheduledEncryptCSSPASS,12pickerframesbuttonabsent. Functionalstatusowner independentlyrechecked exact126identityset+alloriginalSHA unchanged+reference5dd5652c. evidence/verifier-round5-design/{E17-126-review.md,E17-126-manifest-review.json}. Additional livebusy rawRGBnegatives retained separately; not counted amongscheduled126/notall-transitionRGBclaim, narrowassessment evidence/reviewer-round5/live-busy-contract-note.md. E18/E20stillpending.

## E18 · Живые переходы и доступность [design] [regression]
- **Тип:** ui
- **Шаги:** 375×667 обе темы: настоящими клавишами пройти пусто → строка → четыре строки с Return → счётчик >3500; открыть/прокрутить/закрыть список, выбрать самое длинное имя (40 Character), выполнить ошибку/повтор/успех. Границы 402/440 и все три альбомных размера: ready↔picker, поворот с черновиком. VoiceOver: выбрать контакт, проверить выбранность, disabled/busy, ошибки и полное имя. Снять геометрию и последовательность действий.
- **Ожидается:** Каждый переход доступен, курсор виден, все четыре ряда и поле хозяина остаются на экране, нет второй клавиатуры, скрытого управления или обрезанной инструкции. Области касаний и высоты AC13 соблюдены; статус не меняет геометрию. Labels русские, ids AC14 сохранены, полное имя доступно без эллипсиса в accessibility. Статические 126 кадров не заменяют эту проверку.
- **Почему провалит плохую работу:** Ловит класс дефекта 05 D5: при обычном вводе контент обрезается, хотя статичные fixtures зелёные.
- **Статус:** pending
- **Доказательство:** R5 frozen19abc786/runtime442244589: completedHEADLESS six full live methods PASS1/1each,116/116 originals personallyopenedbyindependentdesigner/currentSHArechecked,375both1751ordinarytaps→3502UTF8,104geometryrecords0fail; actualVOspeech/navigation1/1(95.921s)/4originals, cleanupactualfalse2. FreshO1sixteen402/440postlooporiginals445ink/260solid closeboundedobservedglyphdefect, internalcauseUNKNOWN.16completedphasessource100/79Swift+installed14/host3+8drivers/binary/currentversions/min0beforeaftermatched; headlessown3Shutdown/runners-hosts-extension0/clipboard0/protecteduntouched. E18STILLPENDING requirednativeAXdefaultActivateactual-effectchain underVOenabled/currentSpeech: hostpositivecontrol, recipient/full40name/encrypt/error/retry/busy/success. После повторного unlock nativeAX attempt завершился FAIL399.571s: hostAXpositivecontrolPASS при actualVOtrue/currentSpeech, но coordinateCUA noWindowsAvailable не позволил активировать recipient; product activation не доказана. Cleanup-only1/1PASS/actualVOfalse, own3Shutdown; original501failureattachments сохранены. Root mirror touch delivery не подтверждена, после нового Maclocked всё остановлено. Пользователь явно прекратил проверки и разрешил слияние при E18/E20pending. См. native-ax-active-attempt.json, native-failed501-artifact-manifest.json, nativeAX375-cleanup-receipt.json, final-allclear.json в evidence/verifier-round5-design/. FourlivebusyrawRGBnegatives/twowithin±1retainedseparately; noalltransitionRGBpass/firstdeadlinewaiver/causeclaim. evidence/verifier-round5-design/{E18-live-review.md,E18-116-live-manifest-review.json,completed-phase-attestation.json,headless-allclear.json,native-ax-environment-block.json,native-ax-resume.json}; narrowcontractnote evidence/reviewer-round5/live-busy-contract-note.md. E20pending/noFTUE.

## E19 · Регрессия, Release и стабильность расширения [regression] [security]
- **Тип:** command
- **Шаги:** На финальном SHA выполнить scripts/test.sh core, scripts/lint.sh, scripts/build.sh, сборку Release через scripts/build.sh -configuration Release, полный scripts/test.sh ui без фильтра и существующие typing runtime checks. В настоящем расширении 10 циклов выбора/шифрования/закрытия, один 4096-байтовый текст; сохранить host trace и crash/jetsam evidence. Проверить Release бинарники/entitlements и работающее превью набора 05.
- **Ожидается:** Все команды exit 0, полный UI suite без skip/скрытых failures; число и имена тестов записаны отдельно от focused reruns. Новый функционал не ослабил регрессии 01–05. Превью read-only, «До встречи!» неизменно, без новых действий шифрования. Нет freeze/crash/jetsam/подмены клавиатуры, debug seed/delay/fault hooks отсутствуют в Release. Сеть/RequestsOpenAccess/App Group/Keychain entitlements без незаявленных расширений. AC14.
- **Почему провалит плохую работу:** Ловит только локальные тесты модели, неполный UI suite и Debug-only работоспособность.
- **Статус:** pass
- **Доказательство:** R5 FINALfrozen19abc786/runtime442244589: independentcore169(34+135),lint79,Python4,ownDebug/actualRelease4signatures/Debugpositive/Releasehooks0/permissionsunchanged; NEWcleanunseededUI499 full33/33(990.370s), exactnames/new1/removed0/0fail/skip/warnings; NEWruntime125 FULLnative10/10(634.438s),FULLlegacy7/7(280.428s),FULLsupplement7/7(216.289s),NoKey1/1(46.837s),auditLAST3+1PASS. Actual10cycles+4096/lifecycle/read-onlypreview; all100sources79Swiftincluntrackedfrozen, all14app/ext+host3beforeafter/finalmatched, newtargetcrashes0,ownshutdown/runners0/main+FTUEuntouched. UIinitialmin0→final1undetermined preserved; exactruntimephase min0+actualkeyboardchecked. OriginalR4fullnative9/10FAILretained/causeunknown; nofocusedsubstitute. Simulator evidence doesnotclaimphysicaljetsamlimit. evidence/verifier-round5-functional/{independent-command-checks.json,fresh-full-ui-reconciliation.json,encrypt-runtime-reconciliation.json,typing-runtime-reconciliation.json,supplemental-reconciliation.json,final-source-attestation.json,final-diagnostic-inventory.json,shutdown-allclear.json}.

## E20 · Независимая приёмка высокого риска [security]
- **Тип:** ui
- **Шаги:** После зелёных технических evals отдельные verifier/reviewer в свежих контекстах проверяют замороженный SHA, reviewer выполняет глубокое security review по REVIEW.md. Затем first-time-user без доступа к коду: в готовой песочнице с синтетической личностью/контактами выбрать получателя, набрать текст и вставить шифротекст, убедиться, что отправка ручная; отдельно восстановиться после отсутствия выбора. Сохранить отчёты и замечания, передать пользователю для приёмки.
- **Ожидается:** Независимые отчёты относятся к проверенному установленному SHA; нет открытых важных находок. First-time-user достигает целей по UI без подсказок о внутренних механизмах, не отправляет реальных сообщений. Отчёт фиксирует помощь координатора/ограничения инструментов, если были. Слияние и done только после явной приёмки пользователя; до неё verified. Все AC.
- **Почему провалит плохую работу:** Ловит самоприёмку builder, скрытую помощь и преждевременный merge high-risk фичи.
- **Статус:** pending
- **Доказательство:** Frozen 19abc786d9a4d1cb86a1b478808470f01b6a0e09 / runtime442244589: независимые functional/design/reviewer отчёты R5 сохранены, 18/20 PASS; nativeAX часть E18 не завершена, отдельный UI-only Release first-time-user не запускался. Пользователь остановил приёмку и прямо указал «Делай слияние». Это разрешение слияния при неполных проверках, а не основание для pass E20 или verified/done; E20 остаётся pending. Решение и ограничения записаны в state.md.

## E21 · Предупреждение о длине сообщения Telegram [regression] [security]
- **Тип:** test
- **Шаги:** `scripts/test.sh core --filter EncryptInsertTests/singleMessageWarningDoesNotOverrideErrorsOrChangeDraft; scripts/test.sh core --filter SecurityReviewTests/singleMessageBoundaryUsesRealTimestampedCiphertext`
- **Ожидается:** 2720 байт дают не более 4096 символов ckmsg2, 2721 и 4096 — больше; реальный round-trip проходит. После 2720 появляется подсказка, ошибки приоритетнее; черновик не обрезается, шифрование доступно, удаление снимает предупреждение.
- **Почему провалит плохую работу:** закрепляет воспроизведение из security review 2026-11-04; старое поведение не удовлетворяет проверке.
- **Статус:** pass
- **Доказательство:** Independent verifier 2026-11-04: singleMessageWarningDoesNotOverrideErrorsOrChangeDraft и singleMessageBoundaryUsesRealTimestampedCiphertext PASS — границы 2720/2721/4096, реальный round-trip, предупреждение, доступность шифрования, сохранение черновика, приоритет no-access, удаление. Дополнительный utf8Boundaries PASS подтвердил приоритет limitError и шифрование 4096 байт. specs/security-review-fixes-2026-11-04-evidence/{targeted-swift.log,utf8-priority-swift.log}; SHA256 в source-sha256.json. UI/Release/приёмка сюда не включены.
