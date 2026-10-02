# Live Collaboration Evidence Acceptance

This opt-in Android instrumentation fixture uses the phone's paired Codex Desktop and configured DeepSeek provider. It makes real model requests and transfers original tool evidence over the production authenticated MQTT path. It is not part of unattended CI and requires explicit user authorization.

## Scope

- Create one isolated conversation with two members and a three-node dependency graph: document author, independent reviewer, coordinator acceptance.
- Run a read-only arithmetic command with a fresh fixture token on Desktop. Failed read-only commands may be corrected; successful commands must not be repeated solely to obtain receipts.
- Import the actual Codex completed-item payload using the production evidence protocol, encrypted checkpoints and hashes.
- Have DeepSeek use the host-bound `collaboration_recall` tool to inspect the original, then publish a review of the exact saved document revision.
- Require a direct reference to the original `desktop_codex_tool/codex.commandExecution` observation and a recorded reviewer read of that exact original. Browsing its ID or reading only the author's workspace document is insufficient.
- Require the program-owned documentary acceptance gate to accept the exact delivery and independent review. A model's `achieved` field alone cannot pass.

The fixture does not send contact messages, operate other devices or physical controls, rerun original research, or start an unbounded goal loop. Its dedicated execution store prevents a failed test from automatically expanding after the test ends. The fixture group and conversation are removed and the previous conversation selection is restored. Content-free dispatch tombstones may remain for duplicate suppression; only dedicated fixture reports are exported.

## Invocation

Build and install matching application/instrumentation APKs. Use the explicitly authorized device serial, never a default device when several are attached:

```powershell
adb -s AUTHORIZED_SERIAL shell am instrument -w -r `
  -e class com.galaxyssi.chat.CollaborationLiveEvidenceDeviceTest `
  -e collaborationLiveEvidence true `
  com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

The phone must be unlocked and able to reach its configured providers. The fixture refreshes the existing capability manifest after Desktop deployment. It does not bypass pairing or fabricate evidence capabilities. The 12-minute test-harness deadline is not a product goal deadline.

Reports are stored under the application's external files directory as `collaboration-live-evidence.txt` and, on success, `collaboration-live-evidence.png`. These files contain only the dedicated synthetic fixture's results. Do not upload logs from other conversations, provider credentials or pairing state.

## Interpretation

Passing establishes this scoped real-provider path and documentary evidence integrity. It does not establish qualified computational/scientific correctness, natural-language planner quality across arbitrary tasks, superiority over an equal-budget single Agent, device reboot/Doze recovery, other providers, or all remote native recall paths. Test the local member isolation and paging case separately with `CollaborationScopedRecallDeviceTest`.

## Recorded run: 2026-10-02

Desktop 1.4.1 was restarted from the current evidence-provider implementation after confirming that it had no active or pending tasks. Android 1.4.17 (1102) was installed on the authorized S26U without clearing app data. No other device, contact or original research was used.

Both full live attempts **failed**, and neither should be counted as completed documentary acceptance:

- Baseline, 345.852 seconds: Codex's command failed because of nested PowerShell quoting. The failed original was correctly imported. DeepSeek could not consume it because its advertised cloud catalog lacked the internal recall capability; it searched the web for internal tool information instead. The fixture now permits correcting a failed read-only command, but not repeating a successful command merely to get a receipt.
- After the scoped recall fix, 259.610 seconds: Codex returned the fresh fixture token, sum `15`, mean `3.75`, and exit code zero. Android imported the original provider observation. DeepSeek invoked `collaboration_recall` and accurately quoted its command, original output and status in a separately authored review. It retained host observation references. This establishes actual consumption, not merely a prompt telling the member to read evidence.
- Final delivery still failed: Desktop returned `Required artifact verification failed`. The saved reviewer decision also embedded `acceptance_review` as prose inside `body.content` rather than a structured `body.acceptance_review`, and listed unresolved issues. The overall run remained `INTERRUPTED` with continuation requested. Neither the fixture nor the product gate was changed to accept that output.

Evidence transfer also added approximately two minutes after the successful author command in this sample. Its transport/retry behavior needs separate measurement; these runs do not establish acceptable latency or a stable percentile. The next acceptance work is structured review publication/repair and the final Desktop artifact-contract mismatch, followed by rerunning this unchanged full acceptance criterion.

Separately, 205 JVM tests across 17 suites and 15 isolated S26U instrumentation cases passed. These cover provider catalog shapes, scoped cloud/native recall, paging, member revocation, independent-member isolation, immutable evidence, work dependencies, archive retrieval and existing documentary acceptance/recovery. The live failure remains an explicit open integration result.

## Follow-up: assignment intent and typed reviews

The first 1.4.18/1.4.2 run completed in 262.131 seconds and passed the former fixture assertions: member assignment intent no longer triggered an unrelated build/file requirement, and the reviewer published structured acceptance metadata. Manual inspection invalidated that run as proof of full original-evidence consumption: the reviewer cited only a workspace-read receipt and explicitly admitted it had not seen the original command output. This was a test/acceptance gap, not a successful end-to-end result to count in the final pass rate.

The fixture was strengthened without weakening its original goal. Its preserved criterion now requires `desktop_codex_tool/codex.commandExecution`; it checks that the reviewer directly cites the imported original and that the host ledger records a reviewer tool call fetching that exact original with the fixture token. The production acceptance gate also preserves and checks the required source types instead of treating any successful read receipt as equivalent. This is still documentary/provenance acceptance, not qualified computational or scientific verification.

The first strict run took 252.148 seconds and correctly remained `INTERRUPTED/continue`: its test criterion used the provider item type `commandExecution`, but the established Android importer namespaces the ledger tool as `codex.commandExecution`. The reviewer did fetch and directly cite the original. Only the fixture's required tool name and corresponding assertion were corrected to the production protocol name; the importer and exact-source acceptance check were not relaxed. This failed attempt is not counted as a passed run.

## Strict real-provider pass: 2026-10-02

The corrected fixture passed in **243.898 seconds** on S26U Android **1.4.18 (1103)** with Desktop **1.4.2**. All three dependency nodes succeeded and the final disposition was `achieved` with an accepted host-owned receipt. Assertions checked the actual imported original, the review's direct reference, and a successful reviewer `collaboration_recall mode=evidence` fetch of that exact observation whose output contains the fresh fixture token. The author, reviewer and coordinator used the real production model dispatch and MQTT paths, not stub responses.

The saved output was inspected after the test: the review contains an actual `body.acceptance_review` object, the correct original source reference and exact delivery version/hash; the final criteria preserve `required_observations`. The screenshot shows the coordinator result in the two-member conversation. The fixture removed its group/conversation and restored the prior selection. Only this synthetic report and screenshot were exported locally; no user chat history or credentials were uploaded.

This is a single scoped passing sample, not a measured general reliability or superiority score. The approximately four-minute duration still needs latency investigation. The generated discussion remains overly technical in places, including long evidence identifiers; that is not claimed as polished user-facing output. Scientific/computational validators, repeated repair, long-offline/Doze/reboot acceptance and equal-budget outcome comparisons remain outstanding.
