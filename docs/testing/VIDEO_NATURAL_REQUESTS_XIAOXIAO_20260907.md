# Natural Video Requests and Xiaoxiao

Desktop source version: 1.0.55. Android version unchanged. Main 8f8cda527 was
merged before PR submission.

## Incident

The SM-T575 request to introduce RAG principles in a video missed the explicit
create/make matcher. The ordinary Codex path generated its own script using
zh-CN-YunxiNeural, bypassing host-prepared narration. This was not an Android
playback voice setting.

## Changes

- Recognize modality-first explainers and direct video/animation requests.
- Exclude existing-video discussion, negations, capability questions, and
  script/storyboard requests from the rendering route.
- Use zh-CN-XiaoxiaoNeural for Chinese, English and mixed-language video speech.
  Pass original text unchanged; selecting a voice does not translate it.
- Reject a service response identifying another voice; network failures do not
  silently select an alternative TTS voice.
- Give ordinary execution the same video voice instruction as defense in depth.
  This is an instruction, not a sandbox restriction on arbitrary generated code.
- Remove renderer instructions suggesting Windows System.Speech or other TTS.
  Renderers must reuse host-generated measured clips.
- Replan narration checkpoints made under an older voice policy.
- Leave ordinary message read-aloud voices and Android UI unchanged.

## Validation

Focused pytest coverage includes intent matching, MQTT dispatch selection,
gateway planning/render permissions, unchanged multilingual input, wrong-voice
rejection, unavailable TTS, cancellation, checkpoint invalidation, media timing,
and execution contracts.

Result: 184 tests and 67 subtests passed. Repository checks and git diff
whitespace checks passed.

Live Microsoft Edge TTS was called through the production narration helper:

| Input | Returned voice | WAV duration | WAV bytes |
| --- | --- | ---: | ---: |
| Chinese RAG explanation | zh-CN-XiaoxiaoNeural | 5.424 s | 260430 |
| English RAG explanation | zh-CN-XiaoxiaoNeural | 6.024 s | 289230 |

Generated evidence is local only under build/xiaoxiao-live, including the cue
manifest and WAV clips. This confirms live synthesis, not human-rated English
pronunciation or a newly generated end-to-end Agent video on the tablet.

## Deployment Boundary

No running Desktop restart, Android installation, or replacement of the old RAG
MP4 was performed. After deployment, use only SM-T575 for device acceptance:
request Chinese and English explainers, verify the host route and narration
manifest, receive the MP4 through MQTT, and play its audio. Previously generated
MP4 files retain their original embedded audio.
