# Android #4293: explicit report-image transcription

Reference: https://github.com/galaxyssi/GalaxySSI/pull/4293
Android merge: `9d8ec64da2329538bdbb72f734e43096e1667c3c`.

## iOS scope

Completed or failed single-image recognition jobs expose a separate vision-model
transcription screen. Local OCR pages and the encrypted original remain intact.
The screen displays the source image, configured effective vision model and endpoint,
bounded JPEG size and explicit per-image disclosure before a one-shot send.

Online-health permission, measurement-processing permission and a new default-off
report-image permission are independently required. The request binds their epochs,
the exact recognition job, original hash, capture crop revision, interface owner,
time zone, provider route, credential and destination blocklist before and after
network suspension. Backgrounding, leaving, locking, source removal or owner change
cancels the task. There is no automatic retry, fallback or provider switching.
Existing DeepSeek image routing is resolved before preview and rechecked unchanged.

OpenAI-compatible, Anthropic and Gemini image bodies contain a single bounded JPEG
and transcription instructions, not chat history, saved measurements or a care plan.
The existing ephemeral no-redirect transport bounds the response. External images
and model output are treated as data, not executable instructions. The disclosure
ledger records an image attachment and the exact cloud destination.

Strict typed parsing accepts at most 80 distinct supported rows with verbatim values,
units, reference intervals and source excerpts. The iOS metric catalog IDs are used
in the provider prompt instead of Android enum names. Unknown fields, wrong types,
unsupported units, control text and malformed/truncated responses fail closed.

The encrypted job retains the transcription and interpretation time zone separately
from local OCR. Rows open the existing editable measurement review screen, marked
as unverified model transcription. Measurement time and ownership are never confirmed
by the model. No confirmed records, clinical actions, research authorization or
reminders are created by sending or receiving a transcription. Final saving uses the
existing explicit draft and batch confirmation flow. Missing/ambiguous collection
times remain user decisions rather than falling back to report/birth dates.

## Verification limits

Added XCTest source covers typed result validation, permission separation and epoch
renewal, encrypted result commit without confirmed records, stale job rejection,
legacy job decoding, model provenance, all three request formats and image bounds.
Windows cannot run Xcode compilation, XCTest, iOS image UI or a live configured
vision provider. No Android device evidence is claimed as iOS evidence. This PR does
not add PDF cloud transcription, change Android/Desktop or produce an IPA.
