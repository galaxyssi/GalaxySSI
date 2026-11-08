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
ledger still remains to be implemented.

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
- [ ] Persistent question ledger with answered/deferred/declined/conflict states.
- [ ] Full issue lifecycle transitions and invalidation across every entry path.
- [ ] Personal Health overview, comparable trends, and evidence-focused details.
- [ ] Global indexed action queue, versioned plans, feedback and reminder recovery.
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
