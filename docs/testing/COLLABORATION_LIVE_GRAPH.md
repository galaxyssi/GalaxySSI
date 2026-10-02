# Live Collaboration Graph Acceptance

## Purpose

Verify that a real incremental coordinator can append independent work while an
unrelated member remains active, and that the program persists the addition before
dispatch. This is distinct from proving domain correctness or a multi-agent quality
advantage.

`CollaborationLiveExpansionDeviceTest` is opt-in. It uses the authorized phone's
paired Codex Desktop and configured DeepSeek. Do not run it in unattended CI or
against another device without authorization.

## Real-provider sequence

1. Create an isolated group with one Codex author/coordinator and one independent
   DeepSeek reviewer. Preserve the user's previously selected conversation.
2. Run the real author alongside an explicitly local harness gate. The gate is not
   a third model, research result, or acceptance evidence; it releases its execution
   permit while held.
3. Save a synthetic document containing a fresh token and four supplied numbers.
   Require a literal synthetic-input marker to avoid locale-dependent assertions.
4. Ask the real incremental coordinator for `galaxyssi.work-expansion.v1`. Its
   unchanged JSON must append a new independent VERIFY task depending only on the
   completed document, not on the still-held gate.
5. Reopen the encrypted execution store and verify the exact task and completed
   planner result before invoking DeepSeek.
6. Require DeepSeek to read the author's exact saved revision through the production
   scoped recall tool. Check its actual read receipt, the review's exact target and
   parent, and the linked host-observation ID/digest.
7. Release the gate only after the new review's success is durably recorded. The
   final coordinator must receive every executable dependency, including newly
   appended planner and review nodes, without truncation in this small fixture.
8. Record graph execution and host documentary acceptance separately. An honest
   `continue` is not falsely promoted to `achieved`.

The fixture requests only synthetic document work and read-only recall. Its ledger
assertions cover recorded observations; incomplete provider telemetry is not an
enforced guarantee that no other tool ran. It does not verify a no-tools sandbox.
Do not report this as physical/scientific validation or complete tool-policy proof.

## Running

Install matching application and test APKs, keep the authorized phone unlocked,
and use its explicit serial:

```powershell
adb -s AUTHORIZED_SERIAL shell am instrument -w -r `
  -e collaborationLiveExpansion true `
  -e class com.galaxyssi.chat.CollaborationLiveExpansionDeviceTest `
  com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

The 12-minute harness deadline and 90-second cleanup wait bound a test, not a
product goal. No original research, contacts, doors, or other devices are involved.
Each run writes `live-expansion-UUID.json` under the app's external files directory.
Only these synthetic reports may be exported; do not upload user conversations,
provider credentials, or pairing state.

Cleanup persists STOP and uses exact-run stop recovery. It removes the dedicated
group, conversation and execution database only after local settlement and no
pending managed response owners remain. A failed acknowledgement retains those
records and diagnostics for recovery; local cancellation is not remote completion.

## Local recovery coverage

`CollaborationLiveGraphDeviceTest` separately checks live append ordering using
local workers, plus a seed/recover pair in different Android processes. The pair
reopens the expanded graph and completed producer/planner results without replay,
then runs the remaining review/final work once. It also checks original goals and
contexts larger than former persistence truncation boundaries.

These tests do not substitute for real-provider interruption, Doze, reboot,
long-offline, large-graph performance, or longitudinal memory acceptance.

## Recorded attempts: 2026-10-02

- First real-provider attempt: **failed in 111.774 seconds** at the author assertion.
  The real Chinese output clearly identified synthetic inputs and no experimental
  observation, but the fixture accepted only the English word `synthetic`. The
  fixture now requests and checks a literal ASCII marker. That failed attempt is
  not counted as a passing live graph test; no model output was rewritten.
- Android **1.4.19 (1104)**: debug application and instrumentation APK builds passed;
  the matching APKs were installed on S26U without clearing application data.
- **303 JVM tests in 27 suites passed** with zero failures, errors or skips.
- **24 local S26U instrumentation invocations passed**: seven live-graph and cloud
  cancellation checks, fifteen existing workspace/evidence/recall/goal regressions
  (105.582 seconds), and separate seed/recover invocations in processes **10415** and
  **10590**. Recovery reused completed producer/planner observations without replay.
- The offline cloud-stop case uses a real local HTTP socket and the production
  response bus: the socket closes, encrypted ownership receives its terminal
  cancellation record, and a late success cannot overwrite it. It is not an
  external-provider outage test.
- The Kotlin source-size gate and `git diff --check` passed. The repository-wide
  check still reports pre-existing i18n-policy findings in unchanged files.
- The corrected real-provider attempt **passed in 312.464 seconds**, using the
  installed build and existing Desktop **1.4.2**. Report:
  `live-expansion-e6355226-1e13-49f5-9748-eae638ffaae1.json`.
  Codex authored the synthetic document and returned an unchanged incremental plan;
  the newly persisted DeepSeek task actually fetched its exact revision and linked
  the read receipt in an independently authored review while the local gate was
  still held. A second coordinator checkpoint returned no additional work. The
  final handoff included all executable nodes, and the program-owned documentary
  receipt accepted the exact delivery/review references (`SUCCEEDED/achieved`).
- The final real-provider cleanup confirmed durable STOP, local settlement and
  zero pending remote owners before removing the fixture group, conversation and
  execution database and restoring the previous conversation. No user data was
  cleared. The report retains `read_only_enforcement_verified=false` because
  recorded observations are not a complete provider sandbox audit.
- This is **one passing real-provider sample**, not a stability percentile or a
  multi-agent superiority result. About five minutes for a small synthetic document
  remains a latency concern; the additional empty planning checkpoint and final
  coordinator call warrant separate optimization without weakening evidence checks.
