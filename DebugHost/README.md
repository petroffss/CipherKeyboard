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

Synthetic design fixtures are available only in Debug through the process environment `CIPHER_TYPING_FIXTURE`: `ru-empty`, `ru-text`, `shift`, `caps`, `en`, `numbers`, `symbols`, `alternate-e`, `alternate-softsign`, `multiline`, `limit`, `no-access`, `no-key`, `key-error`, `contacts-error`, `preview`. For the app preview, launch with `SIMCTL_CHILD_CIPHER_TYPING_FIXTURE=<name> xcrun simctl launch <UDID> dev.cipherkeyboard.app`, then open the preview. The extension reads the same environment variable in its own process. Fixtures contain only synthetic text, are not persisted and must be unset for lifecycle tests. Production no-access storage guards are separately exercised with factory spies.
