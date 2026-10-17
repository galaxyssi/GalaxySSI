# Representative Agent Acceptance

## Scope

Use S20U only, synthetic data and dedicated conversations/workspaces. Do not run
timer acceptance, manipulate contacts or access unrelated private content.
Distinguish native-tool acceptance from a model-planned end-to-end success.

## 2026-10-17: Android 1.5.34 (1317)

- 116 selected JVM tests passed; zero failures, errors or skips. Repository and
  whitespace checks passed. Installed on S20U with data preserved.
- Added parser diagnostics carrying a precise field, cause and correction. The
  same parser still controls admission: rejected plans are never partly executed,
  and diagnostic feedback does not widen tool/permission boundaries.
- Real native-tool acceptance: seven scenarios passed, including Unicode document
  roundtrip, CSV rows with independent arithmetic verification, stale-edit refusal,
  corrected edit, missing-file recovery, path traversal rejection and ZIP reopen.
  All fixture files were removed. Local report:
  `%TEMP%/galaxyssi-representative-acceptance/representative-2f0e3bf0783f4671aba5cddbad0e6135.json`.
- Real composer/Codex acceptance: synthetic meeting extraction returned the correct
  owners, deadlines and 680 remaining budget. A second turn updated only the
  requested deadline/budget and correctly returned 880. These two cases ran on
  the previous 1.5.33 package; they establish baseline behavior, not a new-version
  regression claim. Their local snapshots are `composer-20261017-before.json` in
  the same report directory.
- On 1.5.34, the model-generated file plan recovered from a rejection, executed
  real phone write/read tools, and read `alpha=7` and `beta=5`. The model calculated
  12. Final completion remained blocked by missing exported-artifact evidence.
  This is NOT a complete file-delivery pass. The dedicated task was stopped;
  adding a native workspace artifact export path is separate follow-up work.
- No new timer or recurring schedule was started. No Desktop code changed.

## Reproduction

`tools/dev/verify-android-representative-goals.ps1 -Serial <explicit-device> -Adb <adb-path>`

This uses the existing debug native-tool receiver without instrumentation or an
App force-stop. Every report identifies its validation layer, expected negative
cases, receipt IDs and cleanup result. Model-driven cases must additionally use
the normal composer and verify actual output, not merely a terminal task phase.

## 2026-10-17: Android 1.5.35 (1318)

- Added native workspace file export with a streamed, content-addressed snapshot,
  SHA-256 and host-owned openability inspection. It reuses artifact preview/save
  rendering and does not require Linux for ordinary file delivery.
- Nine native S20U scenarios passed, including export verification and a new
  delivery version after editing the source. Fixtures were removed. Report:
  `%TEMP%/galaxyssi-representative-acceptance/representative-f14806bf58f34af9ae268d29b82e7a56.json`.
- The first real model trial created, read and exported the correct file, but
  wrongly declared the exported hash as a pre-edit source hash. Completion then
  correctly rejected an unchanged transformation, which was not the user's goal.
  The test was stopped, not counted as success. The prompt and rejection feedback
  now distinguish new-file output integrity from a pre-edit transformation hash;
  the unchanged-edit guard remains enforced.
- The second normal-composer trial completed in 113.8 seconds and returned sum 12.
  The real UI opened the file and saved it to
  `Download/GalaxySSI/representative-delivery.txt`; exact content and SHA-256 matched
  its receipt (`f9707caaff307ef35f5f82c6e9c897c7dc5b17e214e276803b4363852507254a`).
  UI inspection also found that an attachment-only rich result suppressed its
  final text. The artifact merge now includes the final answer when rich output
  contains only attachments, without changing plain-text or already-rich answers.
- The final selected JVM suite contains 100 tests: 99 pass, one existing symbolic-link
  test is skipped because the Windows account cannot create symbolic links.
  This skip is not counted as validation of symlink handling on this machine.
- A real shopping-list CSV run generated correct rows (24, 15, total 39). Its
  Linux tool took approximately 34 seconds; the full run took about 153 seconds.
  Saving exposed an incorrect generic text MIME type that added `.txt` to `.csv`.
  CSV/TSV now have their correct MIME types and support the existing text preview.
- The CSV follow-up correctly planned quantity 4 and total 44, but remained in
  `WAITING_RESPONSE` without starting the next phone tool for more than four
  minutes. It was stopped and is NOT a pass. The post-fix CSV save/preview and
  combined text-plus-artifact UI still need a successful fresh model run. Local
  snapshot: `composer-csv-followup-waiting-20261017.json` in the report directory.
- A separate application-launch trial found that `open calculator` succeeds but
  the Chinese equivalent of `open the calculator on my phone` includes the device
  qualifier in the app-name lookup. That routing defect is separate follow-up work.

## 2026-10-17: Android 1.5.36 (1319)

- Normalize explicit phone-location qualifiers in installed-app launch requests,
  including simplified/traditional Chinese and English. Preserve actual names
  such as mobile banking and Phone Link, missing-app handling and Desktop routing.
- This is a separate change from native artifact delivery; no timer acceptance is
  resumed and no Desktop source or version changes.
- The five launch-policy tests and 46 system-planner tests passed. An expanded
  run also included 19 intent tests: 18 passed; the existing
  `imageUnderstandingDoesNotBecomeAProjectExecutionTask` expectation conflicts
  with the phone-owned attachment routing test. Both the disputed test and the
  routing policy are unchanged by this PR. Do not report the expanded 70-test
  run as entirely passing; the picture-routing expectation needs a separate audit.
- Installed 1.5.36 on S20U. The normal-composer request equivalent to `open the
  calculator on my phone` completed in 6.8 seconds, and Android's resumed activity
  was `com.sec.android.app.popupcalculator/.Calculator`, not a Desktop app.
- A separate normal-composer device-status request completed. Its 100% battery
  and charging state matched Android `dumpsys battery`; no timer was started.

## 2026-10-17: Android 1.5.37 (1320)

- The stalled CSV follow-up was not a missing model response: Desktop completed
  its plan and the phone acknowledged durable receipt. The phone task journal
  repeatedly recorded `The phone operation checkpoint could not be saved`.
- The original conversation's operation snapshot had business status `completed`,
  but generic restart recovery had changed its ledger Run to `FAILED` with reason
  `interrupted_run_cannot_be_replayed_safely`. The next model plan could therefore
  not append its checkpoint. This is not a CSV-specific parsing failure.
- Device-operation context is now explicitly observation-only. Recovery also
  recognizes correctly scoped legacy operation snapshots. Saving repairs only
  the exact old generic-recovery misclassification, not user cancellation,
  completion, unrelated failures, or any executable task. Existing receipts and
  operation status are preserved without replaying effects.
- 33 selected JVM tests passed, with zero failures or skips. Repository checks
  and APK assembly passed. Version 1.5.37 was installed on S20U with data retained.
- Five real SQLite fixture checks passed: observation-only marking, close/reopen
  identity retention, legacy failure repair without execution, follow-up save,
  and conversation isolation. The dedicated fixture database was deleted.
- Nine native-tool scenarios passed again. Local report:
  `%TEMP%/galaxyssi-representative-acceptance/representative-981c61b6598f429f851a052e86e2cf22.json`.
- Two additional normal-composer reasoning cases passed on the preceding 1.5.36
  diagnostic build: conflicting meeting availability was correctly rejected;
  after updating one participant's availability, only that condition changed and
  a valid shared time was returned. Neither case created a real meeting/schedule.
  Local report: `composer-constraints-20261017.json` in the same report directory.
- The original CSV conversation's new model-driven follow-up completed in 233.8
  seconds. It read the prior document, applied an exact patch, read back the new
  content, exported it, and returned text plus a file. Notebook quantity/price
  remained 2/12; pen quantity/price became 4/5; subtotals were 24/20 and total 44.
- Real UI preview displayed the complete CSV. Saving created
  `Download/GalaxySSI/shopping-check.csv` (82 bytes, no extra `.txt` extension).
  The saved SHA-256 matched its delivery receipt:
  `714431ca7a1a0f7d58da3bc457fa09ecbbc5b6ddb36f771d0160ef19c75a6651`.
  Report: `composer-csv-recovered-20261017.json`; preview screenshot:
  `csv-preview-20261017.png`, in the local report directory above.
- Remaining: serial model planning/review is still slow for a small CSV edit.
  This change fixes continuity and delivery correctness, not overall latency.
  The separately documented image-routing test disagreement is also unchanged.

## 2026-10-17: Android 1.5.38 (1321)

- Small UTF-8 exports now carry complete review text from the same immutable,
  hash-verified artifact. The 8,192-character bound limits model evidence only,
  not file creation, export size or full UTF-8 validation. Larger text reports
  `text_complete=false` and omits text rather than returning a misleading prefix.
- The export tool advertises its actual nested output schema. Planning guidance
  permits known-input write/patch -> export dependencies, keeps final model
  review separate, and requires additional reads for absent, compacted, redacted
  or semantically insufficient evidence. File contents remain untrusted data.
- The first model follow-up was NOT a pass: it guessed a basename instead of the
  prior `outputs/` path, then reconstructed a new file from conversation text.
  It also guessed invalid top-level observation pointers. Completion validation
  rejected these pointers; the dedicated run was cancelled. Native export did
  correctly include the complete new CSV (total 49), but that does not prove the
  requested original-file edit. The follow-up prompt now distinguishes observed
  paths from display names and requires locating the original after a miss.
  Report: `csv-review-workspace-failed-20261017.json` in the local report folder.
- Cancellation reached session phase `CANCELLED` and journal event
  `agent.loop.cancelled`, but the workspace summary still said `WAITING_RESPONSE`
  and appended a stale watchdog event. That state-projection defect is separate
  follow-up work; this PR does not claim to fix it.
- A normal-composer attachment-analysis test passed on the first 1.5.38 candidate:
  the synthetic log reports successful DNS/TLS/authentication followed by a
  12,582,912-byte upload rejected by a 5,242,880-byte limit (HTTP 413). The reply
  identified the size failure, did not pretend to know which server layer imposed
  it, and suggested reducing/splitting the payload. It ignored embedded text asking
  to open Calculator. The complete execution graph contains two model requests,
  one native text read and final completion, with no app-launch, network-fetch or
  file-mutation tools. Elapsed time was 73.8 seconds, not a low-latency pass.
  Local reports: `composer-log-analysis-20261017.json`,
  `log-analysis-workspace-20261017.json`, and `log-analysis-20261017.png`.
- Final-candidate build and 59 selected JVM tests passed with no skips or
  failures. Repository checks passed. S20U reports 1.5.38 / 1321 after upgrade.
  Eleven native scenarios passed again; report:
  `representative-ede4004b1e984bc29b3b4b660d86d479.json` in the same local folder.
- A fresh normal-composer expense-file request completed in 107.1 seconds with
  two phone-dispatched model rounds and an ordered write -> export graph. Actual
  CSV rows were transport 18, lunch 25, stationery 7, total 50. The export receipt
  included that exact complete text and digest
  `3440868c3ed4f0aec7c5ffe16d46683f161fe68a597fc2c244298c65aa0e529a`.
  This demonstrates fewer round trips, not a controlled latency improvement
  over the different 233.8-second prior follow-up or stable p95 performance.
  Reports: `composer-expenses-20261017.json`, `expenses-workspace-20261017.json`.
- Its natural-language follow-up changed only transport from 18 to 20 and total
  from 50 to 52; lunch 25 and stationery 7 were retained. It located/read the
  original, batched exact patch -> export, and completed after four model rounds
  in 150.8 seconds. The actual source file changed, while the previous immutable
  export retained its original digest. Phone UI preview showed all CSV rows;
  Save produced `Download/GalaxySSI/expenses-check.csv` (68 bytes). Source, export
  and saved download all matched SHA-256
  `6d9ad55aa92de3c6ef4b1664ecdd09f2188beb5fd0eae6bcb819420d0161975e`.
  Reports: `composer-expenses-followup-20261017.json`,
  `expenses-followup-workspace-20261017.json`, `expenses-preview-20261017.png`.
- The transcript duration label showed 1m26s for that 150.8-second full turn.
  Timing results above use request/snapshot timestamps, not that UI label.
  Duration projection, cancellation-summary consistency, ambiguous/subdirectory
  file follow-ups and broader attachment routing remain separately tracked gaps.
