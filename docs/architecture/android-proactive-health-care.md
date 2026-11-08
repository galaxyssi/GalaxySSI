# Proactive health care

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
- Let the Agent propose lifestyle actions, clinician discussion items and
  justified follow-up windows, with user confirmation before scheduling.
- Deliver durable due reminders with deduplication, permission-aware lock-screen
  privacy, restart recovery, snooze and subsequent-result reassessment.
- Implement clinically reviewed urgency handling separately from routine advice,
  individual targets and maintenance review, without promising all-danger detection.
- Verify broader measurement/risk-context coverage, lab-method comparability,
  source deletion, backup/restore and privacy revocation across active model calls.
- Complete real-provider, isolated-device, process-restart, scrolling and
  accessibility acceptance of the entire workflow.

Local tests and a native overview alone must not be used to mark this goal complete.

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
effect replay. Discussions cannot mutate records, schedule reminders, send messages,
inspect unrelated local data or delegate to another model. A proposed improvement
or follow-up window is not a durable care plan or a delivered reminder.

This does not yet implement a clinical evidence validator, automatic due delivery,
or the complete plan-confirmation workflow. Transport already submitted to a remote
provider cannot be retracted by revoking a permission. Further requests are checked
again; in-flight cancellation and background recovery require end-to-end acceptance.
