# Background Connector Inbox Checkpoint

This is an implementation checkpoint for draft PR #3045, not full multi-broker
acceptance. Android/Desktop remain 1.2.0; Android versionCode remains 1005.

## Implementation

- An authenticated response is persisted in the existing encrypted inbox before
  a unique WorkManager request is enqueued. Work data contains only its opaque
  inbox identity, not the response body or a second copy of conversation state.
- The existing page consumer retains priority. Its claim does not retire the
  durable wake-up: the worker retries until the inbox row is actually handled.
  Startup reconciliation also pages through outstanding inbox entries.
- With no page consumer, the worker restores the original task-scoped runtime
  under the existing supervisor lease. A second recovery owner cannot acquire
  that workspace concurrently. Scope conflicts do not redirect a reply into the
  currently selected conversation or change the original task to failed.
- Runtime outcome handling, finalization, transcript/rich-output projection,
  usage accounting and workspace snapshots reuse the foreground implementations.
  The new path does not paste raw supervised control payloads into chat, dispatch
  a replacement task, or grant tool approval.
- Accepted-response checkpoints bind the inbox identity to the saved session,
  timestamp, phase and loop revision. A changed session cannot reuse an old
  projection checkpoint. Matching partial commits retain the inbox until output,
  usage, old delivery completion and continuation binding have succeeded.
- Run finalization is shared with background execution. Structured handoff
  completion can use the durable workspace's run ID after a page removes its
  in-memory mapping. Handoff store mutations serialize across helper instances.
- Background execution uses the existing recovery foreground notification;
  chat layout, colors, input controls and output formatting are unchanged.

## Verification

The final normal full-runtime build passed in **5m 1s**, with **102 JVM tests**
across nine suites and zero failures, errors or skips. Android-test Kotlin also
compiled. Log: `build/mqtt-background-full-v1.log`. The default embedded runtime
and native build were enabled; no isolated init script or runtime exclusions
were used in this final build.

The seven device cases compiled in the preceding isolated build
(`build/mqtt-background-isolated-v3.log`, 5m 48s). That build predates the final
explicit conversation/private-mode binding and formatting follow-up. Regenerate
the isolated APK from current source before running on S26U; none was installed.

Full APK: `build/artifacts/mqtt-background-v1/GalaxySSI-1.2.0-1005.apk`,
**418,793,502 bytes**, SHA-256
`BFEEEE90AB9D1F1439DE39697D9FB14ECC05CA4F2EC7FD407F58F7D8D4C2B423`.
Package identity verified with aapt: `com.galaxyssi.chat`, version 1.2.0 (1005).

JVM suites: background identity (12), reply commit (6), response router (6),
control plane (17), conversation skill lifecycle (8), learning engine (17),
recovery transcript (10), task identity (5), task supervisor (21). These overlap
previous checkpoints and are not added to their counts.

ADB currently lists only SM-T575. The designated S26U (R5GL546G3LZ) is absent.
No alternate phone was operated. No APK was installed and no production data,
pairing, Desktop process or broker setting was changed in this checkpoint.

Seven device cases are added but **not run**: ten independent connector outcomes
without an Activity, duplicate retirement, cross-conversation rejection, missing
user-record projection retry, ownership exclusion, page-claim recovery, and
opaque inbox lookup/supersession and read-only approval projection are covered
across those cases. Model and action
executors are controlled fixtures; even a later pass will not prove ten live
model tasks or real public-broker latency.

## Remaining Boundaries

- Run the new cases and the existing window/storage suite on S26U, then real
  model/window/foreground-service lifecycle acceptance with all pages destroyed.
- Interrupt every runtime-acceptance/checkpoint/finalization boundary. The gap
  before an accepted checkpoint, or a saved session changed after that checkpoint,
  is deliberately retained for reconciliation, not reported as completed or
  replayed blindly. Full automatic convergence across those gaps is not proven.
- Complete background native/model-tool event timeline parity, continuation
  timeout/cancellation coverage and idempotent learning/handoff event recovery.
  Projection-only replay does not instantiate a runtime or claim to replay
  an interrupted learning/finalization operation.
- Finish the original specification's attachments, all pair routes, owned-network
  performance/chaos, power/Doze and deployment acceptance. Public brokers remain
  limited to small compatibility smokes, never load/fault injection.
