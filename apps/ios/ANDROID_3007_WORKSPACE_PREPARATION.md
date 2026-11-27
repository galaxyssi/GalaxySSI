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
- A per-executor lock owns both restore and every workspace operation. Restore
  happens once. An invocation arriving before queued preparation may restore
  synchronously first; the queued preparation then becomes a no-op. An invocation
  arriving during restoration waits for it instead of mutating empty state.
- Read/modify/save operations share that lock, so concurrent registries using
  the same executor cannot overwrite one another's in-memory workspace snapshots.
- File format, restore sanitization, path/size/ZIP policy, exports, file algorithms,
  registry permissions/consents, effect ownership and persistence are unchanged.

## Verification limits

The dedicated source guard pins the exact initializer/locking/factory delta and
compares the rest of both files to main. Four negative mutations reject altered
queue/locking/preparation behavior; an unrelated appended mutation is retained
and cannot satisfy the whole-file equality check.

Six XCTest methods are authored, not executed: eager compatibility, deferred
off-main preparation, early invocation, mutation during blocked restore,
concurrent writes through independent registries and denied invocation.
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
The existing store still reports missing/unreadable/corrupt state as an empty
snapshot and best-effort save has no success result. This change does not repair
those persistence semantics or promise crash durability. It also does not add
Android process isolation APIs to iOS. Full #3007 and broader parity remain open.
