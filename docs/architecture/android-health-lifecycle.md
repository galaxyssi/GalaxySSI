# Longitudinal Health Agent

This is the delivery contract for prevention, change detection, professional
evaluation, treatment or rehabilitation follow-up, and the next prevention
cycle. It extends the existing [proactive care foundation](android-proactive-health-care.md),
not a second chat engine or health database. Planned capabilities below are not
claims of completed implementation or clinical validation.

## Preserve the Agent page

The existing Agent page is an explicit product constraint. Do not redesign its
header, product logo, conversation controls, shortcuts, composer, voice entry,
or message layout. Use existing health entries and ordinary discussion turns
for health interaction. New overview, evidence, plan, visit, and follow-up
layouts belong inside Personal Health. Do not add a permanent health dashboard
to every Agent conversation or inject unrelated health facts into normal chats.

The clinical concern owns its durable state; its associated private conversation
is an interaction surface. Changing models, navigating away, or deleting a chat
must not silently create a new concern or mark the original concern resolved.

The local reassessment surface is restricted to that independent private
conversation: its `health-care:<concern-id>` topic and the encrypted discussion
binding must agree. Ordinary Agent and collaboration conversations never load
the global latest concern as a fallback. Switching conversations clears the old
surface immediately; generation checks reject late loads from the prior scope.
Personal Health exposes an **Open Health Agent** action near the top of the
concern details. It reuses the linked active conversation, which remains available
in the conversation list even before its first message. Opening it does not
submit a model request, authorize research, or share health records.

Inside that discussion, the assessment starts as a compact, collapsed summary.
Expanding it reveals the complete explanation and actions in a bounded scrolling
area; the collapse control remains outside that scroll. Priority status remains
visible in the summary. Refreshes preserve the user's current expansion choice,
while leaving the conversation or backgrounding clears the expanded sensitive UI.

## Six connected views

| View | Content and interaction |
| --- | --- |
| Existing Agent discussion | Why this review is relevant now, already-known facts, a material information gap if needed, evidence, and the next proposed action. Reuse the current layout and voice interaction. |
| Personal Health overview | Today's confirmed actions, ongoing concerns, visit/follow-up entries, and records. Empty, stale, unavailable, and all-done states are different; missing data never means healthy. |
| Change and evidence | Current measurement and date, comparable trends, collection conditions, saved context, missing/conflicting facts, source records, report range, and separately confirmed personal targets. |
| Daily plan | Proposed versus accepted actions, source and timing, reminders, completed/partial/difficult feedback, pause, adjustment, and history. Completion and measured effect are separate. |
| Visit preparation and return | A scoped previewable summary and questions before a visit; review of imported clinician instructions afterwards. Recording an appointment is not booking it. |
| Follow-up review | Actions, feelings, results, comparability, unresolved issues, plan revisions, and an explicitly reviewed transition to maintenance. Missing follow-up never means recovery. |

Use the current colors, typography, navigation, and native controls. No health
score, reference-range midpoint target, or decorative gauge should imply a
clinical conclusion. Large histories and aggregate counts must use indexed,
bounded queries; never label a single page as the entire archive.

## Shared context contract

1. Read only the authorized profile, concern, source revisions, and purpose.
2. Return known, missing, conflicting, stale, and unauthorized facts distinctly.
3. Retain origin, measurement time, confirmation time, and exact record revision.
4. A negative answer and zero are values. Unknown is not a negative answer.
5. Track why a question matters and whether it was answered, deferred, declined,
   or invalidated. Explain any justified repeat question.
6. Use the same scoped snapshot for manual model selection, Auto, and recovery.
7. Never claim a chat answer was saved without a successful write receipt.

The `clarification_context` handoff preserves exact-record known and unconfirmed
collection answers. Independent profile context now uses an explicit per-concern
field and record selection configured inside Personal Health, not a whole-profile
prompt. Selected saved values are read afresh; name and drafts are excluded and
birth date is reduced to age on the measurement date. Unselected and unavailable
entries never imply a negative medical history. A complete persistent question
ledger is being integrated across the remaining interaction paths.

The encrypted concern and turn grant retain dependency tokens, not duplicated
profile values. A selected source edit invalidates previous results and action
bases, produces one new research trigger, and leaves paused/closed concerns
paused/closed. New records and unrelated fields do not expand the selection or
trigger a new review. A deleted entry is explicitly unavailable; archive deletion
changes the generation and requires a new selection.

Standing research consent permits updates only within the same selected fields
and record IDs. A changed selection requires renewed consent, including for old
authorizations with no profile scope. Manual and Auto discussions use the same
snapshot and approval/result freshness gates. The picker clears on background
and permission/source changes; existing Agent layout remains unchanged.
Scope changes require a new linked private discussion. Older conversations remain
readable but cannot dispatch under a different scope or supply their history to
the new request. This prevents recalled answers from reintroducing withdrawn data.

### Question ledger

The care database now has indexed, row-encrypted questions and revision history.
Each question binds a stable semantic key, purpose, concern, source basis,
measurement revision/time, originating turn and profile-sharing scope. Native
tools `galaxyssi.health.questions.propose` and `galaxyssi.health.questions.read`
record questions or read bounded pages; neither can write an answer or select
another person/concern. Same-key retries reuse the existing question, including
its deferred or declined state. Models must reuse semantic keys, not bypass a
preference with paraphrased questions.

Personal Health offers explicit answered, deferred, declined, conflicting and
unanswered review. Saved measurement/profile facts are surfaced before asking
again. User replies remain self-reports and do not rewrite records or clinical
instructions. Source changes hide stale replies from the current snapshot;
conflicts retain both assertions without resolving them automatically. A reply
revision invalidates dependent grants/actions and triggers a new authorized
review, but does not invalidate unrelated question answers. Paused concerns stay
paused. Deferral/decline creates no reminder and requires user reopening.
Permission or refresh clocks alone do not stale answers whose source facts are unchanged.

The Agent base UI is unchanged. Discussion preparation and the phone-native
tools use the same scoped ledger for manual/Auto models and later conversations.
New consent explicitly discloses reviewed replies. Legacy grants do not gain
question-tool access or question snapshots; an answered concern requires renewed
consent before background research resumes. Initial handoffs include up to eight
rows and an explicit cursor; native reads use pages of up to thirty rows.
Observation compaction retains complete rows and advances only past delivered
questions; insufficient budget is explicit. Question history is encrypted and
removed with the concern. Database schema 8 migrates existing care data in place.

Remaining ledger acceptance includes conversational/voice answer proposals with
explicit confirmation, semantic duplicate evaluation across real providers,
and full process/boot and performance matrices. A model's prose alone must never
be represented as a saved answer or a completed clinical review.

## Persistent domain boundaries

| Entity | Required identity and provenance |
| --- | --- |
| Health fact | Owner/profile, source record/revision, value/unit, measurement time, collection context, source, quality. |
| Concern | Stable identity, topic, clinical stage, independent execution state, source clock, revision, assessment, next action. |
| Question ledger | Field/purpose, record and observation time, answer state, answer source, reason to reconfirm. |
| Care plan | Identity/version, sourced goals, proposed actions, applicability, confirmation, pause and supersession. |
| Action/reminder | Stable identity, confirmation, date/time zone, idempotency, delivery/read/snooze/completion, outcome links. |
| Encounter/instruction | Original document/page, reviewed fields, provenance, recorded appointment, and mapped follow-up drafts. |
| Evidence review | Research question, source/version/date, retrieved passage, applicability, conflicts, expiry and execution state. |
| Outcome | Execution feedback, symptoms, valid measurements, reassessment, and the next prevention/maintenance plan. |

Reuse row-encrypted SQLite, bounded pagination, and background plaintext clearing.
Do not introduce a whole-archive JSON file. Keep issue stage, model execution,
notification delivery, and clinical interpretation independent. Use optimistic
revision checks and short transactional writes; no network/model work under a
database lock or on the main thread.

## Interaction and execution

Record edits, new results, user feedback, and due reviews trigger incremental
assessment. Coalesce duplicate events per concern and source version. Do not
continuously invoke a model to poll unchanged records.

Tools should expose scoped context/history/evidence, plan proposals, explicit
confirmation, feedback/outcomes, reminders, pause/snooze, visit-summary preview,
and reassessment. Extend existing tools where possible. New write tools require
an expected revision, user confirmation where appropriate, and a durable receipt.
Research permission is not permission to change medication, share records,
schedule an appointment, or contact another person.

Research uses minimal nonidentifying queries and retains source versions,
retrieval dates, relevant passages, applicability gaps, and conflicts. Retrieved
web text is untrusted evidence, not tool authority. Failure to retrieve evidence
must remain a visible gap, not a fabricated successful recommendation.

Notifications must be deduplicated and suppress duplicates while the associated
concern is visible. Lock-screen content is private by default. Read, snoozed,
cancelled, completed, and unanswered are separate states. Normal reminders honor
quiet hours and user preferences. Permission denial leaves an in-app action;
it must not be recorded as successful system delivery.

## Clinical and privacy boundaries

AI drafts support user and professional review; software tests do not establish
clinical effectiveness. Rules and urgent guidance need versioned population,
exceptions, sources, and appropriate medical review. Never derive an ideal target
from the midpoint of a report interval or diagnose from a single measurement.
Do not delay urgent guidance for research or a questionnaire.

Confirmed clinician instructions retain their original source. Ambiguous drug,
dose, unit, frequency, or date fields cannot become executable reminders. AI does
not independently change treatment. A single in-range result, a finished model
task, or a missing follow-up does not establish recovery.

Online analysis, local assessment, original images, profile fields, notifications,
and sharing need distinct scope checks. Withdrawal blocks new access and invalidates
in-flight results. Process/boot recovery rechecks scope, revision, source existence,
and timing before resuming the same durable job. Family-profile support must remain
unavailable until storage, authorization, and every query enforce isolation.

## Incremental delivery gates

- [x] Exact-measurement known/unconfirmed handoff for existing care discussions.
- [x] Field-scoped independent profile context and source-version invalidation.
- [ ] Cross-provider conversational acceptance of the persistent question ledger.
- [x] Indexed question storage, scoped native tools and explicit Personal Health answer review.
- [x] Current-turn answer drafts with explicit local review and atomic saved-answer receipts.
- [ ] Full issue lifecycle transitions and invalidation across every entry path.
- [ ] Personal Health overview, comparable trends, and evidence-focused details.
- [x] Global indexed action pages and shared action/reminder review inside Personal Health.
- [ ] Complete versioned-plan feedback and reminder recovery acceptance.
- [ ] Previewable visit summary and explicitly reviewed clinician instructions.
- [ ] Treatment/rehabilitation follow-up and next-cycle prevention integration.
- [ ] Cross-provider, offline, process/boot, privacy and notification acceptance.
- [ ] Domain-specific clinical review and real-device performance acceptance.

These boxes describe implementation scope, not a clinical approval or a promise
that all scenarios are already covered. Each completed increment receives an
affected-platform version bump, latest-upstream review, and a new English PR.
Do not mark the overall lifecycle goal complete after one increment.

Acceptance covers prefilled/unknown/declined/stale/conflicting context, revised or
deleted sources, different units and devices, multiple conversations/providers,
late receipts, source failures, proposal versus confirmation, concurrent changes,
pause/snooze/cancellation, lock-screen privacy, permission denial, time-zone change,
process death and restart. Use the same persisted synthetic concerns across
recovery tests. Never upload test reports, private device data, or screenshots.

Measure click feedback, first-page load, pagination, and event processing
separately from model/network latency. Target first-page P95 below 300 ms and
click feedback below 100 ms on representative devices, but report measured
results rather than treating these targets as guarantees.

## Conversational answer review

`galaxyssi.health.answers.propose` extracts an answer for an existing question ID
and revision. It requires an exact quote from the current human message, not a
model reply or retrieved document. The per-turn grant carries a digest of the
approved input. The host reads one indexed original turn entry and verifies its
role, conversation, turn and digest. Legacy grants and autonomous research cannot
stage human answers. Typed and transcribed submissions share this path; this does
not add a new microphone implementation.

Schema 9 stores pending drafts in separately encrypted, paginated rows. A retry
for the same question and turn returns the first draft without changing it or
reopening a dismissal. Pending drafts never populate the saved question ledger,
edit a measurement/profile, or authorize a reminder. Only local user review can
accept an edited answer or discard a draft. Acceptance updates the question and
draft receipt in one transaction, retains provenance and invalidates dependent
research through the existing question-version mechanism. Unrelated questions
from the same message remain reviewable; a changed source, sharing scope, original
message or question revision prevents stale confirmation. A paused concern stays
paused. The saved answer remains a self-report, not a verified clinical finding.

Review uses the existing Agent health details entry and Personal Health concern
page. The Agent header, transcript, shortcuts, composer and voice layout do not
change. Reviews clear on background, navigation and observed privacy/source
changes. Drafts survive process death, but expired source evidence cannot be
silently accepted after reopening. Real-provider extraction and continuous voice
acceptance remain distinct from synthetic tool/storage/UI regression tests.

## Global action agenda

Personal Health now links to an independent, globally paged action agenda rather
than flattening every action from the current concern page. The Agent main page
is unchanged. Today, later, review and recorded views use keyset pages of at most
thirty actions. Today includes unfinished actions with an existing planned window
or explicit reminder before the next local midnight; unscheduled actions remain
under later. A started window is not automatically a missed clinical deadline.
Day boundaries follow the local time zone, including daylight-saving transitions.

Schema 10 adds a rebuildable metadata-only action projection in the same care
database. Descriptions, rationale, sources and outcomes stay in authenticated
encrypted concern records. Concern and reminder writes update the projection in
the same transaction; readers validate selected index fields against those
canonical records. Existing databases backfill in resumable batches of at most
thirty concerns on a worker, not during UI/database-open work. An unfinished
backfill is shown as loading rather than an empty healthy state. Changed queue
generations or day boundaries invalidate a cursor and restart the visible page.

Opening an action reuses the existing scoped reminder/outcome review. Proposed,
paused, closed or stale-basis actions require review. Cancelling a reminder does
not remove the action; delivery does not complete it. Recorded feedback never
establishes clinical recovery. Privacy withdrawal and background navigation clear
the visible content and dialogs. Visit instructions and full long-cycle
acceptance remain separate increments.

## Action execution feedback

The shared action review now requires an explicit completed, partial or barrier
selection plus a note. Partial progress and barriers keep the action confirmed
and preserve an otherwise valid reminder. Only completed execution finishes the
action and cancels its reminder. Feedback requests reassessment without resuming
paused tracking, changing measurements, confirming improvement or adjusting
treatment. The agenda retains reminder timing alongside the latest feedback state.

Schema 11 stores authenticated encrypted feedback receipts independently of the
latest action snapshot. Saving the concern, feedback, reminder effects and agenda
projection is atomic. An editor operation ID makes retries idempotent and rejects
changed content or ownership. History is keyset-paged by concern revision, at most
30 records at a time, including records for actions no longer in the latest plan.
Opaque IDs and revisions are indexed; notes, titles and timestamps are encrypted.
Legacy outcomes remain on their original actions without fabricated timestamps
or migrated feedback events. Deleting a concern deletes its feedback receipts.

The existing authorized Agent snapshot includes the latest feedback, explicitly
marked self-reported and not a verified clinical result. Its selected-profile
scope and plan basis are checked; withdrawn-scope notes are excluded, and stale
plan feedback is marked historical. Feedback can trigger already-authorized
research once, but does not itself grant network consent. Partial feedback is not
misreported as a new due date. The saved timestamp is not an asserted execution
date, and the snapshot does not claim to include the full local feedback history.

Background navigation and privacy withdrawal clear feedback editors and history
dialogs. Automatic voice-to-feedback writes, correction/retraction workflows,
and the full visit/rehabilitation lifecycle remain future increments. No software
test establishes clinical effectiveness.

### Scoped feedback history for Agent discussions

The existing manual discussion approval now discloses paged access to this
concern's execution feedback. A persisted per-turn flag authorizes the read-only
phone tool `galaxyssi.health.feedback.read`; old grants default to false, and
automatic research requires a separate explicit choice for this permission. The Agent main
layout is unchanged. No feedback is included automatically in the first prompt
beyond the existing latest action notes. The snapshot names the available tool.

The tool uses indexed revision-keyset pages of at most 30 encrypted receipts,
including feedback for actions no longer in the current plan. It binds the
conversation, turn, concern revision, measurement clock, selected profile and
privacy approval before and after reading. It cannot select another concern or
write records. New feedback or changed permission/source data requires a fresh
approval instead of mixing pages from different snapshots. Local-model access
works offline; remote-model access still requires online-analysis permission.

Feedback outside the current profile-sharing scope is redacted, including its
action title and timestamp, while its revision keeps pagination continuous.
Current-plan membership, stale basis, user-reported execution and save time are
separate facts; no entry proves clinical improvement. Legacy outcome text is not
fabricated into feedback receipts. Observation compaction retains entire entries
and advances only past delivered entries; an insufficient budget preserves the
cursor and explicitly requires a larger budget, not repeated identical reads.

The proactive research consent dialog offers a separate, initially unchecked
history option. It does not replace the mandatory destination/standing-consent
acknowledgement. The disclosed data preview and saved scope show the choice.
New research turns inherit only the persisted standing scope, not a manual turn's
permissions. Authorization matching includes the history flag. Replacing or
narrowing consent cancels unfinished jobs durably; revoked, terminal and
superseded turns cannot continue paging. New feedback requires a new revision
and turn while retaining a still-valid standing authorization. Reads remain
phone-local and read-only; online analysis is still required for remote models.
This does not authorize clinical plan changes or expand selected profile data.
Without history consent, generic conversation recall is unavailable and both
planning and launch filter prior dialogue through its persisted turn grants.
Unattributed summaries and broader-history turns are excluded; already-permitted
turns and the fresh scoped health snapshot remain available. Existing transcripts
are not deleted. This prevents a narrowed grant from reintroducing feedback
through an old conversation summary instead of the paged tool.

This adds model access to recorded follow-up evidence, not an independently
verified clinical review, automatic treatment adjustment or background authority.

## Local visit-preparation preview

The existing Personal Health concern detail opens a local visit-summary workflow.
The Agent main-page layout is unchanged. Users choose measurements, measurement
context, confirmed actions and feedback, question history, and optionally the
already selected profile fields/background entries. Profile details are off by
default; enabling them never expands the concern's approved profile scope. Each
resulting item can be excluded again before sharing. Missing or unselected
history is not represented as absence of disease, medications or allergies.

The preview separates measurements and exact source revisions from self-reported
context, user-confirmed actions and questions. It includes up to eight recent
measurements and eight scoped questions, explicitly disclosing additional history.
Original records remain accessible independently by record ID and revision; no
original attachment is included in a text share. Incompatible measurements retain
their comparison caveats. Stale questions and actions are not silently promoted
to current advice, and user confirmation is not described as clinician review.

Generation runs on a worker without a model or network call and creates no disk
report. A final explicit confirmation opens Android's text share chooser with
exactly the selected preview items. Internal IDs, paths and profile names are not
added; free text may still identify someone, so the UI does not promise automatic
anonymization. Sharing transfers plaintext to the selected app, outside GalaxySSI's
subsequent control. Cancelling confirmation does not launch the chooser, and
opening it is not recorded as successful delivery to a clinician.

Source clocks, concern revision, privacy version and selected profile stamps are
checked after generation and immediately before sharing. Changed data or permission
requires a new preview. Previews expire after ten minutes and clear on background,
recreation, memory pressure and observed source/privacy changes. Oversized text is
rejected, not truncated. No new database or persisted plaintext snapshot is added.

This increment provides a selected text summary, not a PDF report, symptom intake,
hospital booking, medical record transmission or post-visit instruction review.
Agent-triggered preparation, appointment reminders, reviewed prescriptions and
rehabilitation follow-up remain separate work in the full lifecycle goal.

## Local encounter records

The next increment introduces local encounter records bound to an existing self
concern. Planned, user-recorded booking, attended and cancelled are separate
states. A planned date alone does not imply a booking. Attendance requires an
explicit non-future date. These records are always user reports, not hospital
receipts, verified clinician findings, prescriptions or permission to change a
plan. Correcting a record preserves its original source anchor and creation time.

Schema 12 adds individually authenticated encrypted current records and immutable
operation receipts. Only opaque IDs and concern revisions are indexed; facility,
purpose, visit dates, time zone and notes stay encrypted. Updating the concern
revision, current encounter and history is atomic. Replayed operation IDs return
the same receipt; changed content, ownership or editor revisions fail closed.
Recording attendance does not complete existing actions or mark a concern cured.

Current lists and per-encounter history use revision-keyset pages of at most 30
records. A mutable-list cursor also requires the original concern revision, so
concurrent edits require a refresh rather than silently losing moved records.
Deleting an encounter purges its current row and encrypted history; deleting the
concern purges all its encounters. Old operation retries cannot revive them.

The existing concern detail opens the native list, editor, detail and change
history. Explicit deletion confirms the removal of this encounter and its history,
not its measurements or confirmed actions. Editors use native date/time pickers
and retain the recorded time zone. Nonexistent local times are rejected; ambiguous
clock-change times require an explicit offset selection. Saving a user-recorded
booking requires its planned time. Planned and actual times remain distinct.

Repository snapshots bind privacy and settings versions, the concern revision and
the measurement clock. Changed inputs require a fresh review. Local writes hold a
short consent transaction so concurrent revocation cannot pass an obsolete check;
no model or network work runs under that lock. Manual records remain available
when proactive checking is off, as long as the relevant local permissions remain
granted. Backgrounding, recreation, source changes, memory pressure and a ten-minute
TTL clear the editor and loaded plaintext; resuming reloads from encrypted storage.
Invalidated worker results never render into a newer screen, and current failures
offer an explicit retry instead of looping.

Appointment reminders, post-visit original import and reviewed clinical
instructions remain separate increments. This implementation has no external
booking or clinical execution tool. Device UI, storage migration and privacy
regression acceptance must pass before it is considered ready for delivery.

## Encounter source documents

Visit detail now opens a local source list. Users select an existing retained
original, link the whole file, or preview a PDF/image and explicitly choose a
page. Native pinch/drag preview reuses the bounded original rasterizer. The
existing import workflow remains available; returning from it reloads local
sources, without automatically associating an imported document or interpreting
it as a prescription. Private review-only imports cannot be selected.

Schema 13 stores each association independently with authenticated encryption.
The payload binds the concern, encounter, their expected revisions, original ID,
SHA-256, byte size, MIME type, optional page/count and user confirmation time.
Indexed source fingerprints use a keyed digest, not a public file hash. Recording
the association and its concern event is atomic; duplicate sources and operation
retries do not create duplicate links. Changed replay payloads and stale parents
are rejected. Removing a link leaves the original file intact. Deleting the visit
or concern purges its associations; stale callbacks cannot revive removed links.

Preparation verifies the complete original through a bounded stream, without
creating a plaintext file. Rendering, verification and library reads run outside
the main thread and outside the short commit lock. A prepared confirmation expires
after ten minutes and rechecks privacy, source metadata, parent revisions and
measurement clocks before committing. Lists use at most 30 items per page; linked
source continuations are tied to the concern revision. Backgrounding, memory
pressure, source changes and expiry discard dialogs, loaded plaintext and preview
bitmaps, including obsolete worker results.

Missing or changed originals remain visible as unavailable associations that can
be removed, never as verified clinical evidence. Preview failure is explicit;
password-protected PDFs require the original-library reader rather than an
invented page preview. Selecting a source is not clinician verification and does
not create medication, appointment or rehabilitation reminders. The sections
below describe source-backed drafts, field review, original dependencies and
scoped Agent assistance. Full post-treatment follow-up remains subsequent work.

## Source-backed instruction review

Linked encounter originals now provide a local page-reading entry. A PDF text
layer is preferred; image-only pages use the existing on-device OCR engine. Only
the selected page is decoded. Users select exact source lines to create an
unreviewed instruction draft, then classify and transcribe its fields. The
retained source includes original identity/hash, page, recognition method, line
indices, available bounding boxes and blur warning. There is no invented numeric
OCR confidence. Password-protected PDFs remain unsupported in this page workflow.

Medication, test, follow-up, rehabilitation, lifestyle and other drafts have
explicit field states: unreviewed, checked against the source, or not stated in
the source. Editing checked text resets its review. Not-stated fields contain no
guessed text. Review records user transcription, not a clinician signature or
medical validation. Field review alone cannot create executable actions or
reminders. The explicit action confirmation step below is separate.

Schema 14 adds encrypted current drafts and immutable operation receipts with
authenticated ownership indices. Draft and concern revisions commit atomically;
retries cannot change their source or overwrite newer edits. Current drafts and
review history use indexed keyset pages of at most 30 items. Source quotations
and creation time survive later reviews. Deleting a draft purges its review
history but not the original. A linked source cannot be unlinked while it has
dependent drafts. Missing original bytes leave historical transcription visible,
but block further field confirmation. Visit/concern deletion purges dependent
drafts and review history.

Reads, OCR and rendering run on a worker. Save rechecks the encounter, concern,
privacy, measurement clock and original metadata/presence. Revocation, background,
memory pressure and ten-minute expiry discard draft editors, selected source
lines and preview bitmaps. No new plaintext file or network request is produced.

Source selection remains explicit; the scoped Agent drafting increment below
assists classification, not autonomous clinical extraction. Full
treatment/rehabilitation follow-up remains subsequent work.
Software and device tests do not establish clinical effectiveness;
the full lifecycle still requires its separate clinical and end-to-end gates.

## Confirmed instruction actions

The instruction detail can add a separately confirmed action to the existing
care agenda. The confirmation shows the immutable quotation, page, reviewed
fields and an unchecked acknowledgement. Cancel or backgrounding discards an
unconfirmed dialog; authorization is rechecked when committing a confirmed
action. An unreviewed draft cannot offer confirmation. Medication
requires every required field to be explicitly transcribed and checked, including
name, dose, unit, route, frequency, start/end dates and details. Other instructions
require a checked name/details and explicit review of the remaining fields;
not-stated dates remain unknown. Users must clarify ambiguous instructions with
their clinician; the application does not validate prescriptions clinically.

Schema 15 adds an optional typed instruction reference inside the existing
encrypted action payload. Existing actions and schema-14 sources survive the
upgrade. The reference binds instruction revision, encounter, source association
and original hash/page. Confirmation verifies the complete encrypted original on
a worker, then rechecks authorization, parent revisions and source presence in
the short commit path. One deterministic action ID per instruction revision
prevents repeated confirmation from creating duplicates or rearming a completed
action. No reminder is created by confirmation itself.

The existing reminder/feedback UI displays all transcribed fields and links back
to the source. Its date/time picker schedules one user-selected reminder; it does
not infer a recurring dose schedule from free text or rewrite clinical dates.
Scheduling and delivery check the current instruction and original presence in
addition to existing privacy, measurement and profile checks. The default store
scheduling path rejects clinical actions without an explicit source-availability
check. Generic model plan schemas and parsers cannot create clinical instruction
actions. Scoped model-assisted clinical drafting uses the separate proposal flow below.

Editing/deleting an instruction or deleting its encounter invalidates dependent
action references and cancels old reminders in the same transaction. The old
action remains in review/history rather than silently becoming the new medical
instruction. A changed instruction requires a fresh confirmation. Missing
original bytes block confirmation, scheduling and actual reminder delivery.
Feedback continues to use the existing encrypted, idempotent receipts; completing
an action never establishes recovery or clinical improvement.

This does not yet deliver recurring prescription schedules, diagnosis-specific
rehabilitation cycles or full lifecycle acceptance.
The existing 30-action concern budget is unchanged; exceeding it must fail
without dropping history, and durable paged plan archival remains a separate
architecture gap. No Agent main-page layout changes are introduced.

## Selected-source Agent proposals

An unreviewed instruction can open its existing private health discussion with
an opaque instruction ID. MainActivity consumes that ID only in the foreground
after conversation hydration, then uses the normal one-turn consent dialog and
selected provider configuration. The disclosure shows the selected quote and
provider/model. Cancel or backgrounding does not submit. Only the selected
quote, page, recognition method and blurry flag enter the model snapshot; no
profile, measurements, questions or earlier chat accompany this extraction turn.
The source identity, revision and hash remain in the local persisted grant.

The restricted tool `galaxyssi.health.instructions.propose` accepts a kind and
exact, contiguous excerpts for every required field. Missing fields are explicit
`NOT_FOUND` values, not reviewed omissions. `QUOTED` means text matched, not
clinical confidence; blurry sources force `UNCERTAIN`. All fields remain
`UNREVIEWED`. No model tool can confirm an instruction, prescribe, alter an
existing reviewed field, create an action or schedule a reminder.

Schema 16 adds an encrypted per-proposal table, authenticated owner/state indexes,
one pending proposal per instruction and turn-level replay receipts. Proposals
do not change the concern revision or original instruction, so a successful
tool receipt does not revoke its own turn. Replaying a dismissed result cannot
resurrect it. Review loads the existing editor with unchecked fields and source
certainty labels. Saving records model-assisted provenance; a separate user
confirmation still gates actions. Manual edits dismiss old pending proposals;
stale source versions, removed originals and changed privacy block adoption.
Deleting the owning instruction, encounter or concern also purges proposals.

Selected-source turns are excluded from later ordinary history and recall.
Unproven summaries/global context are omitted because they may incorporate
older extraction turns outside the current history page. Authorized ordinary
turns and scoped paged feedback remain available. Proposal/editor plaintext
uses the existing background, memory-pressure and ten-minute cleanup paths.

Acceptance uses synthetic documents in isolated databases. The opt-in real
provider probe exercises production prompts, phone tools and encrypted writes,
not the Activity consent UI. It is not clinical validation or full lifecycle
acceptance. Multiple independent instructions require separate source selection;
recurring dose interpretation and autonomous treatment changes are not provided.

Visit refreshes retain the selected visit identifier while clearing plaintext and
reloading the source. A delayed write notification cannot send a newly opened
detail back to the list. Ownership and privacy are still rechecked on reload;
missing or revoked records fail closed rather than retaining stale details.

## Post-visit follow-up journals

An explicitly recorded attended visit can start its own follow-up journal. It
retains a goal, subjective physical feelings, daily function, sleep, barriers and
review notes separately from action completion and laboratory assessments.
Review can record continuation, a proposed adjustment or a proposed maintenance
discussion. The latter two remain pending review; they do not change the concern
stage, treatment, targets or existing reminders. Pause/resume and archive/reopen
are journal states only. Archiving requires an explicit acknowledgement that it
does not establish recovery or stop treatment/reminders.

Schema 17 adds encrypted current journals and immutable operation receipts, with
indexed 30-entry keyset history. Parent concern revisions and journal writes
commit atomically. Retries preserve the first payload; stale ownership, revisions
and revoked privacy fail closed. A revised visit remains flagged until an
explicit journal review, not merely another check-in. Deleting a journal retains
the visit and instructions; deleting its visit or concern purges dependent
journals. UI reads/writes use a worker and clear plaintext on background, memory
pressure and the existing ten-minute expiry. Snapshot reads revalidate the
concern, source and permission versions after loading history, so a concurrent
check-in cannot combine different journal revisions on one screen.

The opt-in process-recovery test retains only an isolated synthetic journal
between its seed and recovery phases. It requires a different process identity,
checks the same journal and paged history, replays the last operation without a
duplicate, and verifies an explicit resume returns to review. It also supports
covering an application upgrade between phases and cleans up only its fixture
databases after recovery.

This stores self-reported post-visit evidence, not an autonomous rehabilitation
plan. Recording notes is not an emergency assessment or a clinical outcome, and
no observed change proves an effect caused by the application.

## Scoped Agent follow-up discussion

The journal's discussion entry opens the existing Agent page without changing
its layout. A separate per-turn preview identifies the model destination and
discloses the selected visit purpose, journal goal, state and paged entries.
Confirmation is required before dispatch. It does not add journal content to
ordinary discussion grants or standing research consent. Original files,
instructions, unrelated visits and profile values are not included.

`galaxyssi.health.visit_followup.read` is a phone-local, read-only tool for all
reasoning providers. A persisted grant binds conversation, turn, concern,
journal and encounter revisions, privacy, settings and destination. Reads check
these bindings before and after retrieval. Pages have at most eight entries and
a 24,000-character row budget. Observation compaction preserves whole entries
and advances only past delivered entries. An oversized entry supplies its exact
revision and nonempty fields for 256-character chunk reads; the caller resumes
older history only after reading those fields. Neither path permits arbitrary
person, journal or visit selectors. Deletion, new check-ins, source changes,
permission withdrawal and expiry invalidate old reads rather than mixing pages.

Follow-up questions reuse the selected journal but require a fresh sharing
preview. Only earlier turns with the same journal scope, destination and privacy
binding can enter that discussion's history. New journal revisions do not reuse
older journal prose. Ordinary health discussion and conversation recall exclude
these scoped turns; summaries without per-turn provenance are omitted.

The Agent may read the approved journal and public sources, but cannot use this
grant to write plans, change treatment, mark recovery, schedule reminders or
launch other models. Software tests of storage, scoped tools and UI do not
constitute clinical validation. The opt-in paired-provider probe reads an
isolated ten-entry synthetic journal through the production phone tool and
observation pipeline, checks complete paging and verifies no plan or reminder
was created. It does not exercise the Activity sharing dialog or establish
clinical accuracy. Full consent-to-provider UI acceptance, review reminder
integration, diagnosis-specific review and longitudinal lifecycle acceptance
remain separate outstanding work.
