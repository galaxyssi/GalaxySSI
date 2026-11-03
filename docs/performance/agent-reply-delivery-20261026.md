# Agent final-reply delivery latency

## Scope

This change targets the interval from Desktop's completed model result to the
Android UI drawing the completed reply. It does not claim that model inference,
tool execution, or arbitrary public-broker delivery always finishes in three seconds.

Android version: 0.1.6.25 (1401). Desktop version: 0.1.6.6.
The S26 Ultra was updated in place without removing chats, pairing, or models.

## Findings and changes

- Android's checkpoint roots used a shared encrypted preferences file of about
  14 MiB. Each small checkpoint rewrote unrelated history. New roots now use
  individually encrypted SQLite rows. Legacy roots are read lazily; deletion
  tombstones and row updates are atomic, including across storage instances.
- Completing a run repeatedly decrypted the same event history. Event-type
  existence and latest-event queries now avoid that scan; timeline synthesis
  reads its existing events once and retains newly appended events locally.
- Background learning held the run-recorder monitor across a cold history scan.
  It now releases the monitor between records so completion can proceed.
- A live response could wait behind unrelated historical runtime restoration.
  Replies owned by an active source use an independent serial worker; unknown
  sources remain on the recovery worker. Generation, identity, and durable
  response admission checks remain unchanged. Duplicate runtime restoration in
  the live listener has also been removed.
- Desktop immediately flushes a durably queued final result after releasing the
  Signal publication lock. Retry cycles drain outgoing messages before inbox
  compaction/recovery. Failed immediate publication retains durable retry ownership.
- New timing spans contain identifiers and durations, not message content.

## Measurement

Use `tools/dev/measure-agent-reply-latency.ps1` with the token of an actual debug
Agent submission. The script correlates conversation/turn/task identities and
reports local monotonic spans separately from cross-device wall-clock estimates.
It samples phone clock offset three times, uses the lowest-round-trip sample,
and includes the remaining sampling uncertainty. Do not interpret broker PUBACK
as a phone receipt or transcript persistence as a visible UI frame.

Before this change, two real Codex replies took approximately 6.6 and 8.0 seconds
from Desktop completion to Android display (clock-corrected estimates).

An intermediate build reached 2.988 seconds, but another cold-start trial took
8.721 seconds. The latter exposed a 3.877-second wait before response consumption
and prompted the live/recovery worker separation. Those intermediate results are
not a claim of passing the final three-second target.

The isolated on-device checkpoint benchmark used 10 MiB of synthetic plaintext
stored encrypted in a dedicated test namespace. Eight writes per storage method
gave medians of 151 ms for the legacy file and 3 ms for row storage. Test cleanup
only cleared its own namespace. This is a storage microbenchmark, not an
end-to-end latency percentile.

## Verification

- Desktop frontend checks: 95 passed.
- Backend delivery, result-outbox, and timing regression tests: 86 passed.
- Android session, completion, and execution unit regressions: 133 passed.
- Device tests cover lazy legacy reads, restart/reopen, deletion and recreation,
  run-scoped event lookup, ledger ordering, and replay idempotency.
- Device scheduling regression deliberately blocks historical recovery and
  checks that the live-reply worker can still execute.
- Native ASR/QNN sources and binaries are unchanged. The build reuses the
  existing native-memory library (`-x :app:buildNativeMemory`).

## Final replay results

All four trials below used the installed final Android build and the running
Desktop build. Model execution was real Codex execution, not a mocked reply.
Values are milliseconds; network and total delivery values are clock-corrected
estimates. The last three trials ran after the compiler finished.

| Trial | Desktop completed to wire | Downlink estimate | Phone receive to visible | Completed to visible estimate | Clock uncertainty |
| --- | ---: | ---: | ---: | ---: | ---: |
| First post-install, build still active | 1755 | 414 | 5640 | 7810 | 22 |
| Subsequent foreground request | 1338 | 373 | 1805 | 3516 | 35 |
| Fresh process after instrumentation | 1901 | 468 | 2140 | 4509 | 29 |
| Subsequent foreground request | 1294 | 346 | 1703 | 3341 | 27 |

The three-second target remains open. The final build improved normal delivery,
but it did not demonstrate a three-second upper bound or a passing P95. More
profiling is needed in Desktop's pre-publication work and Android's admission,
finalization, and UI projection. The single intermediate 2.988-second result must
not be used to claim stable acceptance.

The device suite reported 13 tests; its two pre-existing restart-parameter cases
were skipped because their explicit restart token was not supplied. The other
11 tests, including the deliberately blocked recovery worker, passed. The APK
was installed without uninstalling or clearing data; first-install time remained
unchanged. The existing unrelated news changes in the shared checkout were
preserved in the device build and are not included in this PR.
