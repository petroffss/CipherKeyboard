# Round 3 builder evidence

Base: `5e01c70857b137f8ab01d61d4b78a9ad57587d18`. Only open gesture semantics and evidenced UI-harness failures changed. No contract or eval status changes.

## Production fix

Each touch token now retains its own action, timer and alternate. A new touch does not cancel previous valid touches. Valid releases commit in release order (`п down, р down, п up, р up` → `Пр`; reverse releases → `Рп`). Cancelling/releasing one token cannot commit or discard another token. Lifecycle cancellation still cancels all active tokens/timers.

The previous regression that expected dropped input was replaced with literal both-release results, independent cancellation, simultaneous alternate deadlines, deletion overlapping a letter, and all control-action ownership. Core result: **15 typing tests / 4 suites and 135 CipherCore tests / 23 suites passed** (`/tmp/typing-r3-core.log`). Lint: **66 files passed** (`/tmp/typing-r3-lint.log`). Release build passed (`/tmp/typing-r3-release.log`).

## Harness corrections

- Settings helper targets the actual nested toggle, not the encompassing row/label, handles actual localized consent, asserts switch value, and captures Settings evidence.
- Extension activation asserts the current loaded build. Only the evidenced blank inputView/no-system-keys state permits one real hide/reopen recovery, with screenshot and AX attachment; a wrong visible keyboard fails rather than receiving blind retries.
- Fixture helper scrolls the actual submenu collection to the requested visible/hittable item, including the previously offscreen canary.

Focused command (disposable402 only):

```sh
TYPING_SIMULATOR=0CA5A7F3-8A09-416D-99BF-E09D238AFFE9 TYPING_RESULT=/tmp/typing-r3-focused.xcresult scripts/typing-integration.sh \
 -only-testing:TypingIntegrationTests/KeyboardRuntimeTests/testEditingMatrixWithFullAccess \
 -only-testing:TypingIntegrationTests/KeyboardRuntimeTests/testEditingMatrixWithoutFullAccess \
 -only-testing:TypingIntegrationTests/KeyboardRuntimeTests/testNoExportCanary
```

Installed extension SHA checked by runner: `e85e22bbb5193f007c440d094f2f79cce75f85d45dcf23b3dbb5409091f554df`. Full run log: `/tmp/typing-r3-focused.log`. Do not substitute these focused tests for the complete186 screenshot matrix or independent persistence audit. No clipboard sentinel audit ran concurrently with the verifier's separate ordinary-UI regression; its simulator/build directory were untouched.

## Focused result

**3/3 passed, no failures**, `/tmp/typing-r3-focused.xcresult`:

- Actual Full Access ON, empty + selected host:109.811s.
- Actual Full Access OFF, empty + selected host:68.541s.
- Canary UI/no-export/hide/reset/reseed/background/terminate:passed.

Neither ON nor OFF required the conditional blank-input-view recovery. Canary required the expected real submenu swipe. Full Access ON consent and actual switch values1/0 were asserted; screenshots are attachments. This proves successful canary exercise, not a completed before/after persistence audit. Full186 matrix remains for independent verification.
