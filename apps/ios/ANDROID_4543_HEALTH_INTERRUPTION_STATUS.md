# Android #4543: unexecuted Health reply boundary

Reference: Android #4543, merged as `2a8bb348cea9c9f2e3724951623a62f393ca2e3a`.

This is a partial port, not completion of Android #4543.

## Implemented

- The existing approved Health discussion reply commit path classifies the reserved
  recovery marker and JSON ActionPlan `actions` arrays using the existing plan JSON
  extractor. Classification does not validate or execute a plan.
- A bounded decoded control reply is retained exactly in the encrypted Health turn,
  under the existing owner, thread, turn, destination, consent and revision checks.
  It is not saved as an answer. No full HTTP envelope is claimed to be retained.
- An associated dispatched research job becomes interrupted, not completed. No
  checkpoint or assessment is invented, and the same research trigger is not replayed.
- Exact duplicate receipt commits are idempotent while approval remains current;
  conflicting replies and further scoped reads/tool mutations are rejected.
- Current and archived discussion views display a localized interruption message.
  Legacy answer fields containing the recognized control shape are also withheld
  without deleting their original bytes. These fields are excluded from subsequent
  discussion prompts and reusable research-source history.
- Native fixture sources cover encryption/reopen, exact binding, duplicate and
  conflicting receipts, no completion/replay, legacy display filtering, and
  permission/expiry/size limits. They were not executed on Windows.

## Still required

- Full model-driven Health Agent submission, with the persisted exact grant and
  provider/model snapshot driving initial planning and the native action loop.
- Grant-scoped initial and continuation planning, no global memory/screen or
  collaboration disclosure, and original conversation/turn reply restoration.
- Full model-driven Agent task recovery and native end-to-end acceptance.
- Broader malformed/other control envelopes and oversized response receipt handling.
  Existing response parser and size limits still reject these rather than retaining
  an HTTP receipt; they are not silently retried by this change.

No native compilation, XCTest execution, network/device validation or IPA build
is represented by source-level checks.

## Durable final-receipt recovery follow-up

The explicitly approved cloud discussion path now persists its exact approval,
original optional Agent conversation binding, start time and execution state in
the encrypted Health turn, atomically with creation of the question. Approval
serialization includes opaque history/question continuation tokens; decoding must
not generate new tokens. Only the 32-byte credential digest is retained, never an
API credential. The provider/model configuration and health disclosure scopes are
preserved exactly rather than reconstructed from the current settings.

Before the initial network request, `prepared` advances once to `dispatched`.
After any scoped-read rounds finish, the bounded final HTTP response bytes are
committed as `received` before local parsing. The exact original approval is
required for both transitions. Identical receipt persistence is idempotent;
changed receipts or scopes are rejected.

On reopening a discussion, a received final reply can be applied locally to its
original turn only after the existing live consent/revision checks and the view's
exact current provider/model/credential and blocked-destination checks pass. The
recovery method performs no network request. Answer, draft, questions or plan and
the `applied` marker are persisted in one Health archive write. Plans remain
unadopted and clarification drafts remain subject to user review. Cancelled
executions cannot apply late replies. Prepared/dispatched jobs without a final
receipt become interrupted instead of replaying an uncertain request.

Live and completed processing duration use the persisted start/receipt times,
with localized English/Chinese labels in current and archived discussions.
Six additional native fixture source methods cover exact encrypted reopen,
opaque cursor round trips, receipt conflicts, cancellation, scope/binding changes,
expiry/revocation/size limits, and recovered control-content quarantine. These
fixture sources have not been executed on Windows.

The final-receipt layer alone is **not** the full Agent task integration requested
by Android #4543. Full scoped planner/run recovery, streaming/intermediate tool-round
checkpoints and restoration after approval expiry remain outstanding. No request
is automatically replayed or granted a longer disclosure lifetime by this work.

Source checks: `node apps/ios/tools/check-health-discussion-recovery-scope.cjs`,
`npm run check:ios`, Swift grammar parsing and `git diff --check`. The source-scope
checker also protects the unchanged HTTP/scoped-read transport, coordinator and
standard task supervisor, and limits shared history/question changes to Codable
conformance and preserving the existing question cursor token during decoding.

## Standard task supervisor integration follow-up

Explicit cloud discussion submission and local final-receipt restoration now enter
the existing `AgentTaskSupervisor` foreground read/reasoning lane. The runtime
uses the supervisor's normal queue, execution handle, heartbeat, cancellation,
pause/block, resume and completion transitions. It does not fork those reducers.
Completion requires the original encrypted Health turn to have committed its
`applied` marker; a quarantined control response or an uncertain dispatch is
blocked rather than reported as success. A committed reply with interrupted task
bookkeeping can reconcile its task status without applying the reply again.

The task workspace uses an owner-authenticated AES-GCM file separate from both
the Health archive and ordinary task workspaces. It has complete file protection
and its production directory is excluded from OS backup. The shared file store
only gains an optional read hook (matching its existing write hook); defaults,
revision checks, per-file locks, bounded serialization and publication semantics
remain unchanged. Wrong-owner or missing-key reads cannot overwrite an existing
file with a fresh empty workspace. No private question, response, API key or
approval payload is copied into workspace goals, results or event messages, and
the supervisor receives no global memory observer.

A shared live runtime per owner/storage path prevents two views from starting
the same executor. Recovery waits for a previous execution handle to finish
before resuming. Navigation interrupts the child task without inventing a durable
user cancellation. Explicit cancellation is also recorded in the private task
workspace, so a cancellation surviving a failed/interrupted Health status write
still fences local final-receipt application on reopening. Legacy final receipts
without a workspace migrate through a local-only supervised task, never an
initial request replay.

Task admission failures settle the disclosure ticket as failed. Ticket finalization
also runs after the execution handle joins when cancellation occurred before the
queued operation started, rather than depending on the network block's defer.

Nine further native fixture source methods cover real supervisor submission,
single-executor admission, interrupted dispatch, legacy receipt migration,
durable cancellation, post-commit bookkeeping recovery, quarantined controls,
cross-owner authenticated encryption and missing-key preservation. They have
not been run on Windows. Grammar, project structure and source-scope checks are
not a substitute for native compilation or runtime/device acceptance.

Still outstanding for Android #4543: the full model-driven Agent action loop,
grant-scoped initial and continuation planning, intermediate tool/stream
checkpoints and original Agent transcript task projection. This private task
integration does not claim those are complete, does not automatically execute
received ActionPlan JSON, and does not extend or renew the approved disclosure
lifetime.
