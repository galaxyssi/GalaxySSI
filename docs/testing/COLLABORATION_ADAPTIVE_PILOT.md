# Adaptive Collaboration Pilot

## Purpose

The older paired engineering fixture supplies a draft/review/final graph and
replaces its prompts. It cannot demonstrate that a team chooses useful work or
changes its plan. `CollaborationAdaptivePilotDeviceTest#runAdaptiveRemotePilot`
instead starts the production research coordinator with a goal and member
roster. Production goal admission, live graph expansion, dependencies, goal
acceptance and checkpoint advancement choose the executable work.

The fixture does not invent assignments, replace prompts, rewrite member
transport identities, force acceptance, or force past coordinator backoff.
It uses the existing Android -> paired Desktop -> Codex execution path and the
explicit model/effort selected in an App conversation. These are trial inputs,
not production defaults. New work is admitted only while that selection matches.

This is a production-kernel integration trial, not a complete UI/service
lifecycle test. The fixture advances saved rounds directly rather than invoking
the production screen controller. It does not establish process-restart or Doze
recovery, resource isolation, equal cost, scientific novelty, or capability gain.

## Private Protocol

Keep goals, trial protocols, raw reports, rubrics and paper data outside Git.
The input JSON has exactly these fields:

- `format`: `galaxyssi.adaptive-collaboration-pilot.v2`
- `pilot_id`: fresh safe identifier, never reused after a trial starts
- `device_model`: one exact authorized Android `Build.MODEL`, not a wildcard
- `target_id`, `model_id`, `reasoning_effort`: exact App selection
- `tool_scope`: `production_tools_not_isolated`
- `goal`: complete user goal; oversized inputs are rejected, not shortened
- `trial_timeout_ms`, `maximum_dispatches`: operator-authorized trial envelope
- `members`: two or more distinct `id`, `name`, `role` objects

No answer keys, scripted work graph, tool permissions or fixed research rounds
are supplied by this schema. Arbitrary goal text is still operator-provided
material; the schema alone cannot certify absence of hints or contamination.
Freeze the protocol before execution and record all mentor interventions.

## Invocation

Install matching debug App and instrumentation APKs only on the authorized
phone. Instrumentation can restart the App: inspect current work first. Prepare
an explicit selection using the normal App store as documented in
`COLLABORATION_REMOTE_PILOT.md`. Do not change global defaults.

Required instrumentation arguments:

- `adaptiveRemotePilot=true`
- `pilotDeviceModel=<same exact model as the frozen protocol>`
- `remotePilotTools=production_tools_not_isolated`
- `adaptivePilotInput=<safe-basename>.json` in the App external-files directory
- `adaptivePilotSha256=<frozen input SHA-256>`
- `adaptivePilotMaxDispatches=<separately authorized phone dispatches>`
- `adaptivePilotMaxMillis=<separately authorized trial milliseconds>`
- `remotePilotSelectionConversationId=<App selection conversation>`

Before reserving a report, creating a conversation, connecting MQTT or calling a
model, the fixture requires the connected `Build.MODEL`, operator argument and
hash-bound protocol `device_model` to agree. Select the actual device using
`adb -s <verified serial>`; a model name does not uniquely identify a phone.
Changing phones requires a fresh authorized protocol and fresh pilot ID, not
editing an old report or silently migrating a v1 protocol. The fixture has no
product-wide device allowlist and its parameters do not grant user permission.
Other legacy live fixtures retain their existing device restrictions.
The conversation-scoped preparation helper also requires the exact operator
device. Preservation checks observe persisted window selections without reading
or changing the legacy first-active-conversation fallback.

The envelope is a test-resource bound, not a production autonomy stop rule.
One phone dispatch may cause multiple provider requests, tool calls and charges.
Provider usage and billed cost remain unknown until complete receipts are joined.
Do not label dispatch equality as equal compute or equal cost.

## Evidence And Cleanup

The report marker is reserved before dispatch. Every admitted action is bound to
the current persisted graph, parent, turn, task, node, model and idempotency key.
Reservation is recorded before remote I/O; a failed journal write consumes the
reservation rather than permitting a duplicate side effect.

Reports preserve original goal/context, member assignments, full worker results,
all archived execution records, prompt hashes and final pending-owner state.
Graph settlement, host goal acceptance, observable blocking, timeout and the
phone-dispatch envelope are separate outcomes. Even host acceptance is not an
independent external evaluator's proof of success.

At the trial boundary only this dedicated run receives STOP. Remote-stop recovery
must confirm an inactive local handle and no pending managed response before
removing its test conversation and execution database. Otherwise retain state
for inspection. The user's active conversation and unrelated research are not
changed. Reports remain available after successful cleanup.

### Reconcile A Retained Stopped Trial

`CollaborationAdaptivePilotCleanupDeviceTest#reconcileStoppedTrial` is a separate,
explicitly opted-in post-trial check. Use it only for an already stopped trial
on its original authorized device. It never resumes the run, admits model work,
deletes evidence, clears managed-response records manually, or changes the
original trial verdict. It uses production stop recovery and waits for terminal
receipts. A later empty pending-owner ledger does not make a failed trial pass.

In addition to the original `pilotDeviceModel`, `adaptivePilotInput`,
`adaptivePilotSha256`, `adaptivePilotMaxDispatches` and `adaptivePilotMaxMillis`,
provide:

- `adaptivePilotCleanup=true`
- `cleanupReportInput=<original-report-basename>.json`
- `cleanupReportSha256=<original report SHA-256>`
- `cleanupMaxMillis=<1..120000>` for this receipt-only observation
- `cleanupOutput=<fresh-basename>.json` for the separate follow-up record

The helper validates both input hashes, the exact device, run and conversation,
the retained checkpoint, and STOP in both the original report and durable
control store before network activity. It refuses to overwrite an existing
follow-up record. Keep that record beside, not instead of, the original report.
`cleanup_confirmed` describes only the pending-owner ledger at the follow-up;
the checkpoint and test conversation remain available for inspection. The
window-selection preservation assertion remains mandatory.

## Instrumentation Verdict

Saving a report is not a passing test. After evidence capture and cleanup, the
instrumentation requires host goal acceptance, a recorded phone dispatch, an
intact worker result bound to an admitted node, an accepted final checkpoint,
confirmed remote cleanup, and an unchanged active conversation. Exceptions,
timeouts, undispatched trials, exhausted envelopes, blockers, incomplete
reports, and cleanup failures fail the test even when a report was saved.

The report includes `test_verdict` and `test_failures` before the final assertion.
Execution exceptions remain attached as the assertion cause. Negative and
interrupted reports are still useful research evidence, but must not be counted
as passing integration tests. A passing host-level test still does not establish
scientific quality, capability growth, or external-evaluator acceptance.

## What To Evaluate Next

Read the real trajectory, not just its duration: did the team discover the
actual problem, challenge competing explanations, perform discriminating tests,
adapt work to observations, preserve negative evidence, and produce a reusable
method? These are questions, not fixture-generated scores.

Subsequent independent trials must measure unseen-task transfer, retention and
quality against strong single-agent and mentor-assisted baselines. This pilot
does not replace the full longitudinal experimental design or justify calling
GalaxySSI superintelligent.
