# Android reply render stability

## Scope

Android 1.2.17 (1022), tested on SM-S9480 on 2026-09-21.
No Desktop, watch, research-budget, or theme changes.

## Fixes

- Keep source-checked provisional paragraphs visible during evidence audit and
  additional reading. They remain ephemeral and excluded from accepted text/TTS.
- Do not replace a visible draft with a shorter prefix from a repair round.
  Explicit invalid-citation, failure, and cancellation retractions remain supported.
- Retain table containers, unchanged rows, expansion state, and horizontal scroll
  while new rows arrive. Reuse unchanged passive content during final handoff.
- Keep stream ordering stable and ignore obsolete automatic-scroll callbacks.
- Prefer the delivered final reply timestamp over a later runtime projection.
  Final-result enrichment preserves its original timestamp; unchanged/empty
  completion lookups no longer trigger process-row rebinding.

## Verification

- Full debug APK and instrumentation APK builds passed, including embedded runtime
  bundle verification. The installed package reported version 1.2.17 / 1022.
- 46 focused JVM tests passed: preview presentation, citations, stream attempts,
  stream handoff, transcript diffing, rich-content updates, and completion clocks.
- 12 SM-S9480 instrumentation tests passed: `AgentStableAssistantRowDeviceTest`,
  `AgentProcessClockDeviceTest`, and `AgentTranscriptProjectionInstrumentedTest`.
  The table test checks View identity and expanded rows across 30 updates; other
  tests cover image retention, corrected output removal, accepted selection actions,
  ten-conversation isolation, and final timestamp preservation.
- One opt-in `AgentWebSynthesisDeviceTest` passed using the configured
  `deepseek-v4-flash`, in a separate private test conversation. It requested a
  sourced papaya nutrition table and summary. End-to-end time was 104.305 seconds;
  the model path took 100.292 seconds. The first cited preview appeared at
  13:44:54.036, verification at 13:44:55.954, and model completion at 13:44:56.156.
  The log did not show the earlier three-to-two visible-row removal during handoff.

## Limits

- The live sample did not require another model round after its preview. The
  longer audit/repair-prefix case is covered by policy tests and code-path review,
  not by a claimed multi-round live reproduction.
- Screenshots and View-identity assertions are not a continuous frame-by-frame
  guarantee against every possible rendering issue.
- Research latency and independent factual verification were not optimized here.
  The live test's quality check is structural, not a medical evidence review.
- Kotlin source-size and diff checks passed. The repository-wide check stopped
  on pre-existing i18n violations in unchanged files, including watch sources.
