import XCTest
@testable import GalaxySSI

final class VoiceSecondPassCoordinatorTests: XCTestCase {
  func testNewVoicePreemptsAnOrdinarySecondPass() {
    let coordinator = VoiceSecondPassCoordinator()
    let ledger = makeLedger()
    let decoderStarted = expectation(description: "decoder started")
    let unexpectedResult = expectation(description: "second pass callback")
    unexpectedResult.isInverted = true
    let callbackCount = LockedInt()

    XCTAssertTrue(coordinator.schedule(
      request: request(),
      executionLedger: ledger,
      decoder: { _ in
        decoderStarted.fulfill()
        try await Task.sleep(nanoseconds: 30_000_000_000)
        return self.hypothesis("accurate", revision: 2)
      },
      onResult: { _ in
        callbackCount.increment()
        unexpectedResult.fulfill()
      }
    ))
    wait(for: [decoderStarted], timeout: 1)

    XCTAssertEqual(coordinator.cancelForInteractiveVoice(), 1)
    wait(for: [unexpectedResult], timeout: 0.2)
    XCTAssertEqual(callbackCount.value, 0)
    XCTAssertTrue(coordinator.activeSessionIds().isEmpty)
  }

  func testDuplicateScheduleCannotProduceDuplicateCorrection() {
    let coordinator = VoiceSecondPassCoordinator()
    let ledger = makeLedger()
    let completed = expectation(description: "second pass completed")
    let callbackCount = LockedInt()

    let first = coordinator.schedule(
      request: request(),
      executionLedger: ledger,
      decoder: { _ in
        try await Task.sleep(nanoseconds: 50_000_000)
        return self.hypothesis("accurate", revision: 2)
      },
      onResult: { _ in
        callbackCount.increment()
        completed.fulfill()
      }
    )
    let duplicate = coordinator.schedule(
      request: request(),
      executionLedger: ledger,
      decoder: { _ in self.hypothesis("duplicate", revision: 3) },
      onResult: { _ in callbackCount.increment() }
    )

    XCTAssertTrue(first)
    XCTAssertFalse(duplicate)
    wait(for: [completed], timeout: 2)
    XCTAssertEqual(callbackCount.value, 1)
    XCTAssertTrue(coordinator.activeSessionIds().isEmpty)
  }

  private func makeLedger() -> VoiceExecutionLedger {
    let ledger = VoiceExecutionLedger()
    ledger.begin(
      sessionId: "voice-1",
      idempotencyKey: "voice-1:dispatch",
      fast: hypothesis("fast", revision: 1),
      risk: .conversation
    )
    return ledger
  }

  private func request() -> VoiceSecondPassRequest {
    VoiceSecondPassRequest(
      sessionId: "voice-1",
      pcm16: Array(repeating: 1, count: 16_000),
      sampleRateHz: 16_000,
      language: "en",
      fast: hypothesis("fast", revision: 1),
      accurateProfileId: "medium_q5_0",
      accurateModelSha256: String(repeating: "a", count: 64),
      mode: .secondPass
    )
  }

  private func hypothesis(_ text: String, revision: Int) -> TranscriptHypothesis {
    TranscriptHypothesis(
      text: text,
      revision: revision,
      provider: "whisper.cpp",
      modelProfileId: revision == 1 ? "tiny_q5_1" : "medium_q5_0"
    )
  }
}

private final class LockedInt {
  private let lock = NSLock()
  private var storage = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  func increment() {
    lock.lock()
    storage += 1
    lock.unlock()
  }
}
