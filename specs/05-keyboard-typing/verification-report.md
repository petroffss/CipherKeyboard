# Independent verification — final round 5

**1 важное замечание; итог 16/17 pass. E14 — fail из-за D5.** Остальные 16 evals прошли заново. Фича не готова к приёмке или слиянию; first-time-user не проводился, потому что E14 не пройден. Это последний из пяти разрешённых раундов; исправления следующего раунда не применялись.

Frozen commit: `1db6b7e172c3bf576345845eabebda25caa63f65`; source/runtime marker: `248220564`. Все 67 Swift-файлов сохранили SHA256 `86011f92293dcb8c4fa67a6d808adfc178e0ff82d2356449968ffa331aa9cb89`. Verifier не строил фичу и не менял product/test/script код, требования или ожидания evals. В evals изменены только status/evidence строки. Старый отчёт сохранён как `evidence/verifier-round5/prior-verification-report-round4.md`.

## Выполненные проверки

Все результаты ниже получены независимо на frozen source; результаты builder/предыдущих раундов не перенесены как текущие доказательства. Артефакты находятся в `evidence/verifier-round5/`.

| Проверка | Результат | Доказательство |
|---|---|---|
| Core | exit0; 15 typing tests/4 suites +135 core tests/23 suites =150 | `core.log`, `core-exit.txt` |
| Lint | exit0;67 файлов | `lint.log`, `lint-exit.txt` |
| Явная Debug сборка | exit0 | `debug-build.log`, `debug-build-exit.txt` |
| Явная Release сборка | exit0 | `release-build.log`, `release-build-exit.txt` |
| Debug binary audit |6 actual Mach-O; положительные Debug controls; network0;4 actual entitlement slices | `debug-binary-audit.json` |
| Release binary audit |2 actual Mach-O;0 из24 Debug markers; selected network references/frameworks0;4 actual entitlement slices | `release-binary-audit.json` |
| Полный unfiltered UI |30 pass,0 fail,0 skip,exit0; все30 уникальных identifiers точно совпали с frozen source | `full-ui-summary.json`, `full-ui-case-results.json`, `full-ui-contract-coverage.json`, `full-ui-process.txt` |
| Реальное расширение/runtime |7/7 pass,0 skip,exit0 | `runtime-summary.json`, `runtime-case-results.json`, `runtime.log`, `runtime-attachments/` |
| E12 isolated audit |setup2/2 +canary1/1,0 skip,exit0; strict compare PASS | `audit/` |
| Полная capture matrix |186/186 unique screenshot/geometry pairs;6 capture tests +3 preflights passed | `matrix/frames/manifest.json`, `matrix-command.log`, `matrix-exit.txt` |
| Независимый визуальный просмотр |все186 original-derived full native frames отдельно открыты;186 frame pass,0 frame fail | `design-review.json`, `*-native/`, `reference-frames.json` |
| Дополнительный actual scroll/caret |pan открыл пятую строку; tap поставил caret в середину; реальная а вставилась именно там; host неизменен | `gui-12…17`, `gui-editor-scroll-gesture.json`, `supplemental-ui-review.json` |
| Дополнительный normal preview 375 |**FAIL D5:** реальные5строк с а/Enter обрезали обязательную инструкцию;2 settled frames | `gui-19-normal-empty.png`, `gui-20-real-five-lines.png`, `gui-21-real-five-lines-stable.png` |

Actual independently built/installed extension dylib SHA256: `293a72a37a1df17c1e6d81ab6c9c16e2fd0c4d433fa792d553189913eb9f45a7`. Runner byte-compared installed and freshly built bytes before test runs and asserted loaded248220564; the comparison was independently repeated before the supplemental UI in `gui-source-context.json`. This is the verifier's fresh `.build/IndependentR5` build, not builder output.

Actual audited Release app, suitable for a later clean first-user test only after the feature passes:
`/Users/segei/Documents/CipherKeyboard/.build/IndependentR5Release/Build/Products/Release-iphonesimulator/CipherKeyboard.app`.
The audit read actual executable binaries and actual `__TEXT,__entitlements` sections, covering both architecture slices of both Release executables. All4 slices contain the expected App Group `group.dev.cipherkeyboard`. It did not mistake an empty codesign signature dictionary for entitlement evidence. Release contains no selected Debug fixture/seed/host/diagnostic routes among24 markers; Debug positive controls prove the scan can find them.

## E17 — full clean suite now passed

A **brand-new** separate iPhone17 simulator was created: `CipherKeyboard-Typing-VerifierR5Clean`, `E0F7ADEB-5F77-434B-BCE6-A436DEC66564`. Neither extension activation nor Full Access was enabled on it. Before tests, its disposable-only `AutomaticMinimizationEnabled=false` readback was0. The actual command was `DEVICE=CipherKeyboard-Typing-VerifierR5Clean DERIVED=.build/IndependentR5Regression scripts/test.sh ui -parallel-testing-enabled NO`, with **no only-testing/skip filter**. It naturally completed with30 pass/0 fail/0 skip/exit0; all30 unique case identifiers exactly match the frozen source list. The formerly failing Contacts keyboard-visibility scenario is among the passed cases. Result: `.build/TestResults/ui-20261101-193958.xcresult`.

After the successful suite, an extra preference read returned1: iOS had changed that OS preference. This is recorded honestly in `clean-postcondition.json`; it does not replace the proven pre-test0 readback or the actual completed tests. The verifier's unnecessary post0 assertion initially stopped the next device prep; the subsequent integration invocation failed149 before any runtime build/test because375 was still Shutdown. That0-case setup attempt is retained as `runtime-initial-setup.log`/`runtime-initial-setup-exit.txt`. After explicit boot and the unchanged pre-test guard/readback0, all7 runtime cases passed. No test assertion or product/script source was changed and no full UI rerun was substituted.

## E10–E13/E15–E16 — real runtime and E12

Seven actual runtime cases covered five status fixtures with typing/deletion and no-access reader counts0; rotation/hide with focused=false, panel absence and empty reopen; background and actual globe list/switch reset; actual preview/extension parity; real Settings Full Access ON/OFF ×empty/selected host documents; no-export interactions; and typing in ordinary Settings search. Text and selection of the host remained unchanged. All9 retained runtime screenshots were independently opened (`runtime-screenshot-review.json`). `receipt-schema.json` proves the real shared access receipt has only date/version and no draft field. Production controller/panel/adapter proxy-spy, Russian labels/Shift/Caps/hints/IDs and true/false globe boundary passed in the full UI suite. Core covered500 fixed operations,10 resets, zero pending timers and independent overlapping touches.

E12 ran alone on440 (`A3F7BEC2-F01C-43BA-90C4-9014BF2FE18C`). Before baseline, setup separately established the actual synthetic clipboard sentinel and a real known nonempty identity. The in-process attributes-only SecItem query proved exact service/account/access group with1row (`audit/setup-attachments/…txt`); no secret bytes/kSecReturnData were requested. Both independent snapshots observed sentinel=true and exactly1 identity metadata row, setupFailures[]. Canary ran via direct test-without-building, with no reinstall/rebuild/preference writes between snapshots. All15 app/extension/group files were unchanged except the allowed `group/keyboard-access.v1.json` date/version receipt. Identity metadata hashes, defaults coverage and clipboard hash/sentinel were unchanged; no new Preferences plist, canary file match or scoped app/extension/host log match appeared. `audit/result.json`: PASS, failures[], unexpectedChanges[], canaryMatches[]. Source write/proxy paths were separately audited in `source-write-proxy-audit.json`.

## E14 — complete matrix passed, but normal preview D5 failed

All186 fresh pairs were captured serially on375/402/440, both real OS appearances, both extension orientations, plus6 portrait previews. Strict export and independent integrity check require exact186 combinations, no duplicate or missing frame, loaded248220564, exact fixture, actual resolved trait, visible caret, primary warning color and font/line-height, lower-case multiline/limit state, fully visible/hittable actual48pt host field, panel/key bounds and minimum key sizes. Every full original-derived native-point frame was opened separately against its exact approved anchor/caption; montages were not treated as individual inspection. D1–D4 are absent on all observed approved frames. Minimum375 letter width26.33pt; key heights44/32pt; maximum375 panel height378/220pt. Real system safe areas and globe variants were respected.

The mandatory live interaction supplement additionally proved editor scrolling and cursor placement: `gui-12` shows the fifth line clipped in the four-line viewport; real begin/move/end pan reveals it in `gui-13`; `gui-14` shows caret after «До »; real а-key center makes «До австречи!» in `gui-17`, with visible caret and the read-only host sample still «До встречи!».

That supplement exposed **D5**, then it was independently reproduced through ordinary UI without a fixture:

1. Back out to Setup, reopen «Попробовать клавиатуру». `gui-19-normal-empty.png`: empty draft, actual «Ваш ключ: CAD0 AB1D · Контактов нет» status, complete mandatory instruction in2lines.
2. Tap actual Cyrillic а/Return keys: `а, Return, а, Return, а, Return, а, Return, а`; no typeText/paste/fixture/seed (`gui-real-key-reproduction.json`). The actual draft is5 lines of «А».
3. Wait for native layout, capture2 settled actual frames. Both `gui-20-real-five-lines.png` and `gui-21-real-five-lines-stable.png` show the instruction ellipsized to «Набирайте текст внутри клавиатуры. При вы…». The sentence warning that the draft is erased on exit is hidden. Host sample and all4key rows remain visible.

**[Важно] [сломан-мобильный-вид] `App/KeyboardPreviewView.swift:11`** — mandatory instruction is vertically compressed when the shared editor grows. AC8 forbids clipped prompts and AC10 requires the full text. Lines10–20 place the instruction Text and growing fixed-height panel in one constrained VStack. This is observable normal behavior, not a fixture-only inference or a font-rasterization difference. Fix must preserve the entire instruction, actual host and approved key/editor sizes on375. See `fix-list.md`/`findings.json`. Other widths/themes for this additional dynamic case were not checked; no passing inference is made about them.

Thus capture/per-frame matrix acceptance remains186/186, but **overall E14 is fail** for D5. The approved preview matrix anchor contains a short draft and cannot disprove the normal multiline case. No requirement was reduced to make the result green.

## All17 verdicts

| Eval | Verdict | Fresh evidence |
|---|---|---|
| E1 | pass | exact insertion/grapheme cursor core test |
| E2 | pass | four exact layouts/transitions core test |
| E3 | pass | auto/one-shot/Caps299/301ms/explicit-off core test |
| E4 | pass |449/450ms alternatives/cancellation/both cases core test |
| E5 | pass | composed/skin-tone/flag/ZWJ deletion core test |
| E6 | pass |399/400/480ms repeat +stop/cancel/hide core test |
| E7 | pass | UTF-8 thresholds/atomic rejection/cursor/error core test |
| E8 | pass | actual production proxy-spy UI,0calls |
| E9 | pass | real preview keys/lifecycle/status/identity/host invariant in clean full30 |
| E10 | pass | actual ON/OFF ×empty/selected host +ordinary Settings +receipt schema |
| E11 | pass | actual hide/rotation/background/globe and preview reset; core timer checks |
| E12 | pass | valid sentinel +known1identity attributes, strict15-file/defaults/clipboard/log comparison |
| E13 | pass | five actual status scenarios typed/deleted; lazy readers0 |
| E14 | **fail** |186 pairs +186 individual frame passes, actual scroll/caret pass; **normal375 multiline instruction D5** |
| E15 | pass | production AX controls/states/hints +actual globe/list/switch +matrix variants |
| E16 | pass |500actions/10resets/zero timers/overlapping touches +actual shell parity |
| E17 | pass | full unfiltered clean30, core150/lint67/Debug+Release +actual binary/network/entitlements audits |

## Environment, tools and retained attempts

Initial CUA access was blocked by Mac lock; the user manually unlocked it. No lock bypass/credential automation was attempted. Native DeviceHub (`com.apple.dt.Devices`, `/Applications/Xcode.app/Contents/Applications/DeviceHub.app`) was selected by the explicit disposable375 sidebar row; mainCE56 was never selected/touched. AX navigation worked; native coordinate input failed `noWindowsAvailable`. Child browser inventory had no IAB capability and explicit parent tab claim was denied; parent root IAB could show the actual live mirror. Safari's capture showed a black MJPEG area despite a healthy stream, so it was not claimed as visual proof.

The `ios-simulator-browser` skill's recognized npm tool was used through bundled pnpm because systemnpx was absent. Pinned tool: `serve-sim@0.1.48`; preview bound only127.0.0.1:3285 and explicitly targeted375. The documented scoped `repair-input --device375` cleared `com.apple.coredevice.dtuhidd.active` and restarted only that disposable's backboardd; helper was then restarted. No host/global preference or main device was modified. Actual touch behavior was judged from native `simctl io375 screenshot` PNGs after1.2–2s layout settling, not exit0 alone.

The early2× coordinate hypothesis is **retracted**: a pre-transition screenshot caused premature attribution. A single nominal-coordinate probe and2 settled native frames proved ordinary normalized x/rawWidth,y/rawHeight coordinates work after repair. A later а-key attempt landed in an inter-key gap; tapping the visually verified key center worked. Those ambiguous/failed attempts are retained and are not product findings. Successful full editor gesture events are recorded in `gui-editor-scroll-gesture.json`. See `ui-access-handoff.md` for exact tool paths, scoped startup/cleanup and input recipe.

## Handoff and limit

No product/test/script edits, weakening, skip, merge or staging occurred. Final source/contract integrity and simulator/process inventory are in `source-integrity-final.json`, `handoff-devices.json`, `handoff-processes.txt`, `handoff.json`. The current failed D5 state is synthetic-only. First-time-user/human acceptance were not run because E14 failed. No sixth round is authorized by this report; coordinator handles any explicit user extension request.

## Final operational handoff

Final source-integrity check passed: frozen commit and all67Swift bytes unchanged, product/test/script inventory unchanged, eval contract unchanged; only approved verification/coordinator metadata changed. See `source-integrity-final.json`. All4owned disposable devices are Shutdown, mainCE56 remains Booted and untouched, no active build/test/input job remains, both scoped mirror sessions exited, and port3285 has no listener. Simulator/build/test/UI ownership is returned to the coordinator; see `handoff.json` and `ui-access-handoff.md`. No FTUE or extra implementation round was run after the E14failure.
