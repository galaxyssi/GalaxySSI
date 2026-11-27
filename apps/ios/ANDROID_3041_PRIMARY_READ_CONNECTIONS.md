# Android #3041: bounded primary read connections

Android merge: `6f2a3b1e2b580e57a8590c92e1c28a7f2d00ac9d`.
Incremental predecessor: iOS #4602 at
`78a541cf118c37f0a01187357c8818e51f4a3709`, including #4601, #4600 and #4596.
This formal main-targeting PR retains those shared ancestor commits rather than
copying patches. Its full-main scope also includes primary partition storage,
write batches, leases, periodic maintenance, checked synchronization,
recoverable allocations and bounded prepared statements.

## Production integration

The actual independent primary-body read now borrows a read-only connection
from one process-wide pool. All production stores default to that shared pool:
eight active plus idle connections total, including opening reservations and
handles being disposed. The existing shared active-reader semaphore remains
as an admission layer; idle handles no longer escape the connection bound.
Pending same-owner write-batch readback still uses its existing writer without
borrowing a reader. Frame SQL, authentication, decompression, hashes, catalog
references and encrypted namespaces are unchanged. No decoded record cache is
introduced; a cached connection can retain prepared programs and ciphertext
SQLite pages only.

Prefer an idle same-root/same-file connection; otherwise reserve capacity or
evict the oldest-returned idle entry. Active same-key reads use independent
handles. Timed admission checks cancellation and the caller's deadline policy
every 50 ms, including after opening. Factory, validation and disposal run
outside the pool condition lock. Opening/disposal reservations count until
completion, preventing capacity overshoot. Throwing actions, throwing/failed
validation and cancellation discard handles. Lease return is idempotent and
cannot return another borrow. Closing a pool wakes waiters and disposes idle
connections; an active action may finish, with disposal deferred until return.

Each borrow checks the main file device/inode using descriptor-relative
no-follow stat. Require regular main/WAL/SHM/rollback-journal members and compare
the root pathname's current directory identity with the anchored root descriptor.
Compare identity before and after opening; reject missing files, symlinks,
changed roots or a swap during open. A different regular main inode discards
the stale reader before reopening. This is not protection against arbitrary
noncooperating filesystem attackers, same-inode content mutation, or every ABA
race; cooperating physical mutation still requires the existing SH/EX lease
protocol and every decoded frame is authenticated.

After acquiring the existing physical-maintenance EX lease, drain root readers
with require-idle semantics before running maintenance. Unlink additionally
invalidates the specific partition before any sidecar/main removal. An active
matching lease refuses retirement rather than closing a live handle. Store
shutdown clears that root, deferring active disposal where needed. A memory
warning or existing runtime-plaintext-clear notification coalesces a trim onto
a dedicated utility queue; the notification callback itself performs no native
close. Trimming allows active work to finish but does not retain its handle.
These caches do not add a payload snapshot lease of their own; a live store or
independent snapshot retains the existing physical-file pinning contract.

## Scope and limits

No schema/format/key changes, corpus cap or model/provider wake is introduced.
The eight-reader budget excludes catalog and writer connections. SQLite's
existing busy timeout is unchanged; the 50 ms cancellation admission cadence
does not promise interruption of arbitrary native I/O within that time. The
pool is not FIFO-fair. Runtime trim is asynchronous, not proof of immediate
RSS reduction. No latency, speedup or energy claim is transferred from Android.

Android #3040 physical copy checkpoints and #3039 mixed-live compaction are
still separate missing storage work. The current retirement hook covers the
existing real unlink path; future physical-copy/compaction producers must use
the same reader invalidation and lease boundary before replacing files.
Header/index sharding and full #3037 parity are not claimed complete.

## Verification limits

Twenty-four synthetic Swift test methods authored and registered, not compiled
or executed. Twelve generic-pool fixtures cover active-plus-idle bounds,
single-slot eviction, same-key exclusivity, return-order LRU, throwing action/
validation/factory cleanup, require-idle retirement, active trim deferral,
callbacks outside the condition lock, invalidation while opening, post-open
cancellation, double-return isolation and waking a blocked borrower on close.
Twelve SQLite/filesystem fixtures cover handle/program reuse, changed/missing/
symlinked main files, sidecar symlinks, replaced roots, a swap while opening,
action failure, active retirement refusal, notification-driven asynchronous
trim, root clear during an active action, actual authenticated primary reads
with subsequent frame corruption, and actual retirement before unlink.
The full-main scope contains 94 authored Swift methods, not 94 passing tests.

The source guard pins the predecessor and permits only declared production
read/retire/owner-clear hooks, fixture injection and project registration.
Existing statement, allocation, durability and primary guards keep their
assertions via a checked normalization hook. Source checks cover these five
guards and their JavaScript syntax, iOS project structure, changed-source/
document literal-Han placement and diff whitespace. No Swift compilation,
typecheck, native SQLite/filesystem/concurrency/XCTest execution, process-death
or device evidence, CI watching, IPA, approval or merge. No all-repository
check pass or complete Android-to-iOS backlog completion is implied.
