# Live Collaboration Evidence Acceptance

This opt-in Android instrumentation fixture uses the phone's paired Codex Desktop, with one explicitly selected model for both members. The route remains Android -> Desktop -> Codex -> OpenAI; no phone-side OpenAI API key or DeepSeek configuration is required. It makes real model requests and transfers original tool evidence over the production authenticated MQTT path. It is not part of unattended CI and requires explicit user authorization.

## Scope

- Create one isolated conversation with two members and a three-node dependency graph: document author, independent reviewer, coordinator acceptance.
- Run a read-only arithmetic command with a fresh fixture token on Desktop. Failed read-only commands may be corrected; successful commands must not be repeated solely to obtain receipts.
- Import the actual Codex completed-item payload using the production evidence protocol, encrypted checkpoints and hashes.
- Have a distinct reviewer identity on the same Codex target/model use the host-bound `collaboration_recall` tool to inspect the original, then publish a review of the exact saved document revision.
- Have the coordinator/author also publish a goal mapping using host-supplied source IDs and goal/criterion hashes. The peer publishes a separate typed semantic coverage review of that mapping; no third member, model-counted offsets or copied original-goal text is required.
- Require a direct reference to the original `desktop_codex_tool/codex.commandExecution` observation and a recorded reviewer read of that exact original. Browsing its ID or reading only the author's workspace document is insufficient.
- Require the program-owned acceptance gate to accept the exact delivery/review and mapping/coverage-review references. A model's `achieved` field alone cannot pass. The semantic verdict remains a reviewer judgment, not scientific truth.

The fixture does not send contact messages, operate other devices or physical controls, rerun original research, or start an unbounded goal loop. Its dedicated execution store prevents a failed test from automatically expanding after the test ends. The fixture group and conversation are removed and the previous conversation selection is restored. Content-free dispatch tombstones may remain for duplicate suppression; only dedicated fixture reports are exported.

## Invocation

Build and install matching application/instrumentation APKs. Use the explicitly authorized device serial, never a default device when several are attached:

```powershell
adb -s AUTHORIZED_SERIAL shell am instrument -w -r `
  -e class com.galaxyssi.chat.CollaborationLiveEvidenceDeviceTest `
  -e collaborationLiveEvidence true `
  -e collaborationModel gpt-6-astra `
  -e collaborationReasoningEffort xhigh `
  com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

The phone must be unlocked and able to reach its paired Desktop. Exactly one available paired Codex target must advertise the requested model; multiple eligible targets fail rather than silently selecting a machine. The fixture refreshes the existing capability manifest after Desktop deployment. It does not bypass pairing or fabricate evidence capabilities. The 12-minute test-harness deadline is not a product goal deadline.

The model and reasoning-effort arguments are mandatory. Missing/automatic IDs fail before creating
a conversation. The target must advertise the exact requested model, and each
assignment rechecks availability before dispatch. The fixture explicitly stores
the model on both the member and execution context, so it does not inherit a
mutable contact/UI default. An advertised model is not proof of account access
or the model actually served; provider rejection still fails the fixture.
The mode report stores the requested model and reasoning effort with null served fields. Join
original Desktop observations and provider usage records separately; never fill missing
provider identity or billing with the requested value. Historical runs below
keep their original model provenance and are not relabelled as these new models.
Android 1.4.56 forwards the explicit per-assignment reasoning effort through the
existing `agent_reasoning_effort`/`agent_invocation` wire path and persists it in
the encrypted task definition. All fixture members use `xhigh` in this invocation;
ordinary assignments without that field retain their existing behavior. The
paired target must advertise the exact model and effort before each assignment.
Desktop already validates that wire selection; no Desktop release is needed.
Requested settings do not establish actual provider execution or equal cost.
This engineering fixture is not an equal-budget comparison.
Remote original reads must have host-frozen, complete page coverage bound to the
reviewer's exact dispatch. They are not required to create a direct-cloud HTTP
tool log. Same-model identities do not establish statistically independent errors.
The historical Codex/DeepSeek runs below remain unchanged; they are not evidence
that this new single-model configuration has passed on a device.

Reports are stored under the application's external files directory as `collaboration-live-evidence.txt` and, on success, `collaboration-live-evidence.png`. These files contain only the dedicated synthetic fixture's results. Do not upload logs from other conversations, provider credentials or pairing state.

## Interpretation

Passing establishes this scoped real-provider path and documentary evidence integrity. It does not establish qualified computational/scientific correctness, natural-language planner quality across arbitrary tasks, superiority over an equal-budget single Agent, device reboot/Doze recovery, other providers, or all remote native recall paths. Test the local member isolation and paging case separately with `CollaborationScopedRecallDeviceTest`.

The host-source-ID mapping contract is newly integrated. Earlier recorded passes below predate that contract and are not retroactive verification of it. The local exact-integer-sum validator is a separate narrow deterministic fixture and is not used to upgrade this live documentary task into computational/scientific acceptance. New-contract verification is recorded separately at the end.

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

## Semantic coverage integration: Android 1.4.20

The first new-contract live attempt on S26U, with Desktop 1.4.2 unchanged,
**failed final acceptance**. Codex ran the read-only command successfully and
published the saved document and host-source-ID mapping. DeepSeek fetched the
original command observation and produced both review objects, but its first
tool round's prose preface had already been emitted as a final-text delta.
Concatenating that preface with the final JSON made the complete response
unstructured; no review publication receipt was issued. The coordinator correctly
returned `continue` and asked for review publication rather than claiming success.

This exposes a managed cloud stream framing defect, not a reason to weaken JSON
or acceptance validation. The failed attempt remains a failed sample. The repair
must separate intermediate tool-round commentary from the final structured
handoff while retaining progress events and ordinary chat behavior, then pass
local stream tests and a new full real-provider attempt.

### Framing repair and strict new-contract pass

Managed collaboration now buffers each model round, keeps tool/usage progress,
and emits only the final response as protocol text. Ordinary chat streaming is
unchanged. Interrupted drafts and presentation-only artifact suffixes cannot be
concatenated outside the structured member result. JSON parsing and host
acceptance checks were not loosened.

The final regression passed **446 JVM tests across 38 suites**. Four additional
loopback-only S26U stream framing/cancellation cases passed in **6.822 seconds**.
The first cancellation fixture delayed its request upload unintentionally; moving
the throttled response into dispatch fixed that test server, without changing
production cancellation or increasing its deadline.

One authorized real-provider retry passed in **328.873 seconds** on S26U Android
**1.4.20 (1105)** with Desktop **1.4.2** unchanged. All three dependency nodes
finished `SUCCEEDED`; the final disposition was `achieved`, and the host-owned
acceptance receipt was accepted. Assertions verified the actual imported command
observation, the peer's exact-original read, direct evidence reference, separate
typed delivery and semantic-coverage reviews, different authorship, exact mapping
revision and final references. The author ran the read-only command successfully
once; no extra researchers, unrelated research or physical controls were used.

Manual inspection confirmed that the saved peer response is structured JSON,
not tool-round prose plus JSON. The final assessment references the host-assigned
saved versions. Cleanup acknowledged durable STOP with no pending remote owners,
removed the dedicated fixture and restored the previous selection. Only synthetic
reports and a screenshot were retained locally, not uploaded.

This is one small documentary/coverage sample, not a general reliability or
scientific-quality score. At about five and a half minutes, latency remains an
open issue; the displayed peer summary also contains excessive technical IDs.
Broad semantic judgments, qualified experiments, large-goal multipart coverage,
real-provider Doze/reboot/long-outage matrices and equal-budget superiority still
require separate work.

## Original-page coverage gate: Android 1.4.26

Formal acceptance now checks a host-owned page-coverage snapshot frozen in the
independent review's saved version. See
[Original evidence page coverage](COLLABORATION_EVIDENCE_READ_COVERAGE.md) for
the exact guarantees, automated/device results and the pending new real-provider
test. The preceding live passes predate this gate and are not presented as its
validation.
