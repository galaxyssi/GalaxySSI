import XCTest
@testable import GalaxySSI

final class VoiceReplyPlaybackPolicyTests: XCTestCase {
  func testIncomingTargetReplyBuildsSystemTTSRequest() {
    let request = VoiceReplyPlaybackPolicy.request(
      message: message("Hello from Hermes", contactId: "hermes"),
      settings: settings(speakReplies: true),
      languagePolicy: LanguagePolicySettings(ttsLanguage: "zh-CN"),
      activeSessionId: "voice-1",
      activeTargetContactId: "hermes"
    )

    XCTAssertEqual(request?.sessionId, "voice-1")
    XCTAssertEqual(request?.text, "Hello from Hermes")
    XCTAssertEqual(request?.language, "zh-CN")
    XCTAssertEqual(request?.providerId, "android")
    XCTAssertEqual(request?.runtimeChannel, .androidSystemTTS)
    XCTAssertEqual(request?.voiceName, "")
    XCTAssertTrue(request?.utteranceId.hasPrefix("galaxyssi_voice_") == true)
  }

  func testPolicyRoutesMicrosoftEdgeToNativeEdgeRuntime() {
    let request = VoiceReplyPlaybackPolicy.request(
      message: message("reply", contactId: "hermes"),
      settings: settings(speakReplies: true, ttsProvider: .microsoftEdge, microsoftVoice: "zh-CN-XiaoxiaoNeural"),
      languagePolicy: LanguagePolicySettings(ttsLanguage: "en-US"),
      activeSessionId: "voice-1",
      activeTargetContactId: "hermes"
    )

    XCTAssertEqual(request?.providerId, "microsoft_edge")
    XCTAssertEqual(request?.runtimeChannel, .microsoftEdgeTTS)
    XCTAssertEqual(request?.voiceName, "en-US-JennyNeural")
  }

  func testPolicySkipsWhenSpeakRepliesDisabledOrMessageIsNotTargetReply() {
    let target = message("reply", contactId: "hermes")
    let mine = message("mine", contactId: "hermes", isMine: true)
    let system = message("system", contactId: "hermes", isSystem: true)
    let other = message("other", contactId: "cloud")

    XCTAssertNil(VoiceReplyPlaybackPolicy.request(
      message: target,
      settings: settings(speakReplies: false),
      languagePolicy: .default,
      activeSessionId: "voice-1",
      activeTargetContactId: "hermes"
    ))
    XCTAssertNil(VoiceReplyPlaybackPolicy.request(
      message: mine,
      settings: settings(speakReplies: true),
      languagePolicy: .default,
      activeSessionId: "voice-1",
      activeTargetContactId: "hermes"
    ))
    XCTAssertNil(VoiceReplyPlaybackPolicy.request(
      message: system,
      settings: settings(speakReplies: true),
      languagePolicy: .default,
      activeSessionId: "voice-1",
      activeTargetContactId: "hermes"
    ))
    XCTAssertNil(VoiceReplyPlaybackPolicy.request(
      message: other,
      settings: settings(speakReplies: true),
      languagePolicy: .default,
      activeSessionId: "voice-1",
      activeTargetContactId: "hermes"
    ))
  }

  func testPolicyTrimsAndBoundsSpokenText() {
    let longText = "  " + String(repeating: "a", count: VoiceReplyPlaybackPolicy.maximumSpokenCharacters + 20)
    let request = VoiceReplyPlaybackPolicy.request(
      message: message(longText, contactId: "hermes"),
      settings: settings(speakReplies: true),
      languagePolicy: LanguagePolicySettings(ttsLanguage: "auto"),
      activeSessionId: "voice-1",
      activeTargetContactId: "hermes"
    )

    XCTAssertEqual(request?.text.count, VoiceReplyPlaybackPolicy.maximumSpokenCharacters)
    XCTAssertFalse(request?.text.hasPrefix(" ") == true)
    XCTAssertFalse(request?.language.isEmpty ?? true)
  }

  func testPolicyRequiresActiveSessionAndTarget() {
    let reply = message("reply", contactId: "hermes")

    XCTAssertNil(VoiceReplyPlaybackPolicy.request(
      message: reply,
      settings: settings(speakReplies: true),
      languagePolicy: .default,
      activeSessionId: "",
      activeTargetContactId: "hermes"
    ))
    XCTAssertNil(VoiceReplyPlaybackPolicy.request(
      message: reply,
      settings: settings(speakReplies: true),
      languagePolicy: .default,
      activeSessionId: "voice-1",
      activeTargetContactId: ""
    ))
  }

  private func settings(
    speakReplies: Bool,
    ttsProvider: VoiceTTSProvider = .system,
    microsoftVoice: String = "zh-CN-XiaoxiaoNeural"
  ) -> VoiceSettings {
    VoiceSettings(
      wakeListeningEnabled: false,
      speechRecognitionEnabled: true,
      textToSpeechEnabled: true,
      autoSendTranscripts: true,
      preferredLocaleIdentifier: "en-US",
      ttsProvider: ttsProvider,
      microsoftVoice: microsoftVoice,
      speakReplies: speakReplies,
      routingMode: .nativeAgent
    )
  }

  private func message(
    _ content: String,
    contactId: String,
    isMine: Bool = false,
    isSystem: Bool = false
  ) -> ChatMessage {
    ChatMessage(
      id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
      contactId: contactId,
      content: content,
      isMine: isMine,
      isSystem: isSystem
    )
  }
}
