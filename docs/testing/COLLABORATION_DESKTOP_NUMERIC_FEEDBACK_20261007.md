# Desktop Numeric Counterexample Recall

Desktop 1.4.23. Android remains 1.4.84 / 1169; this change does not modify
Android, model selection, execution permissions, scheduling, or the UI.

## Defect and Contract

Android already accepts `collaboration_recall` requests with `mode=numeric_cases`
and an optional `case_filter`. The Desktop bridge neither advertised this mode
nor accepted its selectors. A valid request was rejected before reaching the
phone, preventing remote members from reading the same numerical counterexamples
available to the Android cloud-model adapter.

The bridge now advertises and validates that existing read-only contract:

- Exact trial `object_id`, positive integer `revision`, and `sha256` are required.
- The optional filter supports `failed`, `all`, `domain_error`, `improved`,
  `regressed`, `error_reduced`, `error_increased`, `domain_recovered`, and
  `domain_failed`. Omitting it retains the phone's `failed` default.
- An opaque cursor and the same trial/filter identify subsequent content pages.
  Members concatenate those pages before decoding the saved cases.
- Invalid selectors and cross-mode filters fail before transmission.
- Authenticated phone identity, task scope, execution generation, cancellation,
  and the existing recall retry protocol remain unchanged.
- Phone errors, original values, pagination, and trust labels are returned
  unchanged. The bridge neither recomputes results nor declares a trial passed.

The tool description distinguishes saved host-computed numerical checks from
independent reference truth and from evidence of generalization. Reading a
counterexample does not authorize new execution or grant another member's data.

## Regression Coverage

The new test file initially produced three failures and three errors across
seven tests against the old bridge. The same tests pass after the change.

Verified locally:

- 35 focused numeric-recall, recall-bridge, and recall-retry unit tests passed.
- 154 broader Python tests and 103 subtests passed, including dynamic Codex tools,
  tool evidence, conversation identity, experiment boundaries, and startup
  concurrency.
- Desktop's 68 JavaScript checks and structure validation passed.
- Four `CollaborationNumericFeedbackDeviceTest` instrumentation tests passed on
  an authorized SM-S9480 using synthetic data and real encrypted local storage.
  These cover reopening evidence, paging, invalid requests, member revocation,
  and cloud/phone-tool projection parity. Application data was not cleared.

The Python round trips use mock authenticated phone replies, including a real
`RecallBroker` and the Codex dynamic-tool callback. The instrumentation method
whose name mentions Desktop compares phone-side adapters in process; it does
not exercise a live Desktop or a public MQTT broker.

No new real-model request was made for this increment. These results establish
interface parity, not autonomous counterexample repair, peer-driven method
improvement, retained skills, or transfer to unseen tasks. Publishing useful
versioned results while a worker is still running remains separate architecture
work; this patch does not mark partial work complete or change dependency rules.

## Reproduction

From `apps/desktop/core/galaxyssi-link/backend`:

```powershell
python -B -m pytest -q test_collaboration_numeric_recall.py test_collaboration_recall_bridge.py test_collaboration_recall_retry.py test_codex_tool_evidence.py test_agent_tool_evidence.py test_codex_conversation_threads.py test_codex_experiment_boundary.py test_codex_startup_concurrency.py
```

From the repository root:

```powershell
npm run check --prefix apps/desktop
npm run check
git diff --check
```

With the matching debug and instrumentation APKs already installed, select only
the authorized test phone and run:

```powershell
adb -s <authorized-device> shell am instrument -w -r -e class com.galaxyssi.chat.CollaborationNumericFeedbackDeviceTest com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

Private manuscripts, model traces, experimental data, and runtime state are not
part of this change.
