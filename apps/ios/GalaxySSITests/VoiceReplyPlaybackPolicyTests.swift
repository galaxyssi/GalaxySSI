import XCTest
@testable import GalaxySSI

final class VoiceReplyPlaybackPolicyTests: XCTestCase {
  func testReminderTaskLimitAppliesAfterFilteringAndKeepsOriginalIDs() {
    func record(_ id: String, _ phase: AgentPhase, goal: String = "Review") -> AgentTaskRecord {
      AgentTaskRecord(taskId: id, sessionId: "thread-\(id)", goal: goal, phase: phase,
                      routeKind: .localSystem, targetTitle: "", risk: .medium, blocked: phase == .blocked)
    }
    let rows = VoiceReminderSnapshot.taskRows([
      record("done", .completed), record("private", .paused, goal: "Sensitive goal withheld"),
      record("task-42", .waitingConfirmation), record("other", .blocked)
    ], limit: 1)
    XCTAssertEqual(rows.map(\.id), ["task-42"])
    XCTAssertEqual(rows.first?.conversationID, "thread-task-42")
    XCTAssertEqual(rows.first?.phase, AgentPhase.waitingConfirmation.rawValue)
  }

  func testReminderToolChecksConsentBeforeReadingAndReturnsOnlyOneNewsSummary() throws {
    var reads = 0
    let executable = try VoiceReminderNativeTool.executable { context in
      reads += 1
      guard context.conversationId == "active-thread" else { return nil }
      return VoiceReminderSnapshot(
        tasks: [], personal: [
          .init(id: "saved-reminder", conversationID: "thread-42", content: "Follow up", atMillis: 10)
        ], calendar: nil, unreadNewsCount: 12
      )
    }
    let registry = try AgentNativeToolRegistry().registerExecutable(executable)
    let denied = registry.invoke(executable.id, input: [:])
    XCTAssertEqual(denied.error?.code, "missing_consents")
    XCTAssertEqual(reads, 0)
    let result = registry.invoke(executable.id, input: [:], context: AgentNativeToolInvocationContext(
      conversationId: "active-thread", grantedConsents: [VoiceReminderNativeTool.consentID]
    ))
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(result.output["news_bodies_included"], .bool(false))
    guard case .array(let rows)? = result.output["reminders"],
          case .object(let personal)? = rows.first, case .object(let news)? = rows.last else {
      return XCTFail("Expected personal reminder and unread news count")
    }
    XCTAssertEqual(rows.count, 2)
    XCTAssertEqual(personal["conversation_id"], .string("thread-42"))
    XCTAssertEqual(news["id"], .string("news:unread"))
    XCTAssertEqual(news["content"], .string("Unread updates: 12"))
  }

  func testPersonalRemindersSkipReadAndLegacyNewsBeforeTakingTheLimit() {
    func item(_ id: String, messageID: String, viewed: Int64 = 0) -> GlobalProactiveInboxItem {
      GlobalProactiveInboxItem(key: id, messageIds: [messageID], title: "Update", content: "Review",
        topic: "", target: .currentConversation, urgent: false, sourceConversationId: "thread-source",
        destinationConversationId: "thread-destination", causalEventIds: [], createdAtMillis: 1,
        deliveredAtMillis: 2, viewedAtMillis: viewed, feedbackKind: nil)
    }
    let rows = VoiceReminderSnapshot.personalRows([
      item("news", messageID: "attention-feed:story"),
      item("seen", messageID: "seen", viewed: 10),
      item("personal", messageID: "personal")
    ], limit: 1)
    XCTAssertEqual(rows.map(\.id), ["personal"])
    XCTAssertEqual(rows.first?.conversationID, "thread-destination")
  }

  func testVoiceAcknowledgementHasSeparateUtteranceAndHonorsMute() {
    let language = LanguagePolicySettings(ttsLanguage: "en-US")
    let request = VoiceReplyPlaybackPolicy.inputAcknowledgementRequest(
      text: "Processing input", settings: settings(speakReplies: true, ttsProvider: .microsoftEdge),
      languagePolicy: language, sessionId: "voice-1"
    )
    XCTAssertEqual(request?.utteranceId, "galaxyssi_voice_ack_voice-1")
    XCTAssertEqual(request?.providerId, "microsoft_edge")
    XCTAssertNil(VoiceReplyPlaybackPolicy.inputAcknowledgementRequest(
      text: "Processing input", settings: settings(speakReplies: false),
      languagePolicy: language, sessionId: "voice-1"
    ))
  }

  func testPlaybackReferenceRejectsInvertedEchoWithoutSuppressingDoubleTalkOrUnplayedAudio() {
    let reference = VoicePlaybackEchoReference()
    let id = UUID()
    var random: UInt32 = 42
    let samples = (0..<1_600).map { _ in
      random = 1_664_525 &* random &+ 1_013_904_223
      return Float(Int(random >> 16) - 32_768) / 65_536
    }
    func microphone(at offset: Int, mixed: Bool = false) -> [Int16] {
      (0..<80).map { index in
        let echo = -samples[offset + index] * 0.5
        let speech = mixed ? samples[1_400 + index] * 0.8 : 0
        return Int16((echo + speech) * 32_768)
      }
    }
    reference.begin(id: id, samples: samples, at: 0)
    XCTAssertTrue(reference.matches(microphone(at: 600), rate: 4_000, endingAt: 0.25))
    XCTAssertFalse(reference.matches(microphone(at: 600, mixed: true), rate: 4_000, endingAt: 0.25))
    reference.end(id: id, played: 0.25, at: 0.25)
    XCTAssertTrue(reference.matches(microphone(at: 600), rate: 4_000, endingAt: 0.29))
    XCTAssertFalse(reference.matches(microphone(at: 1_050), rate: 4_000, endingAt: 0.29))
    XCTAssertFalse(reference.matches(microphone(at: 600), rate: 4_000, endingAt: 0.7))
    reference.clear()
    XCTAssertFalse(reference.matches(microphone(at: 600), rate: 4_000, endingAt: 0.29))
  }

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
