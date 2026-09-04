import XCTest
@testable import GalaxySSI

final class GlobalAgentContinuityTests: XCTestCase {
  func testQueueSpillsToDurableOverflowWithoutDroppingOldestEvents() {
    let initial = GlobalEventQueueState(ready: [event("a"), event("b")])

    let mutation = GlobalEventQueuePolicy.enqueue(
      state: initial,
      incoming: [event("c"), event("d"), event("e")],
      readyCapacity: 3,
      overflowCapacity: 3
    )

    XCTAssertEqual(mutation.state.ready.map(\.id), ["a", "b", "c"])
    XCTAssertEqual(mutation.state.overflow.map(\.id), ["d", "e"])
    XCTAssertEqual(mutation.acceptedCount, 3)
    XCTAssertTrue(mutation.capacityRejected.isEmpty)
  }

  func testQueueDeduplicatesAcrossReadyOverflowAndDeadLetters() {
    let initial = GlobalEventQueueState(
      ready: [event("a")],
      overflow: [event("b")]
    )

    let mutation = GlobalEventQueuePolicy.enqueue(
      state: initial,
      incoming: [event("a"), event("b"), event("dead"), event("c")],
      deadLetterEventIds: ["dead"],
      readyCapacity: 2,
      overflowCapacity: 2
    )

    XCTAssertEqual(mutation.acceptedCount, 1)
    XCTAssertEqual(mutation.state.ready.map(\.id), ["a", "c"])
    XCTAssertEqual(mutation.state.overflow.map(\.id), ["b"])
  }

  func testCompletedEventsPromoteOverflowInOriginalOrder() {
    let state = GlobalEventQueueState(
      ready: [event("a"), event("b"), event("c")],
      overflow: [event("d"), event("e")]
    )

    let next = GlobalEventQueuePolicy.removeAndPromote(
      state: state,
      removedEventIds: ["a", "c"],
      readyCapacity: 3
    )

    XCTAssertEqual(next.ready.map(\.id), ["b", "d", "e"])
    XCTAssertTrue(next.overflow.isEmpty)
  }

  func testCapacityPressureReturnsRejectedEventsForDeadLetterPreservation() {
    let mutation = GlobalEventQueuePolicy.enqueue(
      state: GlobalEventQueueState(ready: [event("a")], overflow: [event("b")]),
      incoming: [event("c"), event("d")],
      readyCapacity: 1,
      overflowCapacity: 1
    )

    XCTAssertEqual(mutation.acceptedCount, 2)
    XCTAssertEqual(mutation.capacityRejected.map(\.id), ["c", "d"])
    XCTAssertEqual(mutation.state.ready.map(\.id), ["a"])
    XCTAssertEqual(mutation.state.overflow.map(\.id), ["b"])
  }

  func testEventFailureUsesBackoffThenQuarantinesTheThirdAttempt() {
    let first = GlobalEventRetryPolicy.recordFailure(
      eventId: "event",
      previous: nil,
      error: TestFailure("first failure"),
      nowMillis: 1_000
    )
    let second = GlobalEventRetryPolicy.recordFailure(
      eventId: "event",
      previous: first,
      error: TestFailure("second failure"),
      nowMillis: 40_000
    )
    let third = GlobalEventRetryPolicy.recordFailure(
      eventId: "event",
      previous: second,
      error: TestFailure("third failure"),
      nowMillis: 200_000
    )

    XCTAssertEqual(first.attemptCount, 1)
    XCTAssertEqual(first.nextAttemptAtMillis, 31_000)
    XCTAssertFalse(first.quarantined)
    XCTAssertEqual(second.attemptCount, 2)
    XCTAssertEqual(second.nextAttemptAtMillis, 160_000)
    XCTAssertFalse(second.quarantined)
    XCTAssertEqual(third.attemptCount, 3)
    XCTAssertEqual(third.nextAttemptAtMillis, 0)
    XCTAssertTrue(third.quarantined)
    XCTAssertEqual(first.firstFailedAtMillis, third.firstFailedAtMillis)
  }

  func testDelayedFailuresDoNotBlockOtherReadyEvents() {
    let failure = GlobalEventRetryPolicy.recordFailure(
      eventId: "delayed",
      previous: nil,
      error: TestFailure("temporary"),
      nowMillis: 1_000
    )

    XCTAssertFalse(GlobalEventRetryPolicy.eligible(failure, nowMillis: 20_000))
    XCTAssertTrue(GlobalEventRetryPolicy.eligible(failure, nowMillis: 31_000))
    XCTAssertTrue(GlobalEventRetryPolicy.eligible(nil, nowMillis: 20_000))
  }

  func testFailureReasonIsCompactAndStableWithoutAStackTrace() {
    let first = GlobalEventRetryPolicy.recordFailure(
      eventId: "event",
      previous: nil,
      error: TestFailure("bad\n  payload"),
      nowMillis: 1_000
    )
    let second = GlobalEventRetryPolicy.recordFailure(
      eventId: "event",
      previous: nil,
      error: TestFailure("bad payload"),
      nowMillis: 2_000
    )

    XCTAssertEqual(first.reason, "bad payload")
    XCTAssertEqual(first.errorFingerprint, second.errorFingerprint)
    XCTAssertFalse(first.reason.contains("TestFailure"))
  }

  func testReconstructedQueuePromotesEveryOverflowEventWithoutLoss() {
    let initial = GlobalEventQueuePolicy.enqueue(
      state: GlobalEventQueueState(),
      incoming: (1...8).map { event("event-\($0)") },
      readyCapacity: 3,
      overflowCapacity: 8
    ).state
    var reconstructed = GlobalEventQueueState(
      ready: initial.ready,
      overflow: initial.overflow
    )
    var processed: [String] = []

    while let next = reconstructed.ready.first {
      processed.append(next.id)
      reconstructed = GlobalEventQueuePolicy.removeAndPromote(
        state: reconstructed,
        removedEventIds: [next.id],
        readyCapacity: 3
      )
    }

    XCTAssertEqual(processed, (1...8).map { "event-\($0)" })
    XCTAssertTrue(reconstructed.overflow.isEmpty)
  }

  func testDeadLetterReplayMovesEventAtomicallyIntoAvailableQueue() {
    let letter = deadLetter("failed")

    let replay = GlobalDeadLetterRecoveryPolicy.replay(
      state: GlobalEventQueueState(ready: [event("ready")]),
      deadLetters: [letter],
      eventId: "failed",
      readyCapacity: 2,
      overflowCapacity: 1
    )

    XCTAssertTrue(replay.replayed)
    XCTAssertEqual(replay.enqueuedEvent?.id, "failed")
    XCTAssertEqual(replay.queueState.ready.map(\.id), ["ready", "failed"])
    XCTAssertTrue(replay.deadLetters.isEmpty)
  }

  func testDeadLetterReplayRemainsQuarantinedWhenDurableQueueIsFull() {
    let letter = deadLetter("failed")

    let replay = GlobalDeadLetterRecoveryPolicy.replay(
      state: GlobalEventQueueState(
        ready: [event("ready")],
        overflow: [event("overflow")]
      ),
      deadLetters: [letter],
      eventId: "failed",
      readyCapacity: 1,
      overflowCapacity: 1
    )

    XCTAssertFalse(replay.replayed)
    XCTAssertEqual(replay.deadLetters, [letter])
    XCTAssertEqual(replay.queueState.ready.map(\.id), ["ready"])
    XCTAssertEqual(replay.queueState.overflow.map(\.id), ["overflow"])
  }

  func testReplayClearsDuplicateDeadLetterWithoutEnqueueingTwice() {
    let letter = deadLetter("failed")

    let replay = GlobalDeadLetterRecoveryPolicy.replay(
      state: GlobalEventQueueState(ready: [event("failed")]),
      deadLetters: [letter],
      eventId: "failed"
    )

    XCTAssertTrue(replay.replayed)
    XCTAssertNil(replay.enqueuedEvent)
    XCTAssertEqual(replay.queueState.ready.count, 1)
    XCTAssertTrue(replay.deadLetters.isEmpty)
  }

  func testUpgradeRecoverySelectsOnlyLettersFromOlderVersionsOnce() {
    let old = deadLetter("old").with(quarantinedVersionCode: 40)
    let alreadyAttempted = deadLetter("attempted").with(
      quarantinedVersionCode: 40,
      lastAutoRecoveryVersionCode: 42
    )
    let current = deadLetter("current").with(quarantinedVersionCode: 42)

    let selected = GlobalDeadLetterUpgradeRecoveryPolicy.select(
      [current, alreadyAttempted, old],
      currentVersionCode: 42
    )

    XCTAssertEqual(selected.map { $0.event.id }, ["old"])
  }

  func testLegacyDeadLettersBecomeRecoverableAfterAnUpgrade() {
    let legacy = deadLetter("legacy")

    XCTAssertTrue(GlobalDeadLetterUpgradeRecoveryPolicy.eligible(legacy, currentVersionCode: 1))
    let attempted = GlobalDeadLetterUpgradeRecoveryPolicy.markAttempted(legacy, currentVersionCode: 1)
    XCTAssertFalse(GlobalDeadLetterUpgradeRecoveryPolicy.eligible(attempted, currentVersionCode: 1))
    XCTAssertTrue(GlobalDeadLetterUpgradeRecoveryPolicy.eligible(attempted, currentVersionCode: 2))
  }

  func testUpgradeRecoveryUsesOldestFirstAndRemainsBounded() {
    let letters = (1...5).map { index in
      deadLetter("event-\(index)").with(
        quarantinedAtMillis: 6_000 - Int64(index * 1_000),
        quarantinedVersionCode: 1
      )
    }

    let selected = GlobalDeadLetterUpgradeRecoveryPolicy.select(
      letters,
      currentVersionCode: 2,
      limit: 2
    )

    XCTAssertEqual(selected.map { $0.event.id }, ["event-5", "event-4"])
  }

  private func deadLetter(_ id: String) -> GlobalDeadLetterEvent {
    GlobalDeadLetterEvent(
      event: event(id),
      failure: GlobalEventRetryPolicy.capacityFailure(eventId: id, nowMillis: 1_000),
      quarantinedAtMillis: 1_000
    )
  }

  private func event(_ id: String) -> GlobalConversationEvent {
    GlobalConversationEvent(
      id: id,
      type: .messageCreated,
      conversationId: "conversation",
      actor: .user,
      content: "content-\(id)"
    )
  }
}

private struct TestFailure: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? {
    message
  }
}

private extension GlobalDeadLetterEvent {
  func with(
    quarantinedAtMillis: Int64? = nil,
    quarantinedVersionCode: Int? = nil,
    lastAutoRecoveryVersionCode: Int? = nil
  ) -> GlobalDeadLetterEvent {
    var copy = self
    if let quarantinedAtMillis {
      copy.quarantinedAtMillis = quarantinedAtMillis
    }
    if let quarantinedVersionCode {
      copy.quarantinedVersionCode = quarantinedVersionCode
    }
    if let lastAutoRecoveryVersionCode {
      copy.lastAutoRecoveryVersionCode = lastAutoRecoveryVersionCode
    }
    return copy
  }
}
