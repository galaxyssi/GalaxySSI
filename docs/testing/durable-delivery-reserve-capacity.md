# Durable delivery capacity across retries

## Scope

Desktop 1.1.39 fixes durable MQTT scheduling capacity. Android remains 1.1.36;
no Android APK, pairing, keys, models, stored chats, or queue contents were reset.
This builds on the recovery control priority change in PR #2960.

The previous emergency slot was allocated anew by every flush call. Repeated
flushes could admit another recovery or terminal message despite an already
occupied reserve. Ordinary capacity also omitted Paho-owned packets after their
application retry timer expired. A peer receipt could delete a durable row before
PUBACK, incorrectly making that physical packet disappear from capacity counts.

## Changes

- Count outstanding broker ownership as well as recent durable send attempts.
- Retain capacity for broker-owned packets whose durable row was already removed
  by an authenticated peer receipt. Missing priority metadata is conservatively
  charged to the ordinary lane until PUBACK or disconnect releases ownership.
- Calculate remaining reserve from current global and per-route occupancy,
  including selections already made in this flush.
- Keep the artifact lane separate: up to four ordinary/dependency packets plus
  one reserve globally, and up to two ordinary/dependency packets plus one
  reserve per route. The existing artifact lane adds at most two global packets,
  one per route. These are in-flight limits, not lifetime task/action budgets.
- Preserve retry backoff, ciphertext, application receipts, broker ACK tracking,
  and the no-network-I/O-under-durable-lock rule.

This capacity bound covers durable dispatch, not all transient MQTT packets.
It does not retroactively cancel packets already owned by a running broker client.

## Verification

The new real encrypted SQLite queue tests cover repeated flushes, expired retry
timers with broker-owned tokens, per-route isolation, ACK ordering, artifact lane
isolation, concurrent flush during network I/O, publish failure, disconnect, and
priority filtering after a row changes state.

- Before: 5 failures among the initial 6 regression cases.
- After: 155 backend tests passed, including all 10 new queue regression cases.
- Desktop: 6 readiness and voice-playback tests passed.
- Repository guard and `git diff --check`: passed.

Local evidence:

- `build/durable-reserve-capacity-before.log`
- `build/durable-reserve-capacity-after-v2.log`
- `build/durable-reserve-desktop-tests.log`
- `build/durable-reserve-repo.log`

## Real-device result and remaining work

Only T575 (`SM-T575`) was attached during this run. A read-only recovery query
targeted the existing completed test source 13466; it did not resubmit the model
task or execute file operations. Both Desktop 1.1.38 and 1.1.39 failed to return a
verified observation inside the existing eight-second query window. The complete
instrumentation runs took 11.174 and 10.792 seconds respectively, including
connection/setup overhead. These are failures, not successful recovery latency.

Desktop 1.1.39 was started after confirming both execution pools were idle and
gracefully closing the previous window. Health, sidecar, MQTT connectivity, and
all ten subscriptions were verified ready. Existing delivery records were retained.

Evidence:

- `build/recovery-control-live-inspection-1138.log`
- `build/durable-reserve-live-inspection-1139.log`

The live query failure remains unresolved. Further work must trace query/response
queue residence, obsolete observation requests, and response acceptance while
preserving original task identity and preventing tool resubmission. Do not claim
the full recovery, five-second restart, public-network chaos, or unified Run Kernel
acceptance goals are complete based on this scheduler regression suite.
