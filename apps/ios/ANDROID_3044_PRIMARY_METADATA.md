# Android #3044: primary record integrity headers

Android merge: `f66030ecb376b66192dc05d8e7dbee836438616e`.
Incremental predecessor: iOS #4605 at
`ea967c52114fdd6071a0bf5517146babcfd3ebb8`, including #4604, #4603,
#4602, #4601, #4600 and #4596. This formal main-targeting PR retains those
shared ancestor commits; its full-main review includes physical primary storage,
batches/leases, periodic maintenance, checked durability, allocation recovery,
statement/reader reuse, mixed-live compaction and durable copy checkpoints.

## Actual iOS gap and adaptation

iOS already stores the complete encoded record, including its descriptive fields,
in encrypted primary frames; its central record payload was a one-byte marker,
not Android's inline per-record header. This increment adds the missing compact
independent authenticated header/pointer and index binding rather than claiming
that an already-physical full record has just moved out of the catalog.

Real new writes now create an encrypted integrity header containing version,
item HMAC, source HMAC, updated timestamp and complete encoded-body SHA-256.
The row cipher uses a separate item-bound header purpose. Keep only its
69-byte khp1: checksum pointer in the catalog record payload. Write encrypted
header bytes into the immutable entry's physical headers table in the same
transaction as its body frames. Include header bytes in partition accounting.
The authenticated primary reference binds that header checksum and uses version
2; legacy version-1 references remain accepted only without a header checksum.
Older reference readers reject version 2 instead of silently ignoring its
metadata constraints. A missing/malformed/mismatched pointer fails closed.

Header-only resolution uses the caller's actual catalog handle and bounded
pooled reader, or its owned pending writer for uncommitted batch readback.
It does not read body frames. Real ordinary record decoding also resolves the
header, authenticates/decrypts it, compares its item/source/time/body identity,
and checks source_hash/updated_at on the same catalog snapshot. The body hash
comparison uses the authenticated primary reference; ordinary body reading
already verifies its complete hash. There is no extra full-body hash scan on
reads. A record's central index fields can no longer silently drift from its
authenticated new-format header. Source directory/preview APIs are not claimed
to have become physically sharded by this change.

## Physical format and legacy behavior

New physical partitions use schema 2 with frames and headers tables. Existing
iOS schema 0, and compatible schema 1, remain read-only readable without a DDL
rewrite. A writable open upgrades these files transactionally to schema 2 under
the checked primary durability policy, before applying the existing main/WAL/SHM
file protection attributes. Reject unknown physical versions above 2. Header
selection is capped at 4,097 bytes and accepted encrypted headers at 4 KiB;
all writes require an active physical transaction. The full logical record
continues using the existing body codec and encryption.

Untouched inline records and historical headerless primary entries remain
readable. Existing legacy-body migration can still produce headerless version-1
entries without changing logical identity. No identity-preserving background
rewrite of every historical header is added. This uses the existing iOS catalog
schema rather than assigning Android's catalog version 17 to an unrelated format.
The old reference formats, secret accounts and encrypted namespace remain intact.

## Relocation and recovery

Small-record compaction preserves the exact encrypted header, verifies the
destination copy against its authenticated checksum, and includes its bytes
before physical flush/catalog publication. Header copying uses the existing
EX lease and private reader path, never the public SH-acquiring resolver.
The catalog pointer therefore remains unchanged across physical relocation.

Checkpointed large records preserve header identity in their target reference.
After independent frame verification completes, copy and verify the header
inside a destination transaction, check/add metadata bytes exactly once, flush
the destination, and only then allow reference publication and job removal.
A physical header commit followed by catalog rollback can replay the entry's
header row idempotently; its catalog byte counter still reflects the old
checkpoint until successful publication. Retain exact-reference CAS, job
ownership, snapshot exclusion, cached-reader retirement and allocation recovery.
Logical items, source revisions and vector revision identity do not change.

## Verification limits

Fifteen synthetic Swift methods authored and registered, not compiled/executed:
pointer grammar/bounds; header-only access with corrupt body frames; pending
batch readback without an independent reader slot; legacy schema-zero read and
writable upgrade; future-version rejection; missing/corrupt/oversized headers;
pointer mismatch; small relocation identity; checkpointed header commit before
failed catalog publication with idempotent replay/accounting; corrupt source
header rejection; catalog snapshot identity; header/frame staging failure;
legacy inline compatibility; real catalog pointers/index-tamper rejection; and
actual source/vector revision preservation across maintenance/reopen.
Injected throws/object reopenings are not process-death or reboot evidence.

The full-main scope contains 142 authored Swift methods, not 142 passing tests.
The source guard pins the predecessor and reverses only declared header,
reference-format, physical-schema, accounting, real database read/write and
project hooks. All seven older copy/compaction/reader/statement/allocation/
durability/primary guards retain their assertions through a checked normalization
hook. Source checks cover eight guards and their JavaScript syntax, iOS project
structure, changed-source/document literal-Han placement and diff whitespace.
No Swift compilation/typecheck, native SQLite/filesystem/concurrency/XCTest,
device/process-death/reboot/power-loss acceptance, full npm check, CI watching,
IPA, author approval or merge.

Keyed central indexes, source directory/group headers, derived previews, FTS and
vector-control metadata remain centralized. Unknown orphan inventory, exact
uncounted dead-byte accounting, long-cycle OS scheduling and complete Android
parity remain unfinished. No Android timings/energy results, hundred-million-
record acceptance, hard latency/RSS bound or complete backlog claim is made.
