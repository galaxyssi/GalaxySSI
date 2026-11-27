# Unplanned Native Dispatch Envelope

Android #3007 reference: `65655f0c79c6ab04121150229a65b089180f82f2`,
`MobileNativeAgentExecution.kt`: save checkpoint, staged audits and final input before
journaled dispatch. This increment starts from main `c6bad3465`.

## Actual Gap And Connection

The sequential iOS path previously journaled planned actions and required a plan for
connectors, but dispatched plan-less native actions directly. Every new sequential
dispatch now requires checkpoint persistence and the existing durable journal claim.
Already observed receipts remain reusable before rerouting. There is no direct
unplanned execution branch left in `executeLocalNativeAction`.

For an otherwise unplanned task, a minimal execution envelope retains the exact
selected action and remaining pending actions in order. It neither reruns the planner
nor deduplicates, aliases, routes or rewrites tools. The remaining queue is not a consent
grant: existing per-action confirmation, read-only, safety and OS permission paths
still precede their execution. Existing active plans retain their identity and mode;
plan-only, missing plan bodies with existing summaries, pending planning, wrong
task/session/turn/contact, ambiguous IDs and previously dispatched legacy actions
cannot acquire a fresh envelope. The checkpoint helper also rechecks execution pause,
plan-only settings and task cancellation before its owned state commit.

The task-state commit precedes the journal claim, which precedes the external action.
Later queued actions share the envelope but use independent checkpoint/node identities.
A restored pending claim returns unknown rather than re-executing; a saved observation
is returned without another operation. Failure to commit the task prevents dispatch.

These are separate task/journal commits, not one atomic multi-store transaction. No
cross-process CAS, power-loss/fsync or exactly-once external effect guarantee is added.
Legacy operations dispatched before this feature cannot acquire retrospective proof.
Capture uses its previously separate approved-capture path. Supervised browser and cloud
model-loop persistence, generic timeout/deferred discovery and full audit batching
remain separate work; this does not complete #3007 or the overall Android backlog.

## Verification Boundary

The focused source guard restores only three exact service hooks to compare the entire
remaining service with the pinned baseline, including capture, browser, confirmation,
fallback, lifecycle and result paths. Journal, effect, Store and executor kernels are
frozen. The prior capture guard uses this explicit three-hook normalizer without losing
any capture assertions. Eight synthetic XCTest methods are authored but not executed.

Independent capture-queue follow-up #4673 exports a legacy-envelope normalizer. When
that follow-up is present, the unplanned-dispatch guard uses it only for the capture
helper before comparing with this PR's baseline. Without the follow-up, comparison
remains exact. The capture guard separately freezes permission/checkpoint/ticket logic
outside its declared envelope block; no journal, Store or effect assertion is removed.

Independent browser-view lifetime PR #4674 exports coordinator-hook and optional-task-
lease normalizers. When available, only those declared browser deltas are normalized
before this PR's exact baseline comparison. Without #4674, the original comparison is
unchanged. No browser production code is included in this PR, and the browser guard
separately checks view admission, save-before-load and unverified interruption behavior.

Only JS/source/project checks and whitespace checks are run. No Swift/native build,
XCTest execution, device/restart/fault acceptance, full check, CI monitoring or IPA.
