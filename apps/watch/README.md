# GalaxySSI Watch

Native GalaxySSI companion for Wear OS on Android 13+ (minimum API 33).
The app has its own identity, storage, manifest, and build. Phone applications
and their Linux/model features are not modified.

## Development boundaries

- Keep watch-specific source code, dependencies, and build configuration here.
- Reuse shared protocols and core components where appropriate.
- Document protocol changes under `docs/protocol`.

## Included

- Round-screen conversation home, searchable recent conversations with unread
  counts, connected assistants, device pairing, and settings; English and Chinese resources.
- System speech input with transcript review, keyboard fallback, reply speech,
  and optional completion vibration/notifications.
- Direct HTTPS chat-completions connections with user-supplied endpoint, model,
  and encrypted API Key, independent of Desktop pairing.
- Existing GalaxySSI Link v2 privacy packets, Signal sessions, identity pinning,
  encrypted local storage, verified replies, and bounded chunk reassembly.
- Durable outbox with stable message/task IDs, application receipts, bounded
  retry, inbox replay protection, task-state ordering, and explicit remote stop.
- Visible data-sync service holds the connection for at most 15 minutes while
  waiting for a remote task. It does not keep the microphone or display on.

## Build and test

Use JDK 17 or 21 and an Android SDK with platform 35 and NDK 29.0.13113456.
Set `sdk.dir` in untracked `local.properties`, or configure `ANDROID_HOME`.

```powershell
.\gradlew.bat :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
.\gradlew.bat :app:assembleDebugAndroidTest
```

Debug APKs are written to `app/build/outputs/apk/debug/`, separately for
`armeabi-v7a`, `arm64-v8a`, and `x86_64`. Release builds are unsigned until a
production signing configuration is supplied. No signing keys are committed.

After wireless ADB pairing, the helper selects the correct APK for the device:

```powershell
python tools/watchctl.py --serial <ip:connect-port> install
python tools/watchctl.py --serial <ip:connect-port> test
```

Pass `--server-port 5038` if using the isolated development ADB server.

## Pair with GalaxySSI Desktop

ADB installation pairing and GalaxySSI trusted application pairing are separate.
Open the computer application's pairing screen and generate a fresh offer. Import
that trusted offer on the watch, review the displayed identity fingerprint, and
confirm it. The computer must approve the relationship as required by its existing
pairing policy. The watch never treats Wi-Fi discovery as authorization.

For the debug build, a helper transfers the current offer directly into private
app storage without printing its contents or putting it in command arguments:

```powershell
python tools/watchctl.py --serial <ip:connect-port> offer --file <pairing-offer.json>
# Or use the running local Desktop API:
python tools/watchctl.py --serial <ip:connect-port> offer --url http://127.0.0.1:8765/api/pairing/payload
```

The watch still requires an explicit identity review. The imported file is removed
after reading. The production UI also accepts pasted offer JSON. A camera-free,
short-code enrollment bridge is not yet implemented; the short code in the design
preview was illustrative, not an existing GalaxySSI protocol.

Select an assistant advertised by the paired computer, then speak or type a
message. The watch communicates through the existing TLS MQTT relay
`broker.emqx.io:8883`; being on the same Wi-Fi does not make this a direct LAN
transport. It requires network access to that relay.

## Reuse and exclusions

`shared-link` compiles an explicit allowlist of source files from `apps/android`
into generated build output. There is no fork of their crypto implementation.
Its route-revocation adapter removes only matching watch outbox records.
The phone storage engine's optional personal-memory segment interfaces have a
watch adapter that explicitly rejects access. Watch records and Signal sessions
continue to use the actual shared encrypted inline storage implementation; the
phone memory runtime and its maintenance dependencies are not included.
The first watch build's encrypted Signal preference records migrate transactionally
before crypto initialization, preserving the existing identity and sessions. Existing
current-format records are never overwritten by legacy state.

The dependency graph contains no phone `:app` or `:llama-runtime`, Linux runtime,
terminal, Git/JGit, local model catalog, Whisper assets, QNN/GenieX, OCR/camera, PDF
editor, or remote-desktop stream. Signal's test and desktop native libraries are
excluded; Android JNI libraries are stripped and compressed.

## API Key direct connection

On the watch, select **Choose connection > API Key direct connection**, or open
the same page under Settings. Select a provider, then a model, and enter its key.
The watch catalog is generated at build time directly from Android's
`MainActivityConstants.kt` cloud presets: OpenAI (4), Anthropic (3), Google Gemini
(3), DeepSeek (3), Qwen (3), OpenRouter (2), and Custom (1). The model IDs match
that source; availability depends on the provider and the user's account.

OpenAI-compatible chat completions, Anthropic Messages, and Gemini generateContent
have separate request, authentication, and response adapters. Custom HTTPS endpoints
and model IDs remain editable. This watch client supports text conversations;
phone-side image, web-tool, and agent-tool execution features are not included.
Official DeepSeek requests explicitly disable thinking and cap output at 2,048
tokens for watch conversations. Replies currently appear after complete generation;
requests have a 100-second total timeout.

Review the destination before saving. Saving does not make a billable request.

To avoid typing a long key on the watch, run this locally; key input is hidden:

```powershell
python tools/watchctl.py --serial <ip:connect-port> api --endpoint <full-https-endpoint> --model <model-id>
```

For native Claude or Gemini endpoints, add `--api-style anthropic` or
`--api-style gemini`.

Alternatively, import a private JSON file with `endpoint`, `model`, and `api_key`
fields, plus `api_style` (`openai`, `anthropic`, or `gemini`), using `api --file <private-config.json>`. Keep this file outside the source
repository. The helper does not log the key or put it in process arguments. The
watch removes its temporary import file and requires destination confirmation.

The key is encrypted using the reused Android Keystore-backed storage, never
displayed again in plaintext, and is removable from settings. Leaving the key blank
while editing preserves it only when the endpoint stays the same. Redirects and
automatic HTTP retries are disabled. Recent context is bounded and confined to
the same conversation/provider profile. Stopping an API call stops waiting; it
cannot guarantee that the provider stops processing or charging.

## Current boundaries

- This build connects to Desktop-advertised assistants or a configured compatible
  API provider. Phone-to-watch contact
  enrollment, phone handoff, local discovery, and a voice Tile are not implemented.
- Voice recognition and speech languages depend on the installed system services.
- Task approval is shown on the watch with a direction to review it on the computer.
- Background monitoring is time-bounded; open the app to reconnect after it ends.
- `UI_DESIGN.md` is the original proposal; this README describes implemented behavior.

## Branding and result notifications

Launcher and splash assets are synchronized directly from Android at build time.
The conversation home reuses Android's brand and composer icons, with user messages
on the right and assistant replies on the left. Task progress stays in that same
transcript; there is no separate assistant chat or task-detail page. The fixed
composer preserves unsent text and cursor position when a reply arrives. Reading
older messages preserves the scroll position and offers a new-reply shortcut.

Tap the brand or the empty composer's layers icon for the menu; tap the upper-right
conversation title for recent conversations. Long-press that title to configure
the model. Type into the composer and tap the send icon, or long-press the input
to launch system speech recognition and review its transcript before sending.
Samsung watches prefer Samsung Keyboard's public speech-input activity. If it is
unavailable or cannot be launched, the system speech activity is used. This does
not invoke the Bixby assistant. Recognition language follows the watch locale;
language availability and network requirements depend on the installed input service.
Long-press a reply to read it aloud. The contacts directory lists actual connected
assistants; phone contact synchronization and person-to-person chat are not included.

Result notifications and vibration are suppressed only while the matching
conversation screen is resumed. Conversation identity includes endpoint/profile,
assistant, and conversation ID, so other conversations still notify. Opening a
conversation clears its existing result notifications. Background monitoring keeps
the system-required foreground-service indicator.
