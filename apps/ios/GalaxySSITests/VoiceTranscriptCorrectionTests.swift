import XCTest
@testable import GalaxySSI

final class VoiceTranscriptCorrectionTests: XCTestCase {
  func testRiskClassifierCoversConversationThroughCriticalCommands() {
    XCTAssertEqual(DefaultVoiceCommandRiskClassifier.classify("Explain this document"), .conversation)
    XCTAssertEqual(DefaultVoiceCommandRiskClassifier.classify("Check battery status"), .low)
    XCTAssertEqual(DefaultVoiceCommandRiskClassifier.classify("Change settings"), .medium)
    XCTAssertEqual(DefaultVoiceCommandRiskClassifier.classify("Delete Downloads/a.txt"), .high)
    XCTAssertEqual(DefaultVoiceCommandRiskClassifier.classify("Transfer money to Alice"), .critical)
  }

  func testRecipientMismatchIsAProtectedEntityDifference() throws {
    let result = DefaultEntityConsistencyChecker.compare(
      fastText: "\u{7ed9}\u{5f20}\u{4e09}\u{53d1}\u{9001}\u{6587}\u{4ef6}",
      accurateText: "\u{7ed9}\u{5f20}\u{5c71}\u{53d1}\u{9001}\u{6587}\u{4ef6}"
    )

    XCTAssertFalse(result.consistent)
    let difference = try XCTUnwrap(result.differences.single)
    XCTAssertEqual(difference.type, .recipient)
    XCTAssertEqual(difference.fastValues, ["\u{5f20}\u{4e09}"])
    XCTAssertEqual(difference.accurateValues, ["\u{5f20}\u{5c71}"])
  }

  func testPathMismatchBlocksAProtectedCommandBeforeExecution() {
    let fast = hypothesis("\u{5220}\u{9664}\u{4e0b}\u{8f7d}\u{76ee}\u{5f55}\u{4e2d}\u{7684} a.txt", revision: 1)
    let accurate = hypothesis("\u{5220}\u{9664}\u{4e0b}\u{8f7d}\u{76ee}\u{5f55}\u{4e2d}\u{7684} 8.txt", revision: 2)
    let decision = DefaultTranscriptCorrectionController().compare(
      fast: fast,
      accurate: accurate,
      executionRecord: record(risk: .high)
    )

    guard case .requireConfirmationBeforeExecution = decision else {
      return XCTFail("Expected confirmation before execution")
    }
    let diff = DefaultEntityConsistencyChecker.compare(fastText: fast.text, accurateText: accurate.text)
    XCTAssertTrue(diff.differences.contains { $0.type == .filePath })
  }

  func testAmountMismatchBlocksPaymentBeforeExecution() {
    let decision = DefaultTranscriptCorrectionController().compare(
      fast: hypothesis("Pay Alice 50 USD", revision: 1),
      accurate: hypothesis("Pay Alice 500 USD", revision: 2),
      executionRecord: record(risk: .critical)
    )

    guard case .requireConfirmationBeforeExecution = decision else {
      return XCTFail("Expected confirmation before execution")
    }
  }

  func testOrdinaryCorrectionAfterModelDispatchUpdatesFutureContextOnly() {
    let decision = DefaultTranscriptCorrectionController().compare(
      fast: hypothesis("Summarize the blue report", revision: 1),
      accurate: hypothesis("Summarize the new report", revision: 2),
      executionRecord: record(risk: .conversation, primaryDispatchClaimed: true)
    )

    guard case .updateFutureContext = decision else {
      return XCTFail("Expected future-context update")
    }
  }

  func testManualUserEditRemainsAuthoritative() {
    let decision = DefaultTranscriptCorrectionController().compare(
      fast: hypothesis("Open calendar", revision: 1),
      accurate: hypothesis("Open calculator", revision: 2),
      executionRecord: record(risk: .low, userEdited: true)
    )

    guard case .updateFutureContext = decision else {
      return XCTFail("Expected future-context update")
    }
  }

  func testPunctuationOnlyChangeIsIgnored() {
    let decision = DefaultTranscriptCorrectionController().compare(
      fast: hypothesis("Hello world", revision: 1),
      accurate: hypothesis("Hello, world!", revision: 2),
      executionRecord: record(risk: .conversation)
    )

    XCTAssertEqual(decision, .noMaterialChange)
  }

  func testDuplicateCorrectionRevisionIsIgnored() {
    let decision = DefaultTranscriptCorrectionController().compare(
      fast: hypothesis("Open notes", revision: 1),
      accurate: hypothesis("Open Notes app", revision: 2),
      executionRecord: record(risk: .low, highestCorrectionRevision: 2)
    )

    XCTAssertEqual(decision, .noMaterialChange)
  }

  func testLowConfidenceAndProperNounsRequestAccuracyPass() {
    let lowConfidence = VoiceSecondPassTriggerPolicy.evaluate(
      fast: hypothesis("hello", revision: 1, confidence: 0.55),
      utteranceDurationMs: 900
    )
    let namedEntities = VoiceSecondPassTriggerPolicy.evaluate(
      fast: hypothesis("Compare GPT5.6 with ClaudeCode", revision: 1),
      utteranceDurationMs: 900
    )

    XCTAssertTrue(lowConfidence.requested)
    XCTAssertTrue(lowConfidence.reasons.contains("low_confidence"))
    XCTAssertTrue(namedEntities.requested)
    XCTAssertTrue(namedEntities.reasons.contains("proper_nouns"))
  }

  func testConfidentShortConversationDoesNotRequestAccuracyPass() {
    let trigger = VoiceSecondPassTriggerPolicy.evaluate(
      fast: hypothesis("What is the weather", revision: 1, confidence: 0.91),
      utteranceDurationMs: 1_500
    )

    XCTAssertFalse(trigger.requested)
  }

  private func hypothesis(
    _ text: String,
    revision: Int,
    confidence: Float? = nil
  ) -> TranscriptHypothesis {
    TranscriptHypothesis(
      text: text,
      revision: revision,
      provider: "whisper.cpp",
      modelProfileId: revision == 1 ? "tiny_q5_1" : "medium_q5_0",
      confidence: confidence
    )
  }

  private func record(
    risk: VoiceCommandRisk,
    primaryDispatchClaimed: Bool = false,
    userEdited: Bool = false,
    highestCorrectionRevision: Int = 0
  ) -> VoiceExecutionRecord {
    VoiceExecutionRecord(
      sessionId: "voice-1",
      idempotencyKey: "voice-1:dispatch",
      fastTranscriptHash: "hash",
      fastRevision: 1,
      risk: risk,
      primaryDispatchClaimed: primaryDispatchClaimed,
      highestCorrectionRevision: highestCorrectionRevision,
      userEdited: userEdited
    )
  }
}

private extension Array {
  var single: Element? {
    count == 1 ? first : nil
  }
}
