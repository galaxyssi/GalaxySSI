# SignalASI iOS

SignalASI iOS is a native SwiftUI client for iOS 15 and later. It mirrors the Android client's primary mobile surface: chats, contacts, SignalASI Link pairing, direct cloud model contacts, voice capture settings, local notifications, and durable local state.

## Current Scope

- SwiftUI app target and XCTest target in `SignalASI.xcodeproj`
- Chats and contacts backed by a local Codable store
- Android-compatible SignalASI Link v1 QR validation, route generation, pairing claim encryption, envelope creation, and envelope validation
- Native MQTT 3.1.1 transport over TLS for pairing topics, Link topics, and background message delivery handoff
- Direct cloud model contacts for OpenAI-compatible, Anthropic, and Gemini-style APIs, with API keys stored in Keychain
- QR scanning with AVFoundation
- Speech recognition and microphone capture settings with iOS permission prompts
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
