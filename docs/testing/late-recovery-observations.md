# Late authenticated recovery observations

## Scope and motivating evidence

Android 1.1.43 (929), following PR #2968; Desktop remains 1.1.41.

In SM-T575 case `live-final-1788980024707`, recovery took 58,408 ms. Four
eight-second observation waits expired before their responses arrived. The
original client removed correlation state in `finally`, so those responses
were classified as `late_or_unknown`, even within the same process and for an
unchanged paired task. This is distinct from the preceding UI lookup fix.

## Contract

- A wait timeout ends that wait, not the validity of all later observations.
- Explicitly registered recovery observers may retain correlation metadata for
  up to 120 seconds after timeout; at most 128 expired-wait records are kept.
  Active requests are not evicted by this bound. These are memory/nonce lifetime
  bounds, not task/action execution limits.
- Metadata contains only the authenticated Desktop, route, original identity
  tuple, nonce, and an application-context callback. Handoff prompts and Activity
  contexts must not be retained. No reply body is stored awaiting late arrival.
- A scheduled expiry removes records even when no more traffic occurs.
- Unknown, mismatched, duplicate, cancelled, or expired requests cannot invoke
  an observer. Batch identity validation and inline-page nonce/hash checks remain.
- The application revalidates current pairing, registered identity, terminal
  state and execution generation before applying an observation. Existing
  encrypted inbox and result-page recovery handle publication and deduplication.
- Metadata-only inspection does not register an autonomous response observer.
- Observation application runs off the MQTT/UI threads. On-time callers must
  receive only observations accepted by the persistence/version checks; timed-out
  callers do not need to remain alive for accepted late work to finish.

No model execution is restarted by receiving an observation. Correlation is
process-local; after process death the existing persistent pending-delivery
recovery issues a new authenticated query. This change alone is not full device
reboot or unified Run Kernel acceptance.

## Verification plan

Regression cases cover on-time and late response ownership, every identity field,
wrong authenticated Desktop, explicit cancellation, rejected publish, read-only
timeout, monotonic expiry, idle expiry, metadata eviction without evicting active
queries, and concurrent duplicate arrival. Existing inline-page, outcome-version,
receipt, recovery and privacy tests must remain green.

Real-device verification uses the existing Chinese final-drop and process-death
harness on SM-T575, with exact final-body hash, one model execution, one transcript
reply, Activity recreation, and a plain cold launch. A fast sample without an
`accepted_late` event cannot prove the real late-arrival path; retain this
distinction in the results rather than inferring coverage from total runtime.

## Verified results (2026-09-10)

- Full Android JVM suite: 3,438 tests across 497 suites, zero failures/errors,
  five skipped. Eleven new regression cases cover the observer contract.
- Debug App and instrumentation APK builds passed. Repository, 16 KiB native
  alignment (73 libraries), and QNN packaging guards passed.
- Installed 1.1.43 (929) in place on SM-T575 only. The first-install timestamp
  remained `2026-09-07 07:17:23`; pairing, chats, keys and queues were not reset.
- Real case `live-final-1788982265520` passed all four harness phases. Desktop
  reports one completed Codex attempt and execution generation 1.
- In headless PID 25795, query `0c2e1381dde2` started at 03:31:46.124, timed out
  at 03:31:54.201, and was `accepted_late` at 03:32:23.622. The same-process
  correlation therefore survived a real response arriving 29.421 seconds after
  its wait expired. Earlier unknown nonces belonged to prior queries and were
  not counted as this acceptance.
- The exact original final body reached the encrypted inbox in 40,895 ms:
  connection readiness 2,629 ms, followed by 38,266 ms to body recovery.
  No substitute answer or second model execution was injected.
- UI first visibility was 5,010 ms, with exactly one assistant entry and the
  same conversation retained through Activity recreation. A subsequent plain
  cold launch retained exactly one reply and displayed it in 2,472 ms.
- Same-clock stage tracing recorded body processing at 219.415 ms and its
  checkpoint at 35.788 ms. Desktop lookup/page spans were milliseconds, while
  publish-call spans were 1.826-2.466 seconds. These publish spans include local
  preparation/enqueue work, not proof of wire delivery or broker acknowledgement.

Local evidence: `build/late-recovery-observation-verified-build.log`,
`build/late-observation-live-1788982265520.log`, and the case directory
`build/live-final-1788982265520/` (phase logs, scoped process timings, stage
report and filtered Desktop execution metadata). No message contents or device
credentials are committed with these diagnostics.

This verifies real late observation recovery, not the complete recovery SLO:
40.9 seconds remains above the target, one case is not a latency percentile,
and physical device reboot, all execution paths, and the full chaos matrix
remain outstanding. The preceding 58.4-second case and this 40.9-second case
had different network conditions; their difference is not a controlled speedup.
