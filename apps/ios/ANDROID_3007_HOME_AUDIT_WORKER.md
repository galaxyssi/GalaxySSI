# Home audit presentation worker

## Scope

Independent follow-up to Android #3007's background preparation of home content.
Base: `c6bad3465c673dfb2dcecb23b095185c129c7447`.

The home view previously constructed persistent default stores and read the audit
file synchronously from route, message and execution-state presentation callbacks.
It also retained the resulting array when runtime plaintext was cleared.

- A lazy utility worker performs the existing recent-12-record read.
- The existing dashboard refresh state coalesces same-owner bursts into one
  trailing refresh and rejects invalidated or replaced-owner completions.
- The published projection requires a visible, active, readable home view, a
  nonblank current profile fingerprint and no runtime-plaintext-clear boundary.
- Disappearance and runtime clearing invalidate tokens and clear presentation
  records. A keyed task refreshes on foreground, readability and profile changes.
- Existing message, execution, route and session refresh callbacks remain wired.
  No execution, audit append, approval, permission or delivery policy is changed.

## Checks

`node apps/ios/tools/check-home-audit-worker-scope.cjs` verifies exact approved
source deltas, worker placement, projection/lifecycle hooks, mutation rejection,
unchanged storage/execution files and eight Xcode registration entries.

Five XCTest methods are authored for deferred worker reads, burst coalescing,
old-owner rejection, in-flight invalidation and blank identity clearing.
They are not executed. No Swift/native build, XCTest, full repository check,
simulator/device run, CI inspection, IPA or private evidence is included.

Local integration with the twelve pending branches for #4664 and #4671-#4681
had no textual or Xcode registration conflict. All eighteen focused source
guards, `npm run check:ios` and `git diff --check` passed on that combined tree.
The catalog PR's source guard recognizes only the exact independent audit UI
hooks via this change's exported normalizer; no original assertions are removed.
This does not merge or approve any remote PR or establish native acceptance.

## Limits

This is a presentation worker, not a new audit persistence or authorization
implementation. The underlying store still returns a global recent-record list,
not a profile-partitioned or conversation-filtered list. Identity checks prevent
stale UI completions; they do not add ownership metadata to historical records.
The unchanged file store cannot distinguish a failed read from an empty list.

Already enqueued synchronous reads are not forcibly interrupted or securely
erased. Same-owner bursts are coalesced; repeated owner changes do not prove a
globally bounded work queue. Other screen-context/store work and native runtime
initialization remain outside this change. No measured latency or full Android
parity claim is made.
