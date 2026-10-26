# Historical image follow-ups across providers

This change extends #3628. It does not add OCR, change provider selection, grant
Desktop execution rights, or filter phrases out of model output.

## Remaining gaps

Android already distinguished historical references in the OpenAI-compatible,
Anthropic, and Gemini payload builders. Two downstream gaps remained:

1. Desktop adapters collected image paths without restoring the source-turn
   metadata retained in the private request snapshot. As a result, cloud/local
   APIs attached all pixels to the latest user message; ACP and native CLIs
   labeled all pixels as current source images and regenerated orientation sheets.
2. Android's annotation tool instructions still described every available source
   as an attachment in the current turn. Regrouping historical images before the
   latest request also made conversational order differ from annotation indices.

## Contract

- Recover provenance from the original task's request snapshot, including during
  recovery runs. Match only admitted task files by the materialization index and
  name, not by an arbitrary descriptor path or a global filename search.
- Pass provenance explicitly through cloud context-overflow retries, local API
  fallback, native CLI/session retry, and ACP dispatch.
- OpenAI-compatible cloud APIs, including DeepSeek, and local/Ollama APIs receive
  labeled historical reference messages before the unchanged latest user message.
- ACP and Claude/Hermes/Gemini/Codex CLI transports keep native pixels with an
  explicit historical source-turn label. These single-prompt transports do not
  fabricate an earlier assistant reply or claim to have restored a native turn.
- Historical references do not generate another orientation sheet. New inputs
  retain the existing orientation checks and source pixels.
- All Android API styles label source images with their original `image_index`,
  matching the annotation tool's input list regardless of message regrouping.
- Tool instructions describe available sources, not new uploads, and only call
  for annotation when the current request needs it. Image tools remain available
  for a genuine follow-up about an earlier image.
- Turn IDs used in labels are bounded; provenance is context, never authorization.

## Regression coverage

- Snapshot recovery, same-name attachments, absent metadata, and path isolation.
- Historical-only and mixed current/historical images, original bytes, stable
  ordering, unmodified user text, and no repeated orientation sheet generation.
- Cloud tool rounds and context overflow; local Ollama fallback; all four native
  CLI formats; actual ACP subprocess transport; original task ID during recovery.
- Phone request builders and real stream-loop fallback using local mock endpoints
  for DeepSeek/OpenAI-compatible, Anthropic, and Gemini styles. Tests assert the
  selected model, phone-only execution contract, history separation, and output
  survive a streaming-unsupported response followed by non-streaming success.

These transport fixtures are not live-provider semantic accuracy measurements.
Do not infer model availability or recognition accuracy from mocked responses.

## Versions

- Android: `0.1.6.16` (`1392`).
- Desktop: `0.1.6.4`.

## Verification on 2026-10-25

- 157 Desktop backend tests passed, including the ACP subprocess fixture; the
  12 new follow-up tests also passed after the final policy wording review.
- 95 Desktop frontend/packaging tests and the structure check passed.
- Android debug and instrumentation APKs built successfully; 27 focused JVM
  tests passed.
- S26U: 12 existing visual-request, workspace-restoration, and annotation device
  tests passed. The opt-in live Codex conversation test was intentionally skipped.
- The additional S26U stream-loop test passed for all three API styles after
  streaming-unsupported fallback, including the DeepSeek model binding. Total:
  13 executed device tests passed, with one separate opt-in test skipped.
- Android `0.1.6.16` was installed over the existing S26U App without clearing
  data. The running Desktop was not restarted.
- Live DeepSeek/Anthropic/Gemini/CLI model recognition is not claimed by these
  tests. No private user photos or credentials are included in the change.
