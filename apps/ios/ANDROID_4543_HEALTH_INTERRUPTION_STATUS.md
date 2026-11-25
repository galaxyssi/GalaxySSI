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

- Approved Health discussion submission through the standard durable Agent task,
  including a persisted exact grant and provider/model snapshot.
- Grant-scoped initial and continuation planning, no global memory/screen or
  collaboration disclosure, and original conversation/turn reply restoration.
- Standard Agent task recovery and native end-to-end acceptance.
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

This is still **not** the standard durable Agent task integration requested by
Android #4543. Full scoped planner/run recovery, streaming/intermediate tool-round
checkpoints and restoration after approval expiry remain outstanding. No request
is automatically replayed or granted a longer disclosure lifetime by this work.

Source checks: `node apps/ios/tools/check-health-discussion-recovery-scope.cjs`,
`npm run check:ios`, Swift grammar parsing and `git diff --check`. The source-scope
checker also protects the unchanged HTTP/scoped-read transport, coordinator and
standard task supervisor, and limits shared history/question changes to Codable
conformance and preserving the existing question cursor token during decoding.
