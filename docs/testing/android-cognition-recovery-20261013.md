# Android cognition recovery integrity

## Scope

Android 1.5.4 (1287) repairs truncated memory supersession links, bounds failed
background cognition recovery, and avoids constructing an Agent for cancelled
or absent saved sessions. Normal chat/tool action counts, ASR/QNN configuration,
message transport, and Desktop behavior are unchanged by this patch.

## Observed failure

The S26U baseline was Android 1.5.3 (1286). The earlier missing-team recovery
loop was no longer present. A separate background cognition batch repeatedly
failed its memory integrity check with `missing_forward`. Five failures were
observed in approximately four minutes, including two closely spaced retries.

The critic kept each old item's successor pointer but truncated the successor's
cumulative predecessor list to twelve entries. Both world and candidate JSON
decoders applied the same truncation. Once a batch reached the integrity check,
the inconsistent graph prevented the batch from committing. Worker failure
handling also combined replacement scheduling with WorkManager retry, and
treated coroutine cancellation as an ordinary processing failure.

## Changes

- Preserve cumulative supersession edges through consolidation, approval,
  evolution, and serialization. Per-action candidate selection remains bounded.
- On repository load, prompt-context load, and backup import, restore only
  missing inverse links backed by existing same-namespace, superseded items.
  Validate the repaired graph before persisting. Do not invent facts, drop
  records, or silence cycles, missing nodes, or cross-namespace violations.
- Serialize cognition workers across modes. Persist independent failure counts
  and retry deadlines in the encrypted database. Start at 30 seconds and cap the
  application backoff at 30 minutes; WorkManager may schedule later.
- After ten consecutive failed attempts in a mode, stop automatic execution
  and add a deduplicated local system notice. A successful different mode does
  not reset that mode's failures. Fresh explicit processing resumes the budget
  once, but retries of the same request cannot reset it.
- Keep WorkManager as the only failure retry scheduler, propagate cancellation,
  and log only failure types/counts instead of memory IDs or exception contents.
- Check saved session existence and cancellation before Agent construction.
  Existing live receipt identity checks and legitimate late-result handling
  still apply to all other phases.

## Automated validation

The focused JVM regression selection contains 237 tests across 23 suites:
memory evolution, supersession, cognition policy/recovery, team recovery, and
connector receipt admission. All passed with no failures, errors, or skips.
The debug application and instrumentation APKs compile successfully.

New regression cases cover forty linked records, legacy inverse-link repair,
idempotent repair, unsafe graph rejection, codec preservation, persistent
ten-failure exhaustion, independent modes, one-shot explicit resume,
cancellation, serialized workers, and cancelled-session admission.

Device instrumentation additionally covers encrypted database round trips and
opt-in inspection of the installed memory graph. The inspection performs no
model calls and logs counts only. It can persist the same conservative repair
used by production repository loading. Fixture databases use unique names.

```powershell
.\gradlew.bat :app:testDebugUnitTest `
  --tests 'com.galaxyssi.chat.GlobalMemory*Test' `
  --tests 'com.galaxyssi.chat.GlobalAgentCognitionTest' `
  --tests 'com.galaxyssi.chat.AndroidCognition*Test' `
  --tests 'com.galaxyssi.chat.AgentConnectorReceiptAdmissionTest' `
  --tests 'com.galaxyssi.chat.AgentTeam*Test' `
  --tests 'com.galaxyssi.chat.GlobalBackgroundCognitionPolicyTest' `
  :app:assembleDebug :app:assembleDebugAndroidTest
```

## Device evidence and limitations

Baseline sampling used the existing S26U data without clearing databases,
pairing, models, or messages. During a 60-second sample, excluding the initial
`top` snapshot, App CPU averaged 7.72% and peaked at 24.8% (100% is one core).
PSS increased from 388,987 KiB to 399,799 KiB; database connection count remained
54. PSS is not a complete measurement of NPU/DMA allocation. Battery temperature
declined from 40.2 C to 37.6 C during the broader observation period; USB charging
was active, so this is not a battery-drain benchmark.

There was no new crash or ANR in the inspected baseline logs. Cumulative graphics
statistics showed 35 janky frames out of 406 (8.62%), P95 22 ms and P99 150 ms.
These are not a controlled scrolling benchmark. Cancelled Agent restoration was
still repeated approximately every thirty seconds before this patch.

S26U disconnected from ADB during the build. Installation, instrumentation on
the affected data, and post-fix CPU/temperature/UI comparisons remain pending.
Only S20U was connected afterward and was deliberately not used as a substitute.
No measured CPU, thermal, or latency improvement is claimed yet. The local
working checkout also has unrelated transport changes, excluded from this PR.

The first repository guard run included untracked local diagnostic artifacts
and failed the i18n scan on those artifacts. They are not part of this patch;
repository validation must use a clean tracked-source snapshot.
That clean snapshot subsequently passed every repository guard, including the
i18n, Kotlin size, protocol, iOS structure, and Desktop structure checks.
