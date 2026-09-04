import XCTest

@testable import GalaxySSI

final class AgentMemoryPssTelemetryTests: XCTestCase {
  func testProcessOnlyCaptureDoesNotInventTaskAttribution() {
    let monitor = makeMonitor(readings: [reading(160)])

    let snapshot = monitor.capture(activeWorkspaces: [])

    XCTAssertEqual(mib(160), snapshot.processCurrentBytes)
    XCTAssertEqual(mib(160), snapshot.processPeakBytes)
    XCTAssertTrue(snapshot.byAgent.isEmpty)
    XCTAssertTrue(snapshot.bySession.isEmpty)
    XCTAssertTrue(snapshot.byProvider.isEmpty)
  }

  func testSharedPssIsSplitAcrossActiveTasksAndGroupedByEveryIdentity() throws {
    let monitor = makeMonitor(readings: [reading(240)])

    let snapshot = monitor.capture(activeWorkspaces: [
      workspace("task-a", "session-a", "conversation-a", "model:deepseek"),
      workspace("task-b", "session-b", "conversation-b", "codex")
    ])

    XCTAssertEqual(mib(240), snapshot.processCurrentBytes)
    XCTAssertEqual(mib(120), try stat("model:deepseek", in: snapshot.byAgent).currentBytes)
    XCTAssertEqual(mib(120), try stat("session-b", in: snapshot.bySession).currentBytes)
    XCTAssertEqual(mib(120), try stat("deepseek", in: snapshot.byProvider).currentBytes)
    XCTAssertEqual(mib(120), try stat("codex", in: snapshot.byProvider).currentBytes)
    XCTAssertTrue(snapshot.byAgent.allSatisfy(\.estimated))
  }

  func testCurrentAndPeakRemainDistinctAcrossSamples() throws {
    var now: Int64 = 1_000
    let monitor = AgentMemoryPssMonitor(
      sampler: QueuePssSampler([reading(300), reading(180)]),
      store: InMemoryAgentMemoryPssSampleStore(),
      clock: { defer { now += 1_000 }; return now },
      idGenerator: CountingIds().next
    )
    let active = workspace("task", "session", "conversation", "cloud:openai")

    _ = monitor.capture(activeWorkspaces: [active])
    let snapshot = monitor.capture(activeWorkspaces: [active])
    let provider = try XCTUnwrap(snapshot.byProvider.first)

    XCTAssertEqual(mib(180), snapshot.processCurrentBytes)
    XCTAssertEqual(mib(300), snapshot.processPeakBytes)
    XCTAssertEqual(mib(180), provider.currentBytes)
    XCTAssertEqual(mib(300), provider.peakBytes)
    XCTAssertEqual(mib(240), provider.averageBytes)
  }

  func testCompletedTaskDoesNotRemainAsCurrentMemory() throws {
    var now: Int64 = 1_000
    let monitor = AgentMemoryPssMonitor(
      sampler: QueuePssSampler([reading(200), reading(150)]),
      store: InMemoryAgentMemoryPssSampleStore(),
      clock: { defer { now += 1_000 }; return now },
      idGenerator: CountingIds().next
    )

    _ = monitor.capture(activeWorkspaces: [workspace("task", "session", "conversation", "codex")])
    let snapshot = monitor.capture(activeWorkspaces: [])
    let agent = try XCTUnwrap(snapshot.byAgent.first)

    XCTAssertEqual(0, agent.currentBytes)
    XCTAssertEqual(mib(200), agent.peakBytes)
  }

  func testRetentionRemovesExpiredAndOverflowSamples() {
    let store = InMemoryAgentMemoryPssSampleStore()
    for index in 0..<5 {
      store.append(sample(id: "\(index)", at: Int64(index) * 1_000))
    }

    store.prune(beforeMillis: 1_000, maxSamples: 2)
    let retained = store.recent(limit: 10, sinceMillis: 0)

    XCTAssertEqual(["3", "4"], retained.map(\.id))
  }

  func testProviderIdentityNormalizesModelsWithoutHidingAgents() {
    XCTAssertEqual("deepseek", AgentMemoryPssMonitor.providerIdForAgent("model:DeepSeek"))
    XCTAssertEqual("openai", AgentMemoryPssMonitor.providerIdForAgent("provider:OpenAI:gpt-5"))
    XCTAssertEqual("on-device", AgentMemoryPssMonitor.providerIdForAgent("galaxyssi-mobile"))
    XCTAssertEqual("claude", AgentMemoryPssMonitor.providerIdForAgent("Claude"))
    XCTAssertTrue(AgentMemoryPssMonitor.providerIdForAgent("").isEmpty)
  }

  func testUserDefaultsStorePersistsAndroidWireNames() throws {
    let suiteName = "AgentMemoryPssTelemetryTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      UserDefaultsAgentMemoryPssSampleStore.destroyPersistentStore(defaults: defaults, key: "pss-test")
      defaults.removePersistentDomain(forName: suiteName)
    }
    let store = UserDefaultsAgentMemoryPssSampleStore(defaults: defaults, key: "pss-test")
    store.append(sample(id: "persisted", at: 4_000, agentId: "model:deepseek"))

    let restored = UserDefaultsAgentMemoryPssSampleStore(defaults: defaults, key: "pss-test")
    let encoded = try JSONEncoder().encode(try XCTUnwrap(restored.recent(limit: 1, sinceMillis: 0).first))
    let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

    XCTAssertEqual(object?["sampled_at_millis"] as? Int, 4_000)
    XCTAssertEqual(object?["process_total_bytes"] as? Int, Int(mib(100)))
    XCTAssertEqual(object?["measurement_kind"] as? String, AgentMemoryMeasurementKind.androidPss.rawValue)
    XCTAssertEqual(object?["attribution_mode"] as? String, AgentMemoryAttributionMode.processTotal.rawValue)
    XCTAssertEqual(object?["agent_id"] as? String, "model:deepseek")
  }

  private func makeMonitor(readings: [AgentMemoryPssReading]) -> AgentMemoryPssMonitor {
    AgentMemoryPssMonitor(
      sampler: QueuePssSampler(readings),
      store: InMemoryAgentMemoryPssSampleStore(),
      clock: { 10_000 },
      idGenerator: CountingIds().next
    )
  }

  private func reading(_ totalMib: Int64) -> AgentMemoryPssReading {
    AgentMemoryPssReading(
      totalBytes: mib(totalMib),
      nativeBytes: mib(totalMib / 4),
      dalvikBytes: mib(totalMib / 2),
      otherBytes: mib(totalMib / 4)
    )
  }

  private func workspace(
    _ taskId: String,
    _ sessionId: String,
    _ conversationId: String,
    _ agentId: String
  ) -> AgentWorkspace {
    AgentWorkspace(
      workspaceId: "workspace-\(taskId)",
      sessionId: sessionId,
      conversationId: conversationId,
      taskId: taskId,
      agentId: agentId
    )
  }

  private func sample(
    id: String,
    at: Int64,
    agentId: String = ""
  ) -> AgentMemoryPssSample {
    AgentMemoryPssSample(
      id: id,
      sampledAtMillis: at,
      processTotalBytes: mib(100),
      attributedBytes: 0,
      nativeBytes: 0,
      dalvikBytes: 0,
      otherBytes: 0,
      measurementKind: AgentMemoryMeasurementKind.androidPss.rawValue,
      attributionMode: AgentMemoryAttributionMode.processTotal.rawValue,
      agentId: agentId
    )
  }

  private func stat(
    _ id: String,
    in stats: [AgentMemoryDimensionStats],
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws -> AgentMemoryDimensionStats {
    try XCTUnwrap(stats.first { $0.id == id }, file: file, line: line)
  }

  private func mib(_ value: Int64) -> Int64 {
    value * 1_048_576
  }
}

private final class QueuePssSampler: AgentMemoryPssSampler {
  private var readings: [AgentMemoryPssReading]

  init(_ readings: [AgentMemoryPssReading]) {
    self.readings = readings
  }

  func sample() -> AgentMemoryPssReading {
    readings.removeFirst()
  }
}

private final class CountingIds {
  private var nextValue = 0

  func next() -> String {
    defer { nextValue += 1 }
    return "sample-\(nextValue)"
  }
}
