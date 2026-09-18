# Unified research quality

## Contract and execution boundaries

`apps/desktop/core/galaxyssi-link/backend/research_contract/research-quality.json`
is the versioned source of truth. Desktop loads it locally; Gradle packages the
same directory as Android assets. No network policy fetch or provider-specific
copy is required. Shared fixtures exercise both Python and Kotlin adapters.

The standard requires question-directed retrieval, entity disambiguation,
primary-source preference, claim-to-passage checking by the executing model,
date/attribution checks, preservation of uncertainty and concise final answers.
It does not promise that a particular model will always obey these rules.

| Path | Integration |
| --- | --- |
| Android streaming conversation | Common policy, evidence/provenance checks, bounded quality repair, versioned final checkpoint |
| Android non-streaming conversation setting | Same research loop; complete JSON replaces SSE only |
| Provider rejects SSE | Switch the current round to complete JSON, preserving observations and tool history |
| Desktop Codex App Server | Native search events/checkpoints and final quality gate; one native repair turn, no host search loop |
| Desktop CLI/ACP agents, including Claude | Common gateway policy and response-self-check repair path |
| Older direct blocking/structured cloud APIs | Common policy and final risk/citation checks; their own orchestration remains |

The last row is deliberately not described as full Run Kernel parity. Structured
internal model calls, autonomous skills, and every third-party connector require
separate execution/recovery acceptance. The change does not replace their loops.

## What validation means

Three separate concepts must never be conflated:

1. Citation integrity: a cited URL belongs to recorded source evidence.
2. Structural risk review: conservative lint flags known overbroad absence claims
   and speculative relationships for model correction.
3. Semantic correctness: the passage actually supports the claim, the entities
   match, the decisive evidence was found, and important counterevidence was not
   omitted. This still requires model judgement and factual evaluation.

Reports explicitly say `semantic_verification=not_independently_verified`.
`no_structural_risk_detected` is not a truth score. A regression fixture includes
a plausible but unsupported claim that passes lint to enforce this distinction.
The same-model correction is not an independent judge and must not be marketed
as one. There is no whitelist of people or hardcoded answer to the motivating
relationship question.

The model is instructed to track each material claim against an exact source
passage, but this iteration does not require a machine-readable claim ledger.
Cross-language parity fixtures are structural tests, not benchmarks of source
recall, entailment, or research accuracy.

## Stops, failure and recovery

- Source errors stay observations, not task-level failures.
- The cloud loop retains independent retrieval/model/synthesis limits and
  completed read-only observations from the existing Run Kernel journal.
- Switching wire format does not restart the task or replay tools.
- Final answers are keyed by quality-contract version; old answers cannot
  bypass a new standard, while their saved observations remain reusable.
- Quality/citation correction is bounded. Continued failure is a partial result,
  not a successful factual verification or an invitation to loop forever.
- Native remote Agents retain their own tool selection and scheduling. Codex
  quality repair uses its existing thread context, not another host research loop.
- Repeated native `webSearch` source failures no longer trigger a competing host
  replan or consume the whole task's identical-failure budget. Native turn errors,
  cancellation and stalled-task recovery retain their existing owners.
- A recovered completed Codex turn also passes the quality gate before delivery;
  the saved citation-repair flag prevents an unlimited series of repairs across
  recovery attempts.
- This change does not alter pause/cancel leases or couple MQTT connection state
  to Agent execution state. Existing reliable transport owns reconnect/replay.

## Observable stages and delivery

Native source completion records `retrieval_observed`, not whole-research
completion. `quality_checked` records citation and risk scope separately.
`synthesis_completed` means a final payload was produced, not delivered.

Codex result metadata and Android final checkpoints explicitly set delivery to
`not_confirmed`. Phone delivery remains owned by the existing authenticated
application receipt (`RX_STORED`) and reliable outbox. Broker PUBACK, a socket
reconnect or an Agent's final text is not a phone receipt. These receipt states
must be correlated using the existing task/turn/message/peer identity, never
inferred from a research stage. No new progress UI or layout is introduced.

## Acceptance matrix

Automated checks cover shared policy packaging, Chinese/English risky claims,
qualified unknowns, quoted/code examples, non-streaming protocol conversion,
native Codex with and without host Evidence Packs, bounded native repair,
existing citation/response/harness/recovery regressions, and checkpoint versioning.

Before claiming product-quality acceptance, run the same fresh questions through
DeepSeek SSE, complete JSON, remote Codex and (when configured) Claude. Include:

- Named entities with decisive coauthor records and ambiguous initials.
- Official evidence that contradicts a popular secondary claim.
- A true absence claim supported only within a bounded official dataset.
- One failed source plus another sufficient source.
- Weather/news with event/publication/timezone ambiguity.
- Several documents with copied content masquerading as independent sources.
- A detailed research request where a short answer would omit requirements.
- A paused/resumed run and a link outage while the remote Agent remains active.

Score decisive-source recall, supported-claim precision, unsupported inference,
uncertainty calibration and task completion independently. Report wall time and
tool/model usage separately. Do not convert process-completion tests into an
accuracy percentage. Real-provider and real-device results are not implied by
unit tests or a successful build.

## Local validation results

- Android focused JVM suite: 47 tests passed, zero failures/errors. Includes the
  shared cross-platform cases, versioned checkpoint recovery and complete-JSON
  HTTP tool-call parsing for OpenAI-compatible, Anthropic and Gemini adapters.
- Android `mergeDebugAssets` and `compileDebugAndroidTestKotlin` succeeded. The
  packaged standard and Desktop source standard have identical SHA-256 hashes.
- Desktop focused suite: 135 tests and 78 subtests passed. Covers quality rules,
  response policy/self-check, Codex conversations, cloud tools, execution harness,
  MQTT Codex recovery and Desktop runtime scheduling.
- Desktop packaging script syntax and `git diff --check` passed.
- The development APK built successfully and was installed on S26U as v1.2.3
  (1008), preserving application data. Startup completed with no crash-buffer
  entries. Android source was subsequently bumped to v1.2.4 (1009); that version
  has not yet been rebuilt or installed.
- Desktop was restarted from current source as v1.2.4. Its window opened and
  backend health reported ready with MQTT connected. The receive queue reached
  128 pending entries; this is an unresolved transport issue, not a passing
  end-to-end delivery result or a fix included in this change.
- No new real-provider research accuracy evaluation was performed for this
  follow-up. Previous device results belong to the earlier streaming-only
  implementation and are not reused as acceptance.
