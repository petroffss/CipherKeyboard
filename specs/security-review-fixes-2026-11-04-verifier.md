0 находок — исправлять нечего в проверенном объёме.

Независимый verifier проверил только новые регрессионные evals: **4/4 pass**. Рабочая копия `/private/tmp/cipher-review-fixes-20261104`, ветка `fix/security-review-20261104`, базовый HEAD `309c9f3e6327a49d950da2f7e3a9cc963e21eced` с незакоммиченными исправлениями. Состав проверенных исходников и тестов зафиксирован в [source-sha256.json](security-review-fixes-2026-11-04-evidence/source-sha256.json). Production-код verifier не менял; в evals изменены только статус и доказательство новых E29/E18/E21/E22.

| Eval | Результат | Наблюдение |
|---|---|---|
| 03-contacts E29 | pass | Смешанные own/contact X25519 отклонены, книга не мутировала; старая книга прочитана, переименована и очищена от второй записи. |
| 05-keyboard-typing E18 | pass | При 1998 байтах счётчика нет, при 2000 байтах кириллицы показано `2000 / 4096 байт`. |
| 06-encrypt-insert E21 | pass | Реальные ckmsg2 на 2720 байт укладываются в 4096 символов, 2721 и 4096 — нет; round-trip точный. Предупреждение сохраняет черновик и доступность шифрования, не перекрывает no-access/limitError, исчезает после удаления до 2720. |
| 07-decrypt E22 | pass | Default coordinator после реального seal/open возвращает полный отпечаток неизвестного отправителя и `unknown=true`. |

Команды независимого прогона:

- `scripts/test.sh core --filter 'SecurityReviewTests|SecurityReviewTypingTests|EncryptInsertTests/singleMessageWarningDoesNotOverrideErrorsOrChangeDraft'` — exit 0, 6/6 тестов. [Лог](security-review-fixes-2026-11-04-evidence/targeted-swift.log).
- `scripts/test.sh core --filter EncryptInsertTests/utf8Boundaries` — exit 0, 1/1; дополнительная проверка приоритета ошибки максимальной длины. [Лог](security-review-fixes-2026-11-04-evidence/utf8-priority-swift.log).
- `python3 scripts/test-network-boundaries.py` — exit 0, 3/3. `scripts/lint.sh` — exit 0, 95 Swift-файлов; сетевые границы и границы расширения OK. [Вывод](security-review-fixes-2026-11-04-evidence/command-results.txt).

При просмотре кода подтверждено: проверка X25519 добавлена только в `validatedKey`, декодирование старых книг не ужесточено; app и extension используют default formatter с 8 группами/128 битами. Предупреждение находится после ошибок, busy, success и выбора получателя; лимит формата остаётся 4096 байт. Криптографический формат, единственная вставка шифротекста и границы хранения открытого текста не менялись. Новый сетевой guard покрывает перечисленные в исходном review API, переносы строк и внешние URL; разрешение открытия Настроек привязано к полному телу функции без входного URL. Это статическая проверка, а не изоляция сети средствами ОС.

Оба privacy manifest успешно разобраны `plistlib`. `CA92.1` соответствует локальному `UserDefaults.standard` для UUID получателя; системное `AppleKeyboards` больше не читается. `35F9.1` соответствует `systemUptime` для интервала между нажатиями Shift. Назначение причин сверено с [документацией Apple](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype). Это проверка исходников и деклараций; наличие manifest в итоговом Release-пакете проверяет основной агент.

Проблемы окружения: первый sandbox-запуск Swift остановился на запрете записи `~/.cache/clang/ModuleCache`; после разрешённого доступа к compiler cache тот же набор завершился успешно. Кодовой ошибки компиляции не обнаружено.

Полный core, UI, Debug/Release и симулятор находятся у основного агента и не входят в независимый итог 4/4. Verifier не запускал xcodebuild, UI или симулятор. Этот отчёт не подтверждает живую вёрстку, Release first-time-user, работу на физическом iPhone, блокировку устройства, защиту файлов на устройстве или лимиты памяти. VoiceOver не запускался и исключён из этой работы прежним решением пользователя. Исторические pass/pending, deferred evals и приёмка человеком не изменены.
