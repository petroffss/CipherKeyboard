# Round 2 builder evidence and reproducible commands

This is builder evidence, not verifier acceptance. Contract/eval statuses are managed separately.

## Changes

- Production gesture ownership uses per-press UUIDs: a superseded touch cannot release/cancel the current touch, including long press/delete timers. Eleven typing tests cover this and existing behavior.
- Extension disappearance unconditionally clears the session; rotation only cancels pending gestures. No sticky rotation flag suppresses clearing.
- Debug-only fixed-state menu is in the existing status strip. Synthetic text stays in process memory; no persistent fixture transport or App Group write. Error fixtures call the production lazy status reader.
- Integration runner builds, explicitly installs the app, compares installed/built extension bytes, then runs tests. Unhosted UI tests otherwise build the app dependency without installing it. A fresh extension PID alone did not prove a current binary. A Debug build marker also matches the test-bundle source revision.
- Host publishes settled window-space button centers. iOS 27 XCTest retained stale element hitpoints after rotation: the old Hide test tapped `(288,288)` although Hide was around `(286,114)`. Current test sends a real tap to the freshly laid-out center and asserts host resigned focus and keyboard disappearance before reopening.

## Disposable devices

Never use the user's main simulator. All scripts require explicit disposable UDIDs.

- 402: `0CA5A7F3-8A09-416D-99BF-E09D238AFFE9`, CipherKeyboard-Typing-Builder
- 375: `E8CC012E-3C24-4A97-AE3F-E9B7A319DA04`, CipherKeyboard-Typing-375
- 440: `DED85B7C-DF7E-4EA5-92AD-E1A1AC9B5ABD`, CipherKeyboard-Typing-440
- Standard-keyboard regression: `C8EC1724-548D-412C-A865-343C157E9909`, CipherKeyboard-Typing-Regression

Debug app: `.build/DerivedData/Build/Products/Debug-iphonesimulator/CipherKeyboard.app`.
Debug host: `${TMPDIR}/CipherKeyboardTypingHost.app`, built/installed by `TYPING_SIMULATOR=<UDID> scripts/typing-host.sh`.

## Commands

```sh
TYPING_SIMULATOR=<UDID> scripts/typing-host.sh
TYPING_SIMULATOR=<UDID> TYPING_RESULT=/tmp/typing-runtime.xcresult scripts/typing-integration.sh -only-testing:TypingIntegrationTests/KeyboardRuntimeTests
TYPING_SIMULATOR=<UDID> TYPING_RESULT=/tmp/typing-fixtures.xcresult scripts/typing-integration.sh -only-testing:TypingIntegrationTests/KeyboardExtensionTests
TYPING_SIMULATOR=<UDID> TYPING_RESULT=/tmp/typing-smoke.xcresult scripts/typing-integration.sh -only-testing:TypingIntegrationTests/KeyboardMatrixTests/testMatrixSmoke
scripts/typing-matrix.sh <375-UDID> <402-UDID> <440-UDID>
```

Full matrix requires keyboards enabled on all devices. `testCaptureAllCurrentProfile` configures Full Access via actual Settings UI; captures 60 extension + 2 preview frames per native profile, screenshot + geometry JSON each. Exporter rejects missing/duplicate frames with `--complete`; native AppKit montage utility groups all corresponding states. Visual acceptance still requires independent review. Debug status-strip menu can select fixed states manually (Макет/Состояния/Статусы).

Persistence audit, after app/key/settings setup and current app installation (avoid including unrelated setup changes):

```sh
python3 scripts/typing-audit.py set-sentinel <UDID>
python3 scripts/typing-audit.py snapshot <UDID> /tmp/typing-before.json
# Run testNoExportCanary, background/hide, then:
python3 scripts/typing-audit.py snapshot <UDID> /tmp/typing-after.json
python3 scripts/typing-audit.py compare /tmp/typing-before.json /tmp/typing-after.json /tmp/typing-audit.json
```

Audit hashes app/extension/group files and defaults; scans fixed synthetic canary in UTF-8/16; reads identifying Keychain metadata only (never value/secret columns), checks clipboard sentinel and scoped logs. Only schema-valid access-receipt timestamp changes are allowed. Any other difference fails for investigation.

## Evidence locations and limitations

- `/tmp/typing-r2-final-core.log`: 11 typing tests / 4 suites and 135 CipherCore tests / 23 suites passed.
- `/tmp/typing-r2-final-lint.log`: lint (includes DebugHost/DebugHostTests).
- `.build/TestResults/ui-20261101-145540.xcresult`, `/tmp/typing-r2-full-ui.log`: clean standard-keyboard full UI 29 pass / 1 fail, no skips. Failure ContactsUITests.swift:615 waits five seconds for add-contact sheet disappearance after Save, called by long-list test line423. No contacts product changes made.
- `/tmp/typing-r2-installed.xcresult`, `.log`: installed-byte-verified five-status fixture test passed; lifecycle geometry expectation failed because XCTest app frame remained landscape after portrait transition. Fixed expectation derives width from device orientation and min/max dimensions.
- `/tmp/typing-r2-audit-smoke.json`: successful read-only audit snapshot; not a complete before/after no-export pass.
- `/tmp/typing-r2-lifecycle-diagnostic.xcresult` and `/tmp/typing-r2-lifecycle-images/`: original mis-hit diagnostics. Screenshot `259EFD11-52E0-47F3-8BEE-D7785372F3D9.png` shows retained draft because host remained focused. Prior fresh-PID lifecycle results alone are superseded by explicit-install runs.

Full 186-frame matrix, real Full Access ON/OFF editing matrix, complete canary before/after audit and shell-parity/ordinary-app runs must be assessed from their actual independent results. Harness availability is not a claim that those evals passed.

- Focused unchanged Contacts long-list rerun: `.build/TestResults/ui-20261101-151534.xcresult`, passed 1/1. Full run is still recorded as 29/30, not relabeled.
- Release build `/tmp/typing-r2-release.log` passed. App and extension binaries were scanned for `keyboard.debugFixtures`, `CIPHER_TYPING_FIXTURE`, `TypingCanary05`, `Debug fixtures;build=`: none present.
- `/tmp/typing-r2-smoke.xcresult`: current-installed-binary lifecycle test passed (30.7s), including actual hide and empty reopen after rotation.
- `/tmp/typing-r2-smoke.xcresult` completed **2/2 passed**: lifecycle and 9-frame matrix smoke. Exporter output `/tmp/typing-r2-smoke-frames/manifest.json` contains 9 screenshot/geometry pairs (four extension states in both orientations + preview), explicitly `complete=false`, expected186. Montages: `/tmp/typing-r2-smoke-montages`. Final test source caches the panel frame to reduce redundant remote AX queries; final fixture source removes duplicate warning-string overrides so fixtures expose production status-reader output.
- Screenshot correction: first smoke used app-cropped screenshots, whose landscape crop inherited XCTest's stale portrait bounds. Those landscape images are superseded. Matrix now uses the full `XCUIScreen` screenshot, and exporter rejects PNG orientation mismatches. Corrected smoke: `/tmp/typing-r2-screen-smoke.xcresult` (result below).
- E15 controller probe now asserts both injected OS globe-visibility values, Russian labels, Caps value, and alternate hints/custom actions on the actual production controller/panel. Actual system input-list interaction remains the runtime test; injected boundary coverage is not presented as an OS-level second-device run.
- E12 canary test now verifies actual hide and disappearance, empty reopen, then reseeds canary, backgrounds and terminates host before the external after-snapshot.
- Corrected full-display smoke passed 1/1: `/tmp/typing-r2-screen-smoke.xcresult`. Export succeeded: `/tmp/typing-r2-screen-final/manifest.json`, 9/186 pairs. XCTest PNG stores portrait raster with EXIF orientation8 in landscape; exporter records displayed pixel dimensions and original EXIF orientation without altering screenshots. `/tmp/typing-r2-screen-montages/alternate-e.png` visually inspected: complete portrait and landscape frames, no cropped black region.
- Expanded production-controller accessibility/isolation probe passed 1/1: `.build/TestResults/ui-20261101-152123.xcresult`, `/tmp/typing-r2-accessibility-probe.log`.
