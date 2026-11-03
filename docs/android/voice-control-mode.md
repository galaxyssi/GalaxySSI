# Voice control mode

## Implemented entry points

The existing Agent voice entry opens the compact status/route/stop panel. The ordinary
composer is unchanged when voice mode is off. Long-pressing the entry still opens voice
settings. Optional camera, keyboard and screen actions remain under a long press on the
status, without a permanent second control row.

The foreground voice session keeps its original Agent conversation while opening a
peer chat or the news reader. ASR finals are claimed once per trace/generation. Changing
the Agent conversation ends the old voice session. Stopping voice playback does not
cancel the durable Agent run. The route label observes AudioManager, not merely a list
of connected devices. QNN/ASR sample rates and peer voice encoding are unchanged.

`galaxyssi.app.*` tools are registered in the phone native catalog and are allowed on the
phone execution path for all providers. Intent understanding belongs to the model:

- `context`: identity-bound current conversation, contact, article and playback state.
  An ASR final freezes opaque page/contact/article IDs and binds them to its created
  Agent turn. Later navigation cannot redirect a pronoun or news follow-up. The bounded
  10-minute anchor cache contains no message text or contact names; expired/missing
  context must be resolved explicitly, never substituted with another turn's context.
- `reminders`: typed personal reminders, tasks needing attention, authorized upcoming
  calendar instances, and at most one news-update summary. This uses the same read-only
  projection as the voice landing view, not the news reader's article-body preview.
  Source availability and stable resource/conversation IDs accompany the result.
- `contacts`: bounded person/device lookup; ambiguous names require clarification.
- `send_message`: durable peer message and actual queue/publication receipt. Publication
  is not verified recipient delivery. The native effect journal guards replays.
- `news` / `read_article`: downloaded readable articles, stable IDs, source and body.
- `navigate`: App navigation/new conversation, never a Desktop action. An optional
  message on `new_conversation` schedules the remaining question in that new session,
  using its saved model selection. The old turn keeps ownership of its own answer.
- `playback`: ordered article queue, pause/resume/next/stop. One article is loaded at a
  time using the existing streaming TTS pipeline. The current spoken paragraph is
  replayed when resuming; there is no claim of sample-accurate resumption.

UI operations reject another conversation's stale invocation and require a foreground
App host. A superseded voice turn cannot operate the newest utterance's UI or playback.
Opening a passive capture after navigation does not supersede the executing App turn;
only a claimed new utterance does. Duplicate ASR finals do not invalidate that binding.
Storage, article loading and MQTT publication are not run on the UI thread.
Tool schemas do not expose a direct SIM audio recording/injection operation.

## SIM phone assistant

The opt-in dialer page and `GalaxySSIInCallService` provide real call state, answering,
rejection, hangup, microphone mute, audio route and DTMF. Telecom owns call connection,
ringtone and audio. Installation does not change the default dialer; only Android's
user-visible role request can do that. No real call is placed by tests.

The page uses the approved avatar/name/status header, language row, bilingual transcript
area and compact route/hangup footer. Dialing and the default-phone role request appear
only in the bottom dialog opened by the idle dial command. There is no permanent number
field or extra toolbar. In-call mute and DTMF are available from the footer status control.
An idle phone page disables hangup. Transcript render fixtures are tests only; production
passes no translated lines until a real audio integration supplies verified content.

SIM audio capture and injection are **unavailable** for this ordinary third-party build.
The page shows this explicitly. It does not display fictional translations, listening
state or successful spoken replies. Native SIM audio support requires a separately
verified integration; default dialer status alone does not enable it.

## Independent news playback

`VoiceNewsPlaybackService` owns public-news TTS, audio focus, bounded next-chunk prefetch,
MediaSession and the media-playback foreground notification. It retains no Activity.
Article reads and sentence preparation run off the main thread. The queue checkpoint
contains at most 20 article IDs, its index and a normalized-text paragraph offset; no
article body, contact message or Agent transcript is written into the checkpoint.

Backgrounding/destroying an Activity does not cancel news audio. System media controls
provide play/pause, next and stop. Audio-focus loss and headset unplug pause playback.
No microphone is opened by this service. Process recreation restores a paused bookmark,
not automatic speech; explicit resume is required. Paused idle services release after
one minute, and stopping clears the bookmark. Playback releases audio focus and its
time-bounded wake lock on pause/failure/stop. The notification displays generic news
status, not a private conversation or transcript. Edge TTS failures remain failures;
the service does not silently substitute a different voice provider.

Ordinary voice input and peer voice recording synchronously pause news before opening
their capture path. This does not change the existing ASR/QNN pipeline or peer encoding.

The news body highlights the spoken paragraph without changing layout dimensions or
scroll position. Updates are scoped to the matching article and removed when paused,
hidden or detached. Other articles cannot inherit the highlight.

## Remaining acceptance and follow-up work

Completed Agent replies now use the same independent media service as news when the
user taps Read or double-taps a paragraph. The service receives a conversation ID,
entry ID and normalized character offset, then reads that one encrypted transcript
entry off the UI thread. Both identifiers must match, the entry must be a completed
assistant reply, and process/approval/preview text is rejected. Reading continues to
the end of the selected reply; resuming a paused segment repeats that segment, not
the whole answer. Starting news replaces reply playback and vice versa.

Reply selection is in-memory only and never overwrites the persistent news bookmark.
Notifications show generic playback state, not private text, and system pause/stop,
audio-focus loss and recording handoff release the speech queue. Natural completion
and stop terminate reply playback and clear its state. Process death does not resume
private speech automatically. The service does not retain an Activity. Edge TTS uses
an in-memory MediaDataSource and zeroes each segment when released; it no longer needs
a plaintext MP3 that could race with background cache cleanup. Playback errors and
timeouts are reported as failures rather than successful completion.

The conversation microphone, automatic voice replies and replies that are still
streaming remain on their existing MainActivity path. Continuous background voice control still needs a
microphone foreground service and session-owner migration. Backgrounding the last voice
surface pauses recording; no microphone is silently started in background.

Validate real provider decisions, cross-page streaming, headset unplug/reconnect,
speaker echo and interruption on devices. Validate Telecom incoming/ongoing calls,
multi-SIM, call waiting, video/conference behavior, emergency fallback and notification
restrictions before making this an everyday default dialer. Do not replace the user's
default phone app as part of installation/testing.

The design's proactive examples are not seeded into the database. The reminder projection
reads delivered personal messages, up to 24 recoverable workspaces (showing only paused,
blocked or confirmation-waiting tasks whose conversations still exist and are active),
and at most two non-cancelled/non-declined visible calendar instances in the next 24 hours.
Calendar access is read-only and uses an existing permission; voice activation does not
request it. Missing permission is reported to the model, not interpreted as an empty calendar.
Weather has no verified producer in this increment and is explicitly `not_connected`.
New weather producers and model-driven voice-message recording still need their own
integration/acceptance; text sending must not be described as recorded audio delivery.

The proactive read index classifies article rows structurally before applying the reminder
limit, so a busy feed cannot bury personal reminders. News bodies are never loaded by the
reminder query; news contributes only one unread-update summary. The existing public-news
reader and stored articles are unchanged. Index v4 is rebuilt transactionally from stored
records and retains existing messages and read state. Each source gets a bounded share of
the reminder area; paused/blocked tasks are not advertised as successfully recovered.

The reminder view occupies the existing empty transcript viewport rather than inserting
a fixed-height pane above it. A real transcript hides it and restores the conversation
title. Reads are asynchronous and coalesced; late results cannot repopulate a hidden view.
While visible, delivery/schedule events and a one-minute local refresh update reminders
without invoking a model. Leaving voice mode or backgrounding clears its view text and
unsubscribes/removes callbacks. Existing background playback is unaffected.

## Local build notes

Reminder-source fix, Android `0.1.6.23` (1399), Samsung SM-S9480 / Android 17:

- Reproduced through the actual voice entry: four news bodies appeared under Reminders.
  After cover installation the same entry showed one unread-news summary, no article
  bodies or fabricated forecasts/appointments. Existing data was preserved.
- 64 JVM tests passed across six reminder, App-tool, inbox, session and playback suites.
- 19 device tests passed. Five new checks cover an older reminder behind 200 articles,
  read-state preservation, v3 index migration, empty/error rendering, late-load cleanup,
  and the live provider-facing reminder tool. The existing fourteen voice/phone/news/
  completed-reply checks also passed, including real Edge TTS background playback.
- Calendar-event display with granted calendar access, real provider voice decisions,
  physical headset changes and SIM audio remain outside this validation. No calendar
  permission, default dialer, user conversation or pairing was reset by these tests.

Completed-reply increment, Android `0.1.6.22` (1398), Samsung SM-S9480 / Android 17:

- 112 JVM tests passed across 12 voice, App-tool, queue, protocol and audio-source suites.
- Fourteen device tests passed, including the original ten voice/news/phone checks and
  four reply-playback checks. The live reply test starts through the existing Read
  button, destroys its Activity, pauses/resumes through system media controls, verifies
  recording handoff and stops playback without changing the news bookmark.
- Natural completion clears playback state; a cancelled pending start cannot speak
  later, and a mismatched conversation cannot read another conversation's reply.
- Real synthesis used `zh-CN-XiaoxiaoNeural` through Edge protocol v2. No plaintext TTS
  MP3 was left in the app cache. Notifications contained generic status, not reply text.
- Device tests used isolated Chinese reply fixtures and downloaded public news. They
  did not send contact messages or place calls. Physical headset/lock-screen transitions
  and continuous background microphone capture are not covered by this increment.

Validation on 2026-10-26, Android `0.1.6.21` (1397), Samsung SM-S9480 / Android 17:

- 148 JVM tests passed across 14 native-tool, session, context, news queue and TTS suites.
- Ten instrumentation tests passed: compact widths, bounded news queries, cross-page
  voice state, real paired-contact navigation, stale-turn rejection, SIM capability gating
  and the compact phone page, playback-only service declaration, layout-stable article
  highlighting and live background news playback. The default dialer remained Samsung Phone.
- Live playback used the device's Microsoft Edge TTS setting and downloaded public news.
  Tests covered Activity backgrounding, system media pause/resume/next/stop and synchronous
  recording handoff. Media-session discovery alone borrows MEDIA_CONTENT_CONTROL; audio
  focus and playback use the app's own identity. Broad test permission adoption had caused
  Android 17 audio-hardening rejection and is intentionally not used during playback.
- Navigation tests deliberately mute capture and do not send messages or place calls.
  Bilingual phone layout fixtures are renderer data, not a successful SIM audio test.
- Real microphone/headset capture, live provider command selection and real SIM calls
  are not covered by these results. They remain in the acceptance matrix above.

The development environment has the existing staged arm64 memory native library but
does not currently have the Rust 1.97.1 Cargo executable required by `buildNativeMemory`.
Validation of this Android-only change uses `-x :app:buildNativeMemory`, reusing that
unchanged native library. This is not a clean native rebuild or release-build claim.

`npm run check` currently stops at the pre-existing Kotlin source-size guard:
`GalaxySSIMqttClient.kt` is 153,629 bytes, above the 153,600-byte limit. The file is
unchanged by this feature; the same size is present in the base Git blob.
