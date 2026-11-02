# Typing integration checks (Debug only)

Use an explicitly disposable Simulator. The rotating host is a separate app; neither its sources nor its bundle are included in the shipping app or extension. The container app remains portrait-only.

```sh
DEVICE=CipherKeyboard-Typing-Builder scripts/build.sh
xcrun simctl install "$TYPING_SIMULATOR" .build/DerivedData/Build/Products/Debug-iphonesimulator/CipherKeyboard.app
TYPING_SIMULATOR=<disposable-UDID> scripts/typing-host.sh
```

In that simulator, add CipherKeyboard in Settings → General → Keyboard → Keyboards. Enable Full Access only in the disposable simulator when testing that variant. In TypingHost press «Открыть», hold the system globe and choose CipherKeyboard. «Пустое» sets an empty host document; «С выделением» sets `До встречи!` with UTF-16 selection `(3, 7)`. The diagnostics report the actual host text/selection through UITextViewDelegate. The host supports portrait/landscape.

The opt-in integration scheme requires this preparation; it is separate from the ordinary app UI regression suite:

```sh
xcodebuild test -project CipherKeyboard.xcodeproj -scheme TypingIntegration \
  -destination 'platform=iOS Simulator,name=CipherKeyboard-Typing-Builder' \
  -derivedDataPath .build/DerivedData -resultBundlePath /tmp/typing-integration.xcresult
```

`KeyboardExtensionTests.testRealExtensionTyping` taps the real extension keys, verifies host text/selection, rotates, verifies draft preservation, and verifies hide/reopen clearing. It retains a screenshot attachment. Run with Full Access off and on.

The ordinary `KeyboardTypingTests.testProductionControllerIsolation` instantiates the shipping controller with a UITextDocumentProxy spy via a Debug-only app route (`-typing-isolation`). This covers the actual controller/panel/adapter, rather than an isolated fake implementation. The route and probe are excluded in Release.

Synthetic design fixtures are DEBUG-only, process-local constants. Tap the status strip to open a fixed grid (3×6 portrait, 6×3 landscape); selecting a state removes the grid before it applies the fixture. No draft uses clipboard, defaults, files or App Group transport. The optional environment fixture remains DEBUG-only. Every capture asserts loaded source revision, exact selected fixture, orientation, stable geometry and absent picker.

Serial disposable preparation / capture (native SE3=375×667, iPhone17=402×874, iPhone16ProMax=440×956):

```sh
DERIVED="$PWD/.build/TypingFinal" TYPING_MATRIX_OUTPUT="$PWD/.build/TypingFinalMatrix" \
  scripts/typing-matrix.sh <UDID375> <UDID402> <UDID440>
```

The script runs a retained actual Settings Full Access/identity preflight separately from capture on each profile, installs and byte-compares the extension, and checks the runtime revision. On the explicitly disposable UDID, the runner disables and reads back `com.apple.keyboard.preferences/AutomaticMinimizationEnabled`: a CoreDevice hardware-keyboard reconnect must not hide the software keyboard during verification. Host/global Simulator preferences and the main device are untouched. Each profile uses two31-frame batches: `testCaptureLightCurrentProfile` and `testCaptureDarkCurrentProfile`. The runner sets actual Simulator OS appearance through `TYPING_APPEARANCE=light|dark`, checks its readback, and each frame separately checks the production panel's resolved UIKit trait; a launch argument or filename cannot establish the theme.

Every extension capture checks the actual editable48pt `host.editor` (value, hittability and full visible intersection above the panel), not its diagnostic duplicate. The host anchors that field to `keyboardLayoutGuide` and keeps the controls/diagnostic accessibility IDs in a compact header. Render metadata also checks visible draft caret, warning primary color and12pt/15pt portrait or10pt/12pt landscape text, and the lowercase multiline/limit fixtures. Those fixtures explicitly switch Shift off with the cursor at the visible beginning of the exact approved excerpt; the limit keeps4096bytes and a rejected insertion/error/counter.

For a full app UI regression, use a brand-new separate device without enabling the extension or Full Access. Before launching its tests, set/read the same software-keyboard precondition on that explicit disposable UDID; this does not install or activate CipherKeyboard:

```sh
xcrun simctl spawn "$REGRESSION_SIMULATOR" defaults write com.apple.keyboard.preferences AutomaticMinimizationEnabled -bool false
test "$(xcrun simctl spawn "$REGRESSION_SIMULATOR" defaults read com.apple.keyboard.preferences AutomaticMinimizationEnabled)" = 0
DEVICE=CipherKeyboard-Typing-Regression scripts/test.sh ui
```

The exporter requires exactly186 unique named screenshot/geometry pairs (180 extension +6 preview) from one loaded source revision and rejects actual-theme/style/host-visibility mismatches. A manifest is a capture inventory, not visual acceptance: independently open every original image and compare its matching approved reference. Montages assist navigation only.

For isolated persistence/clipboard audit (no other clipboard/UI tests concurrently):

```sh
TYPING_SIMULATOR=<UDID> scripts/typing-host.sh
TYPING_SIMULATOR=<UDID> DERIVED="$PWD/.build/TypingFinal" \
  TYPING_AUDIT_OUTPUT="$PWD/.build/TypingAuditFinal" scripts/typing-audit.sh
```

Setup opens the production app without memory-store arguments to establish its real Keychain identity. A DEBUG attributes-only query verifies the exact identity service/account/access group with one row; no secret bytes are requested. The SQLite audit uses the exact access group because simulator service/account indexes are opaque blobs, and rejects empty metadata. The separate DebugHost setup action writes only the fixed synthetic clipboard sentinel and checks it in-process; the baseline snapshot must independently read that same sentinel before the canary test runs. Failed setup/evidence is preserved and stops testing. Canary gestures/hide/reopen/background run alone between before/after snapshots, then files/defaults, identity metadata, clipboard and scoped logs are compared. Only the existing version/date access receipt may change.
