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
