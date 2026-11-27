# Default workspace preparation

Independent iOS startup follow-up to Android #3007's background preparation of
native tool content. Base: `c6bad3465c673dfb2dcecb23b095185c129c7447`.

## Actual startup connection

`MessageCoordinator.start()` constructs its mandatory native runtime synchronously.
The default registry previously constructed `AgentWorkspaceNativeToolExecutor`,
which synchronously loaded and decoded the entire saved workspace state from its
initializer. That concrete persistent restore now runs on a shared serial utility
queue when the default registry creates its workspace executor.

- The native runtime and its original tool registrations are still installed
  synchronously. There is no temporarily unavailable or descriptor-only runtime.
- An explicit injected workspace executor is not replaced. The executor's default
  initializer behavior remains eager for existing/custom callers; background
  preparation is an optional queue parameter selected by the default factory.
- A per-executor lock owns both restore and every workspace operation. A successful
  restore happens once. An invocation arriving before queued preparation may restore
  synchronously first; the queued preparation then becomes a no-op. An invocation
  arriving during restoration waits for it instead of mutating empty state.
- Read/modify/save operations share that lock, so concurrent registries using
  the same executor cannot overwrite one another's in-memory workspace snapshots.
- File format, restore sanitization, path/size/ZIP policy, exports, file algorithms,
  registry permissions/consents and effect ownership are unchanged.

## Checked persistence follow-up

The default file store now implements an additive checked read/write protocol.
Only a genuine missing-file read produces an empty initial snapshot. JSON decode
and other read errors leave executor preparation incomplete; the operation returns
an I/O failure before accessing workspace state. A later explicit operation can
retry restoration after the underlying problem is repaired.

Workspace helpers stage changes under the existing executor lock. A failed
operation discards its staged changes, including implicit workspace creation.
A successful dirty operation saves once using the checked store before reporting
success. A reported save failure restores the previous in-memory snapshot and
returns an I/O error. Before an atomic write, the default file store rechecks that
an existing file is readable/decodable; a corrupt file cannot be silently replaced
even via the legacy void save wrapper. Explicit store clearing remains separate.

Legacy custom stores remain source compatible and retain their void save
semantics. Their unreported persistence failures cannot be detected or certified
by the executor. The default file store takes the checked path, not that fallback.

## Verification limits

The dedicated source guard pins the exact initializer/locking/factory delta and
compares other executor/defaults code to main. The checked file-store implementation
is pinned in full. Ten negative mutations reject altered preparation, rollback,
missing-file classification and pre-save checks; an unrelated appended mutation is retained
and cannot satisfy the whole-file equality check.

Twelve XCTest methods are authored, not executed. Six cover eager compatibility, deferred
off-main preparation, early invocation, mutation during blocked restore,
concurrent writes through independent registries and denied invocation. Six more
cover missing/reopened storage, corrupt and wrong-shaped JSON preservation,
unreadable file shape, repaired restore retry, failed-save rollback and rejection
of staged mutations from failed operations.
No Swift/native build, XCTest execution, full repository check, CI inspection,
live network/model, simulator/device run, IPA or private evidence is included.

Local integration with the fourteen pending branches (#4664 and #4671-#4683)
had no textual or Xcode registration conflict. All twenty focused source guards,
`npm run check:ios` and `git diff --check` passed on that combined tree.
The historical observation guard in #4683 recognizes only this exact independent
workspace/defaults delta through the exported normalizer. Its normalized file
projections equal main; no original assertion or storage policy is removed.
That historical guard's separately documented old whole-Services snapshot
failure is not reported as passing. No remote PR is approved or merged here.

## Remaining work

This removes one actual startup read, not all native runtime construction or
provider initialization from MainActor. First-use operations can still wait for
restoration; the lock/read has no new cancellation/deadline interruption guarantee.
No measured first-frame or latency improvement is claimed.

The lock is per executor, not a multi-executor or multi-process file transaction.
Checked writes do not provide fsync/crash durability, exact-once effects or a
cross-process compare-and-swap. Another executor/process can still change a valid
file after a checked read. Existing restore sanitization remains lossy for invalid
logical entries in otherwise decodable JSON; full semantic validation/migration is
not added. External artifact exports are not a rollback transaction with workspace
storage. No new encryption, secure erase or Android process isolation is claimed.
Full #3007 and broader parity remain open.
