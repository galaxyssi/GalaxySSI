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
the visible content and dialogs. Partial-completion/barrier feedback, visit
instructions and full long-cycle acceptance remain separate increments.
