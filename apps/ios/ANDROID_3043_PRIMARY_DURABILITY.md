# Android #3043: checked primary-storage synchronization

Android merge: `41495d2f6e50dd8bac810abfd1b71a581dceadc7`.
Incremental predecessor: iOS #4596 at
`97374e5882356fd28a3a251873b6c5cd7dfa6a54`.
The PR targets main, but includes that unmerged primary-partition implementation
as shared commit ancestry. Its full-main diff is not only this durability increment.

## Production changes

Previously SQLite commands requested WAL/FULL/fullfsync without inspecting the
resulting configuration. The new common writer policy requests and reads back
WAL, primary-body EXTRA (3) or catalog FULL (2), fullfsync and checkpoint_fullfsync.
Nil, read-only, in-memory, unexpected journal/sync settings, missing pragma rows
and SQLite failures are rejected. Configuration requires autocommit; readback
verification also works inside a pending transaction.

The real catalog open configures before schema/partition initialization and
closes on failure. Primary writer creation and reopen use the same policy.
Verify each physical participant immediately before commit. Verify the catalog
on namespace setup and after the existing pre-publication fault hook, before a
direct reference can be staged or a batched publication can be approved. Failed
batch preparation poisons the existing batch; existing rollback paths retain
previous committed catalog references. New physical frames may remain orphaned
after a failed catalog publication under the predecessor's documented lifecycle.

No schema, ciphertext, key, compression, namespace, frame/reference format,
rotation, reader-slot or lease changes. No new allocation journal or Android
process/reboot fixture is imported. The iOS allocation metadata remains in its
WAL catalog; Android's separate DELETE-journal allocation architecture is not
claimed implemented by this change.

## Platform distinction

iOS keeps its predecessor's WAL reader/writer contract rather than converting
existing partitions to Android's DELETE journal. SQLite documents that EXTRA and
FULL have the same WAL durability; EXTRA's additional directory sync applies to
DELETE journals. Readback of fullfsync flags verifies requested SQLite policy,
not actual VFS/hardware power-loss guarantees. See the primary
[SQLite synchronous](https://www.sqlite.org/pragma.html#pragma_synchronous) and
[fullfsync](https://www.sqlite.org/pragma.html#pragma_fullfsync) documentation.

## Verification limits

Seven synthetic Swift methods authored and registered, not compiled/executed:
primary/catalog settings, nil/in-memory rejection, read-only rejection, active
transaction boundaries, runtime downgrades and retention of the previous body
when catalog publication loses its sync policy. Two existing primary fixture
setups now configure their real catalog writers; old assertions remain unchanged.
The source guard compares complete surrounding files with the pinned predecessor
after only declared policy calls and fixture/project hooks. It also checks the
exact commit/publication call sites and retains earlier scope assertions.

Source/project checks are not SQLite execution, Swift compilation, crash/reboot,
power-cut, device, VFS or performance acceptance. No native run, CI monitoring,
IPA, approval or merge. Android #3043 platform equivalence, predecessor #3037
completion and the full Android-to-iOS backlog remain unproven.

Source verification passed: the dedicated durability and original primary-
partition guards, both guard syntax checks, iOS project structure, changed-source/
document literal-Han placement and diff whitespace. This is not a rerun of every
inherited scope guard or any native fixture.
