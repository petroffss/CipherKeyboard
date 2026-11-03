# Evals: Расшифровка полученных сообщений

> Контракт до кода. Статусы ставит только независимый verifier с доказательством. Все проверки пока pending.
> E17 отложен по прямому указанию пользователя; исходная проверка и её статус сохранены в [deferred-evals.md](deferred-evals.md). В активной приёмке 20 проверок.
> Имена новых тестов ниже — задания builder, не утверждение о существующих тестах. Только синтетические ключи/сообщения. Runtime: установленный extension и приложение, SHA/хеши бинарников/runtime revision в evidence.

## E1 · Чтение буфера только по действию [security]
- **Тип:** test
- **Шаги:** `Packages/CipherCore/Tests/KeyboardTypingTests/DecryptTests.swift › explicitReadOnly` и `UITests/DecryptUITests.swift › testExplicitClipboardRead`: открыть панель, ждать 5 секунд, сменить раскладку и повернуть; затем одно нажатие «Расшифровать». Reader spy считает отдельно metadata и content; UI проверяет реальный адаптер.
- **Ожидается:** до действия 0 чтений; после 1 попытка получения текста, без опроса/автоповтора. Чтений контекста хозяина ради сообщения нет. Действие доступно без выбранного адресата и с пустым черновиком; учебное превью буфер не читает. AC1.
- **Почему провалит плохую работу:** ловит чтение при открытии/таймере и кнопку, ошибочно зависимую от получателя шифрования.
- **Статус:** pass
- **Доказательство:** Core explicitReadOnly PASS; реальный A402: draft 0, metadata/content 0/0 через смену раскладки, поворот и 5 секунд, затем 1/1 по одному действию и без роста после Close. Host selection intact; приложение testExplicitClipboardRead PASS, preview UI прошёл и в preview отсутствует подключение clipboard reader. specs/07-decrypt/evidence/verifier-round3/native-explicit-read-counters.log.

## E2 · Получатель видит точный проверенный текст
- **Тип:** ui
- **Шаги:** в настоящем 06 зашифровать `  Привет, Анна!\nЗавтра в 19:30 👨‍👩‍👧‍👦  ` для B от A; скопировать вставленную строку; открыть расширение B с A в контактах; нажать «Расшифровать», затем повторить в приложении B.
- **Ожидается:** точные пробелы/Unicode/перевод строки, «Расшифровано», «От: Анна», «✓ Подпись верна», «Закрыть». Исходная строка соответствует полному ключу A. Никаких клавиш редактирования результата. AC4/15.
- **Почему провалит плохую работу:** ловит заглушку, обрезку whitespace и проверку лишь fake-opener вместо пути от 06.
- **Статус:** pass
- **Доказательство:** Независимый обмен реальными публичными Keychain keys A402/B375; actual06 вставил C в TypingHost один раз, A прочитал self на двух поверхностях. B прочитал тот же 565-байтный C на расширении и в приложении, точные пробелы/newline/emoji, «От: Анна», подпись и Close. cmp и совпавший SHA-256 28ea34ab9c8ca5c5fffb0c0eed15bc65f2cd319300f63f6419eaf55963e09bb2. specs/07-decrypt/evidence/verifier-round3/E2-exact-C-hashes.txt; E2-B375-receive-exact-C.xcresult.

## E3 · Собственный и неизвестный отправитель [security]
- **Тип:** test
- **Шаги:** `DecryptTests.swift › senderIdentity`: открыть своё сообщение, A без контакта, контакт с тем же именем и иным ключом; ввести разные полные ключи с одинаковым отображаемым short fingerprint через управляемое представление, не менять криптоядро. UI `DecryptUITests › testSenderVariants` — self/unknown на обеих поверхностях.
- **Ожидается:** self → «От: вы»; unknown → «От неизвестного ключа <2 группы>», подсказка добавить контакт и верная подпись. Сравниваются обе части PublicKey; чужое имя не назначается. AC4/5.
- **Почему провалит плохую работу:** ловит совпадение по короткому отпечатку/имени и ложное подтверждение личности.
- **Статус:** pass
- **Доказательство:** Own core senderIdentity и displayFingerprintCollision PASS (сопоставление обеих частей полного ключа). Full app testSenderVariants PASS; реальные self A keyboard/app в E2; установленный extension controlled contact/self/unknown, unknown hint и подпись в testLiveExtensionBranches PASS. specs/07-decrypt/evidence/verifier-round3/core-scoped.log; native-A402-lifecycle-compose.xcresult.

## E4 · Контакты перечитываются, ошибки не дают старого имени [negative] [security]
- **Тип:** test
- **Шаги:** `DecryptTests.swift › contactsRefresh`: с задержанным opener переименовать/удалить контакт, заменить одну часть ключа, сделать reader недоступным перед публикацией; отдельно self при ошибке reader. Проверить также изменение до запуска. UI — contact/unknown/contacts-warning.
- **Ожидается:** переименование видно, удаление/замена → unknown, ошибка → unknown с предупреждением AC5; self остаётся self. Старый кеш и UUID не определяют отправителя, текст подлинного сообщения доступен. AC5.
- **Почему провалит плохую работу:** ловит имя из устаревшего списка или полный отказ читать подлинное сообщение при сбое контактов.
- **Статус:** pass
- **Доказательство:** Own core contactsRefresh PASS (переименование/удаление/смена ключа/недоступность reader, self). На установленном app и extension контроль warning: неизвестный ключ, точное предупреждение и проверенный текст с подписью; contact и unknown также проверены. specs/07-decrypt/evidence/verifier-round3/native-A402-lifecycle-compose.xcresult (testAppContactsWarning/testLiveExtensionBranches).

## E5 · Первый конверт и вход с текстом вокруг [negative]
- **Тип:** test
- **Шаги:** `DecryptTests.swift › firstEnvelopeMatchesCore`: сравнить UI-модель с прямым `CipherMessage.open` для текста до/после, whitespace внутри, двух сообщений, повреждённого/чужого/ckmsg2 первым и корректного вторым; пустой текст и обычная фраза. В `MessageParsingTests.swift` сохранить регрессию ядра.
- **Ожидается:** одинаковые результат/ошибка с ядром, второе сообщение не подменяет первое; noMessage даёт точный текст AC6 для соответствующей поверхности. AC3/6.
- **Почему провалит плохую работу:** ловит самостоятельный regex, поиск только ckmsg1 и пропуск неуспешного первого сообщения.
- **Статус:** pass
- **Доказательство:** Core 187/29 PASS, firstEnvelopeMatchesCore и parser regression: контекст, whitespace и первое повреждённое/чужое/ckmsg2, noMessage обеих поверхностей. specs/07-decrypt/evidence/verifier-round3/core-scoped.log.

## E6 · Подделка, чужой получатель и версия [negative] [security]
- **Тип:** test
- **Шаги:** `DecryptTests.swift › rejectedMessagesNeverPublishText`, реальные `TamperTests.swift`: изменить байт ciphertext/подписи, подменить ключ отправителя, оборвать base64, дать шифротекст для C и `ckmsg2:`. В `DecryptUITests › testErrorsAfterSuccess` сначала успех, затем каждую ошибку и управляемую прочую ошибку на обеих поверхностях.
- **Ожидается:** точные ошибки AC6; нет старого/нового открытого текста и значка успешной подписи ни в визуальном, ни в accessibility дереве. AC4/6.
- **Почему провалит плохую работу:** ловит показ текста до верификации, неверный mapping и оставшийся успешный экран после ошибки.
- **Статус:** pass
- **Доказательство:** Core rejectedMessagesNeverPublishText и TamperTests PASS; все app error-after-success в полном UI, native extension после успеха проверил corrupt/foreign/version/generic/changed с точными ошибками и отсутствием текста/подписи. specs/07-decrypt/evidence/verifier-round3/core-scoped.log; full-ui-summary.json; native-A402-lifecycle-compose.xcresult.

## E7 · Нативное разрешение и отказ clipboard [negative] [security]
- **Тип:** ui
- **Шаги:** на целевой iOS скопировать синтетический шифротекст из отдельного приложения; в реальном расширении разрешить чтение, отдельно отклонить системный запрос/настроить запрет. Затем пустой буфер и нетекстовый тип. В приложении проверить системную вставку с разрешением/отказом, включая прежний ввод. Зафиксировать SDK/iOS, реальные результаты API и системное состояние, без private API; не ограничиваться fake-reader.
- **Ожидается:** разрешение даёт сообщение, пустой/нетекстовый → noMessage; объявленный текст без полученного значения → «Нет доступа к буферу обмена». Отказ не обходит защиту и не повторяет запрос. Системная вставка приложения без callback/значения сохраняет ввод и не запускает open, сообщённая ошибка показывает AC7. Невозможность вызвать реальный отказ на данной среде фиксируется как непроверенная часть, не pass по fake. AC7.
- **Почему провалит плохую работу:** ловит несуществующий callback отказа, скрытые повторные чтения и фиктивное нативное доказательство.
- **Статус:** pass
- **Доказательство:** Реальный A402: public Allow/Deny/Ask, 1 denied read, подсказка и отсутствие повтора, пустой/image дают noMessage. В приложении явный системный Paste разрешён iOS даже при Deny; отдельно реальный внешний text provider отказал через production UIPasteControl с точной ошибкой и сохранением непустого прежнего ciphertext, без open/result. Независимый production UIKit boundary 5/5. Ask body доказан, отдельный сбой Settings Back при cleanup сохранён, Allow readback и следующий native Allow PASS. specs/07-decrypt/evidence/verifier-round3/shipping-permission-A402.xcresult; shipping-provider-old-input-attachments/; native-paste-results.json.

## E8 · Полный доступ и личный ключ [negative] [security]
- **Тип:** test
- **Шаги:** `DecryptTests.swift › accessAndIdentity`: no-access, missing key, Keychain unavailable/corrupted; отозвать доступ/сменить полный identity при задержанном opener. UI `testAccessAndKeyErrors` — доступные сценарии в расширении и временная ошибка на вкладке приложения.
- **Ожидается:** сообщения AC8/9, без доступа 0 вызовов reader/Keychain/contacts ради действия, 0 создания/записи ключей; смена identity не публикует результат. Повтор после восстановления работает. AC8/9.
- **Почему провалит плохую работу:** ловит утечку до проверки права и самовольное восстановление ключа.
- **Статус:** pending
- **Доказательство:** Core accessAndIdentity/identityFailureAfterSuccessClearsBothSurfaces PASS, app key error PASS. Нативные no-access/no-key и восстановление на установленном extension целиком не повторены в known-red R3. specs/07-decrypt/evidence/verifier-round3/core-scoped.log; full-ui-summary.json.

## E9 · Двойное нажатие и взаимоисключение операций [negative]
- **Тип:** test
- **Шаги:** `DecryptTests.swift › singleFlightAndCancel`: задержать reader и opener отдельно, дважды нажать запуск, сменить clipboard, пытаться шифровать, закрыть, начать новую операцию и завершить старую последней. `DecryptUITests › testBusyAndCancel` показывает реальный busy и отмену.
- **Ожидается:** один вход/один open; вход зафиксирован; «Расшифровываем…»; закрытие работает; старое завершение не убирает/не меняет новый результат; 0 вставок. AC2/9/10.
- **Почему провалит плохую работу:** ловит гонку старого callback и параллельное шифрование.
- **Статус:** pass
- **Доказательство:** Core singleFlightAndCancel PASS: управляемые reader/opener, зафиксированный вход, взаимное исключение и stale completion. Full app testBusyAndCancel PASS, подтверждена реальная busy→Close/отмена без публикации. Установленный extension отдельно показал busy и освобождение при проверенном hide. specs/07-decrypt/evidence/verifier-round3/core-scoped.log; full-ui-summary.json; E11-A402-confirmed-hide.xcresult.

## E10 · Закрытие возвращает прежний черновик [regression]
- **Тип:** ui
- **Шаги:** настоящий extension: набрать многострочный черновик с курсором внутри слова, выбрать B, поставить курсор/выделение в поле хозяина с текстом до и после; открыть успех и ошибку, закрыть. Сравнить всё до/после; модель `DecryptTests › preservesComposeAndHost` использует spy proxy.
- **Ожидается:** прежний черновик/курсор/получатель сохранены, поле хозяина/выделение не изменены; 0 insert/delete/adjust. После окончания сессии черновик очищается по 05. AC10/12.
- **Почему провалит плохую работу:** ловит потерю черновика и восстановление его вставкой в мессенджер.
- **Статус:** pass
- **Доказательство:** Core preservesComposeAndHost PASS; native testComposeHostPreservation PASS: тот же многострочный draft, внутренний курсор, выбранный получатель, host text/caret/selection и proxy trace после success/error; завершение сессии очищает draft. specs/07-decrypt/evidence/verifier-round3/native-A402-lifecycle-compose.xcresult.

## E11 · Жизненный цикл стирает просмотр [negative] [security]
- **Тип:** ui
- **Шаги:** `DecryptUITests › testLifecycle` на успехе и задержанной операции: закрыть клавиатуру, глобус, фон хозяина, смена документа; приложение — другая вкладка/фон. Возврат и новая операция. Проверить actual lifecycle и disappearance, не только тестовый флаг; модель `DecryptTests › lifecycleInvalidatesGeneration` покрывает все переходы и отзыв доступа.
- **Ожидается:** результат/вход/ошибка отсутствуют после возврата; поздний callback не возвращает текст, старая операция освобождена, новой не мешает. AC9/11.
- **Почему провалит плохую работу:** ловит сохранение состояния в модели после исчезновения view и перенос текста в другой документ.
- **Статус:** pending
- **Доказательство:** App success/busy × tab/background reset/recovery PASS. Native extension actual success on stable hide/document/background/globe cleared visible text and signature, operations=0 and next read recovered. Busy stable hide PASS; busy document remained visibly busy only in separate dec-busy fixture (panel model replaced, production lifecycle resets another instance), so production delayed cancellation and remaining busy controls are pending. specs/07-decrypt/evidence/verifier-round3/E11-A402-confirmed-hide.xcresult; E11-A402-native-transitions.xcresult; E11-native-transition-attachments/.

## E12 · Приватность результата и системный снимок [security]
- **Тип:** ui
- **Шаги:** попытаться long-press/select/drag/share результата на обеих поверхностях; снять переключатель задач после ухода в фон с открытым canary; до/после проверенные логи, файлы/настройки App Group/приложения/расширения, метаданные Keychain. Известные identity и clipboard sentinel; подтверждённая доступность источников аудита; read-only проверка всех новых paste/proxy/log/storage вызовов Debug и Release.
- **Ожидается:** нет меню/копирования/записи/сети/новых Keychain записей; буфер побайтно прежний; canary только в активной памяти/UI и синтетических test artifacts, не в проверенных persisted источниках/системном снимке. Отсутствие доступа к источнику не считается отсутствием утечки. AC9/12.
- **Почему провалит плохую работу:** ловит стандартный выделяемый TextEditor для результата, утечки в snapshots и пустой аудит недоступного контейнера.
- **Статус:** pending
- **Доказательство:** Нативные gestures и обе поверхности с реальным canary PASS; clipboard source 522 байта unchanged, доступные nonempty app/group/ext/host и Keychain metadata1 unchanged, 6881 non-XCTest log rows без canary. Синтетические 184 совпадения происходят только из XCTest injected AX diagnostics. В App Switcher карточка host полностью проверена, видимая часть карточки app непрозрачна; целиком карточка app не зафиксирована. specs/07-decrypt/evidence/verifier-round3/privacy-comparison.json; privacy-A402-original-host-attachments/; privacy-app-switcher-devicehub.png.

## E13 · Полный сценарий вкладки приложения
- **Тип:** ui
- **Шаги:** `DecryptUITests › testAppPasteEditClose`: пустой/пробельный ввод, системная вставка, ручная правка, ошибка→редактирование→успех→закрыть, смена вкладки/фон. Изменить clipboard после заполнения поля до запуска.
- **Ожидается:** submit disabled для пустого/пробельного; расшифровывается поле, не новый clipboard; ошибка сохраняет ввод, редактирование убирает ошибку; успех скрывает ввод/системную клавиатуру; закрытие/уход стирают состояние. AC11.
- **Почему провалит плохую работу:** ловит сохранение введённого сообщения между вкладками и запуск по другому clipboard.
- **Статус:** pending
- **Доказательство:** Full app testAppPasteEditClose PASS; actual native paste в E2 и app lifecycle, error preserves OLD в E7. Дополнительный shipping сценарий с заменой clipboard после заполнения поля остановился до ввода на мгновенной проверке stock keyboard; нужен полный actual run. specs/07-decrypt/evidence/verifier-round3/full-ui-summary.json; native-A402-lifecycle-compose.xcresult.

## E14 · Предел входа и максимальный результат [negative]
- **Тип:** test
- **Шаги:** `DecryptTests.swift › utf8Bounds`: вход 65536/65537 байт с валидным конвертом и окружением; многобайтные строки, целиком отклоняемая вставка в непустое поле. Реальное ядро — открытый текст 4096 байт, в том числе Unicode; существующий `LimitsTests` с 4097 байт.
- **Ожидается:** 65536 допускается к ядру, 65537 — ошибка AC3/0 open; старое поле сохранено. 4096 точно расшифровано, 4097 не создаётся seal. UI не обрезает и не смешивает два предела. AC3/15.
- **Почему провалит плохую работу:** ловит подсчёт Character вместо UTF-8 и лимит шифротекста 4096.
- **Статус:** pass
- **Доказательство:** Core utf8Bounds и LimitsTests PASS: 65536/65537 UTF-8 и atomic preservation old input, 4096 exact plaintext, 4097 seal reject. specs/07-decrypt/evidence/verifier-round3/core-scoped.log.

## E15 · Макет всех состояний [design]
- **Тип:** design
- **Шаги:** сравнить реальные экраны с `mockup.html`: все state-* якоря и 94 рамки из requirements, точные поверхности/темы/размеры. Синтетические известные имена и сообщения; перечень кадров с SHA/runtime и соответствующим якорем. Generic failure дополнительно с текстом AC6.
- **Ожидается:** те же блоки/порядок/тексты/смысловые цвета, все состояния присутствуют; нет скрытого текста ошибки/имени, перекрытий и горизонтального overflow. Отличия системного растрирования шрифта не являются дефектом; точные RGB переходной анимации не часть контракта. AC4/6/7/8/13.
- **Почему провалит плохую работу:** ловит пропущенные состояния и макет результата, фактически не помещающийся в расширение.
- **Статус:** pending
- **Доказательство:** Независимо визуально открыт оригинальный A402 sender кадр: «От: Анна07» читается полностью, Close и выделение на месте. Полная матрица 94+4 не запускалась на known-red R3 и остаётся обязательной. specs/07-decrypt/evidence/verifier-round3/native-A402-sender-attachments/.

## E16 · Живые переходы, прокрутка и поворот [design] [regression]
- **Тип:** ui
- **Шаги:** обе темы, 375/402/440: idle→busy→длинное имя/4096 байт→прокрутка до последней строки→поворот в альбом и назад→закрытие; приложение также со стандартной клавиатурой при вводе. Повторить крайний 375 с accessibility XXXL. Геометрия и исходные screenshots до/после, без подмены статической матрицей.
- **Ожидается:** панель ≤420/240 pt без safe area, поле хозяина видно, «Закрыть» закреплена и ≥44×44, последний фрагмент доступен; поворот без нового чтения/потери результата, клавиши после возврата работают. В приложении ввод/действия/таб-бар доступны, без overflow. AC10/13.
- **Почему провалит плохую работу:** ловит ошибки реальной смены layout, которых не видно на отдельных картинках.
- **Статус:** pending
- **Доказательство:** Живой A402 поворот на чтении, sender/Close и возврат раскладки проверены. Полная 4096-byte динамика трёх размеров/двух тем/375 XXXL с прокруткой и stock keyboard остаётся обязательной после исправления. specs/07-decrypt/evidence/verifier-round3/native-A402-ask-and-identity.xcresult.

## E18 · Десять циклов без падений и накопления
- **Тип:** ui
- **Шаги:** на настоящем extension и приложении 10 циклов 4096-byte успех→закрытие→повреждённое сообщение→закрытие; измерить память до/после в одинаковом idle, проверить освобождение координаторов/операций weak-probes в Debug и отсутствие crash/jetsam/замены клавиатуры.
- **Ожидается:** все циклы рабочие, нет старого текста/зависания/живых завершённых координаторов и устойчивого роста удерживаемых операций; приложить измерения и runtime. Разовая аллокация кешей не объявляется утечкой без удержания/тренда. AC15.
- **Почему провалит плохую работу:** ловит retain cycle и деградацию расширения после нескольких просмотров.
- **Статус:** pending
- **Доказательство:** Полные 10×4096-byte циклы на каждой поверхности, idle RSS/weak probes и crash/jetsam ещё не запускались на known-red R3. План/инструменты сохранены. specs/07-decrypt/evidence/verifier-round3/preflight.md.

## E19 · Регрессия, сборки и Release [regression]
- **Тип:** command
- **Шаги:** `scripts/test.sh core`, `scripts/lint.sh`, `scripts/build.sh`, `CONFIGURATION=Release scripts/build.sh`, `scripts/test.sh ui`; дополнительные harness-тесты 05/06 для затронутых модулей; аудит entitlements/Release на отсутствие новых прав и debug fixtures.
- **Ожидается:** все exit 0, полный UI без failing/skipped обязательных сценариев; клавиатура собирается без модулей записи ключей; учебное превью/набор/контакты/шифрование сохранены; SHA/runtime/счётчики в отчёте. Focused не заменяет полный suite; E18/E20 этапа 06 не меняются. Архитектура/AC14/15.
- **Почему провалит плохую работу:** ловит работающее превью при сломанном extension, Debug-only реализацию и регрессию шифрования.
- **Статус:** fail
- **Доказательство:** Own core187/29, lint89, Debug/Release и release audit PASS. Новый unfiltered full UI 39 PASS/1 FAIL/0 SKIP exit65: ContactsUITests.testCardAndRename .711 увидел «Бори» через 166мс после одного typeText; следующий AX через 74мс и оригинал кадра показывают «Борис». Save не вызван. Без нового полного прогона и legacy native gates E19 не закрыт. specs/07-decrypt/evidence/verifier-round3/full-ui-summary.json; full-ui-card-rename-staged-excerpt.log.

## E20 · Независимая security review [security]
- **Тип:** command
- **Шаги:** отдельный reviewer читает REVIEW.md, requirements/evals и diff в контексте; проверяет все новые clipboard/proxy/log/storage вызовы, доверие отправителю, lifecycle/гонки, границы и отрицательные криптотесты. Отчёт с путём:строкой и доказательствами.
- **Ожидается:** нет открытых «Важно»; прошлые findings и исправления сохранены, фактический риск high подтверждён. Reviewer не builder/verifier. Приёмка не основывается на одном автотесте/компиляции.
- **Почему провалит плохую работу:** ловит формально зелёные тесты с неверными гарантиями/непроверенными адаптерами.
- **Статус:** pass
- **Доказательство:** Fresh independent reviewer на exact 47fa9a2/runtime583745497: high risk, 0 Important/Minor/Preexisting. Полный статический отчёт с путями/строками; non-VO scope далее изменён пользователем без product diff. specs/07-decrypt/evidence/reviewer-round3/report.md.

## E21 · Первый пользователь на Release
- **Тип:** ui
- **Шаги:** свежий агент без кода/fixture-инструкций на реально установленном Release получает синтетическое сообщение и задачу прочитать в клавиатуре/приложении, определить отправителя, закрыть; также повреждённое сообщение и повтор. Зафиксировать экранные шаги и хеш установленной версии в ftue-report.md.
- **Ожидается:** находит путь, читает и понимает contact/unknown/подделку, возвращается к вводу без утечки/тупика. Все обязательные evals подтверждены отдельно; отчёт не заменяет технические проверки. Перед merge результат принимает пользователь.
- **Почему провалит плохую работу:** ловит работоспособность только под тестовым runner и непонятный пользователю сценарий.
- **Статус:** pending
- **Доказательство:** Exact independent Release построен и сохранён с подписью/хешами; свежий независимый Release first-user и пользовательская приёмка ожидают закрытия остальных gates. specs/07-decrypt/evidence/verifier-round3/release-recovery-artifacts.json.

## Покрытие требований
AC1→E1; AC2→E9; AC3→E5/E14; AC4→E2/E3/E6; AC5→E3/E4; AC6→E5/E6; AC7→E7; AC8→E8; AC9→E8/E9/E11/E12; AC10→E9/E10/E16; AC11→E7/E11/E13; AC12→E1/E10/E12/E20; AC13→E15/E16; AC14→E19; AC15→E2/E14/E18/E19. Все состояния макета→E15, живые переходы→E16. Независимая проверка→E20/E21.
