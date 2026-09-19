# Direct-cloud research loop

Follow-up: [Unified research quality](UNIFIED_RESEARCH_QUALITY_20260918.md)
adds a shared Android/Desktop standard and routes the non-streaming conversation
setting through the same cloud loop. The device outcomes below describe the
earlier build only, not acceptance of that follow-up.

## Scope

The streaming OpenAI-compatible, Anthropic and Gemini conversation harness uses
an iterative research policy rather than sharing 60/180 seconds between all
retrieval and final synthesis. This follows the public agent-harness pattern,
not an implementation of private Codex or ChatGPT internals.

Public references:

- https://developers.openai.com/blog/codex-as-a-platform
- https://developers.openai.com/api/docs/guides/tools-web-search
- https://developers.openai.com/api/docs/guides/deep-research

## Execution

1. The model determines whether retrieval is needed and plans complex research.
2. Independent tool calls run with at most four concurrent execution slots.
3. Each tool receives a fresh timeout after acquiring its slot. A failed source
   does not spend another source's allowance or the synthesis allowance.
4. Original evidence remains available for citation integrity checks. Model
   requests receive deduplicated, query-relevant passages and reference IDs.
   Redundant raw results/documents are omitted only when an Evidence Pack exists.
5. After each batch, the model receives source/call counts and instructions to
   investigate a specific gap or material conflict, or answer when sufficient.
6. Three consecutive batches without new evidence trigger tool-free synthesis.
   Source count alone never proves coverage or answer correctness.
7. Safety ceilings stop new retrieval but permit synthesis of supported findings
   and explicit unresolved questions. Empty synthesis and citation correction
   each have one repair opportunity, with independent model-request timeouts.

Simple weather and image requests keep their existing focused-tool guidance.
The change does not require lengthy research for ordinary questions.

## Limits

Optional `cloud_research_limits` in the cloud contact JSON controls these values.
This change does not add a settings page.

| Key | Default | Accepted range |
| --- | ---: | ---: |
| `tool_calls` | 128 | 4-512 |
| `model_rounds` | 64 | 4-256 |
| `active_minutes` | 20 | 1-120 |
| `tool_timeout_seconds` | 45 | 5-180 |
| `model_timeout_seconds` | 120 | 15-300 |
| `evidence_chars` | 2000000 | 24000-8000000 |

These are application safety ceilings, not claimed Codex defaults. The active
time/round counters apply to an invocation; restored observations count against
its tool and evidence allowances. Transport-specific source limits remain in
force. The active ceiling is checked between rounds; in-flight operations are
bounded by their own timeout, and finalization can outlive that ceiling.

## Durable observations

The main Android Agent path supplies stable conversation, turn, task, provider
and action identifiers. Research leases and encrypted immutable records reuse
`EncryptedAgentModelLoopJournal`; there is no global search-result cache shared
between conversations.

Each completed read-only call is committed immediately, including completed
siblings of a still-running parallel batch. On recovery, observations populate
the evidence ledger and semantic cache. The model replans from those observations
rather than replaying an incomplete provider transcript. Valid final answers can
also be reused. Input/provider binding changes and corrupt journals fail closed.

Mutation tools (including watch creation/cache clearing) are not replayable
research observations. This is not a replacement for the existing side-effect
coordination system. Image-bearing requests retain their existing attachment
lifecycle and do not enable this checkpoint path.

## Boundaries

- Progress uses existing task events; no page layout or colors change.
- The explicit non-streaming compatibility implementation is not migrated by
  this change. Do not report complete parity across every provider fallback.
- Citation URL integrity does not prove factual entailment. Source quality,
  entity disambiguation, conflicting claims and uncertainty still need model
  judgement and real-task evaluation.
- Android scheduling restrictions remain. Checkpoints allow continuation when
  the existing task supervisor resumes work; they cannot keep a force-stopped
  application running.
- Network/model failures can still prevent synthesis. Such a fallback must not
  be counted as a successfully researched answer.

## Validation

Unit coverage includes continuation beyond the former 60-second cutoff, 80
distinct sources, independent tool deadlines, resource ceilings, deduplication,
read-only checkpoint recovery, input binding, conversation isolation and refusal
to replay mutations. Real-device validation is opt-in on S26U only.

Build and device outcomes are recorded after execution; a compiled APK alone is
not acceptance of the real model/network recovery path.

### Results on S26U

Android 1.2.3 / 1008 was installed in place on SM-S9480 (S26U). Existing data,
model configuration and pairings were retained. No other phone was operated.

| Check | Result |
| --- | --- |
| Focused JVM regression suite | 51 passed; zero failures/errors |
| Debug APK and instrumentation APK | Built successfully; embedded runtime bundle verification enabled |
| Encrypted research checkpoint on device | Passed reopen, semantic reuse, conversation isolation and plaintext-marker exclusion |
| Original main-page synthesis regression | Passed in 54,699 ms with `background_research=true`; returned cited prose, no sources-only fallback, task ended |
| Real DeepSeek weather probe | Passed in 6,067 ms; one structured weather call |
| Real DeepSeek three-news probe | Passed completion/citation checks in 115,036 ms; 73 distinct source URLs, 13 searches and one fetch |

There were four successful device tests. The weather and news probes exercise
the real provider/tool loop, not main-page end-to-end UI timing. A source URL
count is not a count of independently verified facts or full-text page reads.
The news run demonstrates useful continuation beyond the former shared deadline,
but is not a latency success: it misses the earlier 30-second news target.

### Remaining acceptance gaps

- News research still expands too far, and the model-facing evidence can remain
  large despite projection (162,204 JSON characters in the last news request,
  including 135,234 tool-result characters). A more reliable evidence-sufficiency decision and
  further field-level compaction need focused follow-up, not a return to an
  abrupt short global deadline.
- The relationship answer marked uncertainty but still included a speculative
  possible relationship and overly broad absence-of-evidence wording. It passed
  citation provenance, not factual entailment or exhaustive identity validation.
- The encrypted journal was closed and reopened on the device. A real network
  research run killed mid-flight and resumed by the task supervisor was not
  exercised in this run; do not describe it as process-death acceptance.
- No claims about p95 latency, sustained offline recovery, Doze, or reboot
  recovery follow from these four samples.

Logs, screenshots and public-query reports remain local under
`C:/Users/agent/MQTTDiagnostics/s26-research-loop-*`; they are not committed.
