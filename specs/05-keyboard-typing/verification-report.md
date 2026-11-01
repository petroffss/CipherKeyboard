# Independent verification — round 4

4 важных замечания по E14; итог **15/17 pass**. E14 и E17 — **fail**. Фича не готова к приёмке или слиянию.

Frozen commit: `2c7726eb52ee2b1691e4fef50de376971e50785c`; loaded/source marker: `956018778`. Verifier не строил фичу и не менял product/test/script код. Проверены 67 Swift-файлов: после прогонов их хеши не изменились. Все результаты ниже получены независимо на этом frozen source; старые builder/round3 результаты не использованы как текущие.

## Выполненные проверки

| Проверка | Текущий результат | Доказательство |
|---|---|---|
| Core | exit0; 15 typing tests/4 suites +135 core tests/23 suites, всего150 | `evidence/verifier-round4/core.log`, `core-exit.txt` |
| Lint | exit0;67 файлов | `lint.log` |
| Явная Debug сборка | exit0 | `debug-build.log` |
| Явная Release сборка | exit0 | `release-build.log` |
| Debug/Release binary audit | pass; Debug положительный контроль, Release0из21Debug markers; сетевых маркеров/frameworks0 | `debug-binary-audit.json`, `release-binary-audit.json` |
| Реальное расширение |7/7 passed,0skipped,exit0 | `runtime-summary.json`, `runtime.log`, `runtime-attachments/` |
| Изолированный E12 | setup2/2 +canary1/1 passed,exit0; strict persistence compare pass | `audit/` |
| Полный unfiltered UI |29passed,1failed,0skipped,exit65; все30 фактически выполнены | `full-ui-first-summary.json`, `full-ui-first-case-results.json`, `full-ui.log` |
| Чистый контроль |3/3 passed,0skipped,exit0; только оговорённые3теста | `clean-supplement-summary.json`, `clean-supplement-case-results.json` |
| Матрица |78/186 уникальных screenshot/geometry пар;108missing; все78 просмотрены,28 отдельных кадров pass/50fail | `matrix-frames/manifest.json`, `design-review.json`, `fix-list.md` |

Actual Release bundles audited at `.build/VerifierRound4Release/Build/Products/Release-iphonesimulator/`, not the generic Debug path printed by build.sh. Actual Mach-O binaries were scanned; Debug contains19 selected markers and all6 positive controls, Release contains none of21 selected Debug routes/fixtures/host/seed markers. No selected forbidden network reference or linked network framework was found. Actual Simulator entitlements were extracted from all4 Mach-O architecture slices and contain the expected App Group; see `release-entitlements.json`. The initial signature-only/otool-format read attempts were corrected: simulator entitlements live in the actual `__TEXT,__entitlements` sections, while codesign's signature dictionary was empty. No product change or secret read was made.

The independently built/installed extension dylib SHA256 is `c0715d9fb4c129b4d6fd24b9190f2e6eb64f1952ab3f9da5e68a7acdd4d3551b`; the runner byte-compared installed and freshly built binaries and asserted loaded956018778. This fresh DerivedData binary is not the builder's earlier hash.

## E12 — now valid and passed

Before any canary interaction, DEBUG setup wrote only the fixed synthetic sentinel and checked actual readback. The independent baseline then confirmed `clipboardIsSentinel=true`, no setup failures and exactly1 real identity metadata row. An attributes-only SecItem query separately proved exact identity service/account/access group; no kSecReturnData or secret/value SQL column was requested.

The canary ran alone between snapshots, with no reinstall/rebuild between them. All15 checked app/extension/group files were unchanged except the allowed `group/keyboard-access.v1.json` version/date receipt. Clipboard hash and actual sentinel, identity metadata hashes and defaults coverage were unchanged. No Preferences files existed in either checked container snapshot; creation of a new plist would have been an unexpected file change. No UTF-8/UTF-16 canary appeared in checked files or scoped app/extension/host logs. `audit/result.json`: pass, failures[], unexpectedChanges[], canaryMatches[]. This addresses the old zero-row/sentinel setup gap without weakening assertions.

## E14 — confirmed fail, coordinator-bounded capture

375 preflight passed and its complete62-frame capture test passed. Every native375 frame was explicitly reviewed against the exact matching approved anchor, including both themes and orientations. 402 preflight passed, then16 pairs were captured (all15light portrait states plus light landscape ru-empty). After four concrete failures were confirmed, coordinator explicitly ordered fail-fast for this already failing E14. Only the active402xcodebuild was gracefully interrupted; its xcresult says Testing was canceled and matrix command exit75. 440 design capture was not started. Strict `--complete` export retained78/186 and correctly exited1 with108missing. No missing frame or uninspected width/theme was inferred as passing.

All78 captured frames were independently opened through original-derived native panel crops; representative full originals were also opened for host visibility/theme diagnosis. Every frame has its own path, anchor, inspection flag and verdict in `design-review.json`. Panel/key-size assertions pass for all78; this does not pass all of AC8, because real host-field visibility fails on the observed landscape frames. Four remaining issues:

1. **D1:** multiline/limit use cursor0, activating automatic uppercase keycaps; their approved anchors show lowercase. Confirmed on both375themes/orientations and captured402portrait. The literal reference excerpt and upper-edge clarity are now correct. Start caret is the cause, not permission to move the caret offscreen: preserve AC1 while reproducing the intended lowercase state.
2. **D2:** all warning states are muted secondary gray; the approved `.warning` uses primary black/white. Portrait is11pt instead of12pt. Landscape reference overrides size to10pt, matching current size but not color. RequirementsAC9 does not override that style; E14 explicitly requires matching colors. Exact source/PNG paths are in `fix-list.md`.
3. **D3:**375dark preview is actually light despite its dark name/metadata. Full original `matrix-375-frames/raw-0/F61D7D46-7820-4E99-8613-868BC3F9C4FD.png` proves the wrong resolved theme. This is a capture-state failure, not proof that production preview cannot render dark mode. Final capture must set real appearance and assert actual resolved theme in both preview and extension.
4. **D4:** the real host UITextView is obscured in observed375/402landscape; only its top edge/selection handle remains. The visible duplicate “Текст: До встречи!” belongs to a diagnostic UILabel. The DebugHost vertical stack does not adapt above the keyboard. Original375`9980FC7E-5199-41CA-B8A5-71B0A9B11835.png`,402`340FD39A-69E8-4F04-9168-81D1D4EDEC33.png`; source/actionable layout cause in `fix-list.md`.

All186 must be freshly captured and independently reviewed on the corrected final round5 frozen revision; wrong-state/current incomplete captures cannot be reused as pass. Requirements/expectations and frame count were not changed.

## E17 — full UI failed; clean control does not replace it

The completed unfiltered suite executed exactly30 cases:29pass/1fail/0skip, exit65. Failure: `ContactsUITests/testNameFieldVisibleAboveSaveWithKeyboard()` at the app.keyboards existence assertion (“Нужна настоящая экранная клавиатура”). That prepared402 device still had CipherKeyboard active from design capture. Retained failure hierarchy `full-ui-first-attachments/CC70AEF7-80C7-465E-8247-4BD98A7FBC1A.txt` contains the actual CipherKeyboard panel/keys even though app.keyboards was empty. Both new KeyboardTypingTests passed in this full run.

A new clean iPhone17 device was created without enabling CipherKeyboard or Full Access. A full clean retry was briefly started, then promptly canceled at coordinator instruction: exit75,0recorded tests/unknown summary, `.build/TestResults/ui-20261101-175054.xcresult`; never claim this as a green suite. Coordinator instead authorized the precise clean control: Contacts keyboard-visibility test plus both KeyboardTypingTests. All3passed,0skipped,exit0 on `.build/TestResults/ui-20261101-175149.xcresult`. This supports the keyboard-environment confound and proves preview/controller availability without system setup. It does not prove baseline attribution or turn the failed full suite green. E17 remains fail for missing full green final-source UI; core/lint/build/Release successes remain separately recorded.

Final round5 should use a separate clean regression device with the system keyboard for the whole30-case unfiltered suite, distinct from native devices used to activate the extension and capture186frames. All17evals must be rerun on its final frozen code.

## All17 verdicts

| Eval | Verdict | Current independent evidence |
|---|---|---|
| E1 | pass | Exact insertion and grapheme cursor core test |
| E2 | pass | Four exact layouts/transitions core test |
| E3 | pass | Auto/one-shot/Caps;299/301ms; explicit off |
| E4 | pass |449/450ms alternatives/cancellation, both cases |
| E5 | pass | Whole composed/flag/skin-tone/ZWJ deletion |
| E6 | pass |399/400/480ms repeat and cancellation |
| E7 | pass | UTF-8 thresholds/atomic rejection/cursor/error |
| E8 | pass | Current production controller proxy-spy UI,0calls |
| E9 | pass | Real preview keys, lifecycle/status/identity invariance, clean no-setup control |
| E10 | pass | Actual ON/OFF×empty/selected host; ordinary Settings; receipt schema |
| E11 | pass | Real hide/rotation/background/globe and preview resets; zero pending timers |
| E12 | pass | Valid sentinel+known nonempty identity baseline; strict before/after audit |
| E13 | pass | Five actual status fixtures typed/deleted; lazy no-access factories0 |
| E14 | fail | Four visual/capture issues;78/186reviewed,108missing; canceled402 |
| E15 | pass | Russian labels/states/hints, true/false boundary, actual globe list/switch |
| E16 | pass |500actions/10resets/zero timers/overlapping touches +actual shell parity |
| E17 | fail | FullUI29/30exit65; clean3/3supplement does not substitute |

## Handoff

No active verifier UI/build/test jobs remain. All four verifier disposable devices are Shutdown and retained for coordination:375CCA87562-08F4-40EF-8C14-32FD4D505439;4022C979135-65D2-40A7-8F6D-6FC62B6B729B;440A3F7BEC2-F01C-43BA-90C4-9014BF2FE18C;clean7B77C778-4A7C-431D-9213-CF9F3B72EBD7. MainCE56E4D3-8193-4BFA-8996-FA3AA4A628C9 was untouched and remains Booted; see `handoff-devices.json` and `handoff-processes.json`. Nothing was merged/staged; coordinator's pre-existing state.md was not edited by verifier. Only eval status/evidence lines and the authorized report/evidence files were written. The previous verification-report.md was preserved as `prior-verification-report-round3.md` before replacement. First-time-user and human acceptance were not performed; these remain after all required final checks pass.

Full local evidence directory: `specs/05-keyboard-typing/evidence/verifier-round4/`.
