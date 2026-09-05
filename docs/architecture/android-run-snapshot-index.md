# Android Run Snapshot Index

## Scope

Android 1.0.8 adds a durable projection index to the encrypted Run event ledger.
The first consumer is `AgentRunEventVoiceAgentRunRepository`, which also handles
connector progress and legacy final responses. It does not change ASR inference,
QNN model residency, Desktop execution, provider selection or the wire protocol.

Previously, task/message/request lookups enumerated up to 256 recent Run roots
and decrypted each Run's entire event history. A lookup miss did the same work.
Runs older than that window could not be found even though their events existed.
PR #2811 moved these scans off the UI thread; they still delayed the background
reply-consumer queue. Its last S26U sample waited 8,046 ms in that queue.

## Transactional Projection

- Database schema v2 adds `run_snapshot_index`; it does not replace the database.
- Each `(snapshot kind, Run)` points to the latest matching encrypted event.
- Task, source-message and request lookup keys use domain-separated SHA-256.
- The event body is not duplicated, cached indefinitely or stored in plaintext.
- Event append, root state and projection update share one SQLite transaction.
- An index write failure rolls back the event and root update as well.
- Idempotent replays do not append another event or move the projection.
- A successful exact lookup decrypts one event; a miss decrypts no event bodies
  after the initial migration. The decoded identity is validated again.
- A lookup-key hash is metadata minimization, not encryption of all metadata:
  sequence, ordering, kind and hashed identifiers remain visible in the index.

The generic ledger still owns event ordering and root isolation. The registered
snapshot contract validates voice Run, task, conversation and source-message
identities against the enclosing event. Existing voice events use a different
event turn identifier, so this migration does not rewrite historical turn IDs.

## Upgrade and Recovery

Old databases receive an empty index at schema upgrade. The first snapshot read
backfills at most 32 encrypted events per transaction, releasing the ledger lock
between batches. This is a migration batch size, not a retention/action budget.

The durable checkpoint records both the last processed event ordinal and a fixed
high-water mark. A restart resumes from the committed checkpoint. New events are
indexed immediately, including during migration. A backfill never replaces a
newer sequence with an older one. Decode/validation failure rolls back the current
batch and leaves its prior checkpoint intact for diagnosis and recovery.

The first read waits for migration completion on its background caller. This is
not a claim of constant-time first upgrade: migration cost depends on historical
event volume. Subsequent lookups use the index without rereading history.

## Bounded Restore

Startup calls `recentSnapshots(limit)` instead of enumerating all Runs and then
taking the last items. Database pages contain at most 256 projection pointers;
the voice repository requests pages of at most 128. Neither number deletes data.
Explicit full enumeration remains paged internally. Clear-voice removes all
voice Runs, including older ones, while preserving unrelated Run kinds.

## Verification

The regression suite uses isolated, uniquely named databases with the real
Android SQLite and Keystore paths. It never resets production App data.
It covers exact lookups beyond the previous window, paging, cold reopen,
transaction rollback, duplicate replay, invalid identity, SQL query plans,
unrelated corrupt history, interrupted backfill, concurrent new events, recovery
after repair and the actual voice repository's bounded startup API.

The force-stop test exposed an existing evaluation recovery crash: recorded Runs
can exist before a provider is assigned, but evaluation wrote their empty
`executionResourceId` into the required event `agentId`. Evaluation now preserves
an existing event's full root/turn identity. If no event/resource exists, it uses
the explicit `galaxyssi-eval-observer` actor with observation-only/unassigned
metadata, rather than claiming a model executed. Failed observations are logged
without private content, and recovery failures are isolated per recorded Run and
stage. This does not relax the Run Kernel's nonempty identity validation.

Real-provider timing is measured separately using the opt-in Chinese reply probe
and the existing monotonic latency journal. Single samples are not P95/P99, and
Desktop wall clocks are not subtracted from phone monotonic timestamps.

## S26U Results (2026-09-05)

- Installed 1.0.8 / versionCode 854 using `adb install -r`; original install time
  stayed 2026-09-05 10:48:56. No production uninstall, reset or re-pairing.
- Final APK SHA-256:
  `69b446e60897c5702b65a1de708c42ba1978e8dbcbce32f8f5bd33831f614341`.
- 100 JVM tests passed, including snapshot contracts, evaluation identity,
  voice Run transitions, Run roots, reply correlation and latency accounting.
- Final device suite: 24 passed, 2 opt-in legacy process-restart methods skipped.
- The two new opt-in migration phases saved a 32/65 checkpoint, force-stopped
  the App and recovered the same database after the evaluation crash fix. All
  65 snapshots remained and the next append received sequence 2 as expected.
- Two Chinese real-Codex reply probes completed. Each instrumentation invocation
  starts a new phone process; these are not pure warm-App startup measurements.
- The temporary test package was removed, and the production App reopened with
  the last answer intact. `am start -W` reported 562 ms for the Activity launch;
  that is not a measurement of every restored message or startup background job.
- Repository checks and APK/test-APK builds passed. iOS/Desktop were not edited.

On the same isolated 301-Run dataset, the legacy root/history scan primitives
took 1,578.15 ms. Thirty indexed target queries measured P50 3.41 ms / P95 4.66 ms;
one miss took 0.11 ms. This is a database microbenchmark, not an Agent-reply SLO.

| Phone monotonic interval | PR #2811 sample | 1.0.8 sample 1 | 1.0.8 sample 2 |
| --- | ---: | ---: | ---: |
| Send to first visible output | 22,941.80 ms | 16,669.39 ms | 17,298.53 ms |
| Send to final draw | 37,641.38 ms | 19,759.91 ms | 21,107.18 ms |
| Final receive to consumer start | 8,046.04 ms | 128.98 ms | 138.46 ms |
| Consumer start to accepted | 1,066.73 ms | 417.60 ms | 543.22 ms |
| Accepted to finalized | 4,556.62 ms | 559.29 ms | 745.77 ms |
| Final receive to final draw | 13,775.77 ms | 1,190.41 ms | 1,489.94 ms |
| UI callback queue | 0.65 ms | 0.53 ms | 0.31 ms |

The two current Desktop tasks independently reported `agent_id=codex`, completed
with no error, and took 11,303 / 12,142 ms there. The older Desktop sample took
14,529 ms, so the whole end-to-end difference must not be attributed solely to
the Android change. Neither current probe recorded a main-thread heartbeat wait
of 250 ms or greater. The last crash-buffer entry remained the pre-fix evaluation
failure; no new same-path crash appeared through recovery, both probes and cold
reopen.

The complete-reply 10-second target and P95/P99 across realistic traffic are
still unproven. Provider/network latency, other recovery paths and broader chaos
coverage remain separate work; these results do not complete the overall goal.
