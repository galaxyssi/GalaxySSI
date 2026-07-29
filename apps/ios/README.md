# SignalASI iOS

SignalASI iOS is a native SwiftUI client for iOS 15 and later. It mirrors the Android client's primary mobile surface: chats, contacts, SignalASI Link pairing, direct cloud model contacts, voice capture settings, local notifications, and durable local state.

## Current Scope

- SwiftUI app target and XCTest target in `SignalASI.xcodeproj`
- Chats and contacts backed by a local Codable store, including searchable chat/contact lists, unread conversation summaries, local message deletion, chat history clearing, message details, and delivery trace inspection
- Android-compatible SignalASI Link v1 QR validation, route generation, pairing claim encryption, envelope creation, and envelope validation
- Native MQTT 3.1.1 transport over TLS for pairing topics, Link topics, and background message delivery handoff
- Durable Link outbox, exponential retry, delivery acknowledgements, Android-style delivery trace stages, inbound dedupe, and Android-compatible `signal-chunk` MQTT payload chunking
- Android-compatible `signalasi_contact` QR export/import with pending friend requests, approve/reject handling, and verified contact creation
- Local contact management with Android-style remark rename, soft delete, optional chat deletion, and private data reset
- Explicit file/photo attachments with Android-compatible descriptors, inline `data_b64` transport for small payloads, metadata-only fallback for larger files, and chat composer previews
- Direct cloud model contacts for OpenAI-compatible, Anthropic, and Gemini-style APIs, with provider-level model selection, readiness checks, and API keys stored in Keychain
- Android-style language policy settings for interface preference, model response language, ASR locale, and TTS language
- Android-style app display text sizing with System, Standard, Comfortable, Large, and Extra Large modes
- Android-style Agent Safety settings for task execution mode, action permission mode, safety guards, pause state, and allowed action surfaces
- Android-style Agent confirmation policy for Direct, Confirm Once, and Confirm Always action gating
- Android-style agent clarification policy for deciding when to execute, ask locally, or ask with model context
- Android-style final response self-check for empty, echo, acknowledgement-only, attachment, and identity mismatch repair signals
- Android-style agent task budget settings with Adaptive/Fast/Economy/Private/Custom profiles, per-task limits, and resource access policies
- Android-style custom device connector configuration for HTTP REST, MQTT, WebSocket, TCP, UDP, MCP, SignalASI Agent, BLE, and Matter/Thread targets
- Android-style Home Assistant configuration with enabled state, local server URL, Keychain access token storage, and default entity target
- Android-style model planner settings for model-driven planning, replanning, coordination, privacy sharing, and task-control limits
- Android-style active turn policy for interrupting, steering, or separating new user requests while an agent task is in progress
- Android-compatible encrypted `.hcbak` backup envelope with iOS local state, Link peers, voice settings, messages, and cloud API secrets restore
- QR scanning with AVFoundation
- Speech recognition and microphone capture settings with iOS permission prompts, Android-style wake words, wake threshold, welcome text, speak replies, and voice routing preferences
- UserNotifications integration for incoming background messages

## Compatibility Note

Android uses libsignal-backed Signal sessions after the encrypted pairing claim is accepted. This iOS foundation keeps the same protocol boundaries and pairing claim format, but the full libsignal Swift bridge still needs to be wired before paired desktop chat can be considered end-to-end encrypted parity.

## iOS Version

The deployment target is iOS 15.0. Newer platform affordances are avoided unless guarded by the app layer.

## Build And Test

On macOS with Xcode installed:

```sh
xcodebuild test \
  -project apps/ios/SignalASI.xcodeproj \
  -scheme SignalASI \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

On any development host:

```sh
npm run check:ios
```

The cross-platform check verifies that the iOS project exists, keeps the iOS 15 deployment target, and includes the parity-critical source and test files.
