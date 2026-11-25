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

- General Agent planning/transcript integration beyond the explicitly approved
  cloud Health discussion native-tool loop described below.
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
checker also protects the unchanged base HTTP transport, coordinator and
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

At this historical layer task admission failures settled the early disclosure
ticket as failed. The shared native-loop layer below supersedes that arrangement:
it creates a ticket only immediately before HTTP dispatch, so cancelled queued
work does not create a disclosure record for a request that never started.

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

## Scoped-read round checkpoint follow-up

Explicit cloud Health discussions now retain intermediate request/response state
inside their original encrypted Health execution. Each checkpoint contains the
exact request body, bounded response, history and selected-history cursors,
question/feedback continuation cursors and remaining page budgets. It does not
contain HTTP headers or API keys. Requests are still reconstructed from the
current exact approved provider/model/credential and endpoint, not from a stored
authorization header.

The durable phases are `prepared`, `dispatched` and `received`. Dispatch intent
commits before HTTP; a received response commits before parsing the next local
read. Next-round preparation atomically records the new request body and cursor
state with exactly one page-budget decrement. The round index is bounded at 12,
the existing request body at 180,000 bytes and each response at 65,536 bytes; the
serialized checkpoint is capped at 750,000 bytes. A stale checkpoint cannot
replace a newer round or restore a spent page budget.

The existing private task runtime can now resume a definitely unsent prepared
initial request or continuation, or consume a received response and continue its
approved reads. It never resends a dispatched round without a response receipt.
Legacy executions without round checkpoints keep the previous conservative
interruption behavior. All recovery still requires current ownership, original
thread/Agent binding, unchanged consent epochs, scope/revision checks, exact
current destination and the original ten-minute approval lifetime. Explicit
cancellation remains authoritative in both stores.
Navigation cancellation during round restoration preserves a known prepared or
received checkpoint and pauses task execution; reopening can resume it again.

Structured automatic research retains the previous transport path: its mutation
and review logic is not moved into these manual-discussion checkpoints. A source
normalizer verifies the previous complete transport body byte-for-byte outside
the declared checkpoint hooks and the received-disclosure status correction.
If an HTTP response was received but its local retention is rejected, the
disclosure ledger retains `sent`, not an incorrect claim that the request failed
to reach its destination.

Eight additional native fixture source methods cover received-response reopen,
supervised initial-request recovery, resumed history calls, prepared continuation
cursor/budget preservation, uncertain-dispatch rejection, expiry/revocation/route
and stale-budget fences, received-disclosure status and blocked destinations.
They have not been executed on Windows. Source checks are
`node apps/ios/tools/check-health-discussion-rounds-scope.cjs` and the cumulative
recovery checker, project structure, Swift grammar and whitespace checks.

The round-checkpoint layer alone does not implement the full model-driven Agent
planning/action loop. Generic model/tool journal integration, streaming and
original Agent transcript projection remain separate requirements. This layer
is not a claim of completed Android #4543 parity or native/device acceptance.

## Shared model/native-tool loop follow-up

The explicit cloud discussion path now uses the existing `AgentModelToolLoop`
and `AgentNativeToolRegistry`. Initial and continuation HTTP requests execute from
a scoped `AgentModelAdapter`, including definitely unsent request restoration.
The wire body remains the approved Health request/continuation envelope with its
existing clinical-boundary instructions, rather than a global planner prompt.
No unrelated conversation, screen, installed-app, global-memory or public web
research context is added.

The private registry is constructed only from tool schemas advertised in the
approved request, intersected with the grant's exact allowed Health tool IDs.
History, selected-history, question and feedback reads use the existing scoped
record methods and commit their next request/cursor state before returning a
native success receipt. Plan drafts, question proposals and clarification answer
drafts are native calls with exact input validation and the original local/online
consent epochs. Every call checks the original session, conversation, turn,
workspace, caller and pending provider-call arguments. No default phone registry
or connector fallback is installed.

Terminal local drafts/questions commit through the existing review-only record
methods. Their actual provider response is retained first; after the local
`applied` commit, the loop closes locally without another provider request or
turning its acknowledgement into medical advice. The view does not apply the
same terminal response again. Ordinary replies keep the existing final-receipt
and control-quarantine path; unexecuted tool markup is rejected rather than
treated as a native action.

Registry replay/audit stores are explicitly in-memory and scoped to the call.
The loop has no global model journal, observer or event projection; domain
recovery remains the owner-encrypted wire-round checkpoint. Observation-history
tools and collaboration are explicitly disabled. Budgets retain the remaining
read counts, at most one tool depth, no automatic tool retries and the remaining
original approval lifetime. The cumulative request-byte and round limits still
apply across recovery, not a newly issued disclosure grant.

Disclosure tickets are now created at the actual prepared-round HTTP boundary
inside the adapter. A queued/cancelled operation that never reaches that boundary
creates no fake cloud request entry, and the initial request is not double-counted
by the view and the adapter. Received disclosure still remains `sent` when local
receipt retention fails. Navigation cancellation propagates through the shared
loop cancellation source while retaining known prepared/received checkpoints.

Seven further native fixture source methods cover catalog scope, native question
retention across OpenAI-compatible/Anthropic/Gemini wire formats, foreign-turn
rejection and bound history execution, unknown tools, control-looking prose,
navigation cancellation and tampered catalogs. The existing round recovery
fixture sources now enter the shared loop as well. These sources have not been
executed. Source checks include
`node apps/ios/tools/check-health-discussion-native-loop-scope.cjs`; the unchanged
shared loop/registry/protocol core and legacy research path are explicitly
protected outside declared routing and callback-lifetime edits.

Remaining: original Agent transcript task projection, the broader general Agent
planning/action path outside explicit cloud Health approval, generic private
model-journal integration/streaming, automated-research migration and native
build/device acceptance. No claim that all of Android #4543 or the broader
Android-to-iOS PR backlog is complete.

## Main-composer review routing follow-up

The main Agent composer now intercepts a reserved `health-care:` conversation
before screen-context publication, automatic door actions, target selection or
ordinary message submission. It opens the existing explicit Health review UI with
the question prefilled; it neither dispatches nor creates a turn before approval.
The original composer draft and attachments are not consumed by opening review.
Unreviewed attachments, missing/changed binding, invalid/paused/closed concerns,
locked data and questions outside the existing byte limit cannot enter this route.

The launch freezes owner, Agent conversation, concern, metric, private thread and
permission epoch. Its sheet revalidates those bindings and clears the in-memory
launch on background/lock, owner/session change or invalidation. Existing model,
data and scope review still occurs in the Health view before sending; a composer
question is not itself an authorization. Even a malformed reserved Health topic
or missing privacy flags cannot fall back to the ordinary send path. A matching
early coordinator guard also rejects alternate generic-send callers before target
catalog construction, mention parsing, retry dispatch or message persistence.

Three additional native fixture source methods cover fail-closed reserved topics,
exact binding/revocation, no extra turn at launch, and empty/oversized questions.
They were not executed. `check-health-composer-scope.cjs` protects early ordering
and the unchanged ordinary coordinator flow outside its single guard. All four
Health source-scope checks and the project structure check passed. Five other
changed Swift files and the isolated coordinator guard parse without grammar
errors; the full pre-existing coordinator file has 96 parser error nodes both
before and after the edit, so whole-file grammar success is not claimed. This is
not native compilation or runtime acceptance.

This increment does not yet project private Health replies and task clocks into
the original main Agent transcript, nor make unreviewed main-composer input a
fully supervised general Agent plan. Those remain explicit follow-up work.

## Original Agent output projection follow-up

The main output now renders the original encrypted Health thread directly in its
bound Agent conversation, alongside any existing legacy ordinary transcript. It
does not copy questions, answers, raw replies, checkpoints or grants into the
ordinary chat database, model history, memory or a separate presentation journal.
Rows preserve the original Health turn IDs and question bytes. Retained answers
remain plain text; plan, question and clarification-draft results remain review-only
notices. Raw control content is never shown as an assistant answer or executed.

Projection validates the execution owner, original Agent binding, concern, thread,
turn, question, destination and private workspace key before using its task clock.
Only an actual tracked noncancelled handle plus a matching live workspace and
unexpired original approval can show a running clock. A stale persisted `RUNNING`
record alone cannot keep it spinning. The original final receipt time freezes a
completed duration. Interruption now records an optional `stoppedAt` atomically in
the encrypted Health execution, including control-reply quarantine; repeated
interruption does not advance it. Older snapshots decode without inventing a stop
time and use a conservative fixed fallback rather than a new running timer.

The view clears its private row cache on background, lock, runtime plaintext clear,
owner/session changes and scope invalidation. It reloads only the current bound
thread and reads the separate private task workspace once per refresh rather than
once per historical row. Reopening the existing Health review from the output uses
the existing grant-checked supervisor recovery, not an implicit network replay in
the transcript renderer. No route or disclosure authority is added by presentation.

The shared scroll view observes an identity/revision/has-rows preference containing
no private text. New Health rows can follow the tail even with no ordinary chat
messages, but cannot steal position during dragging/older-message reading. Its
existing epoch and current-conversation/foreground checks fence deferred movement;
the latest button also works for a Health-only transcript. Ordinary scroll behavior
is preserved outside the explicit extra-source hooks.

Nine new native fixture source methods cover binding/isolation, stale workspace
versus live handle, deadlines, original receipt duration after reopen, control
quarantine and review-only results, mismatched execution, durable idempotent stop
time, cancellation, legacy nonrunning turns and old-schema decoding. They have
not been executed. Source checks are not native compilation, rendered UI inspection,
XCTest, API/device acceptance or an IPA build.

This direct bound-thread projection supersedes the earlier projection gap for new
explicit cloud Health turns. Migration/recovery of older ordinary connector receipt
records, full general Agent planning beyond reviewed cloud requests, generic
private model journaling/streaming, automatic research migration and native/device
acceptance remain outstanding. The full Android PR and backlog are not complete.

## Retained legacy receipt presentation follow-up

Already-saved ordinary main-chat Health control receipts can now show a localized
interruption notice and a fixed original receipt duration rather than disappearing
entirely from the output. This is a read-only projection, not a new task, reply,
result, execution claim or migration that consumes a connector outbox. The saved
question and raw receipt remain byte-for-byte unchanged and are never resent.

The currently bound private/tracking-paused Health conversation must still match
its encrypted concern/thread. Candidate source and final receipt must both be
present and unchanged in a strict newest-500 database window for that exact Agent
conversation. Source UUID, source turn, original conversation, main-Agent contact,
nonmerged provenance, ordinary request kind, final delivery state, bounded control
shape and sane timestamps must match. A source omitted by the window is not
assumed to have been checked. Any query/decryption/metadata failure rejects the
entire window, rather than interpreting skipped corrupt rows as absent answers.

The complete newer window also rejects a candidate with a normal final answer.
Any existing local task/workspace, committed turn, remote/voice runtime context or
modern encrypted Health turn excludes this legacy classification. Stream rows
need a persisted final-receipt trace; partial/interim/milestone/failed rows are not
terminal evidence. Markers keep only stable IDs and receipt times, no question,
raw control text, rich payload or tool arguments. One marker is shown per original
turn, with the same private row clearing and scroll ownership as modern rows.

The ordinary transcript's existing control filter is extended only for a valid
private Health topic to withhold bare ActionPlan `actions` shapes too. Non-Health
rendering, response buses, waiting-state reducers, task/workspace transitions and
connector recovery/consumption are unchanged. The database gains only a bounded
throwing read; there is no schema change or history rewrite.

Ten new native fixture source methods cover stable identity/duration and unchanged
inputs, invalid privacy/topic/source/provenance, partial and final streams, existing
recovery contexts and normal answers, byte/time limits, rich-only controls, strict
encrypted database reopen, later-answer visibility and window overflow. These
sources have not been executed. The legacy scope checker protects complete shared
files outside the declared read/presentation hooks; it does not prove native build,
rendered UI, device or network acceptance.

Still outstanding: raw connector outbox receipts not yet saved as a verifiable
ordinary final message, alternate/non-UUID legacy source identities, receipts whose
original question falls outside the bounded window, and full general planning,
private model journaling/streaming, automatic research and native acceptance. Such
records are retained; this presentation layer neither discards nor replays them.
