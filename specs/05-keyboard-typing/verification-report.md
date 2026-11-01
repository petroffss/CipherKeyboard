# Independent verification — round 3

Frozen source: `3df0780388f7df99e6f376c9ab550c2a3a4e1d51`; loaded build marker `861862296`. Verifier made no product or test edits. This report uses independent executions, not builder test claims. Main simulator `CE56E4D3-8193-4BFA-8996-FA3AA4A628C9` was untouched.

## Completed checks

- `scripts/test.sh core`: exit0, **15 typing tests/4 suites +135 crypto/core tests/23 suites**. The overlapping-touch tests now require both valid releases (Пр or Рп), independent cancellations and timers. `core.log`.
- `scripts/lint.sh`: exit0, **66 files**. `lint.log`.
- Isolated Regression device, `.build/VerifierRound2Regression`: `scripts/test.sh ui` restricted to `KeyboardTypingTests`, `ContactsUITests/testDeleteAsksConfirmation`, and `ContactsUITests/testNameValidationInSheet`: **4/4 passed,0 skipped,exit0**. Bundle `.build/TestResults/ui-20261101-154223.xcresult`, `focused-ui.log`, `focused-ui-results.json`. Preview uses actual setup status/fingerprint and real keys; connected production controller verifies proxy isolation and accessibility/globe visibility boundaries.
- `scripts/build.sh -configuration Release` with separate `.build/VerifierRound3Release`: exit0. Actual Release app/extension binaries contain none of nine debug/fixture/seed/isolation/canary/host markers; no DebugHost files in app. `release-build.log`, `release-audit.json`. The script's generic success message prints a Debug path; the audited files were the actual `Release-iphonesimulator` binaries.
- Installed-byte verification: final runtime runner compares installed and built extension dylib, then verifies loaded revision from the real UI. SHA256 `e85e22bbb5193f007c440d094f2f79cce75f85d45dcf23b3dbb5409091f554df`. `runtime.log`.

## E12: no-export interaction passed; full persistence audit did not

The dedicated serial canary UI test passed **1/1 in24.3s**, exit0 (`audit-ui.log`, `/tmp/verifier-r3-audit.xcresult`). It inserted the exact synthetic canary, checked no copy/cut/paste/share menu, dragged toward the host without changing it, confirmed actual hide and panel disappearance, reopened empty, reseeded, backgrounded and terminated the host. No other UI/clipboard test ran concurrently.

Before/after snapshots (`audit-before.json`, `audit-after.json`) show16 checked files unchanged, defaults unchanged, no UTF-8/UTF-16 canary matches in checked app/extension/group files, and no canary in scoped app/extension/host logs. Clipboard SHA256 was also unchanged.

**These facts do not pass E12.** The sentinel did not install: `clipboardIsSentinel=false` already in the before-snapshot. A bounded diagnostic confirmed correct `simctl pbcopy` syntax and exit0, but three immediate `pbpaste` reads retained the same93-byte hash rather than the34-byte synthetic sentinel. No actual clipboard contents were printed. The audit message “clipboard sentinel changed” is misleading here: the observed hash did not change; setup was invalid.

**The selected Keychain metadata lists had0 rows before and after.** An empty-list comparison is not evidence that actual identity entries stayed unchanged. Any earlier shorthand “keychain metadata unchanged” must be understood as an invalid coverage claim and is corrected here. No secret/value columns were read. A future authorized verification must establish a known nonempty identity fixture and validate that the chosen Keychain database/query actually sees its identifying metadata; then compare that metadata without disclosing secrets. It must also assert a successfully installed sentinel before proceeding.

## E14: 18/186 captured; full design acceptance failed

All three native profiles were attempted with independent build directories. Initial375 reached actual Full Access ON but failed extension activation with a visible system English keyboard. Initial402 failed waiting for Full Access value1. Concurrent load is a possible confound, not an established cause.

Native440 passed setup and captured **18 screenshot/geometry pairs**: all15 extension states in light portrait440×956, plus light landscape956×440 ru-empty,ru-text,shift. It then failed when the landscape `caps` submenu item was not hittable after three swipes (`TypingTestSupport.swift:113`). This is a Debug/system-menu test-harness blocker, not proof that the production Caps key is broken. A planned serial402 control run was interrupted before frames at coordinator instruction after E14 failed in the third review round. No further matrix retries or fixes were made.

`matrix-440-frames/manifest.json` names every captured image/reference anchor and explicitly lists **168 missing frames**. All18 raw images were individually opened and compared against the matching approved mockup markup; `design-review.md` records each comparison and `geometry-review.json` records dimensions. Portrait panels316/378pt, landscape220pt; key heights44/32pt; minimum letter widths33.56/61.09pt. Four rows remain visible, popup is inside panel, error/counter are visible in the captured frames.

Observed deviations are unresolved: all15 portrait frames show a soft blur/fade over the upper portion of editor text/placeholder, absent in the three landscape frames and reference. Examples: `matrix-440-frames/raw-0/48A0B5DD-DF07-4385-A68F-F1923CF34608.png` (ru-empty) and `DE41C640-8639-41F0-99E1-4AC17C5848DE.png` (ru-text). The cause was not diagnosed. Multiline and limit fixtures also use different synthetic text from the approved excerpt; the literal reference text therefore was not matched. This is not full design acceptance and must not be reported as “18 frames passed” or silently generalized to missing sizes/themes.

## E17: full regression was not completed green

The earlier frozen round2 full suite was interrupted after11 passes,2 actual Contact UI failures, and one canceled test. On final round3 both actual failures passed focused reruns. Their assertions were sheet disappearance after Save (`ContactsUITests:615`) and row appearance after saving trimmed name (`:205`). This suggests timing sensitivity but does not establish baseline attribution and does not turn the incomplete full suite green. A full final-snapshot suite was not rerun after coordinator bounded the third-round workflow. Core/lint/Release/targeted successes cannot substitute for that requirement.

## Prior finding correction

The original round1 claim of retained draft after genuine Hide was not established: the old test neither confirmed actual Hide after rotation nor proved current installed app bytes. Round2 and current checks use settled host coordinates, focusfalse, panel absence and loaded revision. Preserve that correction; do not repeat the unsupported old production-defect claim.

The final current-runtime result and17-eval table follow below.

## Final result: 14/17 pass; E12,E14,E17 fail

The independent final serial runtime completed **7/7 passed,0 failures,exit0** in266.985s (`runtime-summary.json`). Five statuses22.570s; real rotation/hide/reopen18.046s; background/system globe/shell parity54.044s; Full Access ON with both host variants64.437s; OFF with both variants66.895s; canary/no-export/lifecycle23.665s; ordinary Settings search12.948s. Installed hash/revision verified by runner. Receipt schema independently checked: only date/version,version1,numeric date (`receipt-schema.json`).

| Eval | Verdict | Independent evidence |
|---|---|---|
| E1 | pass | insertsAtGraphemeBoundary, exact insertion/cursor result. |
| E2 | pass | All four exact layout arrays/transitions. |
| E3 | pass | Auto/one-shot/Caps and299/301ms state machine. |
| E4 | pass |449/450ms alternatives and cancellation. |
| E5 | pass | Whole composed/flag/ZWJ Character deletion. |
| E6 | pass |399/400/480ms repeat and timer cancellation. |
| E7 | pass | UTF-8 thresholds, atomic rejection, cursor unchanged. |
| E8 | pass | Current connected production-controller proxy spy UI probe. |
| E9 | pass | Real preview keys; host/status/fingerprint unchanged; reset/absence of second keyboard. |
| E10 | pass | Current real ON/OFF × empty/selected host, full edit sequence, ordinary Settings and receipt schema. |
| E11 | pass | Actual hide/focus loss/panel absence/reopen reset after rotation; background/globe reset; current preview lifecycle and model cancellation. |
| E12 | fail | Successful canary gestures, but sentinel setup invalid and Keychain metadata0rows. No leak observed; complete audit not proved. |
| E13 | pass | Five status fixtures typed/deleted; no-access lazy factory guards. |
| E14 | fail |18/186 reviewed,168missing; system fixture-menu harness blocked; visual deviations documented. |
| E15 | pass | Actual controller accessibility/OS visibility boundary plus real system globe list/switch. |
| E16 | pass |500 actions/10 resets/zero timers, fixed overlapping-touch expectations, actual shell parity. |
| E17 | fail | No completed green full final-snapshot UI suite; matrix failed despite targeted/core/lint/Release successes. |

No further product/test fixes or matrix reruns were made after the coordinator's third-round stop. Remaining work requires the review-loop continuation decision: repair/validate fixture navigation and complete168 missing frames plus re-evaluate all186 as required; establish a real synthetic clipboard sentinel and a known nonempty auditable identity fixture; run the complete final UI suite under controlled load. Preserve initial failed attempts and distinguish harness/environment failures from product findings.
