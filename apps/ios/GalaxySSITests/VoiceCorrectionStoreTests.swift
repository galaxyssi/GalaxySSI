import XCTest
@testable import GalaxySSI

final class VoiceCorrectionStoreTests: XCTestCase {
  func testExecutionClaimsSurviveRecreationWithoutFastTranscriptPlaintext() throws {
    let suiteName = "galaxyssi-voice-execution-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsVoiceExecutionRecordStore(defaults: defaults)
    store.clear()

    let transcript = "private voice command"
    let ledger = VoiceExecutionLedger(initialRecords: store.read(), persistence: store)
    ledger.begin(
      sessionId: "voice-session",
      idempotencyKey: "voice-session:dispatch",
      fast: TranscriptHypothesis(
        text: transcript,
        revision: 1,
        provider: "whisper.cpp",
        modelProfileId: "tiny_q5_1"
      ),
      risk: .high
    )
    XCTAssertTrue(ledger.claimPrimaryDispatch(sessionId: "voice-session"))
    XCTAssertFalse(ledger.claimPrimaryDispatch(sessionId: "voice-session"))

    let restored = VoiceExecutionLedger(initialRecords: store.read(), persistence: store)
    XCTAssertEqual(restored.snapshot(sessionId: "voice-session")?.primaryDispatchClaimed, true)
    XCTAssertFalse(restored.claimPrimaryDispatch(sessionId: "voice-session"))

    let raw = try XCTUnwrap(defaults.data(forKey: "galaxyssi_voice_execution_v1.records"))
    XCTAssertFalse(String(data: raw, encoding: .utf8)?.contains(transcript) == true)
  }

  func testCorrectionJournalAppendsContextAndMarksUserEdited() throws {
    let suiteName = "galaxyssi-voice-corrections-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let journal = VoiceCorrectionJournal(defaults: defaults)
    journal.clear()

    XCTAssertTrue(journal.append(VoiceCorrectionContextRecord(
      sessionId: "voice-session",
      conversationId: "conversation",
      turnId: "turn",
      fastText: "private voice command",
      accurateText: "private corrected command",
      diffSummary: "wording changed",
      risk: .high,
      revision: 2,
      modelProfileId: "medium_q5_0",
      modelSha256: String(repeating: "a", count: 64),
      executionMode: "SECOND_PASS",
      userEdited: false,
      completedAtMillis: 10
    )))
    XCTAssertFalse(journal.append(VoiceCorrectionContextRecord(
      sessionId: "voice-session",
      conversationId: "conversation",
      turnId: "turn",
      fastText: "older",
      accurateText: "older",
      diffSummary: "older",
      risk: .low,
      revision: 1,
      modelProfileId: "tiny_q5_1",
      modelSha256: String(repeating: "b", count: 64),
      executionMode: "SECOND_PASS",
      userEdited: false,
      completedAtMillis: 9
    )))

    XCTAssertEqual(journal.forConversation("conversation").count, 1)
    XCTAssertTrue(journal.contextBlock(conversationId: "conversation").contains("private corrected command"))
    XCTAssertTrue(journal.markUserEdited(sessionId: "voice-session"))
    XCTAssertFalse(journal.markUserEdited(sessionId: "voice-session"))
    XCTAssertTrue(journal.contextBlock(conversationId: "conversation").contains("user edit remains authoritative"))
  }
}
