import XCTest
@testable import GalaxySSI

final class VoiceExecutionLedgerTests: XCTestCase {
  func testExternalEffectsAgentRunsAndTtsCorrectionsAreEachIdempotent() {
    let ledger = VoiceExecutionLedger()
    ledger.begin(sessionId: "session", idempotencyKey: "session:dispatch", fast: hypothesis(), risk: .high)

    XCTAssertTrue(ledger.claimPrimaryDispatch(sessionId: "session"))
    XCTAssertFalse(ledger.claimPrimaryDispatch(sessionId: "session"))
    XCTAssertTrue(ledger.claimExternalSideEffect(sessionId: "session"))
    XCTAssertFalse(ledger.claimExternalSideEffect(sessionId: "session"))
    XCTAssertTrue(ledger.claimAgentRun(sessionId: "session"))
    XCTAssertFalse(ledger.claimAgentRun(sessionId: "session"))
    XCTAssertTrue(ledger.claimTtsCorrection(sessionId: "session"))
    XCTAssertFalse(ledger.claimTtsCorrection(sessionId: "session"))

    let record = ledger.snapshot(sessionId: "session")
    XCTAssertEqual(record?.externalSideEffectCount, 1)
    XCTAssertEqual(record?.agentRunCount, 1)
    XCTAssertEqual(record?.ttsCorrectionCount, 1)
  }

  func testOnlyTheHighestCorrectionRevisionIsAccepted() {
    let ledger = VoiceExecutionLedger()
    ledger.begin(sessionId: "session", idempotencyKey: "session:dispatch", fast: hypothesis(), risk: .conversation)

    XCTAssertTrue(ledger.acceptCorrectionRevision(sessionId: "session", revision: 2))
    XCTAssertFalse(ledger.acceptCorrectionRevision(sessionId: "session", revision: 2))
    XCTAssertFalse(ledger.acceptCorrectionRevision(sessionId: "session", revision: 1))
    XCTAssertTrue(ledger.acceptCorrectionRevision(sessionId: "session", revision: 3))
    XCTAssertEqual(ledger.snapshot(sessionId: "session")?.highestCorrectionRevision, 3)
  }

  func testBoundedRecordsArePersistedWithoutTranscriptPlaintext() {
    let persistence = CapturingExecutionRecordPersistence()
    let ledger = VoiceExecutionLedger(
      persistence: persistence,
      clock: { 1_000 },
      maxRecords: 16
    )

    for index in 0..<20 {
      ledger.begin(
        sessionId: "session-\(index)",
        idempotencyKey: "dispatch-\(index)",
        fast: hypothesis("private-\(index)"),
        risk: .low
      )
    }

    XCTAssertEqual(ledger.all().count, 16)
    XCTAssertEqual(persistence.writes.last?.count, 16)
    XCTAssertTrue(persistence.writes.last?.allSatisfy { !$0.fastTranscriptHash.contains("private") } == true)
  }

  private func hypothesis(_ text: String = "hello") -> TranscriptHypothesis {
    TranscriptHypothesis(
      text: text,
      revision: 1,
      provider: "whisper.cpp",
      modelProfileId: "tiny_q5_1"
    )
  }
}

private final class CapturingExecutionRecordPersistence: VoiceExecutionRecordPersistence {
  private(set) var writes: [[VoiceExecutionRecord]] = []

  func save(records: [VoiceExecutionRecord]) {
    writes.append(records)
  }
}
