# Android recovery efficiency

## Scope

Android 1.4.155 reuses work that was repeatedly allocated or recomputed during
background collaboration recovery. It does not reduce Agent concurrency, slow
the existing watchdog, change ASR/QNN models, or stop valid running tasks.

## Changes

- Production transcript stores borrow one process-owned SQLite helper per
  absolute database path. Short-lived store objects no longer create additional
  connection pools. Custom helpers remain available for isolated tests.
- Concurrent reconciliation wakes share one observation pass. A wake received
  during that pass requests another pass rather than being discarded.
- Unchanged team snapshots skip repeated transcript projection and reputation
  reconstruction. The comparison uses complete snapshots, not timestamps alone.
  Completion delivery and durable acknowledgement checks still run.
- Snapshot readers fingerprint current SQLite ciphertext with SHA-256 before reusing an immutable
  decoded snapshot. Any writer's changed ciphertext invalidates the row, even
  when its event timestamp is unchanged. Deleted rows are not returned. The
  bounded cache expires after 600 seconds and clears at lifecycle boundaries;
  it does not cache mutable execution records or skip real state transitions.
  Only the digest and bounded immutable snapshot are retained, not the entire
  ciphertext. Hashing and decoding happen outside the lifecycle cleanup lock.
- Verified phone identity agreements use a bounded 600-second cache. Identity
  changes produce a different key; trust revocation, identity reset/import and
  lifecycle cleanup clear retained secrets. Time-dependent MQTT topics and
  current send authorization are not cached.
- Managed connector responses use separately encrypted SQLite rows, indexed by
  source, supervisor and state. Legacy array migration writes rows and indexes
  and removes the old array in one transaction. Unreadable legacy records are
  preserved for repair. Missing or inconsistent indexed records raise errors.
- Persisted receipt identity and phase are checked before constructing an
  executable Agent. The live runtime still performs authoritative admission;
  existing dispatch-conflict repair remains available.

Publication and route caches are bounded and participate in the same runtime
plaintext cleanup as the message/configuration caches. Cache expiry is fixed,
not extended by hits. No final delivery acknowledgement is inferred from a
cached projection.

## Verification

Local regressions cover cache expiry/invalidation, recovery coalescing, receipt
identity, collaboration recovery, reputation and Link protocol behavior. Device
tests use uniquely named private databases: migration of 1,000 records,
malformed migration rollback, duplicate and foreign-session replies, corrupt
indexes, external snapshot writes/removal and transcript connection reuse. They do not clear user databases,
pairings, messages or model files.

Measure process CPU, GC logs, SQLite file descriptors and PSS on the same device
and retained dataset. Compare steady-state foreground/background samples and
check that handles do not keep growing. A restart frees already leaked handles,
so a short post-install sample alone does not prove long-duration stability.

Remaining work includes fully event-indexed team snapshot scanning, broader
real-provider/attachment recovery tests and extended thermal/power soak tests.

## S26U measurements (2026-10-11)

Galaxy S26 Ultra SM-S9480 retained its existing conversations, collaboration
tasks, pairing and model files. Version 1.4.154 (1239) was replaced in place by
1.4.155 (1240). The S20U installation was not changed.

| Metric | Before | After |
| --- | --- | --- |
| Process CPU, percent of one core | 492 / 416 / 449 | Ten-sample mean 152.06, range 84.6-223 |
| GC log entries in a 60-second window | 267 | 3 |
| Transcript database/WAL/SHM descriptors | 2,579 / 2,393 / 1 | 2 / 2 / 1 |
| All process descriptors | 5,267 | 309 |
| Total process PSS | 588,078 KiB | 351,709 KiB |
| SQLite memory reported by dumpsys | 160,551 KiB | 5,730 KiB |
| Final cold activity launch | Not captured | 427 ms (am start -W) |

Earlier post-install observation for approximately 15 minutes held transcript
descriptors at seven, rather than growing into thousands. Pool connection counts
can vary with concurrent readers. The final sample uses a newer process after
instrumentation and installation, not a controlled equal-uptime A/B trial.
CPU includes ongoing collaboration, networking and visible UI work. Temperature
and instantaneous CPU varied; these results do not establish a universal thermal
or power reduction, or eliminate the remaining history-scanning cost.

The final build passed 420 selected JVM tests across 61 suites and all six
isolated device tests. In-place installation, cold launch, foreground/background
return and basic scrolling were exercised without clearing user data. ASR/QNN
implementation was unchanged and the build's Whisper isolation check passed;
live speech/TTS, large attachment and real-provider fault matrices were not
repeated as part of this comparison.
