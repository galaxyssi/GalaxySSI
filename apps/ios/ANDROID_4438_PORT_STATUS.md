# Android #4438: Honor Manual Models During Desktop Recovery

Pinned Android merge: `bf8bb0b2a00930e707c333631dab86124eca0efc`.

## Dependency And Scope

Formal iOS PR with base `main`; depends on unmerged #4514 and predecessors.
Incremental base: `18af490a3bc260e0fcaae3b8c5a32f5d44e435ed`.
Full main diff is cumulative, not an independent #4438-only patch.
All eight original files have hashes and individual dispositions. No Android,
Desktop, version, native build or IPA changes are included.

## Native Changes

- Shared action-or-result manual lock check; generic fallback stops before
  candidate selection, regardless of any unavailable-target fallback flag.
  A locked action passed to the preparation helper is returned unchanged.
- Pin action locks and response language into pending provider results, and
  disable unavailable-target fallback/retry on the resolved manual timeout.
  Preserve existing Auto timeout scheduling and failover conditions.
- Persist the request's manual lock for every ordinary paired Desktop endpoint,
  not just Codex. Old locked Codex seeds and explicit direct Desktop contact
  destinations are recognized without consulting mutable current model settings.
- Manual requests cannot automatically replay after Codex silence, even on the
  same model. Enforce the gate before scheduling, durable insertion, restored
  dispatch and final publish. A caller cannot evade the stored lock by passing
  an unlocked seed. Old queued manual recovery is retired without new execution;
  fail its matching active UI task, release its exact local slot and show the
  no-switch message without reopening a completed/cancelled task.
- Passive status/result recovery queries are retained; there is no new remote
  cancellation or claim that an already-dispatched old task can be undone.
- Exact bilingual connection feedback states that waiting stopped without
  switching models. Scope terminal timeout feedback to the pinned binding;
  preserve success, cancellation, non-timeout errors and foreign identities.
  Localize display/history projection, never authenticated payload or receipt
  bytes. A completed task whose result is unavailable retains that distinct error.
- Auto Codex budget, original invocation restoration, same-Desktop restrictions,
  trust/session/privacy/capability checks and receipt/identity logic are retained.

## Verification Boundary

Scoped source checks verify the eight original hashes, exact bilingual XML
reproduction, helper/provider/timeout wiring, all durable replay gates, unmodified
Auto budget and transport/receipt modules, wire-preserving projection and
predecessor source contracts. Added Swift fixture sources cover lock precedence,
preserved inputs, false fallback grant, provider pinning, reopened/legacy manual
queue rejection including stripped seeds, and bilingual binding-scoped feedback.
The positive durable retry fixture is now explicitly Auto. Fixtures are not run.

Seven changed/new Swift files parse without grammar diagnostics. The two large
existing files GalaxySSIServices.swift and AgentRunPolicyTests.swift retain the
same grammar parser diagnostic counts as the pinned base (93 and 4 after
directive stripping); these are parser diagnostics, not a Swift compiler result.
Do not report a clean whole-project Swift parse or compilation from that audit.

Project structure/whitespace/source checks are not Swift type checking, native
compilation, XCTest, actual dispatch counts, paired Desktop timeout/relaunch,
UI/VoiceOver, signature or device acceptance. Windows does not provide Xcode.
Android's reported runtime tests are reference material, not iOS evidence.
