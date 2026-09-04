import XCTest

@testable import GalaxySSI

final class AgentSessionMemoryBudgetTests: XCTestCase {
  func testRecordsRealIncrementInsteadOfDividingWholeProcessMemory() {
    var now: Int64 = 1_000
    let monitor = AgentSessionMemoryBudgetMonitor(
      sampler: QueueAgentMemorySampler(mib(120), mib(132)),
      store: InMemoryAgentSessionMemoryBudgetStore(),
      clock: { defer { now += 100 }; return now },
      idGenerator: { "sample-a" }
    )

    let baseline = monitor.begin()
    let snapshot = monitor.complete(conversationId: "conversation-a", baseline: baseline)

    XCTAssertEqual(mib(12), snapshot.latestIncrementalBytes)
    XCTAssertEqual(mib(12), snapshot.peakIncrementalBytes)
    XCTAssertEqual(1, snapshot.sampleCount)
    XCTAssertEqual(0, snapshot.exceededCount)
    XCTAssertEqual("conversation-a", snapshot.latestConversationId)
    XCTAssertTrue(snapshot.withinBudget)
  }

  func testFlagsOnlyTheSessionShellThatExceedsTwentyMibibytes() {
    let monitor = AgentSessionMemoryBudgetMonitor(
      sampler: QueueAgentMemorySampler(mib(100), mib(121)),
      store: InMemoryAgentSessionMemoryBudgetStore(),
      clock: { 2_000 },
      idGenerator: { "sample-b" }
    )

    let snapshot = monitor.complete(conversationId: "conversation-b", baseline: monitor.begin())

    XCTAssertEqual(mib(20), snapshot.targetBytes)
    XCTAssertEqual(1, snapshot.exceededCount)
    XCTAssertFalse(snapshot.withinBudget)
  }

  func testGarbageCollectionDoesNotProduceNegativeSessionCost() {
    let monitor = AgentSessionMemoryBudgetMonitor(
      sampler: QueueAgentMemorySampler(mib(150), mib(140)),
      store: InMemoryAgentSessionMemoryBudgetStore(),
      clock: { 3_000 },
      idGenerator: { "sample-c" }
    )

    let snapshot = monitor.complete(conversationId: "conversation-c", baseline: monitor.begin())

    XCTAssertEqual(0, snapshot.latestIncrementalBytes)
    XCTAssertTrue(snapshot.withinBudget)
  }

  func testAggregateKeepsAStableBudgetAcrossManyLightweightSessions() {
    let samples = (1...1_000).map { index in
      AgentSessionMemoryBudgetSample(
        id: "sample-\(index)",
        conversationId: "conversation-\(index)",
        sampledAtMillis: Int64(index),
        beforeBytes: mib(100),
        afterBytes: mib(100) + Int64(index % 10) * 1024,
        incrementalBytes: Int64(index % 10) * 1024,
        targetBytes: mib(20)
      )
    }

    let snapshot = AgentSessionMemoryBudgetMonitor.aggregate(samples)

    XCTAssertEqual(1_000, snapshot.sampleCount)
    XCTAssertEqual(0, snapshot.exceededCount)
    XCTAssertLessThan(snapshot.peakIncrementalBytes, snapshot.targetBytes)
  }

  func testInMemoryStoreRetentionRemovesExpiredAndOverflowSamples() {
    let store = InMemoryAgentSessionMemoryBudgetStore()
    for index in 0..<5 {
      store.append(sample(id: "\(index)", at: Int64(index) * 1_000))
    }

    store.prune(beforeMillis: 1_000, maxSamples: 2)
    let retained = store.recent(limit: 10, sinceMillis: 0)

    XCTAssertEqual(["3", "4"], retained.map(\.id))
  }

  func testUserDefaultsStorePersistsAndUsesAndroidWireNames() throws {
    let suiteName = "AgentSessionMemoryBudgetTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      UserDefaultsAgentSessionMemoryBudgetStore.destroyPersistentStore(defaults: defaults, key: "budget-test")
      defaults.removePersistentDomain(forName: suiteName)
    }
    let store = UserDefaultsAgentSessionMemoryBudgetStore(defaults: defaults, key: "budget-test")
    store.append(sample(id: "persisted", at: 4_000, conversationId: " conversation "))

    let restored = UserDefaultsAgentSessionMemoryBudgetStore(defaults: defaults, key: "budget-test")
    XCTAssertEqual(["persisted"], restored.recent(limit: 10, sinceMillis: 0).map(\.id))

    let encoded = try JSONEncoder().encode(restored.recent(limit: 1, sinceMillis: 0).single())
    let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    XCTAssertEqual(object?["conversation_id"] as? String, " conversation ")
    XCTAssertEqual(object?["sampled_at_millis"] as? Int, 4_000)
    XCTAssertEqual(object?["incremental_bytes"] as? Int, 512)
    XCTAssertEqual(object?["target_bytes"] as? Int, Int(mib(20)))
  }

  private func sample(
    id: String,
    at: Int64,
    conversationId: String = ""
  ) -> AgentSessionMemoryBudgetSample {
    AgentSessionMemoryBudgetSample(
      id: id,
      conversationId: conversationId,
      sampledAtMillis: at,
      beforeBytes: mib(100),
      afterBytes: mib(100) + 512,
      incrementalBytes: 512,
      targetBytes: mib(20)
    )
  }

  private func mib(_ value: Int64) -> Int64 {
    value * 1_048_576
  }

}

private final class QueueAgentMemorySampler: AgentMemoryPssSampler {
  private var readings: [Int64]

  init(_ readings: Int64...) {
    self.readings = readings
  }

  func sample() -> AgentMemoryPssReading {
    AgentMemoryPssReading(totalBytes: readings.removeFirst())
  }
}

private extension Array {
  func single(file: StaticString = #filePath, line: UInt = #line) throws -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    return try XCTUnwrap(first, file: file, line: line)
  }
}
