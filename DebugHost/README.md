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

The script runs a retained actual Settings Full Access/identity preflight separately from capture on each profile, installs and byte-compares the extension, and checks the runtime revision. The exporter requires exactly186 unique named screenshot/geometry pairs (180 extension +6 preview). A manifest is a capture inventory, not visual acceptance: independently open every original image and compare its matching approved reference. Montages assist navigation only.

For isolated persistence/clipboard audit (no other clipboard/UI tests concurrently):

```sh
TYPING_SIMULATOR=<UDID> scripts/typing-host.sh
TYPING_SIMULATOR=<UDID> DERIVED="$PWD/.build/TypingFinal" \
  TYPING_AUDIT_OUTPUT="$PWD/.build/TypingAuditFinal" scripts/typing-audit.sh
```

Setup opens the production app without memory-store arguments to establish its real Keychain identity. A DEBUG attributes-only query verifies the exact identity service/account/access group with one row; no secret bytes are requested. The SQLite audit uses the exact access group because simulator service/account indexes are opaque blobs, and rejects empty metadata. The separate DebugHost setup action writes only the fixed synthetic clipboard sentinel and checks it in-process; the baseline snapshot must independently read that same sentinel before the canary test runs. Failed setup/evidence is preserved and stops testing. Canary gestures/hide/reopen/background run alone between before/after snapshots, then files/defaults, identity metadata, clipboard and scoped logs are compared. Only the existing version/date access receipt may change.
