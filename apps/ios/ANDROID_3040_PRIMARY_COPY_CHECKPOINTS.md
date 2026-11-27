# Android #3040: durable large-record copy checkpoints

Android merge: `2e0b5bc3c6b2c6b8eed2ea595b5fd4c0948e2d0d`.
Incremental predecessor: iOS #4604 at
`a51312cd07ff03dab56340d8493802d789cffc8b`, including #4603, #4602,
#4601, #4600 and #4596. The formal PR targets main with these shared ancestors;
its full-main scope includes the physical primary store, batches/leases,
periodic maintenance, checked durability, recoverable allocations, bounded
statements/read connections and mixed-live compaction, not only this increment.

## Prepared-source integration follow-up

The branch now merges updated #4604 at `7daa20adb`, including updated #4602,
#4596 and the #4625/#4623/#4621/#4619/#4616 source preparation, streamed
observation/import, checked failures, committed read views and timing ancestry.
These unmerged prerequisites are part of the complete main diff, not newly
delivered #3040 features. This updates the existing formal PR without changing
its main base, waiting for parent merges or creating a duplicate.

Keep the new targeted source physical batch and generation/lifecycle fences,
the owned committed-view teardown and the existing exact-reference copy CAS.
A pure copy/checkpoint/verification publication does not mutate logical source
generations or observations, so already prepared source content remains usable.
An intervening targeted replacement/deletion changes the authoritative reference;
resume removes the obsolete copy job and retires its destination rather than
publishing the old body. User writes do not unlink files still retained by an
open snapshot or pending job. A failed targeted write rolls back its references
and outbox without changing the exact durable copy checkpoint.

Actual candidate views keep the physical retention lease while validation is
in progress. EX copy maintenance defers rather than advancing prefixes or
reclaiming files under those views. Once they close, normal copy/verification
and retirement can resume. Legacy inline-body migration's conservative source
generation conflict behavior is unchanged; not all physical operations are
claimed to preserve a prepared task's generation.

Five additional synthetic XCTest methods cover preparation across paged copy
and verification, successful replacement invalidating a partial copy, complete
source deletion without resurrection, rollback retaining an exact checkpoint,
and actual candidate view deferral with an unchanged prefix. They exercise the
real database/source APIs, not only low-level synthetic raw payload writers.
The full storage scope has 229 authored methods (206 inherited, 18 original
copy/state and these five), none compiled or executed. These are not device,
process-death, performance or capacity results.

The copy guard compares complete retained production/test/project content
against pinned updated #4604. Older compaction and reader/cache guards retain
their exact full-file comparisons through declared copy-hook normalization.
All branch ancestry and validation limits must remain visible in PR review;
static checks do not establish native behavior.

## Authenticated durable state

Records above 16 frames register a dedicated sealed destination and one copy
job; smaller records retain the bounded single-step fast path. The job stores
the exact original encrypted reference, item/source/destination IDs and an
encrypted versioned checkpoint. Its purpose binds the actual encrypted namespace,
item, source, destination and SHA-256 of the exact original reference. State
contains only the new entry ID, copied/verified cursors, exact decoded-prefix
byte counts, ciphertext byte accounting and separate frame hash chains, never
a plaintext body or serialized crypto-library internals. Validate every decoded
state and bound original/checkpoint selection and decoding sizes.

Use CryptoKit SHA-256 for both chains: previous digest bytes, eight-byte
big-endian ordinal and exact compressed frame bytes. Eight bytes deliberately
preserve the existing iOS Int64 ordinal space; this private iOS checkpoint is
not Android's four-byte-ordinal storage format. Ordinary frame/reference formats,
full-body SHA-256 fields, item IDs, logical revisions and index state are unchanged.
The additive copy table does not change the existing catalog user_version.

Register both partitions and declare SQL foreign keys, but do not depend only
on foreign-key enforcement. Explicitly protect source and destination in
allocation admission, compaction retirement and the real unlink loop. Validate
the active source, sealed single-record destination and prior byte accounting
on every resume. A corrupt ownership/state relationship fails closed.

## Bounded copy and verification

Copy at most 16 frames per page from a keyset query with one extra row for final
tail rejection. Authenticate each source frame, require contiguous ordinals and
exact expected frame lengths, decode it within existing bounds and re-encrypt
the compressed bytes with destination-bound AAD. Commit destination frames with
the existing checked WAL/EXTRA policy before publishing the encrypted catalog
checkpoint. On replay, delete only that entry's physical tail at or beyond its
durable copied cursor, then rewrite the interrupted page. A physical commit
followed by catalog rollback cannot create a visible partial record.

After copying, independently authenticate/decode at most 16 destination frames
per page and persist the verification cursor. Final publication requires exact
prefix counts, no extra tail and identical source/destination compressed-frame
chains. This proves equivalence of the authenticated encoded frames; it does
not persist a CryptoKit full-body SHA context or perform a new whole-body SHA
scan before large-copy publication. The original full-body hash is retained
unchanged and ordinary reads still enforce it before returning a body. An
already-invalid authenticated source/hash combination is not repaired by copy.
The small-record path retains its existing complete streaming hash validation.
No new guarantee against arbitrary noncooperating writes after a prefix was
verified is claimed; cooperating mutations still obey the file lease protocol.

Before each resume, authenticate the current reference and compare its exact
sealed original. A user replacement or deletion wins: clear the job and retire
the unreferenced unpublished destination instead of reviving an old item. Final
publication uses item/source/exact-reference compare-and-swap and requires
exactly one affected row, then removes the expected checkpoint in the same
catalog transaction. The small-record path also gains exact-reference CAS.
The existing dirty queue finishes/retire-unlinks a source only after its final
live reference and copy job disappear.

## Cooperative yield versus cancellation

The existing monotonic storage budget now distinguishes a valid exhausted
deadline from invalid clocks and hard task cancellation. A typed cooperative
yield after completed copy/verify frames returns that valid prefix. Once the
advance step succeeds, physical flush and catalog commit may finish that
checkpoint despite the expired time budget, while rechecking hard cancellation
and non-budget policy errors. Small-record relocation finishes its bounded
record before yielding; completed prior records can commit when the next
record's admission yields. A failure before any completed work still throws.
Hard cancellation, authentication failure or I/O failure rolls back the page.
This does not override BG task expiration cancellation or promise a hard
deadline for native I/O/commit. Periodic OS grants and retries remain required.

## Verification limits

Eighteen synthetic Swift methods authored and registered, not compiled/executed:
six state/budget/chain fixtures and twelve actual store fixtures. They cover
dedicated ownership, 16-frame copy and independent verify pages across reopen,
three-frame cooperative prefix commit, hard current-page rollback, durable
unpublished-tail replay, intervening replacement/deletion, checkpoint/original/
destination-binding corruption, destination frame corruption/tails, stale CAS,
copy-retirement refusal and snapshot deferral. The prior compaction cancellation
fixture now registers its paged job first; its legacy queue fixture adopts the
new Boolean relocation result. Their original assertions remain intact.
Object reopenings and injected failures are not real process-death evidence.

The full-main scope contains 127 authored Swift methods, not 127 passing tests.
The source guard pins the predecessor and limits changes to declared copy,
cooperative-budget, CAS, owner-protection and fixture/project hooks. The six
older reader/statement/allocation/durability/compaction/primary scope guards
retain their assertions through a checked normalization hook. Source checks
cover seven guards and their JavaScript syntax, iOS project structure, changed-
source/document literal-Han placement and diff whitespace. No Swift compilation,
typecheck, native SQLite/filesystem/concurrency/XCTest run, device/process-death/
power-loss evidence, CI watching, IPA, author approval or merge.

No full npm check pass, Android timing/energy result, hundred-million-record
acceptance, hard latency/RSS bound or entire backlog completion is claimed.
Unknown legacy orphan inventory, exact uncounted dead-byte accounting and
header/FTS/vector-control sharding remain separate unfinished work. New copy
destination allocations reuse the durable intent journal; no unknown files are
guessed as owned. Cached reader and independent snapshot leases remain active.
