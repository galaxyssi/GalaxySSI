# Closed-book paired cloud pilot

The iOS XCTest fixture ports Android #3382. Both arms use the same frozen
text task, draft/review/revision graph, provider model, output cap,
temperature and three HTTP admissions. The only role treatment is the
reviewer identity in the team arm. Each slot runs in its own group, run,
turn and encrypted history, using the production iOS team runtime and
single-request cloud client. No external tools, prior user conversations,
model-based summaries or research loop are used.

The frozen manifest follows `galaxyssi.collaboration-pilot.v1`:
`pilot_id`, `target_id`, `model_id`, `trial_timeout_ms` (60000 to
600000), `text_profile` and `slots`. Each slot has `id`, `case_id`, `arm`
(`single` or `team`) and `prompt`. Each case needs both arms with exactly
the same task bytes. The text profile is
`galaxyssi.trial-text-profile.v1`, with `max_output_tokens` (1 to 4096),
`temperature` (0 to 2), `thinking_mode: disabled`, `external_tools: false`,
and `model_summarization: false`. The only live endpoint is the official
DeepSeek chat-completions API; the harness does not infer these controls
for other providers.

## Explicit live authorization

Ordinary tests use a fake transport and do not contact a provider. Run
only `testOptInAuthorizedPairedCloudPilot` on a verified physical device
with all of the following XCTest environment values:

- `GALAXYSSI_PAIRED_CLOUD_RUN=1` and
  `GALAXYSSI_PAIRED_CLOUD_DEVICE_MODEL` with the exact hardware identifier.
- `GALAXYSSI_PAIRED_CLOUD_PLAN` and `GALAXYSSI_PAIRED_CLOUD_SHA256` with
  the fixture path and exact lowercase SHA-256.
- `GALAXYSSI_PAIRED_CLOUD_MAX_ADMISSIONS` with the separately authorized
  cap, at least three times the assigned slot count.
- `GALAXYSSI_PAIRED_CLOUD_TARGET` and `GALAXYSSI_PAIRED_CLOUD_MODEL` with
  the separately selected identifiers; `GALAXYSSI_PAIRED_CLOUD_API_KEY`
  supplied privately, not in the manifest or source control.

All slots are journaled before a model request. A reserved pilot ID never
silently reruns. A killed run leaves its reservation, assigned outcomes
and any unfinished encrypted store for inspection. Completed attempts
export scoped admission and settlement receipts before removing their
isolated store and keys. Results and the journal remain in the app's
test-only `Application Support/XCTest-PairedCloudPilot` directory.
Keep them and private protocols outside Git. The journal has no API key,
answer key or full request prompt.

One reviewer identity on the same model is not independent training.
Matching admission caps do not establish equal billed cost, learning
or a general collaboration advantage.
