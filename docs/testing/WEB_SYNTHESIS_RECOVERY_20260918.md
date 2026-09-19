# Web synthesis recovery

This document records the initial 1.2.2 fix and its device results. The subsequent
1.2.3 research-loop change replaces the short shared retrieval budget and the
30-second synthesis allowance; see [Direct-cloud research loop](CLOUD_RESEARCH_LOOP_20260918.md).

## Observed failure

S26U (SM-S9480), Android 1.2.1 / 1006, direct DeepSeek conversation.
The screen displayed the sources-only fallback after approximately 62 seconds.
The retained latency log showed seven searches and one fetch, followed by:

- Round 4: completed draft, citation validation found two foreign URLs.
- Round 5: tools disabled for citation repair; interrupted after 1,063 ms.
- The repair still used the remaining 60-second web execution budget, rather
  than the separate 30-second finalization budget.

The draft was not accepted, which is correct; losing the opportunity to repair
its citations because retrieval had used the budget is the defect. Logs do
not prove that the original draft's factual conclusions were correct.

## Repair

- Citation repair enters tool-free finalization immediately, with its own
  existing 30-second per-round timeout. It remains one-shot per conversation.
- If retrieval expiry interrupts a model round after evidence is available,
  allow one final synthesis round without rerunning completed tools.
- Retry an empty synthesis once; do not create an unbounded retry loop.
- Share the citation integrity predicate between validation and repair.
  Repair prompts exclude tampered evidence, prioritize valid draft citations,
  and never truncate a URL at the prompt boundary.
- Add entity-disambiguation guidance: matching names do not establish identity
  or a relationship. Unsupported conclusions should be stated as unknown.
- Log recovery/fallback reasons and evidence counts without logging draft
  text, private source bodies, credentials or complete citation URLs.
- The opt-in real-device probe now rejects sources-only fallback as success.

Citation checks still run after repair. This is citation provenance validation,
not a guarantee that a source is true or that every claim follows from it.
Real network/model failures can still result in an honest partial response.

## Verification

- Focused unit suite: 36 passed, zero failures/errors (citation verification,
  evidence prompt projection, grounding adapter, and loop progress).
- Android debug build passed; runtime bundle verification remained enabled.
- APK and instrumentation APK builds passed. S26U was updated in place to
  Android 1.2.2 / 1007; no pairing or conversation data was cleared.
- The same public question passed the opt-in main-page test. Total observed
  task time was 73,184 ms; the final UI showed a processed timer and answer,
  not the sources-only fallback. A screenshot and local JSON report were saved.
- Crucially, this rerun reproduced citation repair: round 4 had one foreign
  citation; round 5 completed in 24,162 ms with zero invalid citations. It was
  not interrupted by the research deadline. This exercises the repaired path,
  not merely a lucky answer that avoided citation checking.
- A separate real-provider weather regression completed in 5,643 ms with one
  weather tool call and a cited answer. This probe is not a main-page latency
  measurement. Both device tests passed; no other device was operated.

## Limits

The relationship answer still used some secondary/social-media sources, and
its leading conclusion was stronger than its later caveats. Passing URL
provenance checks must not be described as independently verifying all facts.
The long lookup still took about 73 seconds and the final model request was
108,452 JSON characters. This repair restores synthesis completion, not a
general latency, source-quality or factual-accuracy guarantee.

Device logs, screenshots and question/answer reports remain local under
`C:/Users/agent/MQTTDiagnostics/`; they are not included in source control.
