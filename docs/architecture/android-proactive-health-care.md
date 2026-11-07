# Proactive health care

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
pages on the phone. The host, not model parameters, supplies the concern, metric,
self profile and granted turn. Every page checks source clock, concern revision,
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
