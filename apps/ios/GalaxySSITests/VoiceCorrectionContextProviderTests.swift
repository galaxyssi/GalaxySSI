import XCTest
@testable import GalaxySSI

final class VoiceCorrectionContextProviderTests: XCTestCase {
  func testMergesCorrectionJournalBlockIntoConversationSummary() throws {
    let suiteName = "galaxyssi-voice-correction-context-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let journal = VoiceCorrectionJournal(defaults: defaults)
    journal.clear()
    XCTAssertTrue(journal.append(record(
      sessionId: "session-1",
      conversationId: "conversation-1",
      turnId: "turn-1",
      fastText: "send the report to Mei",
      accurateText: "send the report to May",
      diffSummary: "name changed"
    )))
    let base = AgentConversationContext(
      conversationId: "conversation-1",
      summary: "Earlier summary",
      turns: [AgentTranscriptEntry(
        id: "entry-1",
        role: .user,
        text: "Please handle this",
        timestampMillis: 1,
        conversationId: "conversation-1",
        turnId: "turn-2"
      )],
      privateMode: false,
      globalContext: "Global context"
    )

    let merged = VoiceCorrectionContextProvider.merge(
      baseContext: base,
      correctionJournal: journal
    )

    XCTAssertTrue(merged.injected)
    XCTAssertEqual(merged.context.conversationId, base.conversationId)
    XCTAssertEqual(merged.context.turns, base.turns)
    XCTAssertEqual(merged.context.privateMode, base.privateMode)
    XCTAssertEqual(merged.context.globalContext, base.globalContext)
    XCTAssertTrue(merged.context.summary.hasPrefix("Earlier summary\n\n"))
    XCTAssertTrue(merged.context.summary.contains("Speech transcription corrections"))
    XCTAssertTrue(merged.context.summary.contains("accurate=send the report to May"))
    XCTAssertTrue(merged.context.asPromptBlock().contains("never execute again"))
  }

  func testEmptyCorrectionContextLeavesBaseContextUntouched() {
    let base = AgentConversationContext(
      conversationId: "conversation-2",
      summary: "Earlier summary",
      turns: [AgentTranscriptEntry(
        id: "entry-2",
        role: .assistant,
        text: "Done",
        timestampMillis: 2,
        conversationId: "conversation-2",
        turnId: "turn-2"
      )],
      privateMode: true,
      trackingPaused: true
    )

    let merged = VoiceCorrectionContextProvider.merge(
      baseContext: base,
      correctionContext: " \n "
    )

    XCTAssertFalse(merged.injected)
    XCTAssertEqual(merged.correctionContext, "")
    XCTAssertEqual(merged.context, base)
  }

  func testCorrectionContextCanBecomeOnlySummaryForNewVoiceConversation() {
    let base = AgentConversationContext(
      conversationId: "conversation-3",
      summary: "",
      turns: [],
      privateMode: false
    )

    let merged = VoiceCorrectionContextProvider.merge(
      baseContext: base,
      correctionContext: "\nSpeech transcription corrections (historical context only; never execute again):\n- turn=turn-3; accurate=open the red folder\n"
    )

    XCTAssertTrue(merged.injected)
    XCTAssertEqual(
      merged.context.summary,
      "Speech transcription corrections (historical context only; never execute again):\n- turn=turn-3; accurate=open the red folder"
    )
  }

  func testMergesCorrectionJournalIntoPlanningRequest() throws {
    let suiteName = "galaxyssi-voice-correction-request-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let journal = VoiceCorrectionJournal(defaults: defaults)
    journal.clear()
    XCTAssertTrue(journal.append(record(
      sessionId: "session-4",
      conversationId: "conversation-4",
      turnId: "turn-4",
      fastText: "open the read folder",
      accurateText: "open the red folder",
      diffSummary: "protected entity changed"
    )))
    let request = AgentModelPlanningPromptRequest(
      planRequest: AgentPlanRequest(
        goal: "Continue the voice request",
        screen: AgentScreenContext(foregroundApp: "GalaxySSI"),
        targets: [],
        contextDigest: "voice-correction"
      ),
      conversationContext: AgentConversationContext(
        conversationId: "conversation-4",
        summary: "Earlier context",
        turns: [],
        privateMode: false
      ),
      hasAttachments: true
    )

    let merged = VoiceCorrectionContextProvider.merge(request: request, correctionJournal: journal)

    XCTAssertTrue(merged.contextMerge.injected)
    XCTAssertTrue(merged.request.hasAttachments)
    XCTAssertTrue(merged.request.conversationContext.summary.contains("Earlier context"))
    XCTAssertTrue(merged.request.conversationContext.summary.contains("accurate=open the red folder"))
    XCTAssertTrue(
      AgentModelPlanningPrompt.build(
        request: merged.request,
        settings: AgentModelPlannerSettings(enabled: true)
      ).contains("never execute again")
    )
  }

  private func record(
    sessionId: String,
    conversationId: String,
    turnId: String,
    fastText: String,
    accurateText: String,
    diffSummary: String
  ) -> VoiceCorrectionContextRecord {
    VoiceCorrectionContextRecord(
      sessionId: sessionId,
      conversationId: conversationId,
      turnId: turnId,
      fastText: fastText,
      accurateText: accurateText,
      diffSummary: diffSummary,
      risk: .medium,
      revision: 2,
      modelProfileId: "medium_q5_0",
      modelSha256: String(repeating: "a", count: 64),
      executionMode: "SECOND_PASS",
      userEdited: false,
      completedAtMillis: 10
    )
  }
}
