# Proactive health care

## Structured model reviews and attention delivery

New authorized automatic reviews record a typed assessment through
`galaxyssi.health.review.record` before completing. The encrypted per-turn row
retains the actual grant, source version, reasoning summary, uncertainty, next
step, evidence references and review conditions. A model opinion is neither a
diagnosis nor a confirmed plan. Earlier assessments can inform a subsequent
authorized turn without replacing the new source snapshot.

Schema 19 adds an encrypted attention outbox. Only a successfully completed
review that requests attention admits an update, in the same database transaction
as completion. Earlier reviews are not backfilled as notifications on upgrade.
There is one current receipt and one stable notification identity per concern;
all assessment history remains separate. Waiting rows are read in pages of 30.

Delivery rechecks the source clock, concern, conversation, standing consent,
privacy, model destination and settings. It respects the existing global health
notification opt-in, the separate Agent-assessment update toggle, pause and quiet
hours, and Android notification permission. A failed OS post retains the same
receipt and backs off. A notification still visible after interruption is
acknowledged without ringing again; a committed receipt is not replayed after
the user dismisses it. OS posting and SQLite cannot be one atomic transaction,
so an interruption followed by dismissal before receipt persistence remains a
small replay window, not an exactly-once guarantee.

The notification contains no measurement, condition or model-generated health
text. It opens the already-bound health Agent conversation. Viewing that exact
conversation or its assessment suppresses the system notification, without
affecting ordinary Agent pages. Revoked or stale updates are cancelled; the
underlying messages and assessments are not deleted. Disabled delivery keeps the
review available in-app and does not later flood the user with old notices.

This routine update channel is not a clinical alarm, and does not bypass quiet
hours, change medication, confirm targets or schedule a clinical follow-up.
Cross-concern plan coordination and clinical outcome validation remain separate work.

## Consent-scoped related measurements

Standing research consent can include explicitly selected additional self-profile
measurement types. The options start unchecked and the disclosure preview follows
the selection. Normal measurements are retained in the encrypted evaluation cache
without manufacturing abnormal concerns. Existing grants share no additional
metrics, and manual conversations do not silently inherit standing consent.

Each automatic turn binds the current version of every selected metric, including
its own units, measurement time, record revision and confirmed collection context.
Missing or withdrawn evidence is not a normal result. The model may request older
pages only for the primary or explicitly selected metrics, using that metric's own
input version. A selected source change invalidates the prior assessment and
creates one new research trigger; unrelated changes do not create another review.
The structured assessment must reference at least one primary record and the
current sample of every available selected metric. These are reviewed-input
references, not proof of relevance, causation or a diagnosis. The model explains
insufficient context or limited relevance; missing references return a correctable
tool error instead of being silently added by the host or accepted as complete.

History handoff, conversation recall, stored questions, prior evidence and model
assessments respect the current selection. A narrower grant cannot reintroduce
withdrawn measurements through derived prose. Source changes are checked before
tool reads, plan confirmation and notification delivery. Revocation does not
delete the user's records, questions, messages or historical assessments.

This supports source-aware joint assessment, not a complete health archive or
automatic cross-concern clinical management. Different measurement dates are not
simultaneous observations, correlation is not causation, and no second concern's
target, accepted actions or reminders can be changed through this grant.

## Longitudinal evidence window

Assessments retain a contiguous recent page of up to 30 self-profile measurements,
including source revision, collection time, units, reference and conditions. An
explicit `has_earlier` flag distinguishes a page from complete history; comparison
anchors outside that page remain separate. No result-value filter selects only
normal readings. The evaluation cache version backfills this evidence without
changing the source clock or silently changing an individual target.

The Agent main page and concern details expose the same paginated history review.
Pages are released on background, conversation changes, source updates or privacy
revocation. `galaxyssi.health.history.read` lets the authorized model read older
pages on the phone. The host binds the concern, allowed metric selection,
self profile and granted turn; an optional model-supplied metric must belong to
that selection. Every page checks source clock, concern revision,
privacy and approval. Changed data requires a new review, not mixing stale pages.
Storage is not limited to 30 records. No unrelated profile, private device/source
identifier, free-form note or original attachment is included in the model page.
Observation compaction retains complete rows and moves the continuation cursor
only past rows delivered to the model. It never silently skips the middle of a
page. A budget too small for one row reports non-delivery without advancing.

The supervised planner reserves the complete authorized concern snapshot instead
of applying the generic 8,000-character head/tail truncation. The bounded health
handoff retains the source version, targets, context and every supplied row; an
oversized handoff fails explicitly rather than sending partial JSON or losing the
pagination version. This is a transport rule, not an authorization bypass: native
reads still validate the persisted per-turn approval and current source clock.

Per-result comparison gaps retain incompatible units, unknown conditions, source
changes, uncertain numbers and unconfirmed context. Historical context is never
copied from the latest result. Arithmetic agreement and a fixed count of readings
do not certify clinical stability. Source-clock changes also invalidate a prior
maintenance stage even if the changed record lies outside the recent page.

This supplies evidence for a subsequent maintenance-plan review; it does not yet
implement the complete source-backed maintenance proposal, confirmation and
long-term clinical validation workflow. No reminder is scheduled by reading history.

## Product objective

The complete feature is an evidence-based, longitudinal health Agent. The Agent
main page owns discussion, consent and follow-up interaction; Personal Health owns
the source records, permissions and durable care issues. A care issue is not a
chat turn and must survive conversation changes and process restarts.

The implementation is in progress. The local assessment and persistence layer
below is **not the completed autonomous clinical workflow**.

## Distinct evidence bases

`HealthCareAssessment` retains the report reference interval, applicable guideline
criterion and a descriptive historical range independently. `HealthCareTarget`
requires a stated rationale, source, confirming person and confirmation time.
No code computes a target from the midpoint of an interval or from the user's
historical readings. An in-range result does not automatically resolve an issue.

Initial local assessment supports strict numeric report bounds/ranges and a
context-gated fasting plasma glucose screening criterion. A comparative series
describes matching units, reported conditions and source identity; this does not
establish that two laboratories used comparable methods. Clinical interpretation
must verify that remaining uncertainty. These rules do not provide comprehensive
emergency detection or diagnose disease.

The glucose criterion requires confirmed adult/nonpregnant/without-known-diabetes
context, laboratory plasma and at least eight hours without calories. This
confirmation is bound to the exact measurement revision. A catalog label of
"laboratory", the word "fasting", a home meter or a CGM is not sufficient.
Published unit thresholds are compared without conversion rounding. Results
reported as bounds, ranges or qualitative labels are not treated as exact values.

Sources:

- [MedlinePlus: understanding laboratory results](https://medlineplus.gov/lab-tests/how-to-understand-your-lab-results/)
- [ADA 2026: diagnosis and classification](https://diabetesjournals.org/care/article/49/Supplement_1/S27/163926)
- [NIDDK: tests and diagnosis](https://www.niddk.nih.gov/health-information/diabetes/overview/tests-diagnosis)
- [ADA 2026: individualized glycemic goals](https://doi.org/10.2337/dc26-s006)

The bundled guideline citation is a versioned starting point, not an implementation
of live guideline retrieval, source validation or clinical decision support review.

## Persistence and concurrency

`health_care_v1.db` uses SQLite WAL and per-row authenticated encryption with
Android Keystore-backed `AgentStorageCipher`. Indexed metadata is separate from
encrypted payloads. Metric lookup uses keyed opaque tokens. Issue ID, revision,
owner, indexed state, due time and update time are checked against authenticated
payloads. History rows are separately bound to the issue and revision.

One issue tracks each self-profile metric across new results; revisions preserve
the prior reasoning inputs, context, plan and review. Pages and history queries
are bounded at 30 rows, with no history-total truncation. Optimistic revision
checks reject stale evaluations, context confirmations and user actions. Source
clocks and settings versions make repeated evaluation idempotent. Deleting an
issue retains its last evaluation marker so a page refresh does not recreate it.
New measurements can produce a new issue.

Suggested actions do not become reminders merely by being proposed. Confirmation
is explicit, and completion requires a recorded outcome. Maintenance requires
an explicit review; the evaluator never enters it automatically after an in-range
result. A numeric target is not mandatory when it is not clinically indicated.
The stored review is a data-integrity requirement, not proof of clinical stability
or a verified clinician identity. Pause retains the evidence but suppresses the
issue's due time.

## Local evaluation and UI

Proactive review is off until explicitly enabled. Confirmed-metric permission is
checked and each local evaluation is audited as `PROACTIVE_CARE`. Measurement
commit events enqueue coalesced WorkManager reconciliation. Work is not performed
under the measurement transaction or on the UI thread. Persisted metric clocks
allow reconstruction after interruption and on returning to the app.

The Agent main page surfaces a local issue without appending its values to an
unrelated chat transcript. Collaboration chats do not display this surface.
Backgrounding clears the surface and the care page's views. No provider request
or cloud disclosure is authorized by enabling local review.

Personal Health links to three sections: needs attention, improvement/follow-up,
and trends/originals. Issue details expose the four evidence bases, measurement
context confirmation, original record, guideline link, pause/resume and history.

## Remaining acceptance work for the full goal

- Complete real-provider acceptance of the scoped Agent discussion described
  below, including Desktop recovery, local models and permission revocation.
- Integrate authoritative guideline retrieval, applicability/version checks and
  source-backed model explanations, including uncertain or conflicting evidence.
- Validate real-provider use of the pending-plan tool and review UI below,
  including source applicability and justified follow-up windows.
- Complete real-device restart and delayed-alarm acceptance of the action-bound
  reminders below, alongside clinically informed subsequent-result reassessment.
- Implement clinically reviewed urgency handling separately from routine advice,
  individual targets and maintenance review, without promising all-danger detection.
- Verify broader measurement/risk-context coverage, lab-method comparability,
  source deletion, backup/restore and privacy revocation across active model calls.
- Complete real-provider, isolated-device, process-restart, scrolling and
  accessibility acceptance of the entire workflow.

Local tests and a native overview alone must not be used to mark this goal complete.

## Subsequent-result reassessment

New evaluations retain bounded before/after measurement snapshots, their exact
record revisions, collection times, component units, collection conditions and
source identity. Previous context confirmations remain attached to their own
measurement; they never authorize the next result implicitly. Corrections and
history changes are distinguished from newly collected follow-up results.
Source/device identity is kept only in the encrypted local snapshot; model
handoffs carry source types and comparison-gap flags, not those identifiers.

The Agent landing surface shows the before/after values. Concern details expose
comparison gaps, and the scoped discussion receives the same structured handoff
along with existing actions and outcomes. Arithmetic differences do not classify
clinical improvement, worsening or stability. Method/laboratory comparability is
explicitly unverified; unit changes are not silently converted. Model reassessment
must explain applicability, remaining uncertainty and the next justified step.
One in-range result does not close the concern or enter maintenance.

The engine uses the existing 30-record window plus at most two indexed anchor
lookups, not a complete-history scan. Deleted or superseded comparison sources
are removed from the active handoff. Historical revisions remain in the existing
encrypted audit history. Legacy payloads stay readable without fabricating missing
measurement metadata; the next measurement event builds the new handoff. Merely
installing the update does not re-anchor or cancel existing reminders.

This supplies longitudinal evidence, not a clinically validated automatic outcome
classifier. Broader real-provider applicability, conflicting-source, maintenance
and complete UI acceptance remain required.

## Recorded blood-pressure priority notice

An opt-in local assessment now flags a confirmed stored systolic reading above
180 or diastolic reading above 120 mmHg. Either component can trigger it. kPa
comparisons use the NIST conventional mmHg factor (0.1333224 kPa) without
intermediate rounding; pulse is never compared to a pressure threshold.

This is a recorded-value warning, not a diagnosis, live monitoring or an emergency
detection service. The Agent surface puts the measurement date and conditional
emergency advice before ordinary concern actions. The detail page distinguishes
current symptoms, a current reading without concerning symptoms, historical
records, and adult nonpregnant scope. It never waits for a model or source fetch
to show the bundled notice, auto-dials, changes medication or creates a reminder.
Children and pregnancy require different professional assessment; absence of
this notice is not safety clearance. There is no arbitrary time-based rule that
turns an imported historical measurement into a present emergency.

Sources checked on 2026-11-07:

- [AHA: when to seek emergency help](https://www.heart.org/en/health-topics/high-blood-pressure/understanding-blood-pressure-readings/when-to-call-911-for-high-blood-pressure)
- [AHA: readings and either-component thresholds](https://www.heart.org/en/health-topics/high-blood-pressure/understanding-blood-pressure-readings)
- [NIST: pressure conversion factors](https://www.nist.gov/pml/special-publication-811/nist-guide-si-appendix-b-conversion-factors/nist-guide-si-appendix-b9)

Schema 6 adds a coarse priority index beside existing lifecycle metadata; values,
sources and symptoms remain inside authenticated encrypted records. Decoding
checks the priority index against authenticated signals. Keyset pagination orders
priority, update time and ID, with no full-history decryption. Existing schema
1-5 rows migrate without rewriting encrypted payloads. A separate, metric-specific
assessment cache version lets a policy upgrade replay blood-pressure evaluation
without changing source identity or invalidating unrelated confirmed reminders.
Deletion retains a source-bound dismissal marker even across policy refreshes;
changed source data can be evaluated again. Pausing remains effective. Background
and privacy-revocation clearing and dedicated discussion scope remain unchanged.

The first notice covers only this blood-pressure case. It is not a comprehensive
clinical triage system; broader urgent conditions, symptoms, provider behavior and
clinical validation still require separate evaluation.

## Action-level applicability review

Every new model-proposed action includes a structured review: discussion-only or
individualized scope, source-indexed conditions, unresolved information and any
material source conflicts with a proposed resolution. All referenced passages
still require same-turn native read receipts. The model declares requirements;
it cannot provide the actual patient values or a clinical-verification flag.

The phone compares declared requirements with the current measurement and
revision-bound confirmed context. Unknown is not false, context from a different
record does not count, and units are not silently converted. Unresolved factors,
mismatches or source conflicts prevent adoption of that individualized action
both in the review UI and in the transactional store acceptance path. Other
information-check and clinician-discussion items remain selectable. Conflicting
intervals and thresholds are not averaged or automatically resolved.

The Agent and Personal Health share the same confirmation surface. It displays
declared requirements, saved facts, numbered sources, unknown factors and next
steps for conflicts. Legacy drafts remain readable; unreviewed clinical actions
need fresh review, while clarification/discussion remains available. Previously
confirmed actions and reminders are not changed just by installing this update.

These are checks of **declared** requirements, not a clinical eligibility engine.
They do not prove that the model identified every contraindication, interpreted
the source correctly, or found all conflicting literature. A source quote proves
retrieval, not medical applicability. Clinically validated source interpretation,
urgency, maintenance criteria and broader real-provider matrices remain required.

## Scoped Agent discussion

An issue can open a dedicated private, tracking-paused Agent conversation. Its
encrypted binding survives issue deletion: an old conversation cannot silently
become an ordinary chat with unrestricted routing. Reopening an active bound
conversation preserves its history. No model request is made merely by opening
the conversation.

Each submitted question previews the concern snapshot and the concrete selected
model. Auto resolves a candidate before confirmation. The approval is bound to
the conversation, turn, issue revision, privacy and review-setting versions and
destination fingerprint. Cloud endpoint, API style and effective model are checked
again at the disclosure boundary. Desktop pairing identity is checked separately
from the frozen model invocation. Fallback to another destination is not implied.
Approval expires after one hour and must be renewed with another submitted question.
Local review permission does not grant online analysis permission.

Only this issue and the private discussion history are included; unrelated memories,
original attachments, screen state and other health records are not supplied to
initial planning. New health files must first be imported and confirmed in Personal
Health. Public research is scoped to search/fetch and tool inspection, with generic
clinical terms requested in the prompt. Search services may receive those terms.
Native invocation authorization is retained by registry subsets and runs before
effect replay. Discussions cannot mutate measurements, schedule reminders, send
messages, inspect unrelated local data or delegate to another model. The only
additional local mutation is a pending-plan submission; it is not user acceptance
or a delivered reminder.

This does not yet implement a clinical evidence validator. Explicitly scheduled
action reminders are separate from model proposals, as described below.
Transport already submitted to a remote
provider cannot be retracted by revoking a permission. Further requests are checked
again; in-flight cancellation and background recovery require end-to-end acceptance.

## Proposed plans and explicit review

`galaxyssi.health.plan.propose` retains one immutable, replay-safe draft per
approved discussion turn. The phone binds the draft to the actual conversation,
grant, concern revision and source clock; the model cannot supply these identities
or a confirmed state. Action IDs are deterministic. The encrypted `plans` table is
separate from concerns so submitting a proposal does not invalidate the current
model turn, change the concern, or activate a deadline. Database schema 3 upgrades
schemas 1 and 2 without rewriting existing encrypted data. Pending pages are
bounded to 30 records; resolving or dismissing them exposes older drafts without
total-history truncation.

The Agent main page and concern details offer the same review dialog. No action
is preselected. The dialog shows uncertainties, model provenance, source version
and population, and any explicit review window. Model citations are labelled as
not independently verified; user acceptance does not certify their clinical
accuracy. Unsupported optimal targets and medication orders are not structured
plan operations. Clinical content validation still requires further work.

Acceptance appends only selected actions and records a concern revision in the
same transaction that resolves the draft. Cancel leaves the draft pending;
dismissal adds nothing. Duplicate delivery cannot append actions twice. New source
data, changes to context, permission/settings versions, pause, deletion and expired
review windows prevent stale acceptance. Source clocks are read immediately before
the care transaction; measurement and care databases are separate, so a concurrent
later measurement is reconciled as a new assessment rather than a cross-database
atomic snapshot. Recheck items enter waiting-for-results; other items do not claim
that a medical test is pending. No target or normal/stable state is inferred.

Review views are dismissed on backgrounding, conversation changes and observed
record/permission changes. Persistence and validation run off the UI thread.
Stored plans remain encrypted across process restarts. Deleting a concern also
deletes its draft payloads while retaining the existing protected conversation
binding. Saving a plan does not schedule an alert; notification scheduling is a
separate user action.

## Action follow-up and reminders

The Agent main-page surface and concern details share action follow-up controls.
Users can pick a reminder date and time, postpone or cancel that reminder, and
record an action outcome. Date/time selection requires a final confirmation.
Reminder time is independent of the medical review window; selecting a time
outside that window warns without rewriting the recommendation.

Confirmed actions retain a fingerprint of the source snapshot and measurement
context. Older actions without that provenance remain readable but cannot be
armed automatically. New readings, context changes, deleted sources, revoked
permissions, paused tracking and disabled local review invalidate old reminders.
Re-enabling a permission does not resurrect them. An unrelated conversation
revision does not invalidate an otherwise unchanged action. Fresh clinical
recommendations still require a new scoped discussion and plan review.

Schema 4 adds per-action encrypted reminder rows with authenticated indexed
identity, generation, state and due time. An action has one current reminder;
postponement rotates its generation so a delayed prior delivery cannot mark the
new schedule as delivered. Completion records a nonempty user-reported outcome,
cancels that action's reminder in the same transaction, and enters reassessment
without declaring normality, stability or maintenance. Other actions remain open.

Delivery uses the existing health-reminder alarm, WorkManager reconciliation and
boot/startup recovery paths. It respects system notification access, the health
notification opt-in, quiet hours and pause-until settings. Blocked system delivery
remains visible in-app and does not busy-poll. Due records use bounded indexed
pages; no historical-total truncation is introduced. Notifications contain only a
generic action-review notice, with no measurement, action text or health result.
Their public lock-screen version remains generic. A posted notification is not a
read receipt. Ordinary Android inexact/background scheduling can defer delivery;
this is not an emergency alarm service.

Notification posting and SQLite acknowledgement are not a distributed transaction.
Reconciliation uses a stable per-action notification identity and only-alert-once
updates, and rechecks scope before posting. A crash between posting and recording
delivery may recreate a dismissed notice; exactly-once human delivery is not
claimed. Database reopening and deterministic replay tests do not replace physical
reboot and operating-system delayed-delivery acceptance.

## Native evidence provenance

Health research reuses the existing bounded, certificate-checked phone web tools.
Only successful native `galaxyssi.web.intelligence.search` or `.fetch` results
containing retrieved bodies can create health read receipts. Discovery snippets,
model-authored URLs/hashes, failed fetches and malformed manifests cannot. The
receipt binds the approved conversation/turn/concern revision to the actual URL,
source title, body hash, reading-window excerpt, retrieval time and observation
time. Cache age remains visible and is never presented as a publication date.

Schema 5 adds indexed, individually encrypted evidence rows. Recording a read does
not revise a concern or invalidate its in-flight discussion. Replay cannot rewrite
a receipt. A new plan must reference receipts from that approved turn and include
a short exact original-language supporting passage. Whitespace normalization is
allowed; paraphrases, translations, omitted clauses and unrelated sources are not
accepted as verbatim support. Compacted observations retain the source-to-receipt
identity instead of silently losing the reference needed for plan submission.
The executor-to-planner compaction path preserves that identity across repeated
passes. Health reading windows use the remaining bounded observation budget for
an exact contiguous excerpt, rather than the 500-character search-preview cap.
Truncation is explicit and the existing total prompt budgets remain unchanged.
Different passages or reading windows from the same URL may support different
actions. Source uniqueness uses URL, receipt ID and quote, not URL alone; identical
receipt/quote entries remain invalid. Each action retains its own supporting quote.

The opt-in `HealthCareLiveResearchDeviceTest` exercises paired Desktop reasoning,
phone HTTPS retrieval, native receipt-backed draft storage and a Chinese follow-up
using synthetic data in isolated health databases. It reuses production planning
prompts, parsing and compaction; it does not replace Activity consent, full runtime
recovery or clinical acceptance. It changes no provider credentials or settings,
does not confirm plans or schedule reminders, and bounds paid test execution only.
Its local report must be pulled outside the repository and never uploaded.

Plan persistence resolves references from the native store rather than trusting
proof supplied by a model. Accepted actions retain their evidence IDs and quoted
passages, available from follow-up controls on both Agent main and Personal Health.
Deleting a concern removes its evidence rows. Existing records remain readable;
legacy pending plans without receipts need an updated research turn before they
can be accepted. Existing actions without evidence fields keep the same serialized
form so this upgrade does not invalidate otherwise unchanged reminder anchors.

This is retrieval/quotation verification, **not** medical validation. A passage can
be real yet irrelevant, outdated, contradicted or unsuitable for a person's age,
pregnancy, medications or diagnosis. Version and applicability fields remain model
claims. The UI explicitly distinguishes these from native retrieval timestamps.
Research must assess authoritative sources, population, conflicting evidence and
uncertainty; professional review, real-provider research/reassessment and clinical
acceptance remain required. A read receipt must never be advertised as proof that
a health recommendation is safe, correct or personally applicable.

## Individually reviewed targets

The existing phone-only `galaxyssi.health.plan.propose` tool accepts an optional
`target_proposal` alongside zero to eight actions. A draft names one required
measurement component, exact bounded decimal limits, explicit inclusive/exclusive
bounds, the current measurement unit, rationale, a native source receipt and
individualized applicability checks. Empty action lists require a target proposal.
The model cannot set confirmation fields, replace the current target, schedule
reminders or declare a stable outcome. Screening criteria and reference midpoints
must not be manufactured into treatment targets.

Agent main and Personal Health use the same pending-plan review. Target selection
starts unchecked and is independent of action selection; unresolved applicability
or a mismatched unit/component blocks target adoption. The native transaction
records user confirmation, not clinician approval, along with the source-bound
proposal ID and current report/context basis. A replacement uses a new approved
discussion turn and explicit confirmation. Encrypted concern history retains both
versions. The target review offers the existing scoped Agent discussion and a
separately confirmed revocation; revocation preserves reports and returns to
reassessment without changing medications.

Target revisions participate in action/reminder anchors. Changing or revoking a
target cancels stale reminders and requires action review. The monotonic revision
prevents revocation from making pre-target actions eligible again. Unchanged
concerns without targets retain their existing reminder hashes. New JSON fields
are optional when reading legacy encrypted records; legacy targets remain visible
but require review before comparison. No database schema rewrite is necessary.

Numeric comparison is limited to the stated component and confirmation basis.
Different report/context versions retain the target as historical context and
request review rather than silently reapplying it. A value inside the bounds does
not establish clinical improvement, stability, maintenance or completion. This
implements target proposal and review infrastructure, not clinically validated
target generation.

## Reviewed maintenance and reassessment

The same scoped plan tool accepts an optional `maintenance_review`: rationale,
source index, individualized applicability, exact consecutive record IDs/revisions,
and the index of a proposed future `RECHECK` action. `CURRENT_TARGET` requires an
already reviewed target on the current evidence basis. `RISK_REVIEW` permits
source-backed follow-up without inventing a numerical target, but cannot bypass
an existing target. A target change and maintenance cannot share a proposal.

The native gate requires a contiguous prefix of the current bounded history page,
including the latest result and distinct measurement times. Two records are only
a structural minimum, never a clinical stability criterion. A truncated page
boundary cannot certify a complete observation window; larger windows currently
need further review, not an invented whole-archive conclusion. Differences in
units, source, reference interval or collection conditions, unconfirmed glucose
context, unresolved applicability, priority warnings, or unfinished prior actions
prevent adoption. Method agreement still lacks independent clinical validation.

Both Agent main and Personal Health present the proposal, evidence window,
limitations, source receipts and next assessment. Maintenance is an independent,
initially unchecked choice and also requires selecting the future reassessment.
Confirmation atomically records the proposal identity, user review, action and
evidence basis in the encrypted concern history. It does not certify clinical
stability, close tracking, cancel existing actions, or authorize notifications.
Reminder scheduling remains a separate user action with existing quiet-hour and
privacy rules. Reviewed evidence remains accessible after acceptance.

Source or target changes, action completion and the next reassessment window
return the concern to reassessment, preserving the earlier decision. An explicit
reassess action is also available. The deadline check runs even when measurement
evaluation is cached. An earlier accepted action also reopens review so its due
time cannot repeatedly wake a still-maintained concern. The existing reminder scheduler carries the next deadline
without posting an unauthorized notification. Reopening encrypted databases and
reconciliation recover the state, but OS scheduling is inexact and is not an
emergency-monitoring guarantee. Paused tracking stays paused. Legacy maintenance
states without a structured review reopen for reassessment rather than silently
acquiring new evidence or authority.

These are workflow and provenance checks. Quotation verification, numerical
agreement and user confirmation are not a professional medical assessment.
Clinical validity, wider longitudinal review and autonomous authorized research
still require separate acceptance; no medication change is supported.

## Authorized research and background execution

Care schema 7 adds separately encrypted, authenticated standing authorizations
and research jobs. Existing installations receive empty tables, not implicit
consent. An authorization binds one concern, its private conversation, privacy
and settings revisions, provider destination, model, effort and configuration
fingerprint. Every execution still requires a fresh, separately persisted turn
grant. A standing authorization does not confer record-writing, reminder or
clinical-plan confirmation authority.

An indexed unique key admits one turn per authorization and evidence trigger.
New source versions, confirmed context, target revisions, action outcomes and
newly due confirmed actions change that trigger. Display revisions, opening a
conversation, proposals and repeated clock ticks do not. Failed or completed
turns are not automatically recreated for the same trigger. Updates use exact
expected-state checks, and the durable turn ID survives database reopening.
Queue reads are paginated rather than loading every historical job.

Pausing or closing a concern, losing its source, disabling care, replacing or
revoking authorization cancels its unfinished jobs. Deleting a concern removes
its authorization and research detail, retaining encrypted routing tombstones
and a durable cancellation outbox so late results cannot revive deleted data.
Scoped history reads, evidence
receipts and plan writes revalidate automatic-turn authorization; ordinary
explicitly approved discussion turns retain their existing contract.

The Agent surface and concern detail expose a shared consent/status dialog.
The current provider, model, effort and snapshot are disclosed before a separate,
initially unchecked consent checkbox can authorize future calls. Opening the
dialog, enabling local tracking and approving a one-off discussion do not enable
automatic research. A failed review requires explicit renewed authorization to
try the same evidence again. Backgrounding clears the dialog and its content.

Source changes, privacy/model changes, startup recovery and the next confirmed
action deadline enqueue WorkManager reconciliation. Online calls require a
connected network. Per-turn unique work, a recovery claim and the task journal
reuse one identity. The normal MobileNativeAgent executes the pinned scoped
planner; connector responses use the existing delivery and transcript recovery
path. Recovery waits for an existing request, rather than resubmitting it. An
interruption without a recoverable execution checkpoint is exposed as a failure
instead of guessing whether it is safe to send again. No medical data is placed
in WorkManager input or a notification.

Automatic reviews include a structured trigger handoff. An indexed query finds
the previous completed review for the same concern and conversation, and loads
its exact encrypted concern revision. The handoff distinguishes new/corrected
measurements, history/context/target changes, action feedback, newly due actions
and authorization-only review. It uses the durable run timestamp, not the clock
at every prompt reconstruction. A missing prior revision is explicitly unknown;
it cannot be described as unchanged. Manual discussions do not acquire this
automatic trigger field.

The model should lead with the triggering change, continue existing actions and
reuse previously verified sources with their dates and limits. A deadline without
new results calls for progress, results or barrier follow-up, not an automatic
repeat of the entire search or a replacement plan. New evidence, applicability,
unresolved questions or source freshness may still justify retrieval. This is
context for the model, not a keyword command router or a ban on further research.

The handoff also contains up to eight source-body excerpts from completed automatic
reviews of this concern. Retrieval uses the existing concern/review indexes,
checks the encrypted grant's conversation, destination, settings and privacy,
and retains original retrieval timestamps. Excerpts are bounded at 1,000 characters
and explicitly marked when truncated. These are historical context, not medical
applicability checks or receipts that can authorize a new plan. An intervening
progress-only review does not erase the earlier source context. Bundled guideline
links are starting citations, not evidence that a source body has been read.

Both manual and automatic discussions also receive a bounded `clarification_context`
with saved answers and unconfirmed fields for the exact measurement revision. Negative
answers and zero fasting hours are known values, not missing data. A fasting label
does not establish an exact duration. Context from another measurement or revision
is not reused as current. The model acknowledges relevant saved facts and asks only
material unresolved questions, rather than repeating the entire form. Reconfirmation
requires an explicit conflict or change. Current symptoms are not inferred from old
measurement-time answers, and an unconfirmed field is never automatically filled in.
This handoff does not expand access to separate profile records or other metrics;
their absence in the payload must not be described as the user having no such data.

Avoiding duplicate research must not suppress the first source check after missing
measurement context is clarified. New plans still require current-turn retrieval
receipts and explicit user review. Retrieval failure is an evidence gap, not an
excuse to claim that a bundled citation has been verified.

Research progress is distinct from transport completion. The handoff reports
available prior source context, whether any plan has been recorded, and the
actual action count. A completed response with none of these does not complete
initial source review. Once essential measurement context is available, this gap
still warrants focused research without waiting for another laboratory result.
Plan existence includes dismissed plans, so an empty action list cannot silently
recreate a declined proposal. Existence does not imply acceptance or applicability.

The opt-in real-provider acceptance supports `health_research_phase=recheck` once
per APK version on the same synthetic concern and conversation. It preserves all
earlier failed review turns, renews only the synthetic authorization, and retains
the source-receipt and pending-plan assertions. Use `verify` to inspect the same
result without scheduling another review. These phases do not clear user data.

Cold-start reconciliation keeps a connector wait admissible when its saved
action and durable source-message receipt agree. It does not convert that wait
into a user pause or redispatch the request. This check uses saved action and
receipt state, not marker text that may have disappeared from a compacted plan.
A previously paused checkpoint can
be repaired only when its existing workspace still awaits a reply; explicit
user pauses, cancellation and terminal states remain excluded. Native actions
without a remote receipt retain interrupted-execution handling. Reply identity
checks still run before and after acquiring the workspace recovery lease.

Revocation immediately invalidates the scoped tool grant. Background cancellation
also stops the local workspace/cloud lease and queues remote cancellation when
a connector receipt exists. An offline remote cancellation remains pending with
WorkManager backoff. Previously transmitted data cannot be recalled. Foreground
and background transcript projections both reject cancelled or obsolete research
turns. These mechanisms do not guarantee immediate termination of a remote
provider that has already accepted a request.

No background research is enabled merely by schema migration. Real-provider
end-to-end acceptance, including device restart during an automatic review,
remains separate from the isolated storage, policy and UI regression suite.

### Production-path acceptance runner

`HealthCareClarificationLoopDeviceTest` exercises the question/answer continuation
with a real paired model and production workers. Select
`-PhealthResearchAcceptance=clarification`, `HealthClarificationAcceptanceRunner`
and `health_clarification_loop=true`. Its isolated synthetic glucose reading has
reviewed measurement context except fasting duration. The `answer` phase requires
the model itself to retain the missing-duration question, then submits a synthetic
reviewed answer through the ordinary question-review store. It must not directly
launch the next research task or overwrite the measurement's structured context.

After saving the follow-up's waiting-response checkpoint, `resume` requires a new
process and continuation in the original private conversation. The reviewed answer
must remain current and not be offered as an open question. Repeating the same
reviewed answer must not create a third research turn. Original measurements,
negative answers and earlier assessments are retained; no action, target or reminder
is accepted automatically. The `inspect` phase exports only this isolated synthetic
scenario for local response inspection. Programmatic identity/state checks are not
semantic or clinical validation; the actual model replies must also be inspected.
This store-path acceptance does not replace the locked device's pending UI tests.

`HealthCareActiveRevocationDeviceTest` tests withdrawal during real paired-provider
execution. Build the test APK with `-PhealthResearchAcceptance=revocation` and use
`HealthRevocationAcceptanceRunner` with `health_active_revocation=true`. Its
`health-revocation-acceptance-` storage also isolates the connector inbox. The
`revoke` phase waits for a real durable request receipt, disables online analysis
through the ordinary privacy store, and observes production cancellation rather
than cancelling the workspace directly. It requires a persisted cancellation,
retired outbox, terminal delivery marker and preserved synthetic source/conversation.

The `resume` phase requires a new process identity, restores the same cancellation,
reenables the isolated online setting and observes the resulting reconciliation.
The old standing authorization must remain revoked and must not create another
research turn. Both phases inject a clearly synthetic late final reply using the
original request identity through the encrypted inbox and background delivery
path. That reply must be retired without rebuilding a model runtime, writing a
model assessment, adding plan actions, committing reply text or creating attention.
This fault injection is not a claim that a real provider returned after cancellation
or that the remote provider erased already transmitted data. An outbox receipt
only proves local transport acceptance, not remote-provider termination.
The `inspect` phase only reads state. Interrupted attempts retain records and
markers; they do not clear data or silently replace a completed/failed request.

`HealthCareAutomaticRelatedDeviceTest` adds an independent, opt-in production
acceptance scenario. Build its test APK with
`-PhealthResearchAcceptance=related`, then run the
`HealthRelatedResearchAcceptanceRunner` with `health_automatic_related=true`.
Its `health-related-acceptance-` namespace isolates application, WorkManager,
health records, conversations and task storage from both real user data and the
older acceptance scenario. Only the existing pairing and live Signal ratchet are
shared; they are never copied or rolled back.

The `start` phase saves a real waiting-response checkpoint. A subsequent `resume`
phase requires a different process identity and continues that original turn.
It then saves a changed, authorized measurement through the normal record store,
without manually launching another research job. The normal workers must deliver
a new structured review in the same conversation. An unselected metric is then
saved and fully reconciled; the existing authorization must still have exactly
two research turns. Neither review may accept actions, targets or reminders.
The `inspect` phase only diagnoses saved state. Durable markers retain the same
records and turns across interrupted attempts; failures do not reset the probe.
After an initial review has actually terminated, `recheck_start` explicitly renews
the synthetic consent once per App version and retains previous reviews. It is
not an automatic retry of a running or unobserved task.
This is a process-recovery and integration test, not proof of physical reboot,
long-term clinical outcomes or complete UI acceptance.

The Agent landing surface shows a compact reason, workflow next step and direct
discussion entry. Detailed plan, reminder, target and history controls expand
inside a height-bounded scroll area instead of consuming the reply viewport.
The display follows the current authorization and evidence trigger; an old
completed review cannot describe a newer measurement or newly due action as
already reviewed. A pending proposal remains separate from accepted actions.
One foreground callback refreshes the next deadline even without another data
event; it is removed on pause and is not a periodic background poll.
Opening the private discussion does not authorize a model call. Backgrounding,
conversation changes and privacy revocation clear the relevant visible state.

`HealthCareAutomaticResearchDeviceTest` is an explicitly opted-in, paid-provider
probe. Build the instrumentation APK with `-PhealthResearchAcceptance=true`,
which selects `HealthResearchAcceptanceRunner`, and run it with
`health_automatic_research=true`. Default builds retain the normal test runner.
It uses the normal authorization,
WorkManager, MobileNativeAgent, scoped tools and transcript-delivery code rather
than a test-owned model/tool loop. The `start` phase waits for the durable
connector receipt; after ending that application process, the `resume` phase
requires a different process identity and the original research turn. The
`full` phase performs a continuous execution without injecting an interruption.
The initial synthetic record deliberately lacks collection context. After its
original response is recovered, the probe confirms synthetic context through
the same store and evaluation path as the review UI. Existing authorization
must react with one new turn that retrieves durable source evidence and leaves
a pending plan, without adopting actions or scheduling reminders. Both turn IDs
survive further test-process restarts. The `inspect` phase only diagnoses the
existing isolated job and receipt admission; it does not submit a new request.

The `followup` phase extends a completed `full` or `resume` run without replacing
its synthetic archive. It renews synthetic consent for the same selected model,
waits for a durable in-flight connector receipt, then saves a new reading through
the normal record store. Record notifications, not a test-owned dispatch loop,
must reassess the original concern and schedule a new turn in its original
conversation. The obsolete turn must no longer project a response. Previous
collection context remains attached to the old measurement; the new measurement
requires its own confirmation. After that confirmation, normal research must
retain source receipts and a pending proposal without adopting actions, targets,
maintenance, closure or reminders. The test revokes its renewed consent on
success. Durable phase markers permit inspection and resumption without inserting
duplicate synthetic readings. Same-day synthetic readings do not establish
clinical improvement, a long-term observation period or physical reboot coverage.

The `outcome` phase continues that archive with a separate explicit review of one
eligible synthetic plan action. It renews scoped consent, waits for an in-flight
receipt and records a difficulty carrying out the action through `finishAction`,
the same store entry point used by the outcome UI. No new reading or user chat
message is inserted. Normal change notifications must initiate reassessment in
the existing conversation, preserve the recorded limitation and leave another
source-backed proposal pending. The completed action is not proof of clinical
improvement; no target, maintenance state, closure, additional adopted action or
reminder may appear. Its consent is revoked on success. Durable markers support
replay without recording the outcome or submitting the request again. This does
not substitute for a real elapsed clinical review window or multi-day follow-up.

The `surface` phase uses that isolated archive to exercise the production Agent
landing entry, rather than a fixture-only view. It opens an unrelated temporary
private conversation, taps the health discussion entry and verifies reuse of the
original private health conversation without renewing research consent. It needs
an unlocked display, does not send another provider request, and removes its
temporary conversation afterward.

The `deadline` phase follows the completed outcome review. It renews consent for
the same synthetic archive and destination, lets the initial review finish, then
adds an explicitly synthetic confirmed action with a future deadline. It verifies
that production WorkManager reconciliation enqueues the deadline before it is
due. The test then only observes: it does not invoke reconciliation, insert a new
reading, send a user message, or open an Activity to trigger the follow-up. The
deadline must yield one additional research turn and a substantive answer in the
original private conversation. If the model proposes another plan, that draft
must be source-backed and pending. A focused progress question can be appropriate
without new measurements; response quality still requires reading the actual
answer rather than treating transport assertions as semantic validation. It cannot
complete the action, manufacture a measurement, adopt a target, schedule a
notification, or close the concern. Durable markers support replay without a new
deadline or provider request; consent is revoked on success. The 45-second window
is a scheduler acceptance fixture, explicitly not a clinical review interval or
proof of real multi-day follow-up.

An optional `health_deadline_run` selects fresh phase markers while preserving
the original synthetic archive and conversation. `health_deadline_step=prepare`
waits for the initial review to finish, persists a five-minute synthetic deadline,
and records the device boot count and process identity. After an explicitly
authorized device reboot, `health_deadline_step=resume` requires a higher boot
count and a different process, then observes normal WorkManager restoration and
delivery without manually reconciling the concern. Existing actions are hashed
before scheduling and compared after completion; only the new synthetic action
may have been added. No real personal health data is copied into this probe.
Because this isolated namespace is initialized by its instrumentation runner,
this tests device-reboot persistence followed by application initialization, not
unattended delivery before that namespace is opened. Do not report it as proof
of production boot-only startup or a multi-day clinical follow-up.

The runner redirects databases, task files and non-pairing preferences into a
dedicated acceptance namespace before the application and workers initialize.
It asserts the care, transcript and WorkManager database locations before
creating synthetic data. Existing contacts, transport pairing and the live
Signal ratchet remain shared: never clone, restore or roll back ratchet state.
No personal health archive or transcript is copied into the sandbox. The runner
is part of the instrumentation APK only, not the shipped application.

Run this probe sequentially while other device testing is stopped. Inspect and
retain its encrypted synthetic state locally until any queued work is terminal;
do not clear a live namespace merely to rerun a failed test. Restart the normal
application after the probe so its normal background scheduling is restored.
These probes do not replace consent-UI, clinical-validity or real-device-reboot
acceptance, and a passing storage test is not evidence that the model completed
an autonomous research task.
