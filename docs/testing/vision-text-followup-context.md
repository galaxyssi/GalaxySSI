# Text follow-ups after image input

## Regression

The composer restored the most recent user image on every text follow-up. Its
transport copy was indistinguishable from a newly uploaded attachment, so the
phone planner reapplied the initial image task and asked the model to state its
reading before answering. Actual Codex `final_response` records consequently
prefixed ordinary translation questions with image orientation reports.

## Contract

- Original uploads remain in their original transcript entry. A text follow-up
  has no new image bubble.
- Replayed image inputs carry `historical_source_turn_id`. The metadata survives
  phone workspace staging, cloud encoding, MQTT request descriptors, and Desktop
  request snapshots. It is context metadata, not execution or identity authority.
- Historical pixels remain available for questions about the original image.
  They do not themselves request another transcription, interpretation, or edit.
- Cloud OpenAI-compatible, Anthropic, and Gemini requests place replayed pixels
  in labeled historical reference messages before the current user message.
  A compacted history can therefore recover visual evidence without pretending
  that the user uploaded it again. Newly uploaded pixels still belong to the
  current user message.
- Desktop planner requests preserve the same distinction in the phone's
  provider-neutral prompt and attachment metadata. This does not change native
  thread isolation, execution ownership, or fallback provider selection.
- Reading direction is checked internally. Orientation is mentioned only when
  explicitly requested or when an actual ambiguity affects the answer. No UI
  regex strips arbitrary model output.
- Historical images do not block the existing phone-operation and collaboration
  dispatch branches solely because they are being replayed.

This change does not promise zero retransmission: a stateless cloud request or a
new provider thread may still need the source pixels. It distinguishes replayed
evidence from a new user upload, not transport caching from model context.

## Tests

- JVM: compact prompt behavior for text/visual follow-ups, optional image tools,
  source image lookup, and all three cloud payload formats, including mixed
  historical/current images.
- Backend: vision adapters and orientation references, request recovery retaining
  historical provenance, and planner continuation receipts.
- Device fixtures: phone staging/restoration, image compression metadata, native
  request bodies for streaming and legacy fallback across all cloud API styles.
- Opt-in live phone loop: submit an image, ask a text-only translation question,
  then refer back to the original image. Assert final replies belong to each
  original turn, follow-ups add no image bubble, and orientation preambles are
  absent. Test prompts are Chinese. The private photo is not committed.

Live command arguments: `live_vision_followup=true` and `vision_image_path` pointing
to an explicitly authorized photo inside the App's private files directory.
The report is `cache/native-vision-followup-report.json` in the debug App.

## Verification on 2026-10-25

- Android 0.1.6.15 (1391) built and installed over the existing S26U App without
  clearing data. Test APK also built successfully.
- 25 focused Android JVM tests passed; 144 backend tests passed; Desktop
  structure check passed.
- Seven distinct device tests passed, including the opt-in live three-turn
  sequence through the actual composer and Codex connector. The existing
  orientation-caption assertion initially compared serialized JSON with raw
  text; after changing it to inspect decoded text fields, all four original
  native-vision device tests passed again. No production output was filtered.
- Live answers: the sideways arithmetic image was read as `1 + 1 =`, with answer
  `2`; the text-only translation question received word meanings directly; the
  next text-only visual follow-up correctly recalled the original expression.
  None included an orientation preamble. End-to-end durations were approximately
  59.8, 41.1, and 31.0 seconds; this is correctness coverage, not a latency pass.
- The live Desktop process was the already-running 0.1.6.1 backend. Android's
  provider-neutral prompt fixes were therefore verified against that existing
  backend; the additional Desktop 0.1.6.3 policy/snapshot changes were covered by
  backend tests, not a production restart.
- Cloud coverage uses real request builders and a local mock HTTP endpoint for
  all three API styles, including legacy fallback. It does not claim a live
  DeepSeek, Anthropic, or Gemini semantic result.
