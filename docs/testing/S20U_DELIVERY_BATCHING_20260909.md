# S20U Delivery and Backlog Verification

## Deployment

- Android 1.1.6 (892), installed in place on SM-G9880 (S20U).
- Desktop 1.1.12, running the bounded ciphertext selection fix.
- Existing identities, pairings, conversations and encrypted transport retained.
- No SM-T575 device operations were performed.

## Reproduced Failure

Two live S20U text probes timed out at the unchanged 180-second deadline before
the Desktop fix. A request subsequently completed on Desktop. Its wall-clock
trace reported about 276 seconds from phone submission to response enqueue;
cross-device wall-clock values are diagnostic observations, not synchronized
benchmark measurements. The Desktop-local receive-to-decrypt-start wait was
about 71 seconds, followed by about 36 seconds before task dispatch. Model
execution accounted for roughly ten seconds.

Read-only route diagnostics confirmed matching direction-specific topic hashes
on S20U and Desktop. Re-pairing was not required.

Thread sampling found the outbound retry worker decrypting every pending row
inside `pending_outbound`, while other device route workers waited on the global
publish/durable locks. The live database contained about 1,620 queued messages.
The old implementation applied its batch limit only after decoding the backlog.

## Fix

Select due candidates using small unencrypted scheduling fields first. Stop at
the requested batch size, then fetch and decrypt only selected ciphertext rows.
Keep the existing route retry barrier, priority ordering, retention, ciphertext,
message identity and receipt semantics. A zero-sized batch does not open storage.

## Results

- Repository checks: passed.
- Android targeted JVM regression: 100 passed on the installed production build.
- S20U device delivery/fallback regression: 21 passed.
- Desktop task isolation and persistence/recovery regression: 104 passed.
- Desktop batching, durable delivery, routing and result receipt/outbox regression:
  88 passed, including five new batching tests. Suites overlap; do not sum them
  into a unique coverage count.
- Synthetic 10,000-row encrypted backlog: selecting eight rows took about 63 ms
  on this run; exactly eight route decodes and sixteen field decryptions occurred.
  This is a local queue microbenchmark, not 10,000 simultaneous model executions.
- After deployment, the unchanged 180-second live test passed both real requests:
  text returned in about 12.5 seconds; image recognition returned in about 41.5
  seconds. The combined instrumentation test completed in 56.662 seconds.
- Both replies matched source message, contact, conversation, turn and task;
  replies reported execution generation 1 and completed successfully.
- Image fixture: generated 640x320 PNG containing `2 + 2 = 4`; no private user
  image was submitted. Large homework images and sustained concurrent load are
  not covered by this fixture.

## Remaining Work

1. Test the complete App/conversation/turn/task/generation fence under late
   outputs, retries, cancellations and process recovery with concurrent real runs.
2. Replace per-task thread creation in AgentTaskManager with bounded scheduling;
   existing provider runtime pools do not cover every high-level task entry.
3. Apply fair admission before consuming global slots, with starvation tests
   across more routes than the available slots. Existing outbound ordering alone
   does not prove cross-App fairness across repeated flushes.
4. Persist scheduling ownership and recovery checkpoints, then introduce trusted
   multi-node leases with fencing tokens. Do not claim current SQLite state is a
   distributed scheduler or share it unsafely between independent workers.
5. Measure real repeated text/image latency, resource limits and cancellation
   under 10 concurrent runs before expanding synthetic queue-scale tests.

The complete scalability objective is not finished by this delivery patch.
