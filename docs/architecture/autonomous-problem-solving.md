# Autonomous problem solving

## Objective and acceptance

GalaxySSI must pursue a user goal through obstacles, not just execute a fixed
script or return the first tool error. This includes navigating websites,
logging into an authorized account, operating its pages and collecting the
requested information. The reasoning provider chooses diagnostics and repairs;
the host supplies truthful observations, durable execution and resource isolation.

The complete goal requires all of the following, not merely passing unit tests:

| Requirement | Evidence required |
| --- | --- |
| Model-owned diagnosis and method changes | Real-provider runs with injected, previously unspecified obstacles; original goal retained |
| Failures returned as observations | Tool, planner and connector regressions; actual error and receipt visible to the next model turn |
| Repair followed by verification | Originally blocked operation succeeds or observed evidence proves an alternative achieved the goal |
| Website login and operation | Real rendered browser, test account, login expiry, changed controls, pagination and extraction verified against server state |
| User-only authentication handoff | OTP/CAPTCHA handoff and resume without restarting the goal or exposing credentials |
| Continued execution and interruption | Process loss while diagnosing and while acting; committed effects not repeated |
| Multi-agent recovery | One specialist fails, coordinator changes the plan while preserving successful independent work |
| Progress and responsiveness | User sees selected action, outcome and changed approach; UI remains responsive |
| Scope and confidentiality | No cross-conversation/account leakage; website instructions cannot authorize operations |
| Generality | Coding, dependency, network, research and browser cases; no website-name or goal-keyword repair rules |

## Research basis

- [ReAct](https://research.google/blog/react-synergizing-reasoning-and-acting-in-language-models/): interleave reasoning, actions and environmental feedback. We apply the feedback-loop principle, not a requirement to expose private reasoning.
- [Reflexion](https://openreview.net/forum?id=vAElhFcKW6): use feedback from failures to improve later attempts. A stored hypothesis is not proof; repairs still need external verification.
- [Building effective agents](https://www.anthropic.com/engineering/building-effective-agents): distinguish model-directed agents from predefined workflows and give tools clear interfaces and real environmental feedback.
- [Effective long-running harnesses](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents): maintain progress across context windows and check actual outcomes rather than relying on a completion claim.
- [Managed agent architecture](https://www.anthropic.com/engineering/managed-agents): separate the durable session, reasoning harness and execution environment. Choosing Codex for reasoning does not select Desktop execution.
- [Agent evaluations](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents): evaluate the trajectory and final environment state. Scripted responses only validate framework mechanics.
- [Playwright actionability](https://playwright.dev/docs/actionability) and [authentication](https://playwright.dev/docs/auth): ground actions in current controls, wait for actionable state and protect reusable authenticated state.

These sources inform the design; they do not establish that GalaxySSI already
implements their full behavior or achieves their reported results.

## Current evidence and changes

The repository already has `AgentModelToolLoop`, encrypted per-operation
checkpoints, native tool receipts, rolling ActionPlans, resource-level execution
and phone Chrome/accessibility operations. Public `browser.session.*` navigation
is not equivalent to a full authenticated interactive browser.

The first implementation changes:

- New model loops receive one provider-independent problem-solving contract.
  New journals pin that exact contract in their initial messages. Pre-upgrade
  journals retain their exact prior messages so replay bindings do not drift.
  Phone ActionPlan prompts use a compact recovery contract in their cached
  prefix, rather than repeating the full tool-loop instructions. Planning and
  continuation prefixes remain bounded at 5,800 and 3,500 characters respectively,
  excluding the tool inventory and dynamic evidence.
- Repeating a mutating operation without another observation produces a tool
  rejection for the model to diagnose, rather than terminating the goal. A
  rejection itself does not manufacture a new external observation and unlock
  another execution. Truly read-only tools may re-observe changing state.
- Safe automatic read retries retain earlier failed receipts in the resulting
  tool evidence; the model no longer sees only the last successful retry.
- `non_retriable` no longer suppresses the whole ActionPlan's recovery decision.
  It still prevents blindly retrying the failed connector resource. Existing
  model settings, scope constraints, cancellation and effect claims remain.
- Stale phone controls return structured current-frame information without
  acting. Rejected UI operations retain diagnostic fields. Back navigation
  returning false is a failure, not a successful result. Accepted controls
  explicitly do not prove the business outcome.
- Phone inspection tools are explicitly read-only, without changing their
  serialized public catalog contract.
- Model context compression retains the original goal and latest user request,
  the latest failure, uncertain effects and live operations. Shrinking keeps
  continuation identifiers, error status and receipts; pending call arguments
  are not rewritten. Host summaries contain counters, not promoted web/log text
  or an assumption that earlier work completed successfully.
- Connector-backed phone planning keeps up to 4,000 characters for each of the
  latest two observations, while older observations keep their 600-character
  summaries and the existing ledger budget. This avoids losing the middle of
  a short source file immediately after the model reads it.
- Rejected native input includes the called tool's actual schema and an explicit
  non-execution result. Runtime errors explain the distinction between source
  and arguments. Runtime status separates current bridge readiness from the
  execution tool's on-demand startup capability; it does not claim execution
  succeeded before receiving an execution receipt.

There is no new lifetime action cutoff. Existing explicit budgets and
cancellation remain authoritative. This patch does not make repeated read polls
free: live tools should use handles/progress and the model should not busy-poll.

## Remaining implementation and validation

The full objective is still active. Specifically:

1. Verify every production reasoning path uses the contract, including
   connector-backed phone plans, local-model tool subsets and collaboration.
2. Establish a rendered browser test site with isolated test accounts and
   observable server-side outcomes. Run real models against changing obstacles,
   not scripts that already know the repair sequence.
3. Complete user takeover/resume for authentication with durable account and
   browser ownership, without exporting cookies to the model.
4. Validate long-run context compaction preserves the goal, unresolved blockers,
   attempts, verified outcomes and live tool handles.
5. Exercise coordinator/specialist replanning, uncertain mutations, process
   death, disconnected networks and responsive progress rendering.
6. Review completion/blockage decisions with real outcome evidence. The current
   prompt contract alone is not a guarantee against premature final answers.

## Regression scope

`AgentProblemSolvingLoopTest` uses scripted model responses to test failure
feedback, dependency repair, non-terminal repeated-operation rejection,
read-only re-observation, a simulated expired-login/stale-control sequence,
serial/parallel retry evidence, interruption, cancellation and simple chat.
`AgentProblemSolvingPolicyTest` checks policy pinning, old-journal replay and
untrusted page separation. `PhoneUiOperationResultTest` checks truthful UI
acceptance/failure evidence. These are not a real-browser login acceptance test.

The expanded Android JVM regression run passed 414 tests in 44 suites with zero
failures or errors. It includes model adapters and context, native registry and
effect recovery, supervised planning, checkpoint replay, untrusted evidence and
the new recovery tests. `git diff --check` also passed.

Android 1.4.156 (1241) was subsequently installed over 1.4.152 on S20U
`R5CN319CESA`, without clearing production data. Its main screen opened normally.
The durable-loop, replanning and continuous-replanning device run registered
19 tests: 15 passed and four opt-in process-death/reboot cases were skipped.
A separate controlled process-death probe then passed: a different process
resumed model round two, retained its committed observation and did not repeat
the write. This probe used a fixture model and did not reboot the phone.

Real-provider inventory found a paired Desktop reasoning contact but no ready
cloud API contact for the existing cloud-only live probe. Chrome was installed,
but no accessibility service was enabled. No real-provider browser/login
acceptance result is claimed and no credentials or pairing were changed.

## Real-provider S20U observations

On October 12, a Chinese goal sent through the production phone planning path
used paired Codex for reasoning and phone Linux for execution. It read an
attached JSON, summed 137, 286 and 419, wrote `outputs/result.json` and delivered
the artifact. Independent readback confirmed sum 842, the original proof marker
and SHA-256 `29f384a0366056b75133ada202acd6cdee804c847aa70db5d0a3dbfc54a6a965`.
The evaluator did not execute the task's Python on behalf of the phone Agent.

A follow-up provided `broken-calculate.py.txt` as `calculate.py`, with an import
typo and string-valued numbers, without specifying the repairs. The real model
reproduced the import failure and eventually corrected both defects. However,
the full outcome was not accepted: it spent many rounds reading files, used an
invalid duplicate-path batch patch, confused source with arguments and supplied
unnecessary collaboration dispatch metadata. It subsequently polled runtime
status without generating the required output. These are live failures, not a
successful autonomous-repair or website-login acceptance result. The observation
and runtime-diagnostic fixes above were made in response and still require a
fresh-device replay with the updated APK.

The subsequent JVM run passed 325 tests in 32 suites with no failures, errors or
skips, covering the updated context, latest-observation, native-input diagnostic
and lazy-startup status behavior alongside the model-loop and planning suites.
This is a separate regression selection from the earlier 414-test run. The phone
accepted an explicit stop-current-task command (`CANCELLED`) for the live probe;
the new context/diagnostic changes are not yet installed on the device.

## Tool contract discovery and subsequent device replay

The registry now exposes `galaxyssi.tools.describe` for an available tool's full
input contract or a JSON Pointer subtree. Resolution uses the invoking registry,
so restricted registries cannot disclose excluded tools. Inspection is read-only
and never executes the target. Both phone planning modes disclose this tool.

Planning instructions now distinguish project-profile verification without
source from arbitrary commands that require source. Ordinary execution must not
include saved collaboration-tool dispatch metadata. Duplicate instructions were
shortened without increasing the existing planning/continuation prompt budgets.
The regression selection passed 342 tests in 34 suites, with zero failures,
errors or skips. Android 1.4.157 (1242), including these changes, was installed
over the existing S20U app without clearing its data.

The fresh production replay was not an autonomous-repair pass. Auto initially
reported no available reasoning model despite displaying a Codex label. After
explicitly selecting the paired Codex, another attempt entered WAITING_RESPONSE
but did not reach the Desktop task endpoint. Desktop health showed zero active
subscriptions out of 16, pending subscriptions on HiveMQ, repeated connection
failures on other broker paths, and expired peer advertisements. A running HTTP
backend and an established MQTT socket are therefore not sufficient evidence
that the reasoning path is ready. Provider availability presentation, transport
readiness and recovery must be reconciled before repeating the acceptance test.

An opt-in, read-only instrumentation probe checks an explicitly selected public
fixture conversation and turn before reading its saved task state. It confirmed
the preceding test's persisted CANCELLED state and the subsequent attempt's
WAITING_RESPONSE state. These diagnostic passes do not count as model or browser
acceptance passes. Browser login, user takeover/resume and full autonomous repair
remain unverified; the goal remains active.

## Input rejection recovery and route-confirmation replay

The model loop's pre-dispatch validation now returns the actual registered input
schema, `executed=false` and `goal_terminal=false`. Previously the registry's
executor provided this contract, but the loop rejected malformed calls before
they reached that executor. Input rejection is not an external observation and
must not unlock another attempt at a mutation with an unknown outcome. Focused
regressions cover both model-directed argument correction and this effect guard.
The focused model-loop, durable-loop and problem-solving selection passed all
42 tests in three suites, with zero failures, errors or skips.

On the next S20U replay, Desktop reported 16 active subscriptions and a ready
MQTT receiver. This did not establish the phone's relationship-specific route:
the phone repeatedly logged subscription expiry and
`Encrypted message awaiting peer route reason=unconfirmed_local_epoch`.
Public fixture turn `6bcb617c-e5f5-44f0-bb8d-ea11884f60cc` remained in
WAITING_RESPONSE and no corresponding Desktop task appeared. The test was
explicitly stopped without resetting the pairing or modifying its script.
This is transport/admission evidence, not an autonomous-repair acceptance pass.
The additional pre-dispatch validation change was subsequently included in the
1.4.158 device installation below; the production repair replay remains open.

## Interactive website execution

`galaxyssi.browser.observe` and `galaxyssi.browser.act` provide a real Playwright
browser in phone Linux. They do not change the static `browser.session.*` tools
or the cookie-free isolated HTML renderer. Driver code is staged from generated
APK assets and runs through the existing `galaxyssi-browser` launcher, so it does
not require publishing a different Chromium runtime pack just to update the
Agent's browser protocol. A missing browser runtime returns its required pack
names and the installation tool; phone-control inventory discloses that tool.

The host binds the browser scope to session, conversation, workspace and caller.
Within that scope, independent contexts isolate accounts. Explicit page/frame
handles, fresh document revisions and observed node references ground actions.
Contexts keep cookies and DOM state across independent runtime tool processes;
they do not export cookie/password state into chat or public files. Browser
requests use bounded ephemeral environment chunks rather than script literals
or command-line arguments. The private IPC capability is not returned to models.

The executor supports form filling, current-control actions, navigation, tabs,
iframes, screenshots, dialogs and paginated observations of long documents and
large control sets. A dispatched action is not reported as verified business
success. Raw Playwright exceptions are not echoed because they can contain typed
values; structured diagnostics retain network error codes, missing-library
names and timeout categories. Observation timeouts never automatically replay
an action or restart a possibly live browser. Process loss returns an explicit
lost-session observation. Abandoned browser services release resources after
30 idle minutes; this is not a lifetime cutoff on the Agent goal.

The controlled host Chromium/IPC selection passed 22 tests with no failures or
skips. It includes actual HTTP form login, isolated Alice/Bob fixture accounts,
authenticated pagination, popup pages, iframe controls, stale-node rejection,
long-document cursors, dialog rejection, JPEG screenshots and browser death.
It also verifies explicit cross-process cancellation of an in-flight navigation
and cancellation of a queued mutation before dispatch. Request IDs accompany
IPC requests so cancellation identifies the actual operation. A possibly
submitted operation retains an unknown-outcome diagnostic; a cancelled queued
operation reports executed=false. Observation timeout alone does not cancel.
These are real browser execution tests but scripted tool choices, not proof of
real-provider autonomous problem solving. Android compilation, device runtime
wiring and actual model-directed website acceptance are tracked separately.

The latest Android regression selection passed 342 tests across 33 suites with
zero failures, errors or skips. APK and instrumentation builds passed. Android
1.4.158 (1243) was installed over the S20U app without clearing user data. Both
opt-in device wiring tests passed: the packaged drivers were present and the
public missing-session probe reached phone Linux, which returned
browser_runtime_missing because the browser launcher is not installed. This
confirms recoverable dependency reporting, not Chromium execution on the phone.
Installing the runtime pack and a real model-directed browser task remain open.

Still outstanding: a user-visible OTP/CAPTCHA takeover interface and durable
handoff/resume, browser restoration after device reboot without duplicating
unknown external effects, and a real model-directed login/recovery/extraction
test on S20U. The existing transport admission blocker also remains open.

## Recoverable model call admission and renewed production probe

Invalid or reused model tool-call IDs now produce non-execution observations
instead of ending a new loop. Transcript-only deterministic aliases pair each
rejected proposal with exactly one result. The original call is never admitted
to an executor, even when reused with different arguments or repeated within one
batch. Rejection is not fresh external evidence and cannot authorize repeating
an uncertain mutation. Normal calls retain their original identifiers.

Each new model response record pins call_admission_version=1. Unversioned
recorded responses retain their original transcript during recovery; subsequent
new rounds adopt the current contract. Regression coverage includes identical
responses, changed arguments, same-batch duplicates, invalid IDs, alias
collisions, unchanged effect guards, interruption replay and unversioned records.
The focused initial selection passed 61 tests. After adding the legacy replay
case, the expanded selection passed 350 tests across 34 suites, with zero
failures, errors or skips. Both APK builds passed and Android 1.4.159 (1244) was
installed over the existing S20U app without clearing user data.
Both device wiring tests passed again on 1.4.159 (42.4 seconds). The actual Linux
probe still returned browser_runtime_missing; no browser pack was silently
installed and no website task was declared successful.

Browser IPC cancellation additionally records a short-lived request tombstone:
the cancellation connection can arrive before the original operation connection.
Such an operation is rejected before dispatch with executed=false, rather than
starting after the caller stopped it. The controlled browser selection remains
22 passing tests and includes this ordering case.

The Chinese public website goal in conversation
5d3814ac-e809-428e-9a33-0f2b58810783, turn
ec079167-fd83-4e80-9c68-93a96868e709, did not reach Desktop task admission. The
phone remained WAITING_RESPONSE; the evaluator explicitly stopped this fixture
and observed CANCELLED, without repairing the website task on its behalf.
Desktop health showed no ready subscriptions or peer routes. Isolated probes
using fresh opaque topics and no production identities confirmed certificate-
verified TLS to all three brokers. EMQX returned Server unavailable; HiveMQ
granted a subscription at approximately 7.6 seconds and completed an opaque
round trip at approximately 8.1 seconds; Mosquitto produced no CONNACK within the
12-second observation window. These probes distinguish transport evidence from
Agent reasoning. They do not prove the cause of every production route failure,
nor successful real-model website execution or autonomous dependency repair.

## Browser user-control ownership core

The browser engine now has host-only beginHumanControl, executeHuman and
finishHumanControl entry points. An unguessable, session-bound capability stays
with the host; the model dispatcher and Android tool input schemas do not expose
it. Acquiring control is serialized behind any in-flight browser operation. Once
acquired, queued and new model reads and mutations are rejected before dispatch,
including screenshots and context close. Independent browser contexts remain
independent. User actions operate on the same live context and authenticated
cookies, rather than moving credentials into a second browser.

Control handoff changes the observation epoch even when the DOM has not changed.
Controls observed before takeover or during user control cannot be replayed by
the model after release. Returning control reports next_action=observe,
authentication_verified=false and business_success_verified=false: a user
pressing Done is not proof that login or the task succeeded. A later lease uses a
new capability, and old or cross-session capabilities cannot operate or release
it. Cancellation of a queued takeover does not close or acquire the browser.

The real host Chromium and IPC selection passed 29 tests with no failures or
skips. It includes ownership exclusion, queue ordering, cancellation, unchanged-
DOM observation invalidation, model-dispatch exclusion, private user form login,
cookie retention, cross-account handles and lease replay. These are scripted
browser tests, not model-directed login acceptance. The Android schema regression
also checks that model input cannot invoke the host-only methods or pass a
control_token. The user-visible phone takeover interface, private IPC bridge and
event-driven continuation of the original Run are still outstanding. The new
entry points intentionally are not advertised as usable model tools yet.

The expanded Android selection passed 351 tests across 34 suites with no
failures, errors or skips. Both APK builds passed in 6 minutes 37 seconds.
Android 1.4.160 (1245) was installed over the S20U app without clearing its data.
Both opt-in device wiring tests passed in 39.9 seconds. The runtime probe still
reported browser_runtime_missing, not successful phone Chromium execution.

The subsequent Chinese public website fixture used token
autonomous-browser-s20u-f2a1, conversation
38f491c1-6f8a-4dc2-8dfd-11e6831202b0 and turn
d1989573-0c5f-492e-97b3-7c0c1ebff5c8. Android selected Codex on DESKTOP-T14 for
reasoning with phone-only execution requested. At 187.5 seconds the phone was
still WAITING_RESPONSE and the local Desktop API had no matching task by
conversation, connector task ID or fixture prompt token. Desktop subscriptions
remained ready while the aggregate confirmed-peer count fluctuated between zero
and one; the count alone does not identify the S20U peer or establish causation.
The evaluator explicitly stopped only this fixture and confirmed CANCELLED.
No production identity was reset or re-paired. This probe does not establish
model-directed dependency installation, website access or autonomous recovery.
The current phone screenshot is a local diagnostic artifact, not a shipped asset.

## Stable route admission during broker churn

Controlled transport reproductions exposed an admission starvation mechanism:
an unrelated broker reconnect could replace the pending local resume request,
making a slow but otherwise valid ACK stale before it arrived. A pending request
now remains stable while an originally advertised generation is still reachable.
A genuinely new broker can still rotate the advertisement so initially disjoint
peers can discover a common path. Expired advertisements are never kept alive.

Android and Desktop separately retain the last authenticated confirmed lease
while its replacement awaits an ACK. Only generations explicitly confirmed by
that lease and still locally connected/subscribed are admitted. A new generation
is excluded until its current advertisement is acknowledged. Lease expiry,
receive-topic replacement, identity replacement and revocation still invalidate
authorization; issuing a new advertisement does not extend the old lease.
Routine renewal does not restart unrelated recovery work while a confirmed path
survives. Existing authenticated identity and replay checks remain unchanged.

The policy filters authorized generations before ranking paths, including large
messages. Otherwise an unconfirmed highest-ranked broker could suppress the
healthy confirmed broker. Durable dispatch obtains a fresh authorization snapshot
outside the policy lock and rechecks authorization immediately before dispatch.
Stored receipts can use a surviving confirmed lease during renewal, but a peer
with no live confirmed lease must defer them and discard them on revocation.

The complete Desktop MQTT selection passed 510 tests. After strengthening the
renewal receipt fixture to issue a real replacement advertisement, the affected
23 bridge/priority tests passed again. Desktop UI and structure checks passed
68 tests. The expanded Android selection passed 604 tests across 55 suites with
zero failures, errors or skips; both APK builds passed in 7 minutes 21 seconds.
Android 1.4.161 (1246) was installed over the existing S20U app without clearing
data or re-pairing. Both device browser wiring tests passed in 46.6 seconds;
the Linux probe still returned browser_runtime_missing.

Desktop source is 1.4.58, but the running Desktop still uses another worktree
and has not been replaced for this check. These regression results establish the
controlled admission repair, not production S20U end-to-end model delivery or
successful autonomous website access. The user-visible login handoff and actual
phone browser installation/execution remain outstanding.

## User-control IPC and event-driven observation

The browser daemon now exposes separate model and host capabilities on its
private local socket. Model IPC rejects every human_control_* operation before
engine dispatch. The host channel can acquire, inspect, operate and release a
user handoff; the engine's control token remains inside the daemon and is never
returned as part of the public handoff or model observation. Nested user actions
cannot replace the session/account bound by the host envelope. A host can query
the current handoff after an unobserved begin instead of acquiring a second one.

The read-only wait_for_user operation subscribes to a specific session and
handoff ID. Release wakes existing subscribers, and a later subscriber observes
the retained completion rather than missing the event. No timer polls the page
or calls the model. Cancellation or a disconnected observation socket removes
only that subscription; it does not release user ownership, close the browser
or repeat an operation. Failed release is not a completion event. Browser/context
loss rejects affected observers and does not disturb another account's handoff.
Completion still reports authentication_verified=false and next_action=observe.

Driver identity is a hash of all three staged browser helper files. A live daemon
with another identity is reported as browser_driver_changed; an observation
timeout or source upgrade never automatically creates a replacement. Explicit
service shutdown remains available for operator-controlled replacement.

These capabilities separate tool API ownership, not operating-system users. The
App derives a per-scope host capability from a Keystore-encrypted master key;
there is no guest host-token endpoint file. The scoped capability is delivered
through the runtime's ephemeral request environment and removed from the Node
environment before dispatch. This does not isolate Chromium or daemon memory
from arbitrary same-account/root guest execution. The Android surface must not
be represented as a credential vault against an untrusted root executor. No
real user account credentials were used in these tests.

The controlled host/real-Chromium selection passed 46 tests with no failures or
skips. It covers actual host-CLI form login, retained cookies, event-driven return
to the original observer, independent accounts, capability rejection, missed-event
recovery, cancellation, failed release, shutdown and browser/context loss. The
Android selection passed 349 tests across 33 suites with no failures, errors or
skips. Both APK builds passed; a final asset-only rebuild includes the subsequent
context-loss and handoff-observation fixes. All three APK helper hashes match
the current source. Android 1.4.162 (1247) was installed on S20U without clearing
data or re-pairing; both device wiring tests passed in 44.3 seconds. The runtime
probe still reported browser_runtime_missing, not successful browser execution.

## Android user-control surface

The native mutation tool now exposes request_user_control, not host control
tokens or raw human_control_* methods. A request binds the original Agent
session, conversation, turn, caller and workspace to the live browser session
and page. One atomic Keystore-encrypted record is stored per browser. An old
notification must match both the record key and generation; a different turn
cannot silently acquire an active request. Interrupted begin observations are
reconciled with host state rather than repeated unconditionally.

The non-exported Android activity displays actual Chromium JPEG snapshots and
sends user pointer, scroll and text operations to the same context. Native text
entry is transient and excluded from autofill, saved view state and command
source. Preview buffers are decoded off the main thread and cleared on stop;
FLAG_SECURE prevents this surface from appearing in screenshots or recents.
Pending browser dialogs require the user's actual decision. Returning to the
App does not silently release control; the retained notification reopens the
same generation. Explicit completion releases the daemon handoff and wakes its
original wait_for_user subscribers, then the model must observe and verify.

Host UI commands use an independent control workspace while retaining the
browser scope. Otherwise a waiting model call holding the task workspace lock
would deadlock the login surface. Host credentials and typed values only use
the ephemeral environment, not source, argv, intents, request records or model
observations. Screenshots have a bounded JPEG envelope to remain below the
runtime's existing stdout bound.

The controlled host/Chromium suite now passes 49 tests with no skips or failures,
including viewport capture, manual pointer selection, password entry, stale
pointer rejection and subsequent Agent observation of the authenticated page.
Cancelling a running preview does not close the account context. Android passed
356 JVM tests across 34 suites with zero failures, errors or skips. Both APKs
built successfully. All three packaged helper hashes match current source.
Android 1.4.163 (1248) was installed over S20U without clearing App data or
re-pairing. Four device checks passed in 43.93 seconds: bundled driver wiring,
Keystore authority/atomic-record reload and stale-generation rejection, an
actual Linux runtime probe, and protected empty-surface layout with bounded
controls. The public empty surface was rendered for visual inspection, not a
real authenticated page. The Linux probe still returned browser_runtime_missing.
The durable original-Run pause/resume and real
model-directed phone browser task remain incomplete. A controlled Chromium
test is not evidence of successful arbitrary authenticated website completion.

## Request timeout isolation

A source audit found that any native execution timeout could quarantine the
entire shared guest generation. This destroys detached browser state even when
only the observation request expired, and also interrupts unrelated executions.
The new request settlement sends cancellation once and observes its terminal
response for a bounded grace period. An authoritative late result is returned
without resubmission. A cancellation acknowledgement confirms termination, not
rollback of earlier effects; the model still receives outcome_unknown and must
inspect state before repeating a mutation. An explicit user cancellation wins
over late success.

The manager requests fresh independent health rather than relying on cached
readiness. Quarantine requires confirmed negative readiness; silence is not a
confirmed unhealthy guest. An unobserved heartbeat does not itself close the
multiplexed connection. Structured timeout evidence is retained in the native
tool result instead of being replaced by a generic timeout string. These changes
are under regression and device verification; they do not yet prove durable
recovery of every browser or Agent execution path.

Two attempts to submit a new public test goal through the existing ADB debug
intent were rejected by the execution tool before running. The second contained
no login operation. No new goal was created, and no alternate injection channel
was used. The user was asked to send a public-page task normally from the App.
The phone browser pack remains missing; no model-owned phone login or arbitrary
authenticated-website acceptance is claimed.

Verification for Android 1.4.164 (1249): 503 JVM tests across 61 suites passed
with zero failures, errors or skips. Both APK builds passed. All three packaged
browser-helper hashes match current source. The controlled browser selection
passed 49 tests with zero failures or skips. App and test APK were installed
over S20U without clearing data or re-pairing. The opt-in real Linux timeout
isolation test passed in 49.358 seconds: a deliberately timed-out sleep retained
confirmed healthy readiness, did not reset the runtime, and an independent
request completed with the identical guest boot ID and bridge object. This is
infrastructure evidence only, not a model-owned website completion. Timeout
reconciliation in other discovery/startup paths and durable original-Run user
handoff resumption still require separate acceptance.

## Task-bound user control

Browser user-control records now include the original task and model-loop IDs,
in addition to session, conversation, turn, caller, workspace and live page.
Requesting user control without a task binding returns a non-terminal,
non-execution observation. Replanning may inspect its same-task handoff with a
new loop ID; it cannot rewrite the original persisted identity. A same-generation
update cannot change the task/page/owner or allocated handoff, move active control
back to requested, or reactivate returned control. Old records with no task
binding are not silently assigned to a different bound task.

Expired notification generations now produce browser_user_request_stale, not an
unrelated generic UI failure. Returned requests close the user surface without
reopening Chromium. A successful completion is applied even if the Activity has
just moved to the background. The encrypted record is still committed only after
the host confirms returning control.

Verification for Android 1.4.165 (1250): 405 JVM tests across 41 suites passed
with zero failures, errors or skips. Both APK builds and six S20U checks passed.
The device checks include original-task encrypted-record reload and mutation
rejection, stale/returned user surfaces, driver wiring, the missing-browser
observation, and independent-request timeout isolation. The timeout test also
verified a workspace marker survives. Browser execution still reported
browser_runtime_missing; model-owned website acceptance remains incomplete.

## Discovery and startup health evidence

Discovery now retains its existing bridge when a health response is unobserved;
it does not unregister or close another request's shared connection. A candidate
with unconfirmed health is retained for a later probe but is not advertised as
ready. Thrown probes are explicitly unconfirmed, not negative health evidence.
Lifecycle inspection preserves that distinction in the degraded reason. Normal
start and automatic ensureRunning cannot replace a running engine, even when a
forced backoff retry was requested. An explicit restart still first stops the
guest. Automatic retries return degraded/starting observations rather than
repeatedly relaunching a live guest.

This prevents an unobserved probe from silently discarding live browser state.
It does not prove recovery from an actually unresponsive running guest: an
explicit diagnostic/reconciliation decision and model-visible lifecycle controls
still need implementation and acceptance. Binding records also does not itself
prove durable original-Run scheduling after App process loss.

Verification for Android 1.4.166 (1251): 408 JVM tests across 42 suites passed
with zero failures, errors or skips; both APK builds passed. App and test APK
were installed over S20U without clearing data or re-pairing. Seven device
checks passed in 57.031 seconds, including an explicit unconfirmed inspection
followed by reuse of the same guest boot ID and bridge, plus independent-request
timeout isolation and workspace-marker preservation. The three packaged browser
helper hashes match source. The missing-browser check still observed the missing
runtime rather than successful website execution. Policy tests exercise the
discard/launch decisions; these results do not prove an actual dropped heartbeat
in Supervisor discovery, an unresponsive live guest's model-selected repair, or
durable original-Run wake after process loss.

## Durable browser-return wake

User-control requests now capture the exact supervised Run workspace and owner
independently of the Linux file workspace and MobileNativeAgent session. Binding
requires a single active owner whose saved pending-planning reference, runtime
session, conversation and task/turn all match. The reference's input hash and
base-plan identity/revision are also bound, so a later planning revision cannot
consume an older return. Unsupervised browser use retains
its live event subscription but reports durable_resume_available=false rather
than inventing a recoverable Run.

After the browser host confirms returning control, the encrypted atomic record
retains an unacknowledged return. A generation-specific WorkManager wake is
enqueued before the user surface closes; an enqueue failure leaves the encrypted
return pending for startup reconciliation. It is separate from generic recovery KEEP work,
so an already-running generic slice cannot discard the new return event. If the
original owner is active, recovery retries without starting another model loop.
Otherwise the worker validates the entire saved binding, respects user pause,
cancellation and terminal states, and restores only the saved initial-planning
or replanning checkpoint. There is no new goal and no browser-mutation replay
outside the existing durable tool-loop admission and effect-claim rules.

Startup reconciliation and reopening an already-returned notification re-enqueue
unacknowledged returns after an enqueue interruption. Acknowledgement is monotonic
and generation-bound; an older worker cannot consume a newer return. Host return
is not authentication or goal-completion proof: the resumed model must observe
the live page. Browser loss still requires model-directed recovery, not invented
login state. These changes require regression and device verification; complete
model-owned phone login, process-death recovery and collection remain unproven.

### Remaining goal acceptance

- A real selected model must discover missing browser prerequisites, choose and
  execute their repair, then verify the originally blocked operation on S20U.
- A model-owned authenticated website task must navigate, operate controls,
  follow pagination and collect server-verifiable information with provenance.
- User-only authentication must yield durably, avoid repeated model polling,
  then resume the exact original planning checkpoint after App process loss.
- Phone browser loss and an unresponsive live guest must produce truthful
  evidence for model-selected reconciliation, without blind mutation replay.
- Local-model web loops and multi-agent specialist paths need equivalent
  interactive-tool, evidence and durable-return integration; the supervised
  phone planner path alone does not prove all-model support.
- Real interrupted, cancelled, duplicate and cross-session cases must verify
  both outcome correctness and responsive, concise progress presentation.

Controlled Chromium, policy fixtures and missing-runtime probes are useful
regressions, not substitutes for these end-to-end requirements.

Verification for Android 1.4.167 (1252): 149 selected JVM tests across 17 suites
passed with zero failures, errors or skips, including eight new browser-return
policy tests. Both APK builds passed and were installed over S20U without
clearing data or re-pairing. Nine device checks passed in 58.341 seconds. The new
checks reload an encrypted pending return, verify monotonic/generation-bound
acknowledgement, and run the actual WorkManager recovery worker for a public
deleted-Run fixture, which is acknowledged without creating another task or
calling a model. The three packaged browser-helper hashes match source. The
public browser probe still reports missing runtime; no real login, process-death
model continuation or website collection is claimed.

## Durable external-event suspension

The generic model tool loop supports WAITING_FOR_EVENT as a nonterminal outcome.
An injected host-owned resolver can suspend after a committed tool result. Such
tools are batch barriers, even if their descriptors allow parallel reads. The
loop releases its journal lease and returns without a timer or another provider
call. Reopening a still-pending checkpoint reconstructs the committed model and
tool responses without reexecuting them or polling the provider. Cancellation
takes precedence over suspension.

The supervised phone planner uses this mechanism for browser user control. The
resolver verifies the encrypted request generation, all runtime scope fields,
the original model-loop ID and supervised Run planning reference. Initial
planning and replanning retain their pending input and base plan, enter PAUSED,
and persist a distinct event-wait marker rather than failing or completing the
goal. Generic liveness recovery leaves that wait dormant. The browser event
source can wake it after a bound return or an observed host-process change;
an explicit user continuation can also revisit the saved checkpoint.

After return, a host event is attached as metadata beside the original tool
receipt, without rewriting its execution result or output hash. That resolved
observation is committed separately before the next model request, so later
replay does not depend on a retained live handoff record. Returning control never
proves authentication or task success. A missing or replaced handoff produces an
explicit unobserved-event diagnostic for the model, not invented authentication,
consumption of another task's event or a hardcoded repair command.

This is currently wired into the supervised GuardedModelAgentPlanner path. Other
loop consumers do not implicitly acquire browser tools or this resolver. Real
provider, browser login and App-process-death acceptance remain outstanding.

Verification for Android 1.4.168 (1253): 161 selected JVM tests across 19 suites
passed with zero failures, errors or skips. Both APK builds passed and were
installed over S20U without clearing data or re-pairing. Ten device checks passed
in 63.296 seconds. The new isolated encrypted-ledger fixture reopens a pending
loop without another provider/tool call, commits a returned event, and replays
its completed checkpoint without duplicate effects. It uses a fixture adapter,
not a real provider, website, user login or newly submitted user goal. The
existing browser/runtime checks also passed; end-to-end autonomous website
acceptance and actual App-process-death continuation remain unproven.

## Model-selected runtime diagnosis and lifecycle control

The phone tool catalog exposes runtime.diagnose and runtime.control in both
phone-development and remote-phone planning modes. Diagnosis reads cached pack
metadata without integrity-rehashing, observes a fresh guest health response and
engine state, and returns an opaque process/generation-bound runtime instance.
Missing responses remain unconfirmed, not evidence of a stopped engine. Diagnosis
does not start, restart, reset, provision a system disk or repair the guest.

The model can explicitly select start or restart using the observed instance.
Start does not replace a running guest. Restart affects the shared guest and can
lose browser sessions, authentication and background process state; persistent
workspace files are not reset. A stale instance is rejected before the lifecycle
operation. A maintenance gate refuses an active execution and prevents new
executions from entering during maintenance. Existing user-stop generations still
invalidate startup; model control does not clear cancellation or replay commands.

Failure to observe a ready guest returns the diagnostic output to the model as a
nonterminal failure. An unexpected lifecycle exception reports an unknown outcome,
not an unexecuted mutation or an instruction to retry it. The model must diagnose
and verify the original task before continuing. These tools do not replace all
existing automatic pack-boot or persistent-disk recovery paths. Full model-owned
repair, actual shared-guest restart and website-task acceptance remain unproven.

Verification for Android 1.4.169 (1254): the final build passed 114 selected JVM
tests across 15 suites with zero failures, errors or skips. The first build
caught the missing phone-development disclosure; the final build includes that
fix and the user-stop generation check. The app and test APKs were installed over
S20U without clearing data or re-pairing. Eleven device checks passed in 65.902
seconds. The new real-guest check obtains a fresh health response, invokes start
without changing the runtime instance or Linux boot ID, and rejects a stale
restart while preserving the same bridge and boot ID. It does not exercise an
actual shared-guest restart, a user-stop race or a model-selected repair.

The existing timeout, encrypted event-wait and browser-host checks also passed.
The instrumentation transcript is retained locally under
.local-artifacts/autonomous-problem-solving/s20u-1.4.169-instrumentation.txt.
The app was relaunched after instrumentation and its installed version verified.
The fresh public browser probe still reports browser_runtime_missing; this is
missing-capability evidence, not a successful website execution.
No new model-owned website goal, authenticated login or dependency repair is
claimed from these infrastructure checks.

## Host-process interruption of browser waits

New browser handoffs retain the originating App process identity in the encrypted
record. Startup reconciliation converts a pending handoff from a different known
host process into an interrupted event, without claiming that the browser died,
the user returned control, authentication succeeded or authentication was lost.
Unbound historical host identities are not guessed. Returned and already
interrupted records are monotonic and are not rewritten on each startup.

The durable event queue resumes only the matching original Run and planning
reference, subject to cancellation, manual pause and active-owner exclusion.
The existing native tool receipt remains immutable; a separate observation tells
the model that runtime, browser availability and control ownership need checking.
No browser operation, login, dependency installation or restart is selected by
this recovery policy. A live human-control lease remains protected by the guest
driver. If the model chooses a new handoff after inspecting the evidence, the
new record has its own generation; old notifications cannot operate it.

The wake is persisted before enqueue and acknowledged only after the recovery
slice settles. Startup retries enqueue rather than polling a provider. User return
and interruption are both generation-bound events in the same host recovery
path. A fixture test runs in two distinct instrumentation processes using an
isolated encrypted ledger and synthetic adapter; it must not be mistaken for a
real model, browser session, authenticated website or full supervised-Run restart
acceptance. Real browser loss without an App process change remains a separate
event-source integration requirement.

Verification for Android 1.4.170 (1255): 140 selected JVM tests across 18 suites
passed with zero failures, errors or skips. Both APK builds passed and were
installed over S20U without clearing user data. Twelve device checks passed in
61.491 seconds. A separate isolated fixture persisted a waiting checkpoint,
then an explicit force-stop terminated the App host. Recovery in a new process
passed in 0.599 seconds, preserving the checkpoint and observing the interruption
without repeating the handoff. Its seed phase passed in 0.408 seconds. These
timings describe instrumentation fixtures, not end-to-end task recovery latency.
The App was relaunched and its installed version verified afterward.

At this version, full supervised-Run acceptance still needs failure injection
between the recovery hook and event acknowledgement: a completed worker job alone
does not prove that the model consumed the observation. Real-provider dependency
repair, authenticated website operation and same-process browser-loss recovery
remain outstanding.
Local transcripts are retained under
.local-artifacts/autonomous-problem-solving/s20u-1.4.170-*.txt.

References: [Android unique work](https://developer.android.com/develop/background-work/background-tasks/persistent/how-to/manage-work)
and [Playwright authentication state](https://playwright.dev/docs/auth).

## Recovery acknowledgement requires durable observation and projection

Job completion is not an acknowledgement of successful recovery. The worker now
records whether its preparation and transcript projection committed. An exception
in that slice pauses the original Run with the actual diagnostic and preserves
its pending event; cancellation still propagates without an acknowledgement.
The worker retries through the existing exponential backoff instead of treating
a failed hook as a successful browser wake.

Separately, the model tool loop notifies its external-event resolver only after
the original journal saved or validated the resolved event result. The browser
resolver checks the exact owner, loop, generation and event before writing a
monotonic encrypted observation marker. The marker is not a claim of successful
authentication, model reasoning or task completion. A crash after the journal
write but before the marker can replay the committed observation without another
browser mutation. A crash after the marker still leaves the wake pending until
the recovery projection commits. A new handoff generation cannot inherit the old
observation marker.

The worker requires both the committed slice and its exact observation marker
before acknowledging an active Run's browser event. Deleted, cancelled or stale
Run bindings retain their separate discard path; they do not need a new model
call. These changes do not prove recovery for every Supervisor transition or
every provider failure, nor do isolated fixtures prove website-task acceptance.

Verification for Android 1.4.171 (1256): the first targeted run passed 70 tests
across seven suites. The final expanded run passed 167 JVM tests across 20 suites
with zero failures, errors or skips; both APK builds passed. The new regressions
exercise a real Supervisor with a preparation failure, retained checkpoint and
subsequent continuation, cancellation priority, event-journal write failure and
host-marker write failure after the event commit. Synthetic model adapters are
used; these are not real-provider repair acceptance.

S20U received an in-place update without clearing data. Thirteen device checks
passed in 70.283 seconds, including encrypted observation-marker persistence,
acknowledgement refusal before observation commit and cross-generation isolation.
The separate seed phase passed in 0.423 seconds, followed by an explicit App
force-stop and recovery in a distinct process in 0.791 seconds. That fixture
validated the original encrypted model checkpoint and committed observation
marker without repeating the handoff. It is not a full supervised-Run restart or
website login test. The app was relaunched and version 1.4.171 verified.
Transcripts are retained under
.local-artifacts/autonomous-problem-solving/s20u-1.4.171-*.txt.

Reference: [Kotlin Job.join](https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines/-job/join.html).

## Browser event waits in supervised ActionPlans

Selected reasoning agents such as Codex normally use the phone-supervised
ActionPlan path, not the guarded cloud model's native tool loop. A native call
from that path previously sent the plan identifier as `task_id` and had no
model-loop checkpoint. As a result, the browser host could not bind its human
handoff to the original supervised Run. The event-loop fixtures alone did not
cover this production path.

Native ActionPlan calls now carry the actual turn/task identifier and a
host-generated binding to the plan, revision, action and active dispatch
checkpoint. The browser request stores this binding separately from native
model-loop identity. An ambiguous or missing Run owner is reported before
beginning a human handoff. The native receipt yields the plan into a persisted
event wait instead of proceeding with verification or proposed mutations while
the user controls the browser.

The exact return or host-interruption event adds a separate observation to the
original node. Its native journal receipt is not changed. Pending actions based
on the pre-handoff page are retired into history; the original reasoning
connector, model and effort settings receive the observation and choose a fresh
batch. The framework neither declares authentication successful nor selects a
site-specific repair. An interrupted host reports control ownership as unknown
and requires observing the existing runtime and page. A handoff recorded before
its native receipt also proceeds from the host observation without replaying
that browser mutation.

The session containing the observation and continuation is persisted before
the encrypted host observation marker is set. A retry can recover that marker
without appending another continuation. The existing recovery worker still
requires committed transcript projection before acknowledging the wake.
Cancellation, manual pause, active owners and changed dispatch checkpoints
retain their exclusion rules. Real-provider website repair and login acceptance
remain separate requirements; synthetic dispatch fixtures do not prove them.

Device dispatch checks exposed two gaps that the policy-only JVM checks did not:
the execution loop must pass through `OBSERVE` before `REPLAN`, and connector
dependency materialization prefers an action's evidence over its result. The
external event is therefore present in both the node result and evidence, with
the observed node first in the bounded dependency-output block. Earlier completed
dependencies retain their identifiers and exact dispatched parameters. The
original native tool receipt remains unchanged. Tests inspect the materialized
provider prompt, not just the continuation plan or an observation marker.

Verification for Android 1.4.172 (1257): the final expanded JVM run passed
393 tests across 37 suites with zero failures, errors or skips; both APK builds
passed. S20U received an in-place update without clearing App data. Four new
ActionPlan dispatch checks passed in 7.757 seconds, including a persisted
continuation before its host marker, a receipt committed before the wait state,
and a host interruption before the receipt. Each case delivered one event to the
original configured provider fixture, preserved the original receipt and avoided
duplicate provider calls or browser mutation replay. Thirteen existing device
checks passed in 69.355 seconds. The separate native-model-loop restart fixture
passed its seed phase in 0.445 seconds and recovery after force-stop in 0.726
seconds, with distinct process IDs. These are fixture timings, not full task
recovery latency or real-provider website acceptance.

The phone runtime probe still reports `browser_runtime_missing`: the optional
interactive browser pack is not installed on S20U. It was not installed manually
on the Agent's behalf. The timeout probe retained the same guest and completed an
independent request without resetting the runtime. The App was relaunched and
installed version 1.4.172 verified. Public instrumentation transcripts are kept
under .local-artifacts/autonomous-problem-solving/s20u-1.4.172-*.txt; the initial
failed transition run is retained separately. Actual model-driven dependency
installation, authenticated website operation, same-process browser loss and
full Supervisor ActionPlan process-death recovery remain outstanding.

## Native failure observations in supervised plans

The ActionPlan adapter previously copied native output and a rendered message,
but dropped the native error code, retryability and diagnostic details. A generic
message or empty output could therefore hide the reason for failure from the
supervising provider. The adapter now keeps a separate bounded, credential-redacted
failure observation alongside the unchanged native output and receipt. Plan
history uses that observation as evidence, so the existing failed-action recovery
prompt can expose the diagnostic to whichever reasoning provider is selected.
Successful native results retain their previous output shape.

The observation preserves the actual terminal status and any verification
failure, not just an execution-error string. Oversized details include an explicit
truncation marker, redacted excerpt and digest. An explicit `outcome_unknown`
diagnostic or `outcome_state=unknown` remains visible at the observation root
even when nested logs are compacted; the framework does not infer outcome certainty
from an error name. Unknown outcomes require observation before a model chooses
another mutation. Missing tools, invalid JSON and phone-development preflight
failures state that execution never started and do not invent invocation receipts.
The observation mechanism itself never installs software, chooses a repair,
retries a tool or treats a failure as task completion.

This follows the principle of returning informative tool failures to the model,
rather than generic failures, described in
[Claude tool-call error handling](https://platform.claude.com/docs/en/agents-and-tools/tool-use/handle-tool-calls).
[Playwright actionability](https://playwright.dev/docs/actionability) documents
that unmet actionability checks can time out; that timeout alone is not a verified
business outcome or a reason for the harness to replay an external mutation.

Verification for Android 1.4.173 (1258): 309 JVM tests across 25 suites passed,
with zero failures, errors or skips. Both APK builds passed. S20U received an
in-place App update without clearing user data. Seventeen existing browser,
event-wait and runtime recovery checks passed in 75.544 seconds. Three new native
failure checks passed in 6.152 seconds through the real MobileNativeAgent
dispatch, failed-action replanning, encrypted session save/reopen and connector
execution paths. The fixtures supplied missing-dependency, missing-element and
explicit unknown-outcome diagnostics; the provider callback received their codes,
component and decoded path, but not the synthetic password. Each case made one
tool invocation and one provider dispatch, including after session reopen.
The test initially used an invalid tool version, then compared a path without
accepting Android's legal JSON slash escaping; both fixture errors were corrected
without loosening production validation. An earlier unit-test constructor error
was also corrected before the passing run.

These checks use synthetic native executors and provider callbacks. They do not
prove that a real reasoning model can install the optional browser pack, recover
a real website failure, log in or complete an authenticated information-gathering
task. Those end-to-end requirements, plus same-process browser-loss notification
and full supervised ActionPlan process-death recovery, remain open. Public device
logs are retained under .local-artifacts/autonomous-problem-solving/s20u-1.4.173-*.txt.

## Observed browser loss without an App restart

The native user-control host now persists explicit session-loss responses as
interruption events for the exact active handoff. A missing handoff reported by
state inspection, completion or a preview snapshot is also observable. An invalid
arbitrary input action is not evidence that the handoff disappeared. Existing
handoff state queries include the recorded handoff ID, so the browser service
checks its live session rather than only returning a cached control record.

The encrypted request store compares the complete original record before saving
an interruption. A late response cannot close a replacement generation, change
the original cause or overwrite an observation-commit marker. Persistence precedes
Run wakeup. Failed wakeup leaves the event available for reconciliation. The
model receives the actual protocol failure and unconfirmed ownership and
authentication; neither user actions nor browser mutations are replayed by this
mechanism.

Readiness uncertainty, a timeout, missing runtime dependencies, a changed live
driver and stale page observations do not prove session loss. These failures
leave the handoff active. This change handles a loss when a native host operation
observes it; an idle browser/guest exit still needs a generation-bound lifecycle
notification path when no host operation is in flight. It does not claim passive
exit detection or real-provider website/login acceptance.

Verification for Android 1.4.174 (1259): both APK builds and 85 JVM tests across
10 suites passed with no failures, errors or skips. S20U received an in-place
update without uninstalling or clearing data. Five new synthetic-host device
tests passed in 3.725 seconds, including three distinct loss codes through the
encrypted model-loop checkpoint and observation-commit/acknowledgement path.
The original browser action and provider continuation were not repeated on replay.
Sixteen existing device regressions passed; four opt-in runtime probes were
initially skipped because their flags were absent, then all four passed in
53.124 seconds with the flags explicitly enabled. The runtime probes confirmed
that uncertain health and a timed-out request did not replace the live guest or
block an independent request. The browser runtime pack remains absent; its probe
reports that prerequisite to the model, not successful browser execution.
Public transcripts are retained under
.local-artifacts/autonomous-problem-solving/s20u-1.4.174-*.txt.

## Passive runtime exit events during browser handoff

Each QEMU child receives a host-generated instance identity after a successful
spawn. The guest bridge captures that identity and refuses a channel open or
handshake against a replacement controller instance. Execution responses carry
the immutable bridge identity, not a fresh sample taken after the command.
Browser handoff records bind that identity after a successful host observation.
Legacy records without a proven identity are not guessed or rebound to another
runtime. Existing generation, task, turn, session and conversation checks remain.

The QEMU process monitor emits a one-shot exit event only after `waitFor()`
returns; interruption of the monitoring thread is not process-exit evidence.
This follows the distinction in the
[Android Process contract](https://developer.android.com/reference/java/lang/Process#waitFor()).
Callbacks run outside the process monitor and lifecycle locks. A delayed old exit
cannot retire the new instance. Subscribing after an exit or replacement still
observes that state, closing the gap between guest exit and handoff persistence.
No timer, model polling, automatic restart or browser mutation is added.

An exact-record compare-and-save persists the browser interruption before
enqueueing the original Run. A queued event cannot overwrite returned control,
a replacement generation or an already committed observation. Failed enqueue
leaves a pending encrypted event; startup reconciliation also consults confirmed
in-process runtime exit/replacement state. The model decides what to diagnose
and repair. Browser-only process loss while its Linux guest remains live still
needs a passive notification path; observed host-operation loss is covered by
the previous change. Real-provider dependency installation, authenticated website
operation and full supervised ActionPlan process-death acceptance remain open.

Verification for Android 1.4.175 (1260): both APK builds and 122 JVM tests across
14 suites passed, with zero failures, errors or skips. S20U received an in-place
update preserving user data. Six new device checks passed in 1.554 seconds.
They include a real short-lived Android subprocess exiting with code 7 through
the production process-monitor helper, a durable browser wait and a synthetic
provider continuation. No real QEMU guest or user task was stopped. The other
cases cover exit-before-subscribe, delayed old events, already-returned control,
failed enqueue and legacy records without an instance binding.

Twenty-five existing device checks passed in 79.739 seconds with both opt-in
runtime probe flags enabled and no skips. The real Linux diagnosis/start probe
now verifies that the execution response carries the actual QEMU controller's
nonblank instance ID and that another request retains it. Health uncertainty and
an observation timeout still preserve the running guest. Public transcripts are
retained under .local-artifacts/autonomous-problem-solving/s20u-1.4.175-*.txt.

This verifies the process-monitor/event/checkpoint components and the identity
source on a real guest separately. It is not acceptance of forced real-QEMU
termination followed by full supervised recovery, or a real model's autonomous
dependency repair and authenticated website workflow.

## Browser-only terminal observations over the shared workspace

The browser host registers a generation-bound event sink during takeover or a
handoff-state observation. The sink uses the existing QEMU 9P workspace mount;
it does not keep a shell command, workspace lease or model call open while a
person controls the browser. A Chromium disconnect, context loss or graceful
browser-service shutdown publishes one terminal observation for that handoff.
Returned control closes the sink without publishing another interruption.

The guest atomically renames a small AES-256-GCM envelope into an App-created
directory. HMAC-SHA256 derives a separate encryption key from the existing
host capability and the handoff key/generation; that binding is also GCM AAD.
Payloads contain only session, page and handoff identifiers and `session_lost`,
not browser text, typed input, credentials or an assertion of login success.
The host accepts no alternate terminal codes from this channel. App records
retain the original task, turn, model-loop and Run ownership checks.

An Android FileObserver schedules bounded reads, authentication, exact-record
compare-and-save and Run wakeup off its callback thread. Its subscription is
retained until settlement; repeated callbacks are coalesced without timers.
Watching starts before an immediate file read, closing the exit-before-watch
and exit-before-active-commit races. Failed enqueue leaves the encrypted
interruption available for existing startup reconciliation. Runtime exit,
explicit return and replacement generations release old subscriptions; stale
events cannot overwrite a returned or replacement handoff. Settled event files
are removed only after durable record settlement.

This uses the documented [Android FileObserver contract](https://developer.android.com/reference/android/os/FileObserver)
and [Node authenticated-encryption APIs](https://nodejs.org/api/crypto.html).
Keeping a strong observer reference and starting it explicitly are required;
watching a directory does not imply recursive observation or prove arbitrary
guest changes are delivered. The physical shared-directory test is therefore a
separate requirement, not inferred from a local file-write fixture.

Limitations: killing the Node browser-service process with SIGKILL cannot run its
publisher. Disk failure or loss of the event directory can also prevent delivery.
Existing observed host-operation failures and Linux-instance events remain
available, but passive Node-service SIGKILL detection is not claimed. Guest root
can inspect its own browser service, process memory and shared files; this
channel does not create a security boundary against that account. No runtime
pack is installed by this infrastructure change on behalf of a model. Physical
browser-pack installation and real-provider autonomous repair/login/task
acceptance are still open.

Browser-side verification: 52 Node/Chromium tests passed without skips after
selecting the installed Chromium executable. The initial integration invocation
used a missing default executable and failed two tests; it was not reported as
passing. These controlled local-site tests include actual browser disconnection
with no active wait RPC, encrypted atomic publication, returned-control isolation,
form login, account isolation and cancellation. They are not real-provider
autonomous website acceptance.

Android 1.4.176 (1261): both APK builds passed in 11 minutes 22 seconds; 126 JVM
tests across 15 suites passed with zero failures, errors or skips. S20U received
an in-place update preserving user data. All four new device checks passed in
47.698 seconds, including an actual Linux request copying an encrypted fixture
through the 9P mount and atomically renaming it into the observed directory.
The native callback authenticated the envelope and saved the interruption before
the injected Run wakeup. No browser operation, provider request or model poll
was needed to receive that event. Additional cases verify pre-commit recovery,
late-event isolation, corrupt/oversized envelopes and a durable failed wakeup.

The 31 existing device regressions passed in 93.672 seconds with both opt-in
runtime probe flags enabled and no skips. Logs are retained under
.local-artifacts/autonomous-problem-solving/s20u-1.4.176-*.txt; the controlled
browser transcript is browser-1.4.176-integration.txt in the same directory.
This verifies the real shared-directory delivery and browser-service publication
separately. It does not prove a complete phone Chromium-to-supervised-model
workflow, passive Node SIGKILL detection or real-provider autonomous repair and
authenticated website completion.

## Local reasoning and phone tool ownership

Ordinary on-device model requests now disclose the existing Linux diagnostic,
runtime control, compatible-software and conversation-file tools alongside web
research tools. The selected local inference backend still makes each decision;
the host does not select a repair from message keywords, forward reasoning to a
cloud provider, install a package implicitly or move execution to Desktop.
Tool errors return through the existing model-tool observation protocol. A
successful installation receipt is not proof that the originally blocked goal
has been completed.

The local runner now derives its file workspace through AgentWorkspaceScope,
matching other phone execution paths. Subsequent turns in one conversation use
the same directory; different conversations remain isolated. Model-supplied file
workspace IDs are replaced by the loop's host-bound workspace before execution.
Collaboration research and publication repair retain their existing scoped tool
views; this change does not give those assignments general shell/file access.

Tool disclosure no longer cuts each schema at 2,000 characters or truncates the
whole prompt at 32,000 characters. If inline schemas exceed the disclosure
budget and the registry includes contract inspection, the prompt lists every
exact available ID and exposes the actual inspection input contract. The model
can request the complete input schema or usage description of a listed tool.
Inspection cannot escape the invoking registry. A scoped registry without that
tool retains complete inline schemas instead of advertising a nonexistent
inspection operation. This is local prompt disclosure, not an implementation of
a provider-specific tool-search API.

Interactive browser takeover is intentionally not added to this local asynchronous
connector yet. That path needs a durable continuation bound to the original
connector response, profile and outer Run before a human handoff can safely
pause and resume. Merely adding browser IDs or treating a waiting result as
completion would strand or misroute the request. Real local-model autonomous
dependency repair and authenticated website acceptance remain open; scripted
inference is only framework regression coverage.

The outer asynchronous local-connector path still needs end-to-end acceptance
for task cancellation and visible tool-progress projection as well as durable
human-handoff resumption. The generic loop's cancellation/event interfaces alone
are not evidence that every outer connector supplies the correct Run binding.

Android 1.4.177 (1262): both APK builds passed; 170 JVM tests across 21 suites
passed with no failures, errors or skips. After correcting a test assertion to
compare decoded JSON text rather than escaped transport text, the instrumentation
APK was rebuilt successfully. S20U received an in-place update preserving data.
Four new device checks passed in 2.213 seconds through the real local adapter and
loop with explicitly scripted inference. They verify the production registry's
full contract inspection, actual file write/read across turns, rejection of a
model-supplied foreign workspace, model-directed failure/repair/original-operation
verification, and ordinary conversation without tool calls. No local model,
provider, package download or real website was invoked by these fixtures.

All 35 prior device recovery checks also passed in 99.079 seconds with both real
runtime probe flags enabled and no skips. The transcripts are
.local-artifacts/autonomous-problem-solving/s20u-1.4.177-local-tools.txt and
s20u-1.4.177-recovery-regression.txt. These checks do not establish real-model
repair/login competence or a production latency bound.

## Event-driven cancellation of local tool loops

PhoneExecutionAuthority now supports task-specific cancellation subscriptions.
Registration and the cancellation mark share a lock, but callbacks run outside
it. A dispatch subscribes before entering the executor queue; a previous STOP
therefore skips inference entirely. Repeated STOP is one-shot, and one failed
observer cannot prevent other observers from receiving cancellation. Finishing
or rejected queued work disposes its subscription.

The local connector owns a lease with an atomic ACTIVE-to-COMPLETED/CANCELLED
decision. Its token enters both the model-tool request and the local request's
coroutine Job, so native-tool hooks and suspended inference receive the same
event without a cancellation polling loop. Completion cannot be reclaimed by a
late STOP, and a STOP-winning request cannot append an ordinary answer/error
after it unwinds. Host-managed team acknowledgement follows unwind instead of
claiming that remote work stopped when the button was pressed. No shared Linux
runtime is reset and no other conversation's token is cancelled.

This does not prove immediate interruption of a blocking hardware inference
backend. Such a backend may need to finish its current cooperative boundary
before the coroutine unwinds; its late output is still suppressed. Dedicated
model-contact outgoing-history cancellation labels, all collaboration STOP
entry points, visible local tool-progress projection and durable browser
continuations still require further integration/acceptance.

Android 1.4.178 (1263): both APK builds passed in 11 minutes 43 seconds. All
192 JVM tests across 24 suites passed without failures, errors or skips; one
test exercises 100 completion/STOP races. S20U was updated in place. Six local
adapter/tool/cancellation device checks passed in 2.409 seconds, including a
waiting native executor and suspended scripted inference. Authority cancellation
settled the operation and suppressed delivery without another inference call.
These are framework-notification tests, not physical STOP-button automation,
hardware inference interruption or real-model autonomous acceptance.

The 35 existing browser/runtime recovery regressions passed in 96.475 seconds
with both real-runtime probe flags enabled and no skips. Logs are
.local-artifacts/autonomous-problem-solving/s20u-1.4.178-local-cancellation.txt
and s20u-1.4.178-recovery-regression.txt. Dedicated-contact cancellation labels,
all managed-team cancellation routes and visible local progress remain open;
these results do not establish end-to-end coverage of those paths.

## Exact local dispatch and managed STOP ownership

Local inference dispatches now register their source message, contact,
conversation, turn, task and action as one exact identity before entering the
executor. Managed receive intents are persisted at that same transport boundary,
before a fast result or STOP acknowledgement can arrive. This closes the local
path's missing pre-dispatch receive-intent window; it does not establish all
cross-process recovery paths.

The local lease also subscribes to the supervising turn's cancellation token,
including cancellation already requested before queueing. Managed STOP recovery
checks both cloud and local registries even when MQTT is unavailable. Exact
local cancellation does not mark a shared task globally cancelled: siblings
with another dispatch identity are unaffected unless separately stopped. The
registration is retired on completion, unwind, rejected queue admission or a
throwing delivery callback. Duplicate registration cannot replace the original
lease or leak its cancellation listeners.

Only a settled local cancellation updates dedicated outgoing history to the
localized Stopped status. It creates no incoming failure answer. A managed
cancellation instead enters the existing encrypted supervisor receipt path;
the supervisor owns it, and a late success cannot replace the first terminal
receipt. Queued work waits for its executor to observe cancellation before
claiming settlement; blocking hardware inference remains a cooperative-boundary
limitation.

### Browser continuation integration still required

Interactive browser tools must not be advertised to a local loop merely by
adding their IDs to its catalog. The current browser wake policy binds the
original planning checkpoint or native ActionPlan. A local connector loop has a
different dispatch/session binding and currently requires a final nonempty
answer; it has no durable nonterminal handoff-to-response continuation. It still
needs an exact persisted provider/profile, dispatch identity, loop checkpoint
and owning Run binding, an external-event wake route, and visible local progress.
No inference polling or new dispatch identity should be introduced to substitute
for resuming that checkpoint.

On user return, page observation must precede any claim of authenticated success.
[Playwright authentication](https://playwright.dev/docs/auth) demonstrates
checking the final URL or an authenticated page control after redirects and
warns that saved authentication state is sensitive.
[Browser disconnect events](https://playwright.dev/docs/api/class-browser#browser-event-disconnected)
are useful while the service is alive, but cannot report the service's own
SIGKILL; that requires an independent process-lifecycle observation. Neither a
return event nor absence of a disconnect is evidence that login or the user's
business goal succeeded.

### Persistence defect found by the S20U check

Android 1.4.179 (1264) built successfully in 12 minutes 40 seconds, and all
226 JVM tests in 27 suites passed. The S20U run passed eight of nine checks;
the new managed-local STOP check failed after reopening its encrypted ledger.
The receipt had reached the correct supervisor, but `AgentManagedResponseCodec`
did not serialize `taskStatus`, `executionGeneration` or `statusSequence`.
Its readback therefore silently discarded the cancellation outcome/version.
The failing assertion was retained, not relaxed. The original failure log is
.local-artifacts/autonomous-problem-solving/s20u-1.4.179-local-managed-stop.txt.

The corrective change preserves those three fields in both directions. Records
created before those fields existed keep their original success/failure boolean,
blank status, generation 1 and sequence -1; no cancellation is invented from
their display text. New terminal outcomes determine the success boolean, and
malformed execution versions or nonterminal statuses are rejected. The added
codec regression covers all terminal statuses, blank legacy status, three
generations and three sequence values, plus inconsistent/malformed records.
These fixes require the subsequent build and device rerun before acceptance.

Android 1.4.180 (1265) subsequently built successfully in 11 minutes 46 seconds.
All 255 JVM tests in 31 suites passed with no failures, errors or skips, including
45 terminal-status/generation/sequence round-trip combinations inside the codec
test. The unchanged failing S20U assertion now passes after encrypted ledger
recreation. All nine local/managed/cloud STOP checks passed in 10.970 seconds:
the stopped local member's receipt remains cancelled, a late success cannot
replace it, its sibling remains active, and dedicated history has no fabricated
incoming error. These are public framework fixtures, not manual STOP-button or
hardware inference acceptance.

The 35 browser/runtime recovery device regressions passed in 81.683 seconds with
both runtime probe flags enabled and no skips, bringing this version's device
total to 44. The Node/browser run passed all 52 tests with no skips in 12.215
seconds, including real Chromium fixture login, pagination and context isolation.
This remains browser-component verification, not real-model autonomous login.

S20U was updated in place without clearing data; installed version 1.4.180/1265
was read back from Android. Evidence files are:

- .local-artifacts/autonomous-problem-solving/jvm-1.4.180-summary.json
- .local-artifacts/autonomous-problem-solving/s20u-1.4.180-local-managed-stop.txt
- .local-artifacts/autonomous-problem-solving/s20u-1.4.180-recovery-regression.txt
- .local-artifacts/autonomous-problem-solving/browser-node-1.4.180-regression.txt

The full goal remains unverified. Local browser continuations, visible local
progress, all physical STOP entry points and blocking hardware interruption
still require integration/acceptance. Real-provider autonomous repair, authorized
login and sustained goal completion have not been established by these fixtures.

## Local model progress delivery (1.4.181)

The local connector now supplies an event sink to its existing model-owned tool
loop. It uses the same localized timeline text as the planning loop, without
copying tool arguments, model prompts, hidden reasoning or a provisional answer
into final assistant history. Tool progress and terminal observations update one
encrypted process row per scoped call. The existing window notification path
refreshes visible windows; no Activity is captured by the inference worker.

Each sink is bound to the exact dispatch's conversation, turn and native task.
Session/task/turn mismatches, a foreign loop, duplicate or older event sequences,
post-terminal events and events received after cancellation are ignored. Storage
failure does not consume the fence sequence. This is not a transactional guarantee
against cancellation racing an already-started storage write.

Managed members use their existing host-registered source/conversation/turn/task
binding and member metadata. Missing or mismatched bindings cannot fall through
to an unattributed ordinary transcript. Ordinary progress can update liveness
only for the matching nonterminal UI turn workspace. A real model-request event
records a heartbeat; actual tool/model observations record progress. No timer
heartbeats or repeated model calls are introduced to conceal inactivity. Managed
member progress does not manufacture activity for a different parent workspace.

The version adds six JVM fence regressions and four Android checks for encrypted
row readback, redaction, ordering, STOP, workspace identity, member attribution and
the local adapter's failure/verification loop. The latter uses scripted inference
and a public tool fixture; it does not establish real-model autonomous repair.
The main APK built and was installed in place on S20U as 1.4.181/1266. All 145
selected JVM tests in 17 suites passed without failures, errors or skips. The
initial test-package compilation exposed a missing required fixture delivery
mode, which was corrected. Fixture workspace setup was also corrected to respect
immutable workspace identities rather than changing an existing identity.

The first 13-check device run passed 12 checks. Its local-adapter fixture blindly
repeated the identical failed operation without an intervening repair, so the
existing repeated-call guard correctly prevented a second execution. The original
failure log is retained as s20u-1.4.181-local-progress-stop.txt. The fixture now
explicitly observes the missing dependency, performs a distinct repair action,
and verifies the original build. Its assertions require all three actual actions,
four inference rounds, the original failure row and no fabricated final answer
in process history. The corrected device run passed all 13 checks in 18.476
seconds, with no skips. The browser/runtime device regression passed all 35
checks in 86.496 seconds, with both runtime probe flags enabled and no skips.
This version therefore passed 48 distinct device checks. The final test-package
rebuild completed successfully in 2 minutes 37 seconds; the main APK was not
changed by fixture-only corrections.

Evidence is retained under .local-artifacts/autonomous-problem-solving/:

- jvm-1.4.181-summary.json
- s20u-1.4.181-local-progress-stop.txt (original fixture failure)
- s20u-1.4.181-local-progress-stop-rerun.txt (13 passing checks)
- s20u-1.4.181-recovery-regression.txt (35 passing checks)

Local interactive-browser durable continuations and real-provider autonomous
login/repair acceptance remain open. The progress sink does not advertise new
browser tools or change ASR/QNN inference, routing, pairing or MQTT behavior.

## Local dispatch continuation identity (1.4.182)

Local connector loops now derive their durable identity from the exact original
dispatch: source message, contact, conversation, turn, transport task and action.
Previously the loop ID depended on the generated prompt and model preference;
changing either could select a fresh journal rather than the existing checkpoint.
The transport task remains distinct from the UI turn/Run workspace. No guessed
Run identity or current foreground conversation is substituted.

Before inference or tools, the runner commits its original prompt, explicit model
preference, attachment flag, collaboration source, system prompt and manifest hash
to the existing chunked encrypted Run Kernel journal. A new store instance can
restore this envelope by exact dispatch identity, without regenerating context or
routing. A locale change retains the saved system prompt. Changed input, model
preference, attachment ownership, collaboration source or catalog is rejected
before execution instead of selecting another executable loop. Missing/corrupt
records do not fall through to a fresh request. An existing legacy checkpoint
requires reconciliation; it is not silently replayed under the new identity.

An empty model preference still means the existing local cooperation policy.
This change preserves that policy; it does not freeze the set of enabled models
or claim that Auto selects the same physical inference model after configuration
changes. An explicit preference is restored unchanged. ASR/QNN implementations,
pairing, MQTT and the disclosed local tool catalog are unchanged.

The new continuation fixture exercises the actual local adapter with scripted
inference, encrypted journal and browser host-event resolver. Waiting produces no
model polling. Return is committed as an observation before the next model round;
the model then requests a page observation. The already executed handoff is not
repeated, and completed replay requires neither inference nor tools. This is a
framework fixture, not real-provider autonomous login or website acceptance.

This is a prerequisite, not complete production local-browser continuation.
The exact owning Run binding, durable wake dispatcher, nonterminal local response
handling, original-source final delivery and managed-member browser ownership
still need end-to-end integration. Interactive browser tools remain undisclosed
to local connector loops until those paths are connected.

Android 1.4.182/1267 built successfully in 11 minutes 52 seconds and was installed
in place on S20U without uninstalling or clearing data. Android's installed
version was read back as 1.4.182/1267. All 127 selected JVM tests in 14 suites
passed without failures, errors or skips, including ten new continuation tests.
All 16 local continuation/progress/STOP device tests passed in 21.572 seconds;
all 35 browser/runtime regressions passed in 90.047 seconds, with both runtime
probe flags enabled. No device checks were skipped. The 51 distinct device
checks are current-version results, not the previous build's totals.

Evidence is retained under .local-artifacts/autonomous-problem-solving/:

- jvm-1.4.182-summary.json
- s20u-1.4.182-local-continuation-stop.txt
- s20u-1.4.182-recovery-regression.txt

## Owned local-browser recovery (1.4.183)

Ordinary local connector dispatches can now disclose interactive browser tools
when their exact supervised Run and persisted native plan node are available.
The small encrypted routing envelope binds the original source/contact,
conversation/turn/native task/action, UI Run identities and dispatched node hash.
It contains no model prompts or browser credentials. Prompts and tool/model
results remain in the chunked encrypted loop journal introduced in 1.4.182.
Dedicated contact history and managed research members retain their previous
tool views; an unbound local browser request cannot adopt a planner's Run.

A local loop waiting for user control returns a nonterminal completion. It does
not publish an answer, mark the source replied, acknowledge context or report
model success. The host wait event suppresses silence assessment without fake
periodic heartbeats. A settled host event enqueues a generation-bound durable
worker, which restores the original request rather than reconstructing a prompt
or redispatching the connector action. A fast user return waits for the initial
lease to close. Worker observation cancellation is not user STOP.

Recovery rechecks conversation existence, Run/session ownership, the native plan
node, explicit pause, cancellation and pending source before invoking the runner.
Old/superseded events cannot execute. A previous-process crash before committing
the pending connector response can restore that binding only from its original
saved dispatch anchor and unchanged native session; the write uses the existing
compare-and-restore session API. Missing/corrupt loop evidence does not start a
fresh executable request. Final delivery uses the original connector response
inbox and its durable receipt, never the current foreground conversation.

This remains a framework integration, not complete autonomous website/login
acceptance. Device fixtures inject inference decisions; Node browser fixtures
exercise actual Chromium on controlled pages. Managed-member browser ownership,
independent Node SIGKILL detection, uncertain side-effect reconciliation and
real-provider obstacle/repair/login acceptance remain open. This version does
not install a browser pack or modify ASR/QNN inference implementations.

Android 1.4.183/1268 built successfully in 10 minutes 53 seconds after fixing an
incorrect executor class reference caught by compilation. All 143 selected JVM
tests in 16 suites passed, with no failures, errors or skips. A test-only rebuild
(2 minutes 53 seconds) isolated synthetic contact/health records from real model
routing. Both APKs were installed in place on S20U; the installed version was
read back from Android as 1.4.183/1268. No uninstall or data clear was performed.

The local recovery/continuation/progress/STOP group passed all 24 checks in
30.623 seconds, including eight new encrypted routing/recovery broker checks.
The browser/runtime regression passed all 35 checks in 87.952 seconds, with both
runtime probe flags enabled. No checks were skipped. Thus this version passed
59 distinct device framework checks. The browser Node regression passed all 52
checks, including its controlled Chromium integration, without skips. These
numbers do not represent real-provider autonomous login or repair acceptance.

The final cold StartupActivity launch reported TotalTime=690 ms and WaitTime=693
ms; MainActivity was subsequently confirmed as the top resumed Activity. This
is an Android launch measurement, not a full first-content latency benchmark.
The crash buffer was empty. Evidence under
.local-artifacts/autonomous-problem-solving/ includes:

- jvm-1.4.183-summary.json
- node-1.4.183-browser.txt
- s20u-1.4.183-local-browser-continuation-stop.txt
- s20u-1.4.183-recovery-regression.txt
- s20u-1.4.183-installed-package.txt
- s20u-1.4.183-cold-start.txt
- s20u-1.4.183-resumed-activity.txt
- s20u-1.4.183-crash-buffer.txt

## Independent browser process exit monitor (1.4.184)

The browser CLI now starts an independent parent supervisor and keeps the browser
daemon as its child. An active host handoff registers its exact session, page,
handoff and encrypted event generation over private IPC. Begin/reattachment waits
for the parent's acknowledgement; release waits for monitor retirement. Old
lease retirement cannot remove a replacement lease or another generation.

Only an actual ChildProcess exit publishes a generation-bound encrypted
session_lost observation. IPC disconnect, request timeout and failed acknowledgement
are not proof of process death. The monitor owns no pages or model calls and
does not restart a browser or replay a mutation. The original model still needs
to inspect external state, choose recovery and verify the result. No page body,
password or browser control token is copied into monitor messages.

Failed retirement rejects existing observers instead of leaving them blocked;
a session lost during reattachment closes the new sink. Browser control release
is not evidence that login or the user's business task succeeded.

All 64 Node regression checks passed, with no skips. These include controlled
Chromium login/observation fixtures and SIGKILL of the actual browser daemon:
the independent parent published the exact encrypted handoff event without a
subsequent RPC or model poll. Evidence: node-1.4.184-browser.txt under
.local-artifacts/autonomous-problem-solving/.

This addresses child daemon death, not simultaneous death of its supervisor or
the whole guest. S20U currently has linux-base and python-uv packs but no Node or
browser pack; phone packaging/event recovery tests must not be presented as an
end-to-end phone Node SIGKILL or real-provider autonomous-login acceptance.
Those acceptance gaps remain open.

Android 1.4.184/1269 built in 11 minutes 22 seconds; all 170 selected JVM tests
in 19 suites passed without failures, errors or skips. Both APKs were installed
in place on S20U and Android reported version 1.4.184/1269. All four browser
assets in the built APK matched their source SHA-256 hashes, including the new
supervisor module. No data clear, uninstall, re-pairing or model replacement was
performed.

S20U passed the 24 local recovery/continuation/progress/STOP checks in 30.629
seconds and all 35 browser/runtime checks in 86.524 seconds; runtime probe flags
were enabled. These are 59 distinct device framework checks, not real-provider
website acceptance. Cold StartupActivity launch reported TotalTime=693 ms and
WaitTime=698 ms; this is not a full first-content latency benchmark.

Additional evidence under .local-artifacts/autonomous-problem-solving/:

- build-1.4.184.txt
- jvm-1.4.184-summary.json
- apk-1.4.184-browser-assets.json
- s20u-1.4.184-installed-package.txt
- s20u-1.4.184-local-browser-continuation-stop.txt
- s20u-1.4.184-recovery-regression.txt
- s20u-1.4.184-cold-start.txt

## Capability discovery for model-selected repair (1.4.185)

The previous describe tool refused registered capabilities whose availability
was not AVAILABLE. Together with the local available-only prompt catalog, this
prevented a model from learning the contract or setup blocker of a capability
it needed to repair. This was a framework discovery gap, not proof that a model
could not reason about the problem.

galaxyssi.tools.discover now searches registered IDs, titles and descriptions
within the invoking registry view, including unavailable capabilities. Each
page contains at most 50 metadata entries, with explicit description truncation
and a contract inspection reference. Continuation is bound to the normalized
query and a deterministic catalog revision. Availability/contract/view changes
invalidate the cursor; volatile checked-at timestamps do not. Explicit discovery
refreshes availability without invalidating ordinary prompt caches on every turn.
Excluded tools remain excluded. Discovery executes no target and performs no
installation or automatic repair.

galaxyssi.tools.describe can inspect a registered unavailable tool's schema,
description and availability, while invoking that tool still checks availability.
The model chooses diagnostic, installation or alternative tools and verifies the
original operation. Generic unavailable results now distinguish non-execution
from goal failure. Unfinished side-effect claims explicitly retain outcome_unknown,
executed_again=false and goal_terminal=false; they do not assert that the original
effect failed. The existing effect owner remains intact.
Capability discovery and contract inspection are not evidence of an earlier
external effect and cannot unlock a repeated mutation. The model still needs an
external-state observation; a regression checks that metadata-only steps cannot
cause a second submission.
Explicitly unknown mutation outcomes require an intervening external observation
even when the ordinary repeated-signature budget permits multiple attempts.
The uncertainty fence is reconstructed from committed tool results on recovery,
not from a new global cache or a lifetime action counter.

This follows the separation of discovery, tool contracts and model-visible
execution errors in the MCP tools specification:
https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2025-11-25/server/tools.mdx

New tests cover complete pagination, unavailable metadata without execution,
restricted views, changing availability, stale/malformed cursors and Unicode
cursor bounds. A phone fixture exercises the actual local JSON adapter from an
available-only initial catalog through discovery, inspection, injected dependency
repair and verification. Injected decisions/dependencies are framework evidence,
not real-provider autonomous repair or login acceptance.

The full objective remains open: real-model browser/dependency/login acceptance,
managed-member browser ownership, uncertain external-effect reconciliation and
recovery across actual tool-contract/runtime changes still need integrated proof.

### Verification of 1.4.185 on S20U

Version 1.4.185 (versionCode 1270) and its test APK were installed in place on
SM-G9880, preserving application data. The final build passed 256 JVM tests
across 27 suites with no failures, errors or skips. Earlier build attempts
identified and repaired a syntax error, a missing test invocation argument and
the existing explicit catalog expectation for the new discovery tool.

All 26 local recovery/continuation/progress/STOP/tool-adapter device checks passed
in 33.831 seconds. All 35 browser/runtime device checks passed in 85.880 seconds
with runtime probes enabled. The Node browser suite passed all 64 checks,
including controlled Chromium login and supervised child-process termination.
These are framework regressions, not real-provider autonomous website acceptance.

After the tests, a force-stop and cold launch reported TotalTime=681 ms and
WaitTime=697 ms. MainActivity was confirmed resumed and the crash buffer was
empty. Activity startup time is not a full first-content latency benchmark.

The public android-runtime-v1 release contains the Node and Playwright browser
packs. Their publication does not prove installation or autonomous use on S20U;
the model still needs to select, install and verify those dependencies itself.
Availability-aware continuation after dependency repair also remains open:
recovery must distinguish volatile availability from immutable tool contracts
without removing scope or checkpoint binding checks.

Evidence is retained under .local-artifacts/autonomous-problem-solving/:

- build-1.4.185-verified.txt
- jvm-1.4.185-summary.json
- node-1.4.185-browser.txt
- s20u-1.4.185-installed-package.txt
- s20u-1.4.185-local-browser-continuation-stop.txt
- s20u-1.4.185-recovery-regression.txt
- s20u-1.4.185-cold-start.txt
- s20u-1.4.185-resumed-activity.txt
- s20u-1.4.185-crash-buffer.txt
- runtime-browser-assets-1.4.185.jsonl

### Incremental delivery validation

Before the first integrated framework PR, the expanded JVM regression passed
701 tests across 90 suites with no failures, errors or skips. Repository Guard
passed against a clean snapshot of the staged source. The existing runtime-tools
CI entry point now includes the four browser suites; its clean-snapshot run
passed 69 checks with six platform-dependent or opt-in integration skips.
Chromium integration was independently exercised in the 64-check browser run
described above. Local logs and application state are not part of the PR.

Future independently verified increments are delivered in new PRs. This first
integrated increment contains the interdependent loop, browser and recovery
foundation accumulated so far; it does not close the overall autonomous goal.
