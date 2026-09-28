# Real Android Business Scenarios

This is an opt-in product test, not a replay benchmark or a model score.
The requested end state is 100 business scenarios with text, images and charts,
up to ten follow-up questions, measured on the real product, with fixes and PRs.
Generating the catalog does not satisfy that end state.

## Current Coverage

The initial catalog has 100 workload records across 20 business contexts and
five input forms: text, image tables, bar charts, line charts and paired images.
Each record currently has an initial request and ten follow-ups. It exercises
extraction, comparison, 100 distinct closed-world business decisions, corrections, hypothetical values, history,
missing evidence, undoing a change, tables and a final summary. Selected turns
run with the app in the background or after reopening its conversation window.

These are mostly numeric workflows. More varied business tasks, tool use and
artifact delivery are still required before calling this a comprehensive
100-scenario functional evaluation. Audio/video and device actions are not
covered by these fixtures.

## Safety and Evidence

- Only an explicitly selected S26U (`SM-S9480`) can run the live test.
- Data and attachments are synthetic. Conversations are private test records.
- No door access, payments, contact messages or production file changes.
- Use the configured real model and transport; never inject expected replies.
- Expected answers stay in the local verifier, not prompts or attachments.
- A reply is complete only after its parent workspace is terminal and its run
  is inactive. A child reply or temporary transcript entry is not completion.
- A timed-out observation remains a checkpoint, not a cancelled task. Inspect
  it before retrying; the runner refuses to resend an unresolved turn.
- Reports retain failures and the full planned denominator. A partial run is
  not a passing suite. Different catalog hashes cannot be combined.
- JSON assertions do not establish the quality of all prose. Review screenshots
  and answers separately. USB battery/temperature samples are not energy usage.
- The transcript `rendered` check is a view-model check, not pixel verification.

## Generate and Check

```powershell
python -m unittest discover -s tools/benchmark/business-scenarios -p test_catalog.py -v
python tools/benchmark/business-scenarios/catalog.py --output C:/Temp/business-eval/plan.json --inventory C:/Temp/business-eval/inventory.md
```

Build the normal debug app and instrumentation APK. After selecting the device
explicitly, push the plan to
`/sdcard/Android/data/com.galaxyssi.chat/files/business-eval/plan.json`.
Do not run instrumentation on another phone or a watch.

```powershell
adb -P 5038 -s $env:GALAXYSSI_TEST_DEVICE shell am instrument -w -r `
  -e class com.galaxyssi.chat.BusinessScenarioLiveDeviceTest `
  -e business_live true -e business_run pilot-new-run `
  -e business_cases B001,B002,B003,B004,B005 `
  -e business_turn_limit 11 -e business_provider codex `
  com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

The observation timeout is configurable from 30 to 900 seconds. It is not a
product deadline and does not stop a remote model. The run directory contains
one JSON report per case, generated fixtures and screenshots. Pull it from the
same external-files directory. Use `report.py --plan ... --reports ... --output
...` to aggregate one run/catalog. Keep evidence outside the repository.

## First Pilot Findings

The initial two-turn text pilot exposed the following, not a passing result:

1. The old test driver advanced after an intermediate assistant entry, before
   the parent task had settled. Its next question became a steering update.
2. A supervised response could be rendered by a different window before its
   internal final-response envelope had been decoded.
3. A managed Codex child response reached the phone transport but was treated
   as superseded merely because the parent had another source ID. The child
   intentionally uses a separate managed-response ledger, not an ordinary
   pending-delivery record. The exception now requires a registered managed
   owner with the exact source, conversation and turn. Unknown sources and
   ordinary retired-source tombstones remain rejected.
4. Managed replies bypassed the normal application-receipt journal, leaving
   the Desktop archive unacknowledged even when the supervisor consumed them.
5. A business JSON `code` field was classified as coding work. Task-intent
   classification, capability routing and phone code execution now ignore
   quoted property names and embedded English keyword substrings. Real code
   requests remain covered by positive regressions.
6. The conversation renderer excluded public tool events. It now includes
   concrete connector activity (such as Stockfish or image inspection) while
   keeping internal audit scaffolding and generic heartbeats hidden. UI and
   render signatures use the same visibility policy.

The first four have targeted changes with passing regression checks: 16 JVM
tests, 35 device tests, and two receipt persistence tests run in separate
instrumentation processes. Five catalog/report tests also pass. The device
fixture test rendered 100 synthetic images; representative table, bar, line and
paired-image outputs were visually inspected. These are not real-model passes.
The initial pilot remains failed evidence and must not be silently relabelled
after a code change. The full live campaign remains incomplete.

The additional intent and public-progress changes passed 83 JVM tests and an
Android build. Their end-to-end visual verification still requires an unlocked
test phone. The live runner rejects a locked phone before sending, and selects
configured DeepSeek cloud models by provider identity rather than an Agent-only
filter or display-name guesses.

## Managed Reply Recovery Follow-Up

Cold-start discovery previously enumerated only ordinary pending deliveries.
Managed child tasks have a separate durable ledger, so a lost child result could
remain missing even after the supersession check was repaired. Discovery now
includes pending managed identities without writing them into the parent turn's
journal. Each task still uses its own authenticated query, existing pacing and
generation fence. Completed, cancelled, mismatched and retired tasks are not
eligible. A sibling's response does not satisfy another child sharing the turn.

Device regression also exposed a retirement check that depended on a turn head
still existing. Explicit retirement is now checked first, including a child that
never had an ordinary head and a head cleared on completion or cancellation.

The opt-in `AgentLiveFinalRecoveryDeviceTest` supports `live_final_managed=true`
on `submitAndDropOnlyTestFinal`, followed by a real process stop and
`restartAutomaticallyFetchesManagedChildBody`. It requests a harmless real Codex
reply once, drops its initial delivery, then requires normal connection readiness
to discover and fetch the archived body. It does not resubmit the model request
or insert a synthetic reply. A setup checkpoint must be inspected before retrying.
Installing an APK between phases can itself restart the app and recover the
reply before the assertion begins; preserve that evidence rather than relabelling
the strict test as passed.

Validation on S26U: 52 targeted JVM tests and 35 device regressions passed,
including a 10,000-row encrypted pending journal. A fresh controlled real-Codex
case passed both setup and post-force-stop recovery phases: 1,927 ms connection
setup plus 2,671 ms after readiness, 4,598 ms total. Its recovered content and
complete task identity match the originally dropped reply, with no ordinary UI
inbox entry. This is one recovery sample, not a p95 or a business-suite pass.
The initial pilot's missing child reply was also recovered into its managed
ledger; its parent remains paused and the historical pilot remains failed.
