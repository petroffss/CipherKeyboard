# Evals: Расшифровка полученных сообщений

> Контракт до кода. Статусы ставит только независимый verifier с доказательством. Все проверки пока pending.
> Имена новых тестов ниже — задания builder, не утверждение о существующих тестах. Только синтетические ключи/сообщения. Runtime: установленный extension и приложение, SHA/хеши бинарников/runtime revision в evidence.

## E1 · Чтение буфера только по действию [security]
- **Тип:** test
- **Шаги:** `Packages/CipherCore/Tests/KeyboardTypingTests/DecryptTests.swift › explicitReadOnly` и `UITests/DecryptUITests.swift › testExplicitClipboardRead`: открыть панель, ждать 5 секунд, сменить раскладку и повернуть; затем одно нажатие «Расшифровать». Reader spy считает отдельно metadata и content; UI проверяет реальный адаптер.
- **Ожидается:** до действия 0 чтений; после 1 попытка получения текста, без опроса/автоповтора. Чтений контекста хозяина ради сообщения нет. Действие доступно без выбранного адресата и с пустым черновиком; учебное превью буфер не читает. AC1.
- **Почему провалит плохую работу:** ловит чтение при открытии/таймере и кнопку, ошибочно зависимую от получателя шифрования.
- **Статус:** pending
- **Доказательство:** Core explicitReadOnly/synchronousSnapshotStillHonorsGates PASS; собственный real-adapter 5s+layout+rotation сценарий не завершён в R1. Native Allow и E2 не заменяют zero-read proof.

## E2 · Получатель видит точный проверенный текст
- **Тип:** ui
- **Шаги:** в настоящем 06 зашифровать `  Привет, Анна!\nЗавтра в 19:30 👨‍👩‍👧‍👦  ` для B от A; скопировать вставленную строку; открыть расширение B с A в контактах; нажать «Расшифровать», затем повторить в приложении B.
- **Ожидается:** точные пробелы/Unicode/перевод строки, «Расшифровано», «От: Анна», «✓ Подпись верна», «Закрыть». Исходная строка соответствует полному ключу A. Никаких клавиш редактирования результата. AC4/15.
- **Почему провалит плохую работу:** ловит заглушку, обрезку whitespace и проверку лишь fake-opener вместо пути от 06.
- **Статус:** pass
- **Доказательство:** Verifier R1: реальные Keychain A/B обменяны PUBLIC keys через ContactStore; actual06-A-insert-and-self.xcresult PASS1/1, actual06-C-receiverB-after-native-consent.xcresult PASS1/1 на том же C, SHA256 f129d9c468bdfa3b4b7776dfec88b41095a3f9f650aa4812e9cc2a9c7144c6e3; byte-identical consumed attachment, exact whitespace/Unicode/sender/signature на keyboard+app; specs/07-decrypt/evidence/verifier-round1/actual06-C-receiver-identity-proof.json, originals actual06-receiverB-success/ лично открыты; runtime1603781559/installed hashes совпали.

## E3 · Собственный и неизвестный отправитель [security]
- **Тип:** test
- **Шаги:** `DecryptTests.swift › senderIdentity`: открыть своё сообщение, A без контакта, контакт с тем же именем и иным ключом; ввести разные полные ключи с одинаковым отображаемым short fingerprint через управляемое представление, не менять криптоядро. UI `DecryptUITests › testSenderVariants` — self/unknown на обеих поверхностях.
- **Ожидается:** self → «От: вы»; unknown → «От неизвестного ключа <2 группы>», подсказка добавить контакт и верная подпись. Сравниваются обе части PublicKey; чужое имя не назначается. AC4/5.
- **Почему провалит плохую работу:** ловит совпадение по короткому отпечатку/имени и ложное подтверждение личности.
- **Статус:** pending
- **Доказательство:** Core senderIdentity/displayFingerprintCollision и полный UI testSenderVariants PASS; self actualA PASS. Собственный native unknown на keyboard в R1 ещё не проверен, потому полный E3 не pass.

## E4 · Контакты перечитываются, ошибки не дают старого имени [negative] [security]
- **Тип:** test
- **Шаги:** `DecryptTests.swift › contactsRefresh`: с задержанным opener переименовать/удалить контакт, заменить одну часть ключа, сделать reader недоступным перед публикацией; отдельно self при ошибке reader. Проверить также изменение до запуска. UI — contact/unknown/contacts-warning.
- **Ожидается:** переименование видно, удаление/замена → unknown, ошибка → unknown с предупреждением AC5; self остаётся self. Старый кеш и UUID не определяют отправителя, текст подлинного сообщения доступен. AC5.
- **Почему провалит плохую работу:** ловит имя из устаревшего списка или полный отказ читать подлинное сообщение при сбое контактов.
- **Статус:** pending
- **Доказательство:** Core contactsRefresh и sender-part collision tests PASS; native contact/unknown/contacts-warning UI сопоставление не выполнено в раннем failed round.

## E5 · Первый конверт и вход с текстом вокруг [negative]
- **Тип:** test
- **Шаги:** `DecryptTests.swift › firstEnvelopeMatchesCore`: сравнить UI-модель с прямым `CipherMessage.open` для текста до/после, whitespace внутри, двух сообщений, повреждённого/чужого/ckmsg2 первым и корректного вторым; пустой текст и обычная фраза. В `MessageParsingTests.swift` сохранить регрессию ядра.
- **Ожидается:** одинаковые результат/ошибка с ядром, второе сообщение не подменяет первое; noMessage даёт точный текст AC6 для соответствующей поверхности. AC3/6.
- **Почему провалит плохую работу:** ловит самостоятельный regex, поиск только ckmsg1 и пропуск неуспешного первого сообщения.
- **Статус:** pass
- **Доказательство:** Verifier R1 scripts/test.sh core exit0: KeyboardTyping50/6 + CipherCore135/23; firstEnvelopeMatchesCore и MessageParsing regressions PASS (surrounding/whitespace/first corrupt/foreign/version/noMessage). specs/07-decrypt/evidence/verifier-round1/core.log.

## E6 · Подделка, чужой получатель и версия [negative] [security]
- **Тип:** test
- **Шаги:** `DecryptTests.swift › rejectedMessagesNeverPublishText`, реальные `TamperTests.swift`: изменить байт ciphertext/подписи, подменить ключ отправителя, оборвать base64, дать шифротекст для C и `ckmsg2:`. В `DecryptUITests › testErrorsAfterSuccess` сначала успех, затем каждую ошибку и управляемую прочую ошибку на обеих поверхностях.
- **Ожидается:** точные ошибки AC6; нет старого/нового открытого текста и значка успешной подписи ни в визуальном, ни в accessibility дереве. AC4/6.
- **Почему провалит плохую работу:** ловит показ текста до верификации, неверный mapping и оставшийся успешный экран после ошибки.
- **Статус:** pending
- **Доказательство:** Core rejectedMessagesNeverPublishText/tamperedBytesAndSenderNeverPublish/TamperTests PASS, app testErrorsAfterSuccess PASS в fullUI38/40; extension error-after-success на обеих поверхностях полностью не выполнен.

## E7 · Нативное разрешение и отказ clipboard [negative] [security]
- **Тип:** ui
- **Шаги:** на целевой iOS скопировать синтетический шифротекст из отдельного приложения; в реальном расширении разрешить чтение, отдельно отклонить системный запрос/настроить запрет. Затем пустой буфер и нетекстовый тип. В приложении проверить системную вставку с разрешением/отказом, включая прежний ввод. Зафиксировать SDK/iOS, реальные результаты API и системное состояние, без private API; не ограничиваться fake-reader.
- **Ожидается:** разрешение даёт сообщение, пустой/нетекстовый → noMessage; объявленный текст без полученного значения → «Нет доступа к буферу обмена». Отказ не обходит защиту и не повторяет запрос. Системная вставка приложения без callback/значения сохраняет ввод и не запускает open, сообщённая ошибка показывает AC7. Невозможность вызвать реальный отказ на данной среде фиксируется как непроверенная часть, не pass по fake. AC7.
- **Почему провалит плохую работу:** ловит несуществующий callback отказа, скрытые повторные чтения и фиктивное нативное доказательство.
- **Статус:** pending
- **Доказательство:** Собственные nativeAllowA2/2 и actualAskB→PB refusal/recovery→штатный AllowB по конкретному согласию→exactC PASS подтверждены PNG/logs; explicitDeny/empty/nontext и app refusal с прежним вводом не выполнены. specs/07-decrypt/evidence/verifier-round1/B-actual-ask-refused-recovery.png и B-native-Allow-selected-after-specific-consent.png; builder evidence не заменяет verifier.

## E8 · Полный доступ и личный ключ [negative] [security]
- **Тип:** test
- **Шаги:** `DecryptTests.swift › accessAndIdentity`: no-access, missing key, Keychain unavailable/corrupted; отозвать доступ/сменить полный identity при задержанном opener. UI `testAccessAndKeyErrors` — доступные сценарии в расширении и временная ошибка на вкладке приложения.
- **Ожидается:** сообщения AC8/9, без доступа 0 вызовов reader/Keychain/contacts ради действия, 0 создания/записи ключей; смена identity не публикует результат. Повтор после восстановления работает. AC8/9.
- **Почему провалит плохую работу:** ловит утечку до проверки права и самовольное восстановление ключа.
- **Статус:** fail
- **Доказательство:** Независимый контрпример: success→identity missing/unavailable→refresh сохраняет result при error!=nil и identityAvailable=false на keyboard/app (4 cases). specs/07-decrypt/evidence/verifier-round1/independent-counterexamples.log и IndependentCounterexamples.swift; Decrypt.swift:100/readIdentity nil branch. Initial gates tests PASS, но этот переход нарушен.

## E9 · Двойное нажатие и взаимоисключение операций [negative]
- **Тип:** test
- **Шаги:** `DecryptTests.swift › singleFlightAndCancel`: задержать reader и opener отдельно, дважды нажать запуск, сменить clipboard, пытаться шифровать, закрыть, начать новую операцию и завершить старую последней. `DecryptUITests › testBusyAndCancel` показывает реальный busy и отмену.
- **Ожидается:** один вход/один open; вход зафиксирован; «Расшифровываем…»; закрытие работает; старое завершение не убирает/не меняет новый результат; 0 вставок. AC2/9/10.
- **Почему провалит плохую работу:** ловит гонку старого callback и параллельное шифрование.
- **Статус:** pass
- **Доказательство:** Verifier R1 core singleFlightAndCancel/synchronousSnapshotStillHonorsGates/preservesComposeAndHost PASS; полный UI testBusyAndCancel PASS: busy/close/late-result absence. specs/07-decrypt/evidence/verifier-round1/core.log и full-ui-tests.json; общий fullUI отдельно FAIL E19.

## E10 · Закрытие возвращает прежний черновик [regression]
- **Тип:** ui
- **Шаги:** настоящий extension: набрать многострочный черновик с курсором внутри слова, выбрать B, поставить курсор/выделение в поле хозяина с текстом до и после; открыть успех и ошибку, закрыть. Сравнить всё до/после; модель `DecryptTests › preservesComposeAndHost` использует spy proxy.
- **Ожидается:** прежний черновик/курсор/получатель сохранены, поле хозяина/выделение не изменены; 0 insert/delete/adjust. После окончания сессии черновик очищается по 05. AC10/12.
- **Почему провалит плохую работу:** ловит потерю черновика и восстановление его вставкой в мессенджер.
- **Статус:** pending
- **Доказательство:** Core preservesComposeAndHost PASS, actual06 self close сохранил host string; настоящий многострочный compose+inside-word caret+recipient+host selection success/error контракт целиком не выполнен.

## E11 · Жизненный цикл стирает просмотр [negative] [security]
- **Тип:** ui
- **Шаги:** `DecryptUITests › testLifecycle` на успехе и задержанной операции: закрыть клавиатуру, глобус, фон хозяина, смена документа; приложение — другая вкладка/фон. Возврат и новая операция. Проверить actual lifecycle и disappearance, не только тестовый флаг; модель `DecryptTests › lifecycleInvalidatesGeneration` покрывает все переходы и отзыв доступа.
- **Ожидается:** результат/вход/ошибка отсутствуют после возврата; поздний callback не возвращает текст, старая операция освобождена, новой не мешает. AC9/11.
- **Почему провалит плохую работу:** ловит сохранение состояния в модели после исчезновения view и перенос текста в другой документ.
- **Статус:** fail
- **Доказательство:** Поздний native item-provider callback после deactivate/reactivate меняет новую строку: NEW-INPUT→NEW-INPUTckmsg1:STALE-DELIVERY. Byte-identical production Delegate в отдельном UIKit probe, native UITextView.paste(itemProviders:), explicit generation transition; это не claim actual shipping tab/background test. specs/07-decrypt/evidence/verifier-round1/native-paste-counterexample.json/PNG; reviewer-round1/report.md finding2. Остальная actual lifecycle matrix ещё не завершена.

## E12 · Приватность результата и системный снимок [security]
- **Тип:** ui
- **Шаги:** попытаться long-press/select/drag/share результата на обеих поверхностях; снять переключатель задач после ухода в фон с открытым canary; до/после проверенные логи, файлы/настройки App Group/приложения/расширения, метаданные Keychain. Известные identity и clipboard sentinel; подтверждённая доступность источников аудита; read-only проверка всех новых paste/proxy/log/storage вызовов Debug и Release.
- **Ожидается:** нет меню/копирования/записи/сети/новых Keychain записей; буфер побайтно прежний; canary только в активной памяти/UI и синтетических test artifacts, не в проверенных persisted источниках/системном снимке; VoiceOver чтение доступно. Отсутствие доступа к источнику не считается отсутствием утечки. AC9/12.
- **Почему провалит плохую работу:** ловит стандартный выделяемый TextEditor для результата, утечки в snapshots и пустой аудит недоступного контейнера.
- **Статус:** pending
- **Доказательство:** Read-only source/Release audit выполнен, но own persisted canary audit, task-switcher snapshots, logs/keychain-before-after, no-copy/drag на обеих поверхностях не исполнены; source audit не заменяет runtime privacy proof.

## E13 · Полный сценарий вкладки приложения
- **Тип:** ui
- **Шаги:** `DecryptUITests › testAppPasteEditClose`: пустой/пробельный ввод, системная вставка, ручная правка, ошибка→редактирование→успех→закрыть, смена вкладки/фон. Изменить clipboard после заполнения поля до запуска.
- **Ожидается:** submit disabled для пустого/пробельного; расшифровывается поле, не новый clipboard; ошибка сохраняет ввод, редактирование убирает ошибку; успех скрывает ввод/системную клавиатуру; закрытие/уход стирают состояние. AC11.
- **Почему провалит плохую работу:** ловит сохранение введённого сообщения между вкладками и запуск по другому clipboard.
- **Статус:** fail
- **Доказательство:** FullUI testAppPasteEditClose PASS для обычного потока, но late native paste не имеет session fence и восстанавливает/меняет очищенный ввод после generation change; независимый native-boundary probe подтвердил production Delegate. specs/07-decrypt/evidence/verifier-round1/native-paste-counterexample.json; actual shipping UI lifecycle сценарий остаётся обязательным после исправления.

## E14 · Предел входа и максимальный результат [negative]
- **Тип:** test
- **Шаги:** `DecryptTests.swift › utf8Bounds`: вход 65536/65537 байт с валидным конвертом и окружением; многобайтные строки, целиком отклоняемая вставка в непустое поле. Реальное ядро — открытый текст 4096 байт, в том числе Unicode; существующий `LimitsTests` с 4097 байт.
- **Ожидается:** 65536 допускается к ядру, 65537 — ошибка AC3/0 open; старое поле сохранено. 4096 точно расшифровано, 4097 не создаётся seal. UI не обрезает и не смешивает два предела. AC3/15.
- **Почему провалит плохую работу:** ловит подсчёт Character вместо UTF-8 и лимит шифротекста 4096.
- **Статус:** pass
- **Доказательство:** Verifier R1 core exit0: utf8Bounds подтвердил65536/65537 UTF8, atomic rejection с сохранением старого поля,4096-byte multibyte plaintext и4097 seal error; LimitsTests PASS. specs/07-decrypt/evidence/verifier-round1/core.log.

## E15 · Макет всех состояний [design]
- **Тип:** design
- **Шаги:** сравнить реальные экраны с `mockup.html`: все state-* якоря и 94 рамки из requirements, точные поверхности/темы/размеры. Синтетические известные имена и сообщения; перечень кадров с SHA/runtime и соответствующим якорем. Generic failure дополнительно с текстом AC6.
- **Ожидается:** те же блоки/порядок/тексты/смысловые цвета, все состояния присутствуют; нет скрытого текста ошибки/имени, перекрытий и горизонтального overflow. Отличия системного растрирования шрифта не являются дефектом; точные RGB переходной анимации не часть контракта. AC4/6/7/8/13.
- **Почему провалит плохую работу:** ловит пропущенные состояния и макет результата, фактически не помещающийся в расширение.
- **Статус:** fail
- **Доказательство:** Лично открыт original native-allow-result.png1206×2622: верхняя часть sender «От: Анна07» закрыта/размыта серой полосой в реальном402 result, reference keyboard-contact требует читаемое имя. specs/07-decrypt/evidence/verifier-round1/native-allow-result.png; точная OS/layout причина не установлена. Полные94+generic frames в R1 не сняты, root перенёс обязательную полную матрицу на fixed frozen R2.

## E16 · Живые переходы, прокрутка и поворот [design] [regression]
- **Тип:** ui
- **Шаги:** обе темы, 375/402/440: idle→busy→длинное имя/4096 байт→прокрутка до последней строки→поворот в альбом и назад→закрытие; приложение также со стандартной клавиатурой при вводе. Повторить крайний 375 с accessibility XXXL. Геометрия и исходные screenshots до/после, без подмены статической матрицей.
- **Ожидается:** панель ≤420/240 pt без safe area, поле хозяина видно, «Закрыть» закреплена и ≥44×44, последний фрагмент доступен; поворот без нового чтения/потери результата, клавиши после возврата работают. В приложении ввод/действия/таб-бар доступны, без overflow. AC10/13.
- **Почему провалит плохую работу:** ловит ошибки реальной смены layout, которых не видно на отдельных картинках.
- **Статус:** pending
- **Доказательство:** Полные живые4096 transitions/themes/profiles/scroll/finalmarker/rotation/375XXXL не запускались: early failed-round handoff после важных дефектов по решению root. Контракт не сокращён, нужен полный R2.

## E17 · VoiceOver читает результат и управляет просмотром [design]
- **Тип:** ui
- **Шаги:** реальная VoiceOver с объявлением результата contact/self/unknown, ошибки и busy; активировать запуск/закрытие accessibility действием на приложении и установленном extension. Сверить labels, enabled, focus и actual activation; после проверки отключить VO, зафиксировать cleanup.
- **Ожидается:** русский текст, полное имя/неизвестный ключ, подпись и весь текст доступны; фокус AC14; закрытие работает, нет copy; disabled/busy объявлены. Снимок AX дерева сам по себе не доказывает activation. AC14.
- **Почему провалит плохую работу:** ловит корректные identifiers при неработающих действиях и результат, скрытый от доступности.
- **Статус:** pending
- **Доказательство:** Genuine VO activation/focus/speech/close не выполнялись. Native public VoiceOver menu доступно, VO не включался; AX labels не засчитаны. Обязательный R2.

## E18 · Десять циклов без падений и накопления
- **Тип:** ui
- **Шаги:** на настоящем extension и приложении 10 циклов 4096-byte успех→закрытие→повреждённое сообщение→закрытие; измерить память до/после в одинаковом idle, проверить освобождение координаторов/операций weak-probes в Debug и отсутствие crash/jetsam/замены клавиатуры.
- **Ожидается:** все циклы рабочие, нет старого текста/зависания/живых завершённых координаторов и устойчивого роста удерживаемых операций; приложить измерения и runtime. Разовая аллокация кешей не объявляется утечкой без удержания/тренда. AC15.
- **Почему провалит плохую работу:** ловит retain cycle и деградацию расширения после нескольких просмотров.
- **Статус:** pending
- **Доказательство:** Десять настоящих cycles+idle RSS/weak probes/crash trend не запускались на уже failed source по решению root; подготовленные own scripts не являются evidence PASS. Обязательный R2.

## E19 · Регрессия, сборки и Release [regression]
- **Тип:** command
- **Шаги:** `scripts/test.sh core`, `scripts/lint.sh`, `scripts/build.sh`, `CONFIGURATION=Release scripts/build.sh`, `scripts/test.sh ui`; дополнительные harness-тесты 05/06 для затронутых модулей; аудит entitlements/Release на отсутствие новых прав и debug fixtures.
- **Ожидается:** все exit 0, полный UI без failing/skipped обязательных сценариев; клавиатура собирается без модулей записи ключей; учебное превью/набор/контакты/шифрование сохранены; SHA/runtime/счётчики в отчёте. Focused не заменяет полный suite; E18/E20 этапа 06 не меняются. Архитектура/AC14/15.
- **Почему провалит плохую работу:** ловит работающее превью при сломанном extension, Debug-only реализацию и регрессию шифрования.
- **Статус:** fail
- **Доказательство:** Verifier R1: core185/29, lint89, Debug/Release exit0; unfiltered UI exit65 — 38 PASS/2 FAIL/0 SKIP, .build/TestResults/ui-20261103-071953.xcresult; оба ContactsUITests падают в replaceText, UITests/ContactsUITests.swift:672 (SelectAll отсутствует при замене имени), callers:201/151; specs/07-decrypt/evidence/verifier-round1/full-ui-summary.json и failure-*.json. Release no writing/debug fixture symbols/permission diff подтверждён; полный native05/06 regression ещё не завершён.

## E20 · Независимая security review [security]
- **Тип:** command
- **Шаги:** отдельный reviewer читает REVIEW.md, requirements/evals и diff в контексте; проверяет все новые clipboard/proxy/log/storage вызовы, доверие отправителю, lifecycle/гонки, границы и отрицательные криптотесты. Отчёт с путём:строкой и доказательствами.
- **Ожидается:** нет открытых «Важно»; прошлые findings и исправления сохранены, фактический риск high подтверждён. Reviewer не builder/verifier. Приёмка не основывается на одном автотесте/компиляции.
- **Почему провалит плохую работу:** ловит формально зелёные тесты с неверными гарантиями/непроверенными адаптерами.
- **Статус:** fail
- **Доказательство:** Отдельный свежий reviewer завершил full review frozen source: 2 открытых Важно (identity refresh retains result; late native paste session fence). specs/07-decrypt/evidence/reviewer-round1/report.md; независимые verifier counterexamples усиливают оба finding. Нет оснований для pass до исправлений.

## E21 · Первый пользователь на Release
- **Тип:** ui
- **Шаги:** свежий агент без кода/fixture-инструкций на реально установленном Release получает синтетическое сообщение и задачу прочитать в клавиатуре/приложении, определить отправителя, закрыть; также повреждённое сообщение и повтор. Зафиксировать экранные шаги и хеш установленной версии в ftue-report.md.
- **Ожидается:** находит путь, читает и понимает contact/unknown/подделку, возвращается к вводу без утечки/тупика. Все обязательные evals подтверждены отдельно; отчёт не заменяет технические проверки. Перед merge результат принимает пользователь.
- **Почему провалит плохую работу:** ловит работоспособность только под тестовым runner и непонятный пользователю сценарий.
- **Статус:** pending
- **Доказательство:** Fresh Release first-user root запустит после technical/reviewer gates исправленной версии; в R1 не выполнялся. Это scheduling gate, отсутствие FTUE пока не объявляется product defect.

## Покрытие требований
AC1→E1; AC2→E9; AC3→E5/E14; AC4→E2/E3/E6; AC5→E3/E4; AC6→E5/E6; AC7→E7; AC8→E8; AC9→E8/E9/E11/E12; AC10→E9/E10/E16; AC11→E7/E11/E13; AC12→E1/E10/E12/E20; AC13→E15/E16; AC14→E17/E19; AC15→E2/E14/E18/E19. Все состояния макета→E15, живые переходы→E16. Независимая проверка→E20/E21.
