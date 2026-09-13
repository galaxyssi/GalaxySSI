# Window-Independent Transcript Projection

Date: 2026-09-13. Continues the complete multipath goal and draft PR #3045.
This is not full all-windows-closed, ten real model runs, Doze or power acceptance.

## Repaired Verification Environment

The previous 18-case device attempt stopped at case 17 because the isolated
manifest removed WorkManager's initializer. The isolated runner now initializes
WorkManager's test scheduler with preserved executors before any test starts.
The real Worker factory remains in use; production startup is not modified.
The README now invokes the custom runner instead of the old default runner.

The isolated build `build/mqtt-reply-window-isolated-v2.log` passed in 7m 11s.
Both APK package identities and the test manifest's target/runner were inspected
before installation on S26U SM-S9480 (`R5GL546G3LZ`). The connected SM-T575 was
not operated. Production App storage, pairing and version were not reset.

| Device selection | Result | Evidence |
| --- | --- | --- |
| Original 18 cases plus two reply-projection cases | 20 passed, 4.040s | `build/mqtt-reply-window-s26u-v2.log` |
| Same 20 cases with class order reversed | 20 passed, 4.108s | `build/mqtt-reply-window-s26u-v3.log` |

Both results explicitly contain `OK (20 tests)` and `INSTRUMENTATION_CODE: -1`,
with no failed-case or crashed-process status. The shell exit code alone was not
used as proof. These are 20 distinct cases repeated twice, not 40 distinct cases.
This clears the specific earlier isolated fixture failure; it does not prove
Android's real WorkManager/JobScheduler or Activity lifecycle behavior.

The cases include SQLite usage idempotence and rollback, 10,000 encrypted
conversation storage, draft/window selection isolation, upgrades, and repairing
usage after final text has already been saved without duplicating that text.
The latter exercises real Android transcript/Keystore storage, not a physical
process kill between stores.

## Shared Production Projection

`MainActivity.syncAgentTranscript` now delegates to `Context.persistAgentTranscript`
with its existing store. The implementation and all formatting dependencies
used by this projection require only Context, not MainActivity. The current UI
continues calling the same implementation with its existing localized Activity
context. There are no changes to backgrounds, layout, message ordering, rich
output filtering, permission choices or task execution.

Four additional device tests call the production projection using application
context without creating any Activity:

- Final text and image metadata survive replay with a single final entry.
- Ten independent window stores retain selection and conversation/turn ownership.
- Waiting output is not committed as a final answer and audit entries deduplicate.
- A pending high-risk action remains an approval card, without finalizing it.

The ten stores in this test are not ten Android Activities or real model runs.
The image fixture is stored metadata and is never downloaded; this is not image
preview/open/save acceptance.

The changed production code and new tests compiled in the isolated build in
6m 31s (`build/mqtt-transcript-projection-isolated-v1.log`). The four new cases
and the prior 20 cases then all passed on S26U: **24 tests, 5.408s**, explicit
`OK (24 tests)` and `INSTRUMENTATION_CODE: -1`, no failure/crash statuses.
Evidence: `build/mqtt-transcript-projection-s26u-v1.log`. The previous 20 cases
overlap this selection; they are not additional distinct coverage.

The exact verification artifacts are retained under
`build/artifacts/mqtt-window-projection-v1/`:

- `verification-app.apk`: `5D89C31943FF64DBDB6D55EFFF40B8E211D64A1764E9FA0B12CB6FDAF102A938`
- `verification-test.apk`: `B7E984895F78B8D12936A9D522A2FF2B6B5FAC504532446A320821951B74C110`

Both disposable packages were uninstalled successfully after the test. No
production package was uninstalled, cleared, reinstalled or navigated. The
normal full-runtime build is rerun separately without the isolated init script;
its result is recorded separately below.

## Normal Build Verification

`build/mqtt-transcript-projection-full-v1.log` passed in 7m 38s using the normal
manifest, native builds and embedded-runtime verification, without isolated init
or runtime exclusions. All 67 selected JVM tests passed across 10 suites with
zero failures, errors or skips. Android instrumentation Kotlin compilation and
full APK packaging also passed. Source-size and whitespace checks passed.

The full APK is `com.galaxyssi.chat`, 1.2.0 (1005), 418,772,978 bytes, SHA-256
`EA1725FDAD686A2EE219078478C51F04BEEFE2BFA2ABB2CED85A330FA301B546`.
An identical copy is retained as
`build/artifacts/mqtt-window-projection-v1/GalaxySSI-1.2.0-1005.apk`.
The isolated test APK/metadata were removed from the ordinary Android-test APK
output directory after their exact hashes, package identities and resolved
workspace boundaries were checked. The retained verification copies remain.

The new full APK has not been installed. S26U production metadata still reads
1.2.0 (1002), last updated 2026-09-13 11:34:31; the two verification packages
are absent. Desktop was neither rebuilt nor restarted in this checkpoint.

## Remaining Headless Integration

Code inspection still shows Activity-owned response restoration and consumption
in `MainActivity.agentConnectorResponseListener`, `runtimeForConnectorResponse`
and `resumeAgentConnectorResponse`. With every Activity destroyed, weak consumers
are absent even though the encrypted response inbox is durable.

The next implementation must use the existing process-owned AgentTaskRuntime
supervisor and the existing response/execution identities. It must share this
projection plus workspace checkpointing, runtime restoration, execution-loop
events, run/learning/handoff projections, continuation binding and cancellation.
It must use `AppLanguage.wrap` for the App's configured background language.
It must not instantiate a hidden Activity, append a raw reply instead of resuming
the original runtime, invent another Run ledger, auto-approve pending actions,
or replay an uncertain external mutation.

Ordered cross-store commits remain non-atomic. Real crash-point replay and
all-hosts-destroyed acceptance are still required even after the shared Context
projection tests pass.
