# Android live planner tool-loop acceptance

This explicit-opt-in instrumentation test calls a configured real cloud model
through `CloudModelClient.nativeToolAdapter`, using the production planner
request factory, model tool loop, protocol adapter and workspace file tools.
No provider response, tool call or resulting file is mocked.

## Privacy and prerequisites

- Install the matching debug app and instrumentation APK on the intended device.
- A ready cloud API contact with usable credentials must already exist. The test
  does not add contacts, alter pairing, select a different user model or write
  planner preferences. Debug fixture credentials are rejected.
- The `providerInventory` preflight prints only model identifiers and a ready
  count, never API keys, endpoint credentials, contact records or chat history.
- Only generated public integers and a random proof marker are supplied to the
  provider. It sees three file tools rooted in a unique test directory, not the
  user's workspace, Linux filesystem, messages, photos or memories.
- Running the live probe can consume provider quota. Without `live_planner=true`
  all tests skip. With opt-in, missing configuration is a failure, not a pass.
- An optional `live_planner_contact` selects an existing contact ID. Otherwise
  the first ready cloud contact is used, without persisting a selection.

## Run

Use an explicit device serial for every ADB command:

```text
adb -s SERIAL shell am instrument -w -r -e live_planner true -e class com.galaxyssi.chat.AgentLivePlannerLoopDeviceTest#providerInventory com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
adb -s SERIAL shell am instrument -w -r -e live_planner true -e class com.galaxyssi.chat.AgentLivePlannerLoopDeviceTest#pairedReasoningInventory com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
adb -s SERIAL shell am instrument -w -r -e live_planner true -e class com.galaxyssi.chat.AgentLivePlannerLoopDeviceTest#realProviderReadsWritesAndContinuesTheWorkspace com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

The first Chinese request asks the model to read a missing input filename,
observe failure, discover the actual source, calculate a sum, write `result.json`
and read it back. The harness checks actual file contents and a random marker
unknown to the model before reading the source. A tool failure and successful
read after writing must be present in the model conversation.

The second request uses a new runtime session and registry but the same
conversation. No prior file contents are copied into its prompt. The model must
read the existing result, increment it and write/read `continued.json`.

Each paid probe has acceptance-only round/token/time bounds; these do not change
production Agent budgets. Only the test directory is removed during cleanup.
Existing user data, model installations and pairing are preserved.

## Scope

This tests real provider-driven tools and workspace continuation. It does not
by itself validate `GuardedModelAgentPlanner` ActionPlan generation, the full
ordinary mobile DAG, MQTT Codex reasoning, multi-day execution, device reboot,
or continuous cross-provider failure recovery. Those require separate tests.
A failed prerequisite or probe must remain visible in the result report; do not
replace the provider with a scripted adapter to make the live test green.

## Observed run (2026-09-09)

- Test-only addition on main `34be01481` (PR #2948). The App remains 1.1.29;
  no product release or user configuration was changed.
- The instrumentation APK built successfully in 2m39s and was installed on
  SM-T575 with `adb install -r`. Repository checks passed.
- Cloud preflight **failed**, reporting `ready_cloud_count=0` in 0.251 seconds.
  No live cloud tool-loop execution or file verification is claimed. Do not
  count this as a successful Provider recovery test.
- Paired reasoning inventory passed in 0.266 seconds: seven entries including
  Codex. This checks stored pairing only, not online availability or execution.
  The Desktop health endpoint returned `ok`; its Agent snapshot reported Codex
  `busy`, Hermes `degraded`, and the other entries `needs_setup`.
- Default opt-out was verified: three tests skipped without the explicit flag,
  so ordinary instrumentation runs do not consume Provider quota.
- Final tightened-oracle build passed in 1m45s. Re-running both preflights on
  that APK produced one pass (stored pairing) and one failure (no cloud contact)
  in 0.329 seconds. Default opt-out again skipped all three tests. Evidence:
  `build/live-planner-acceptance-build.log`, `build/live-planner-final-preflight.log`
  and `build/live-planner-final-optout.log`.
- No pairing was recreated, no credentials were copied, no model was downloaded,
  and no Desktop task was cancelled to make this test pass.

Local evidence: `build/live-planner-inventory.log`,
`build/live-planner-paired-inventory.log`, `build/live-planner-default-optout.log`,
and `build/live-planner-inventory-build.log`. Model inventory markers are emitted
to Android `System.out` logcat, not the instrumentation result stream.

Next acceptance requires a configured cloud Provider for this path and a
separate real MQTT reasoning/phone execution test for the paired Codex path.
