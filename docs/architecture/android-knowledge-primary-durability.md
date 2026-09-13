# Primary body commit durability

Android 1.1.117 requires SQLite synchronous EXTRA on every primary-body writer
and allocation-journal connection. The main catalog remains WAL/FULL, and
read-only partition connections retain their existing configuration.

## Why FULL was insufficient as a general guarantee

With DELETE journaling, a committed rollback-journal unlink can require a parent
directory sync to survive power loss. SQLite documents that FULL alone is not
necessarily durable across power loss in this mode; EXTRA includes that
directory synchronization. This is different from WAL/FULL, which remains the
catalog policy. See [SQLite synchronous](https://www.sqlite.org/pragma.html#pragma_synchronous).

The former primary writer could report its commit complete before that
directory operation was known durable. A subsequent durable catalog commit
could then reference a body transaction that a filesystem recovered differently.
EXTRA closes this policy-level ordering gap using the bundled SQLite driver's
own commit implementation rather than a separately ordered callback.

## Effective policy, not just configuration text

`KnowledgePrimaryDurability.configureWriter` checks that the connection uses
DELETE journaling, applies EXTRA before any writer transaction and reads back
the effective synchronous value of 3. Unsupported or unexpected configuration
fails before body publication. Existing body files in a different journal mode
are rejected, not silently converted while another reader might be attached.

The policy applies to initial body database creation, reopening writers,
rotation/early flush, normal append, migration and compaction/copy. Those paths
share the primary writer factory. Allocation-intent insertion and acknowledgement
connections use the same check; allocation creation retains its explicit parent
sync so the journal's own new filename is also published durably.

No schema, key, ciphertext or serialized-record format changes. Existing memory
does not require an eager rewrite. The main catalog commits only after
`prepareCommit` has completed its body commits. Failed configuration or commit
continues through the existing transaction rollback and allocation recovery.

## Acceptance scope

Device tests query the effective native pragmas and inspect actual live writer
connections, including reopened and rotated writers and the allocation journal.
They also verify rejection of WAL bodies without losing the old committed record.
Existing real-process-death and retained-corpus suites remain applicable.

The reboot sequence leaves a real multi-frame copy checkpoint with 16 frames
copied, records the OS boot identity, reboots only SM-T575, requires a changed
boot identity and readable credential storage, and then resumes that same
checkpoint. A graceful OS reboot and process-kill experiments are not physical
power-cut or filesystem-fault-injection tests. Durability still depends on the
VFS, OS and storage honoring synchronization, as described in
[SQLite's hardware assumptions](https://www.sqlite.org/atomiccommit.html#hardware_assumptions).

Metadata/FTS partitioning, 100-million-record acceptance, sub-200 ms complete
retrieval and the wider Run Kernel/tracing/DAG goals remain unfinished.

## SM-T575 acceptance, 2026-09-13

Android 1.1.117 (1003) was installed without uninstalling or resetting the App.
The seven native-configuration cases passed, followed by 14 allocation, 55
primary-reader/rotation/snapshot and 97 source/backup/search regression cases.
Seven copy-process deaths and four allocation-process deaths recovered with
their durable boundary markers verified. The initial JUnit invocation did not
run production cases: one expression-bodied test inferred a non-void return.
Adding explicit Unit fixed the test signature; the initial failure is retained.

A real OS reboot changed the boot identity and preserved the exact checkpoint
with 16 copied frames. Reopening the fixture and loading that checkpoint took
324.113 ms inside the verification test, then copy/verification/publication
completed. This excludes OS boot and instrumentation startup. The host waited
48.009 seconds for the rebooted device's credential storage to be accessible.

The retained 10,001 complete records had the same full-record digest as before
the upgrade. Full verification took 196.560 seconds, versus 107.806 seconds in
the prior phase; this is a slower sequential observation after reboot, not a
controlled attribution to EXTRA. There was no newly eligible compaction work.

| Isolated API | First run P95 / max (ms) | Repeat P95 / max (ms) |
| --- | --- | --- |
| Public complete-record read | 22.381 / 236.460 | 22.862 / 246.482 |
| Individually committed upsert | 112.013 / 209.661 | 107.172 / 160.624 |
| Individually committed restore | 110.704 / 126.604 | 104.735 / 111.305 |

Each run measured 100 operations of each type on the retained corpus, restoring
and reopening every probed record. Overall, 597/600 samples were within 200 ms;
three exceeded the target. No slow sample was discarded. These measurements
exclude observers, model, UI, network and maintenance contention. Full-query
latency and a universal 200 ms bound are not established by these results.
Separately, 100 new-partition short-record writes were all within 200 ms, with
P95 83.553 ms and first-partition creation 116.340 ms.

The JVM suite passed 3,836 tests with five existing skips and no failures;
all 74 Android AArch64 native libraries passed the 16 KB alignment audit.
See [raw evidence and limitations](evidence/knowledge-primary-durability-20260913/summary.json).

Reproduce on the designated test device after installing matching main/test APKs:

```powershell
tools/dev/test-knowledge-primary-durability.ps1
tools/dev/test-knowledge-primary-reboot.ps1
```

The second command reboots only the explicitly guarded SM-T575. If credential
storage remains locked, preserve the generated fixture and evidence, unlock the
device, and resume its verify phase rather than creating replacement test data.
