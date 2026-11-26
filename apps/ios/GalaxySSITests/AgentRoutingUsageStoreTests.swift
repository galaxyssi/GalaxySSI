import XCTest
@testable import GalaxySSI

final class AgentRoutingUsageStoreTests: XCTestCase {
  private func withStore(_ body: (AgentRoutingUsageStore, UserDefaults, InMemorySecretStore) throws -> Void) throws {
    let name = "RoutingUsage.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let secrets = InMemorySecretStore()
    try body(AgentRoutingUsageStore(owner: "owner-a", defaults: defaults, secrets: secrets), defaults, secrets)
  }

  func testEncryptedReopenDeduplicatesAndIsolatesProfileAndSource() throws {
    try withStore { store, defaults, secrets in
      let usage = ModelUsage(inputTokens: 100, outputTokens: 20)
      XCTAssertTrue(store.record(resourceId: "cloud-model:private-fixture", conversationId: "source", observationId: "round", usage: usage, nowMillis: 1000))
      XCTAssertTrue(store.record(resourceId: "cloud-model:private-fixture", conversationId: "source", observationId: "round", usage: usage, nowMillis: 2000))
      XCTAssertFalse(store.record(resourceId: "cloud-model:private-fixture", conversationId: "source", observationId: "round",
        usage: ModelUsage(inputTokens: 999), nowMillis: 2000))
      let reopened = AgentRoutingUsageStore(owner: "owner-a", defaults: defaults, secrets: secrets)
      let summary = try XCTUnwrap(reopened.snapshot(eligibleConversationIds: ["source"], nowMillis: 2000).resources["cloud-model:private-fixture"])
      XCTAssertEqual(summary.samples, 1)
      XCTAssertEqual(summary.averageTotalTokens, 120)
      XCTAssertNil(summary.averageReportedCostMicros)
      XCTAssertNil(defaults.data(forKey: store.storageKey))
      XCTAssertFalse(defaults.dictionaryRepresentation().description.contains("cloud-model:private-fixture"))
      XCTAssertTrue(reopened.snapshot(eligibleConversationIds: ["different-source"], nowMillis: 2000).resources.isEmpty)
      XCTAssertTrue(AgentRoutingUsageStore(owner: "owner-b", defaults: defaults, secrets: secrets)
        .snapshot(eligibleConversationIds: ["source"], nowMillis: 2000).resources.isEmpty)
    }
  }

  func testPrivatePausedArchivedAndMergedSourcesAreIneligible() {
    var session = AgentConversation(id: "source", title: "Source", createdAt: 1, updatedAt: 1)
    XCTAssertTrue(AgentRoutingUsageEligibility.allows(session))
    session.privateMode = true
    XCTAssertFalse(AgentRoutingUsageEligibility.allows(session))
    session.privateMode = false
    session.trackingPaused = true
    XCTAssertFalse(AgentRoutingUsageEligibility.allows(session))
    session.trackingPaused = false
    session.status = .archived
    XCTAssertFalse(AgentRoutingUsageEligibility.allows(session))
    session.status = .active
    session.mergedIntoConversationId = "parent"
    XCTAssertFalse(AgentRoutingUsageEligibility.allows(session))
    XCTAssertFalse(AgentRoutingUsageEligibility.allows(nil))
  }

  func testUnknownCostIsNotAnExplicitFreeReport() throws {
    try withStore { store, _, _ in
      XCTAssertTrue(store.record(resourceId: "resource", conversationId: "source", observationId: "unknown",
        usage: ModelUsage(inputTokens: 100), nowMillis: 1000))
      XCTAssertNil(store.snapshot(eligibleConversationIds: ["source"], nowMillis: 1000).resources["resource"]?.averageReportedCostMicros)
      XCTAssertTrue(store.record(resourceId: "resource", conversationId: "source", observationId: "explicit-zero",
        usage: ModelUsage(inputTokens: 300), reportedCostMicros: 0, nowMillis: 1001))
      let summary = try XCTUnwrap(store.snapshot(eligibleConversationIds: ["source"], nowMillis: 1001).resources["resource"])
      XCTAssertEqual(summary.averageTotalTokens, 200)
      XCTAssertEqual(summary.reportedCostSamples, 1)
      XCTAssertEqual(summary.averageReportedCostMicros, 0)
    }
  }

  func testLargeAveragesRejectMalformedAndOverflowingSamples() throws {
    try withStore { store, _, _ in
      for id in ["first", "second"] {
        XCTAssertTrue(store.record(resourceId: "resource", conversationId: "source", observationId: id,
          usage: ModelUsage(inputTokens: Int64.max), reportedCostMicros: Int64.max, nowMillis: 1000))
      }
      let summary = try XCTUnwrap(store.snapshot(eligibleConversationIds: ["source"], nowMillis: 1000).resources["resource"])
      XCTAssertEqual(summary.averageTotalTokens, Int64.max)
      XCTAssertEqual(summary.averageReportedCostMicros, Int64.max)
      for usage in [ModelUsage(inputTokens: -1), ModelUsage(inputTokens: Int64.max, outputTokens: 1),
        ModelUsage(inputTokens: 1, cachedInputTokens: 2), ModelUsage()] {
        XCTAssertFalse(store.record(resourceId: "resource", conversationId: "source", observationId: "invalid", usage: usage, nowMillis: 1000))
      }
      XCTAssertEqual(store.snapshot(eligibleConversationIds: ["source"], nowMillis: 1000).resources["resource"]?.samples, 2)
    }
  }

  func testRetentionAndFutureTimesDoNotBecomeFreshObservations() throws {
    try withStore { store, _, _ in
      XCTAssertTrue(store.record(resourceId: "old", conversationId: "source", observationId: "old",
        usage: ModelUsage(inputTokens: 1), nowMillis: 1))
      XCTAssertTrue(store.record(resourceId: "future", conversationId: "source", observationId: "future",
        usage: ModelUsage(inputTokens: 1), nowMillis: 1000))
      XCTAssertNil(store.snapshot(eligibleConversationIds: ["source"], nowMillis: 999).resources["future"])
      XCTAssertNil(store.snapshot(eligibleConversationIds: ["source"], nowMillis: AgentRoutingUsageStore.retentionMillis + 2).resources["old"])
      XCTAssertTrue(store.snapshot(eligibleConversationIds: [], nowMillis: 1000).resources.isEmpty)
      XCTAssertTrue(store.snapshot(eligibleConversationIds: ["source"], nowMillis: 0).resources.isEmpty)
    }
  }

  func testLostKeyAndCorruptCiphertextCannotPublishOrOverwriteMetrics() throws {
    try withStore { store, defaults, _ in
      XCTAssertTrue(store.record(resourceId: "resource", conversationId: "source", observationId: "round",
        usage: ModelUsage(inputTokens: 1), nowMillis: 1000))
      let before = defaults.data(forKey: store.storageKey + ".encrypted.v1")
      let lost = AgentRoutingUsageStore(owner: "owner-a", defaults: defaults, secrets: InMemorySecretStore())
      XCTAssertFalse(lost.record(resourceId: "resource", conversationId: "source", observationId: "next",
        usage: ModelUsage(inputTokens: 1), nowMillis: 1001))
      XCTAssertTrue(lost.snapshot(eligibleConversationIds: ["source"], nowMillis: 1001).resources.isEmpty)
      XCTAssertEqual(defaults.data(forKey: store.storageKey + ".encrypted.v1"), before)
      defaults.set(Data([0, 1, 2]), forKey: store.storageKey + ".encrypted.v1")
      XCTAssertFalse(store.record(resourceId: "resource", conversationId: "source", observationId: "next",
        usage: ModelUsage(inputTokens: 1), nowMillis: 1001))
      XCTAssertEqual(defaults.data(forKey: store.storageKey + ".encrypted.v1"), Data([0, 1, 2]))
    }
  }

  func testRetentionBoundsCompletedRoundRecords() throws {
    try withStore { store, defaults, secrets in
      let entries: [[String: Any]] = (0..<AgentRoutingUsageStore.maximumEntries).map { index in
        let suffix = String(index, radix: 16)
        return ["key": String(repeating: "0", count: 64 - suffix.count) + suffix,
          "resourceId": "resource", "conversationId": "source", "inputTokens": 1,
          "outputTokens": 0, "observedAtMillis": index + 1]
      }
      let data = try JSONSerialization.data(withJSONObject: ["version": 1, "entries": entries])
      XCTAssertTrue(GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: store.storageKey, secrets: secrets))
      XCTAssertTrue(store.record(resourceId: "resource", conversationId: "source", observationId: "new",
        usage: ModelUsage(inputTokens: 2), nowMillis: 2000))
      XCTAssertEqual(store.snapshot(eligibleConversationIds: ["source"], nowMillis: 2000).resources["resource"]?.samples,
        AgentRoutingUsageStore.maximumEntries)
    }
  }

  func testActualRankingUsesBoundedUsageWithoutExcludingResources() throws {
    let first = AgentCallableTarget(id: "cloud-model:a", title: "A", kind: .model, status: .available, capabilities: [.chat])
    let second = AgentCallableTarget(id: "cloud-model:b", title: "B", kind: .model, status: .available, capabilities: [.chat])
    let resource = AgentResourceCatalog.build(targets: [first], tools: [])[0]
    let requirements = AgentTaskRequirements(mode: .economy)
    let baseline = AgentProviderResourceRanking.candidate(resource: resource, requirements: requirements, environment: .init())
    let summary = AgentRoutingUsageSummary(samples: 1, averageTotalTokens: 80_000, reportedCostSamples: 1, averageReportedCostMicros: 700_000)
    let ranked = AgentProviderResourceRanking.candidate(resource: resource, requirements: requirements, environment: .init(), observedUsage: summary)
    XCTAssertEqual(baseline.score - ranked.score, 360)
    var unknown = summary
    unknown.reportedCostSamples = 0
    unknown.averageReportedCostMicros = nil
    let withoutPrice = AgentProviderResourceRanking.candidate(resource: resource, requirements: requirements, environment: .init(), observedUsage: unknown)
    XCTAssertEqual(baseline.score - withoutPrice.score, 120)
    XCTAssertFalse(withoutPrice.reasons.contains { $0.hasPrefix("observed_average_reported_cost_micros:") })
    let decision = try XCTUnwrap(AgentQualityRoutingService.baselineDecision(goal: "", targets: [first, second], primaryTargetId: first.id,
      requirements: requirements, environment: .init(), routingUsage: .init(resources: [first.id: summary])))
    XCTAssertEqual(AgentConnectorRouteSelector.select(targets: [first, second], decision: decision)?.target.id, second.id)
    XCTAssertTrue(decision.orderedTargetIds.contains(first.id))
  }

  func testAnthropicStreamingUsageMergesFieldsWithoutAddingCumulativeOutputs() {
    let adapter = ModelStreamProviderAdapters.create(provider: .anthropic)
    let start = adapter.parse(data: #"{"type":"message_start","message":{"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30,"output_tokens":1}}}"#, eventName: nil)
    XCTAssertEqual(start.usage, ModelUsage(inputTokens: 60, outputTokens: 1, cachedInputTokens: 30))
    let delta = adapter.parse(data: #"{"type":"message_delta","usage":{"output_tokens":4}}"#, eventName: nil)
    XCTAssertEqual(delta.usage, ModelUsage(inputTokens: 60, outputTokens: 4, cachedInputTokens: 30))
    let correction = adapter.parse(data: #"{"type":"message_delta","usage":{"input_tokens":12,"output_tokens":3}}"#, eventName: nil)
    XCTAssertEqual(correction.usage, ModelUsage(inputTokens: 62, outputTokens: 3, cachedInputTokens: 30))
    let reset = adapter.parse(data: #"{"type":"message_start","message":{"usage":{"input_tokens":5}}}"#, eventName: nil)
    XCTAssertEqual(reset.usage, ModelUsage(inputTokens: 5))
  }

  func testAnthropicCompleteAndMalformedUsageUseCheckedIntegerTotals() {
    let adapter = ModelStreamProviderAdapters.create(provider: .anthropic)
    let complete = adapter.parseCompleteJSON(data: #"{"content":[],"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30,"output_tokens":4}}"#)
    XCTAssertEqual(complete.usage, ModelUsage(inputTokens: 60, outputTokens: 4, cachedInputTokens: 30))
    for usage in [#"{"input_tokens":true}"#, #"{"input_tokens":-1}"#,
      #"{"input_tokens":9223372036854775808}"#, #"{"input_tokens":9223372036854775807,"cache_read_input_tokens":1}"#] {
      let frame = adapter.parseCompleteJSON(data: "{\"content\":[],\"usage\":\(usage)}")
      XCTAssertFalse(AgentRoutingUsageStore.validUsage(frame.usage ?? ModelUsage(inputTokens: -1)))
      XCTAssertNil(frame.error)
    }
  }
}
