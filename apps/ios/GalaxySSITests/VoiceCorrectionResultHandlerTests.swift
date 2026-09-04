import XCTest
@testable import GalaxySSI

final class VoiceCorrectionResultHandlerTests: XCTestCase {
  func testDispatchesCorrectedTranscriptAndPersistsJournalContext() throws {
    let coordinator = VoiceInteractionCoordinator(sessionIdFactory: { "voice-1" })
    beginAndFinishFastTranscript(coordinator)
    let ledger = VoiceExecutionLedger(clock: { 1_000 })
    let fast = hypothesis("Summarize the blue report", revision: 1)
    ledger.begin(sessionId: "voice-1", idempotencyKey: "voice-1:dispatch", fast: fast, risk: .conversation)
    let journal = makeJournal()
    let result = secondPassResult(
      fast: fast,
      accurate: hypothesis("Summarize the new report", revision: 2),
      record: ledger.snapshot(sessionId: "voice-1")!
    )

    let outcome = VoiceCorrectionResultHandler.handle(
      result: result,
      risk: .conversation,
      conversationId: "conversation",
      turnId: "turn",
      executionLedger: ledger,
      correctionJournal: journal,
      coordinator: coordinator
    )

    XCTAssertTrue(outcome.dispatchedCorrection)
    XCTAssertTrue(outcome.persistedCorrection)
    XCTAssertEqual(outcome.action, .displayOnly)
    XCTAssertEqual(coordinator.snapshot().correctedText, "Summarize the new report")
    XCTAssertTrue(journal.contextBlock(conversationId: "conversation").contains("Summarize the new report"))
  }

  func testProtectedEntityChangeRequestsConfirmationBeforeExecution() {
    let ledger = VoiceExecutionLedger(clock: { 1_000 })
    let fast = hypothesis("Pay Alice 50 USD", revision: 1)
    ledger.begin(sessionId: "voice-1", idempotencyKey: "voice-1:dispatch", fast: fast, risk: .critical)
    let result = secondPassResult(
      fast: fast,
      accurate: hypothesis("Pay Alice 500 USD", revision: 2),
      record: ledger.snapshot(sessionId: "voice-1")!
    )

    let outcome = VoiceCorrectionResultHandler.handle(
      result: result,
      risk: .critical,
      executionLedger: ledger,
      correctionJournal: makeJournal()
    )

    guard case .requireConfirmationBeforeExecution = outcome.action else {
      return XCTFail("Expected confirmation before execution")
    }
    XCTAssertFalse(outcome.dispatchedCorrection)
    XCTAssertTrue(outcome.persistedCorrection)
  }

  func testUserEditedCorrectionPersistsAsAuthoritativeContextOnly() {
    let ledger = VoiceExecutionLedger(clock: { 1_000 })
    let fast = hypothesis("Open calendar", revision: 1)
    ledger.begin(sessionId: "voice-1", idempotencyKey: "voice-1:dispatch", fast: fast, risk: .low)
    XCTAssertTrue(ledger.markUserEdited(sessionId: "voice-1"))
    let journal = makeJournal()
    let result = secondPassResult(
      fast: fast,
      accurate: hypothesis("Open calculator", revision: 2),
      record: ledger.snapshot(sessionId: "voice-1")!
    )

    let outcome = VoiceCorrectionResultHandler.handle(
      result: result,
      risk: .low,
      conversationId: "conversation",
      turnId: "turn",
      executionLedger: ledger,
      correctionJournal: journal
    )

    XCTAssertEqual(outcome.action, .updateFutureContext)
    XCTAssertTrue(outcome.persistedCorrection)
    XCTAssertTrue(journal.contextBlock(conversationId: "conversation").contains("user edit remains authoritative"))
  }

  func testNoMaterialChangeDoesNotPersistJournalRecord() {
    let ledger = VoiceExecutionLedger(clock: { 1_000 })
    let fast = hypothesis("Hello world", revision: 1)
    ledger.begin(sessionId: "voice-1", idempotencyKey: "voice-1:dispatch", fast: fast, risk: .conversation)
    let journal = makeJournal()
    let result = secondPassResult(
      fast: fast,
      accurate: hypothesis("Hello, world!", revision: 2),
      record: ledger.snapshot(sessionId: "voice-1")!
    )

    let outcome = VoiceCorrectionResultHandler.handle(
      result: result,
      risk: .conversation,
      conversationId: "conversation",
      turnId: "turn",
      executionLedger: ledger,
      correctionJournal: journal
    )

    XCTAssertEqual(outcome.action, .noMaterialChange)
    XCTAssertFalse(outcome.persistedCorrection)
    XCTAssertTrue(journal.contextBlock(conversationId: "conversation").isEmpty)
  }

  private func beginAndFinishFastTranscript(_ coordinator: VoiceInteractionCoordinator) {
    let begin = coordinator.begin(config: VoiceSessionConfig(requestedSessionId: "voice-1", source: "test"))
    XCTAssertTrue(begin.accepted)
    coordinator.dispatch(.capturePrepared(sessionId: "voice-1"))
    coordinator.dispatch(.speechStarted(sessionId: "voice-1", atElapsedNs: 1_000))
    coordinator.dispatch(.speechEnded(sessionId: "voice-1", atElapsedNs: 2_000))
    coordinator.dispatch(.finalizationStarted(sessionId: "voice-1"))
    coordinator.dispatch(.transcriptFinal(sessionId: "voice-1", value: hypothesis("Summarize the blue report", revision: 1)))
  }

  private func secondPassResult(
    fast: TranscriptHypothesis,
    accurate: TranscriptHypothesis,
    record: VoiceExecutionRecord
  ) -> VoiceSecondPassResult {
    let decision = DefaultTranscriptCorrectionController().compare(
      fast: fast,
      accurate: accurate,
      executionRecord: record
    )
    let consistency = DefaultEntityConsistencyChecker.compare(fastText: fast.text, accurateText: accurate.text)
    let diff = TranscriptDiff(
      fastText: fast.text.trimmingCharacters(in: .whitespacesAndNewlines),
      accurateText: accurate.text.trimmingCharacters(in: .whitespacesAndNewlines),
      normalizedFastText: fast.text.voiceNormalizedTranscript(),
      normalizedAccurateText: accurate.text.voiceNormalizedTranscript(),
      entityDifferences: consistency.differences
    )
    return VoiceSecondPassResult(
      metadata: VoiceSecondPassMetadata(
        sessionId: "voice-1",
        fast: fast,
        accurateProfileId: "base",
        accurateModelSha256: VoiceWhisperModelCatalog.model("base").sha256,
        mode: .secondPass,
        requestedAtMillis: 900
      ),
      accurate: accurate,
      diff: diff,
      decision: decision,
      completedAtMillis: 1_500
    )
  }

  private func hypothesis(_ text: String, revision: Int) -> TranscriptHypothesis {
    TranscriptHypothesis(
      text: text,
      revision: revision,
      provider: "whisper.cpp",
      modelProfileId: revision == 1 ? "tiny" : "base"
    )
  }

  private func makeJournal() -> VoiceCorrectionJournal {
    let suiteName = "galaxyssi-voice-correction-handler-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return VoiceCorrectionJournal(defaults: defaults)
  }
}
