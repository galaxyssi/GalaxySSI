# Connector Reply Commit Checkpoint

Date: 2026-09-13. This continues the full multi-broker objective; it is not
all-windows-closed acceptance or a release completion claim.

Follow-up: the isolated WorkManager fixture and two new projection device cases
have now been verified, then the shared application-Context transcript projection
passed a 24-case S26U run. See
[window-independent projection](MQTT_WINDOW_PROJECTION_20260913.md). This clears
the specific fixture/device-test gaps below, not the full headless recovery gap.

## Failure Boundary

The normal Android connector resume hook persisted a workspace, retired its
inbox reply and only then posted the UI callback that saved transcript/usage
and bound a continuation. Workspace persistence also logged and swallowed
exceptions. Window teardown or a write failure could therefore leave final
projection work after the reply had already been marked handled.

The paused-window listener checkpoint is committed as `e5fde1697`. Its full
App 1.1.115 (1001) was installed on S20U, then on S26U at the user's request.
No post-fix real model timing was measured. The original 21.9s phone-side wait
is still a pre-fix baseline, not a demonstrated improvement.

## Current Changes

- `AgentConnectorReplyCommit` orders workspace checkpoint, transcript/usage
  projection, old delivery completion, continuation binding, then inbox
  retirement. The normal and legacy runtime response consumers call it before
  posting UI work. No MQTT receipt meaning or execution identity is changed.
- The normal response path requires workspace persistence to succeed. Other
  existing snapshot callers retain their previous best-effort behavior.
- Old delivery completion precedes continuation binding: the existing journal
  clears the turn's current head, so reversing these operations would retire
  the newly bound request. Later replies remain in the existing inbox.
- Connector usage is keyed by the existing exact response identity, including
  execution generation. A value digest rejects conflicting counters or a
  different conversation using the same projection identity. Negative provider
  counters normalize to zero; addition saturates without overflow.
- The encrypted conversation row and usage receipt commit in the same SQLite
  transaction. Independent helper instances cannot count one reply twice.
  Receipt rows are projection metadata in the existing conversation database,
  not a second transport/run ledger. Deletion and clear remove corresponding
  receipts; replacing retained conversation rows preserves their receipts.
- Schema version 7 adds the receipt table without clearing version 6 data.
  This is local storage upgrade safety, not old wire-protocol compatibility.
- The user subsequently requested a coordinated v1.2.0 PR. Source versions are
  now Android 1.2.0 (1002) and Desktop 1.2.0, including both lockfile root values.
  At that version-only checkpoint the installed App was 1.1.115 (1001) and
  Desktop was 1.1.51. The subsequent full v1.2.0 deployment is recorded below.

## Verification

The first full-runtime build, Android-test Kotlin compilation and 49 focused
unit tests passed in 8m 34s (`build/mqtt-reply-commit-app-1.1.116-v1.log`).
This preceded the final continuation-order extraction and its two additional
unit tests, so that APK is not the verified final artifact and must not be
installed as the final change.

The isolated verification build passed in 8m 12s. It uses
the existing non-launchable `mqttverification` package, real production Kotlin
and Android dependencies. Native/model assets are omitted only from this
non-shipping test package. It cannot replace the normal full-runtime APK. Its
inherited pre-request version is 1.1.116 (1002), not the future v1.2.0 release.
Evidence: `build/mqtt-reply-commit-isolated-v1.log`.

New tests: six usage-policy JVM cases, six ordered-commit JVM cases, and nine
Android SQLite/Keystore cases. The Android cases cover duplicate/reopen,
different executions, conflicting scope/counters, missing conversations,
receipt insertion failure rollback, ten independent helpers, deletion/clear,
retained receipt replacement and version 6 upgrade.

Current-source focused JVM result: 51 passed, zero failures/errors/skips. S26U
SM-S9480 (`R5GL546G3LZ`) passed all nine new device cases in 0.290s. A storage-only
expanded run passed 12 cases in 3.672s, including the existing 10,000 encrypted
conversation paging/mutation test, version 1 upgrade and selection/reopen.
Evidence: `build/mqtt-reply-commit-s26u-v1.log` and
`build/mqtt-reply-commit-s26u-storage-v1.log`. The nine cases overlap these twelve;
do not count them as 21 distinct cases or real network tasks.

The broader 18-case attempt did **not** pass. Existing window-history tests
triggered asynchronous cognition, but the non-launchable test manifest removes
WorkManager initialization; its test process crashed at case 17 with
`WorkManager is not initialized properly`. Evidence:
`build/mqtt-reply-commit-s26u-regression-v1.log`. The runner exit status alone was
zero and is not success: the instrumentation result explicitly reports a crash.
Fix this test environment and rerun the full window suite; do not treat the
subsequent 12-case storage run as clearing that broader gap. The production
App was not the crashing process and its data was not cleared or modified.

Pure orchestration tests alone do not prove real database or process recovery.

## Follow-up Under Verification

The current follow-up repairs interrupted orphan reply projection. An unchanged
transcript upsert means the same final text is already stored, not a storage
failure. Only a matching conversation, turn, remote task, canonical final key
and text can resume that projection; another answer is not overwritten. The
canonical key is turn-based, so the separate task check is required. Usage is
committed idempotently before retiring the inbox, and a retried existing entry
can complete draft promotion and usage. Three JVM policy cases and two Android
store cases were added; their new results must be recorded separately below.

The isolated-only runner now initializes AndroidX WorkManager's test runtime
with preserved executors before tests start. It uses the real Worker factory,
does not stub cognition outcomes, and is guarded against targeting production
App storage. The helper dependency and runner source are added only by the
isolated Gradle init script. This follows the official
[WorkManager test setup](https://developer.android.com/develop/background-work/background-tasks/testing/persistent/integration-testing).
This fixture correction still needs the previously failing full window suite
rerun; merely compiling the runner does not clear that gap.

Previous isolated app/test APKs were retained under
`build/artifacts/mqtt-reply-commit-s26u-v1/` and removed from normal APK output
paths after identity, hash and workspace-boundary verification. Both disposable
verification packages were uninstalled; production App data was left intact.
Retained SHA-256 values:

- `verification-app.apk`: `888ED8AD685B46A1039D997622E7DDDFB89333A6D59C7EFC47D73F5A98E95FC3`
- `verification-test.apk`: `8D623CF76CE45733693E9AFED1E88115052A336F2AEF9FB193F4FEDE0A98A200`

Version-only commit `90bb10c5a` sets both products to 1.2.0. At the user's next
installation request, the Desktop full package completed, including Python and
the JVM sidecar. Its visible window shows v1.2.0 and the three TLS/subscription
paths report ready. These observations preceded PR creation.

## Full v1.2.0 Deployment

The first build (`build/mqtt-1.2.0-full-v1.log`) ran 54 JVM cases and failed one:
the new different-task replay test caught the class compiled before the final
task-ID guard edit. That failed build was not installed. Once it terminated,
the unchanged final source was rebuilt normally, without the isolated init
script, native exclusions or embedded-runtime bypass.

`build/mqtt-1.2.0-full-v2.log` completed successfully in 4m 19s. All 54 focused
JVM cases passed with zero failures, errors or skips. Android instrumentation
sources compiled; the two new device projection cases and repaired WorkManager
fixture have not yet run on-device. The prior 12-case device result is not
relabelled as verification of these new cases.

The full APK identifies `com.galaxyssi.chat`, versionName `1.2.0`, versionCode
`1002`, ARM64, and the normal `StartupActivity` launcher. Embedded runtime
verification passed. Size: 418,728,586 bytes. SHA-256:
`69E222087CFF875AB5A8DC890AE7130FCEAFA5DE6F2C9E3DD7F54A452515C38F`.
An identical retained copy is at
`build/artifacts/mqtt-1.2.0-production/GalaxySSI-1.2.0-1002.apk`.

S26U SM-S9480 (`R5GL546G3LZ`) installation returned `Success`; package metadata
confirmed 1.2.0 (1002), updated at 2026-09-13 11:34:31 local time. Startup returned
`Status: ok`, then MainActivity was resumed. The saved screenshot
`build/artifacts/mqtt-1.2.0-production/s26u-startup.png` shows the existing My Agent
page, not a blank launch. No clearing, uninstallation or pairing reset occurred.
Only this S26U was operated; the connected SM-T575 was left untouched.

Desktop was repackaged only after its scheduler reported zero active/pending
Agent tasks. `build/mqtt-1.2.0-desktop-package-v1.log` records bundled Python and
the Signal JVM sidecar. The visible UI shows v1.2.0; backend health reports three
connected/subscribed TLS paths, two configured/ready peers, and Signal ready.
Packaged `mqtt_bridge.py` and `main.py` hashes match source. The package script
warned that rcedit was unavailable, so the executable's Windows file resources
remain Electron's; application version metadata and the visible App version are
1.2.0. This startup observation does not prove all outage or artifact scenarios.

## Post-Main-Sync PR Verification

PR preparation merges main `f66030ecb` after this deployment. Its versionCode
1004 requires the merged Android source to advance to 1005 while retaining
versionName 1.2.0. The installed 1002 artifact and its checks above precede that
merge. Desktop source and deployed application version remain 1.2.0.

Draft [PR #3045](https://github.com/galaxyssi/GalaxySSI/pull/3045) is open against
main without auto-merge. Source checkpoint `7ee3cbd45` passed the ordinary full
runtime build in 9m 10s (`build/mqtt-1.2.0-main-sync-v1.log`). All 67 JVM cases
passed with zero failures, errors or skips: the 54 connector cases plus the 13
knowledge read-connection-pool cases merged from main. Android-test Kotlin
compilation passed, but this does not claim the new device cases have run.
Desktop `npm run check` again passed 37 cases and its structure check.

The generated APK is 1.2.0 (1005), 418,773,434 bytes, SHA-256
`14DD9FD342A377A285E5C9108EE066DACE168088CD7343098DC20DC32899FE02`.
It was not installed during PR preparation. S26U still runs the previously
verified 1002 artifact; the running Desktop and phone data were not modified.

## Remaining Boundaries

The ordered sequence is not a transaction spanning workspace, transcript,
pending-delivery and inbox databases. Partial commits need idempotent replay;
keeping the reply pending does not itself prove every crash point automatically
recovers. The pure test's simulated projection replay is not an Android
process-death experiment.

All-hosts-destroyed final consumption still needs a process-owned coordinator
and shared runtime/projection services. The direct-control/orphan entry paths,
run/learning/handoff projections and terminal-event path need the same complete
audit; this checkpoint must not claim every path has been decoupled from UI.
No hidden Activity, automatic approval or replay of uncertain tool mutations
was introduced to simulate a headless implementation.

Next real acceptance must include fresh background replies, closing every
window, continuation responses, failure between each commit boundary,
deduplication after process restart and ten real windows. No large load or
fault injection is allowed on the three public brokers. The remaining
artifact, owned-network performance, diagnostics and lifecycle/power acceptance
remain open. The coordinated deployment above is not full release acceptance.
