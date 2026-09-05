# Android and Desktop Run Kernel Validation

Date: 2026-09-05. Baseline: main `87bec9ee6`, including pairing repair PR #2803.
Android and Desktop versions: `1.0.3`; Android version code: `850`.
iOS work is deferred and excluded from this change.

## Verified scope

- Portable event identities and per-Run sequence/idempotency checks.
- Android encrypted append-only SQLite history, indexed paging, and migration
  of the previous encrypted event arrays.
- Checkpoints preserve paused/waiting states instead of resuming execution.
- Desktop event and recovery checkpoint commit in one SQLite transaction.
- Recovery reconstructs missing JSON projections, result text, artifacts,
  result checkpoints, error reasons, and session ownership.
- A real child process exits after event commit and before JSON persistence;
  its completed result is recovered without re-execution.
- Completed UI history is bounded separately from recoverable Runs. The
  complete event ledger remains available for paged reads.
- Replayed high-level task snapshots reuse their original event even when
  the first event changed the reducer's state.

## Tests

| Check | Result |
| --- | --- |
| `python tools/dev/test-run-kernel.py` | 84 tests passed |
| Desktop `npm run check` | 16 tests passed; structure check passed |
| `AgentRunKernelContractTest` | 6 JVM tests passed |
| S26U regular `AgentRunEventStoreInstrumentedTest` cases | 7 passed |
| S26U persist/force-stop/recover phases | 2 separate tests passed |
| `node tools/dev/check-repo.js` | Passed |
| `node tools/dev/check-android-16kb.js` | 72/72 AArch64 libraries passed |
| Debug APK and instrumentation APK builds | Passed |

The Desktop runner gives subprocesses a temporary HOME/USERPROFILE so module
initialization cannot open the operator's live Desktop task database.

## S26U procedure

Device: Samsung SM-S9480. Only this device was targeted by ADB.

1. Overwrite-installed the APK without uninstalling the application or clearing
   its data. The original first-install timestamp remained unchanged.
2. Installed the instrumentation-only test package and ran the seven regular
   tests. The two process-restart tests intentionally skip in a general class
   run because they require a shared test Run ID.
3. Verified 2,051 events survive beyond the legacy array limit, with an ordered
   page of sequences 2,001-2,051.
4. Ran `persistForProcessRestart` with a unique `runKernelRecoveryId` beginning
   with `kernel-process-test-`. It saved started, paused, and checkpoint events.
5. Issued `am force-stop com.galaxyssi.chat`; `pidof` returned no process.
6. In a separate instrumentation process, ran `recoverAfterProcessRestart`
   with the same Run ID. It read PAUSED and sequences 1-3, then appended
   RUN_RECOVERED as sequence 4 and observed RUNNING.
7. Removed only test-created Runs and the `com.galaxyssi.chat.test` package.
   Reopened the main application and verified version `1.0.3 (850)`.

The recovery test body took 35 ms in this sample. A subsequent cold launch
reported 288 ms for StartupActivity. These are **not** end-to-end recovery or
UI-readiness percentiles; neither measurement proves the overall latency SLOs.

## Remaining goal work

This is an initial kernel integration, not completion of the reliability goal.
The high-level task table still owns inputs and resubmission data; its atomic
migration remains to be implemented. Real Provider cancellation/failover,
coordinator-driven resume after a device reboot, full-chain P50/P95/P99 spans,
Blob transfer chaos testing, long-running DAG scheduling, resource locks,
memory 2.0, and the self-evolution PR/CI loop still need their own integration
and acceptance evidence. Desktop packaging and UI smoke for this version have
not been claimed by the backend/unit-test results above.
