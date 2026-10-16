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
- A separate application-launch trial found that `open calculator` succeeds but
  the Chinese equivalent of `open the calculator on my phone` includes the device
  qualifier in the app-name lookup. That routing defect is separate follow-up work.
