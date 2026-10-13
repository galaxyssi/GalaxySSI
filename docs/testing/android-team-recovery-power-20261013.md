# Android team recovery stagnation validation

## Scope

Android 1.5.3 (version code 1286) stops hot recovery loops without imposing an
action budget on healthy agent work. Desktop, Whisper/ASR, model selection,
screen assistant configuration, and transport behavior are not changed by this
PR.

## Root cause

On the S26 Ultra, a saved collaboration run referenced a group that no longer
existed. Recovery started the supervisor before checking that scope. The
acceptance workspace rejected access, the watcher swallowed the failure, and
the release callback immediately scheduled recovery again. Repeated supervisor
starts advanced event sequences but completed no child work.

The diagnostic baseline recorded 244 await failures, 1,734 checkpoint reads,
and 486 checkpoint writes in approximately 194 seconds. Checkpoint reads and
writes accounted for about 70.4 and 21.7 seconds of accumulated operation time.
The repeated encrypted database work also exercised Keystore and garbage
collection. These totals are accumulated operation durations, not independent
wall-clock phases.

## Changes

- Check each saved collaboration group before starting recovery. A missing
  group stops the run's recovery, retains saved progress, and reconciles remote
  cancellation through the existing mechanism.
- Persist per-run consecutive failures and retry deadlines in encrypted
  records. Backoff deadlines are 5, 10, 20, then 30 seconds; actual attempts are
  serviced by the existing recovery scheduler and relevant events.
- Stop automatic retries after 10 failures without new terminal child
  evidence. Show a localized goal-stalled explanation. Ordinary actions,
  timestamps, and supervisor sequence increments do not consume or reset this
  failure budget.
- Allow explicit resume to reset a valid run's failure state. Continue recording
  late results, but do not silently restart an exhausted run on a partial late
  result. A genuinely completed result can settle the run.
- Isolate recovery failures per run and record failure state before releasing
  execution ownership. Waiting for a dispatched result is not a failed attempt.
- Add bounded debug-only diagnostics containing hashed run identifiers,
  counters, timings, exception classes, and application stack locations. They
  exclude user content, exception messages, raw run identifiers, and keys.
  Release builds do not collect these diagnostics.

## Automated validation

The following command completed successfully with 209 tests across 18 suites,
zero failures, and zero errors, and produced the debug APK:

```powershell
.\gradlew.bat :app:testDebugUnitTest `
  --tests 'com.galaxyssi.chat.AgentTeam*' `
  --tests 'com.galaxyssi.chat.AgentCollaborationRuntimeTest' `
  --tests 'com.galaxyssi.chat.CollaborationAcceptanceReviewSnapshotTest' `
  --tests 'com.galaxyssi.chat.CollaborationLiveGraphTest' `
  --tests 'com.galaxyssi.chat.CollaborationTeamPanelPolicyTest' `
  :app:assembleDebug --console=plain
```

New coverage includes persistent exhaustion across policy reconstruction,
backoff deadlines, 1,000 unrestricted ordinary actions, real progress detection,
late results, manual resume isolation, missing groups, unrelated database
errors, cancellation failures, failed writes, cache eviction, UI metadata, and
diagnostic privacy. A runtime/watcher regression injects 10 supervisor-start
failures, verifies the gate is closed before release, then verifies explicit
resume can complete after the injected failure is removed.

## S26 Ultra observation

Both samples used the existing device data. The screen assistant was disabled
and Whisper Tiny GGML was selected; these settings were not changed by the
fix. Version 1.5.3 was installed over the diagnostic 1.5.2 build without clearing
application data.

After startup, the offending run was rejected by the scope preflight once and
logged `RECOVERY_STOPPED`. During the approximately four-minute observation
window, it produced no further resume-ready, await-failure, or watcher-failure
events. Other runs awaiting actual results remained eligible for their normal
recovery behavior.

| Measurement | Before | After |
| --- | --- | --- |
| App CPU, foreground observation | Approximately 100-101% | 13.8% mean over 12 five-second intervals |
| After-fix interval range | Not a matched range sample | 3.8-40.6% |
| Offending run | Repeated supervisor failure with no completed children | Stopped at missing-group preflight |

CPU percentages use Android `top` semantics: approximately 100% represents one
fully occupied CPU core, not the entire phone. The initial `top` sample was
excluded from the after-fix mean.

## Limitations

- This is a short foreground CPU comparison, not a controlled energy or
  battery-life benchmark. Residual periodic CPU spikes remain; this PR does not
  claim that all sources of heating are eliminated.
- The working checkout contained unrelated transport changes in both device
  builds. Those changes are excluded from this PR; these measurements are not
  standalone transport regression evidence.
- Physical cold-start verification after stopping the offending run was not
  completed because the S26 Ultra disconnected before that check. Persistence
  across policy reconstruction is covered by unit tests, not by a completed
  device-reboot acceptance test.
- Raw logs and private diagnostic artifacts remain local and are not included
  in the repository.
