import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testLearnedRoutingRequiresQualifiedRecordsAndModelSelectedTopics() throws {
    let source = try learnedRoutingModel()
    XCTAssertTrue(source.isSearchEligible)
    XCTAssertEqual(source.publicValue()["search_available"], .bool(true))
    XCTAssertTrue(AgentIOSWebSearchEnginePolicy.accepts([source.sourceID], learnedSources: [source]))
    XCTAssertFalse(AgentIOSWebSearchEnginePolicy.accepts([source.sourceID]))
    XCTAssertTrue(AgentIOSWebSearchEnginePolicy.canResolve([source.sourceID]))
    var candidate = source
    candidate.status = "candidate"
    var disabled = source
    disabled.status = "disabled"
    var insufficient = source
    insufficient.observations = 1
    let image = try learnedRoutingModel(vertical: "image")
    XCTAssertTrue(image.isValid)
    XCTAssertEqual(image.publicValue()["search_available"], .bool(true))
    XCTAssertEqual(image.status, "verified")
    XCTAssertTrue(image.isSearchEligible)
    for unavailable in [candidate, disabled, insufficient] {
      XCTAssertFalse(unavailable.isSearchEligible)
      XCTAssertFalse(AgentIOSWebSearchEnginePolicy.accepts([unavailable.sourceID], learnedSources: [unavailable]))
    }
    XCTAssertEqual(source.searchSpec(index: 0)?.indexEngine, "duckduckgo")
    XCTAssertEqual(source.searchSpec(index: 1)?.indexEngine, "bing")
    XCTAssertEqual(source.searchSpec(index: 0)?.allowedHosts, [source.host])
    let selected = AgentIOSWebIntelligenceQueryRouting.select(query: "Galaxy research", requestedVerticals: [],
      requestedEngineIds: [], requestedCategories: ["RESEARCH"], learnedSources: [source, disabled])
    XCTAssertEqual(selected.selected.first?.id, source.sourceID)
    XCTAssertFalse(AgentIOSWebIntelligenceQueryRouting.select(query: "research learned.example", requestedVerticals: [],
      requestedEngineIds: [], learnedSources: [source]).selected.contains { $0.id == source.sourceID })
  }

  func testActualLearnedSearchFiltersDestinationsAndLearnsOnlyOnceThenClearRevokesRouting() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("learned-route-\(UUID()).json")
    let operations = OperationQueue()
    defer { operations.waitUntilAllOperationsAreFinished(); try? FileManager.default.removeItem(at: url) }
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: InMemorySecretStore(), nowMillis: { 1000 },
      learningQueue: AgentIOSWebMaintenanceQueue(queue: operations))
    let source = try seedLearnedRouting(cache, operations: operations)
    let transport = LearnedRoutingSearchFixture()
    let media = AgentIOSURLSessionWebMediaToolProvider(transport: transport, sourceHealthStore: cache, nowMillis: { 1000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(
      provider: AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: media, cacheStore: cache, nowMillis: { 1000 })))
    let input: AgentMcpJSONObject = ["query": .string("Galaxy research"), "limit": .int(1), "engines": .array([.string(source.sourceID)])]
    let denied = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search, input: input, context: learnedRoutingContext(cache: false),
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1000 }))
    XCTAssertEqual(denied.error?.code, "unsupported_search_engine")
    XCTAssertTrue(transport.requests.isEmpty)
    let result = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search, input: input, context: learnedRoutingContext(),
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1000 }))
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.output["results"]?.arrayValue?.first?.objectValue?["url"], .string("https://learned.example/article"))
    XCTAssertEqual(result.metadata["selected_learned_sources"], .array([.string(source.sourceID)]))
    XCTAssertEqual(result.metadata["official_sources"], .array([]))
    let request = try XCTUnwrap(transport.requests.first)
    let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
    XCTAssertEqual(query, "site:learned.example Galaxy research")
    XCTAssertTrue(["www.bing.com", "html.duckduckgo.com"].contains(request.url.host ?? ""))
    operations.waitUntilAllOperationsAreFinished()
    XCTAssertEqual(cache.learnedSources()?.first?.observations, source.observations + 1)
    XCTAssertEqual(cache.sourceHealth()?[source.sourceID]?.attempts, 1)
    let count = transport.requests.count
    XCTAssertEqual(cache.clear(expiredOnly: false)["committed"], .bool(true))
    let stale = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search, input: input, context: learnedRoutingContext(),
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1000 }))
    XCTAssertEqual(stale.error?.code, "unsupported_search_engine")
    XCTAssertEqual(transport.requests.count, count)
  }

  func testDirectRawSearchQueuesScopedLearningWithoutIntelligenceWrapper() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("learned-raw-\(UUID()).json")
    let operations = OperationQueue()
    defer { operations.waitUntilAllOperationsAreFinished(); try? FileManager.default.removeItem(at: url) }
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: InMemorySecretStore(),
      learningQueue: AgentIOSWebMaintenanceQueue(queue: operations))
    let media = AgentIOSURLSessionWebMediaToolProvider(transport: LearnedRoutingSearchFixture(), sourceHealthStore: cache, nowMillis: { 1000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: media))
    let result = registry.invoke(AgentIOSWebMediaNativeToolCatalog.webSearch,
      input: ["query": .string("Galaxy research"), "max_results": .int(1), "engines": .array([.string("bing")])],
      context: learnedRoutingContext(), hooks: AgentNativeToolInvocationHooks(nowMillis: { 1000 }))
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.output["learning"]?.objectValue?["status"], .string("queued"))
    operations.waitUntilAllOperationsAreFinished()
    XCTAssertEqual(cache.learnedSources()?.count, 1)
    XCTAssertEqual(cache.learnedSources()?.first?.observations, 1)
  }

  func testLaterUnavailableLearnedEngineRejectsWholeResearchPlanBeforeSearching() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("learned-plan-\(UUID()).json")
    let operations = OperationQueue()
    defer { operations.waitUntilAllOperationsAreFinished(); try? FileManager.default.removeItem(at: url) }
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: InMemorySecretStore(),
      learningQueue: AgentIOSWebMaintenanceQueue(queue: operations))
    let source = try seedLearnedRouting(cache, operations: operations)
    let media = BudgetWebMediaFixture()
    let registry = try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(
      provider: AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: media, cacheStore: cache)))
    let result = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.research,
      input: ["query": .string("Galaxy research"), "query_plan": .array([
        .object(["query": .string("first"), "engines": .array([.string(source.sourceID)])]),
        .object(["query": .string("later"), "engines": .array([.string("learned_0000000000000000")])])])],
      context: learnedRoutingContext(), hooks: AgentNativeToolInvocationHooks(nowMillis: { 1000 }))
    XCTAssertEqual(result.error?.code, "unsupported_search_engine")
    XCTAssertTrue(media.inputs.isEmpty)
  }

  func testTopicScopedLearnedSearchDoesNotReuseUnscopedTextCache() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("learned-topic-\(UUID()).json")
    let operations = OperationQueue()
    defer { operations.waitUntilAllOperationsAreFinished(); try? FileManager.default.removeItem(at: url) }
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: InMemorySecretStore(), nowMillis: { 1000 },
      learningQueue: AgentIOSWebMaintenanceQueue(queue: operations))
    let source = try seedLearnedRouting(cache, operations: operations)
    XCTAssertTrue(cache.putDocument(url: "https://stale.example/article", title: "Galaxy research", content: "Galaxy research stale text",
      contentType: "text/plain", contentSHA256: String(repeating: "a", count: 64), retrievedAtMillis: 1000,
      expiresAtMillis: Int64.max, metadata: ["text_decoding_lossless": "true"]))
    let transport = LearnedRoutingSearchFixture()
    let media = AgentIOSURLSessionWebMediaToolProvider(transport: transport, sourceHealthStore: cache, nowMillis: { 1000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(
      provider: AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: media, cacheStore: cache, nowMillis: { 1000 })))
    let result = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: ["query": .string("Galaxy research"), "limit": .int(1), "engine_fanout": .int(1),
        "use_cache": .bool(true), "categories": .array([.string("research")])], context: learnedRoutingContext(),
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1000 }))
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertEqual(result.output["results"]?.arrayValue?.first?.objectValue?["url"], .string("https://learned.example/article"))
    XCTAssertEqual(result.metadata["selected_learned_sources"], .array([.string(source.sourceID)]))
    XCTAssertEqual(result.output["cache"]?.objectValue?["hit"], .bool(false))
  }

  func testExplicitNativeSearchOrderIsRetainedWithoutDuplicateDispatch() throws {
    let transport = LearnedRoutingSearchFixture()
    let media = AgentIOSURLSessionWebMediaToolProvider(transport: transport, sourceHealthStore: nil, nowMillis: { 1000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: media))
    let result = registry.invoke(AgentIOSWebMediaNativeToolCatalog.webSearch,
      input: ["query": .string("Galaxy research"), "engines": .array([.string("duckduckgo"), .string("bing"), .string("duckduckgo")])],
      context: learnedRoutingContext(cache: false), hooks: AgentNativeToolInvocationHooks(nowMillis: { 1000 }))
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(transport.requests.count, 2)
    XCTAssertEqual(result.metadata["providers"], .array([.string("duckduckgo"), .string("bing")]))
  }

  private func learnedRoutingModel(vertical: String = "general") throws -> AgentIOSLearnedWebSource {
    var model: AgentIOSLearnedWebSource?
    for query in ["first", "second", "third", "first"] {
      let observation = try XCTUnwrap(AgentIOSWebSourceLearningPolicy.observations(query: query, categories: ["research"],
        results: [["url": .string("https://learned.example/article"), "vertical": .string(vertical)]]).first)
      model = AgentIOSWebSourceLearningPolicy.evolve(model, observation: observation, now: 1000)
    }
    return try XCTUnwrap(model)
  }

  private func seedLearnedRouting(_ cache: AgentIOSWebIntelligenceCacheStore, operations: OperationQueue) throws -> AgentIOSLearnedWebSource {
    for query in ["first", "second", "third", "first"] {
      _ = cache.learnSourceCandidates(query: query, categories: ["research"], results: [["url": .string("https://learned.example/article")]])
    }
    operations.waitUntilAllOperationsAreFinished()
    return try XCTUnwrap(cache.learnedSources()?.first)
  }

  private func learnedRoutingContext(cache: Bool = true) -> AgentNativeToolInvocationContext {
    .init(grantedPermissions: Set([AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission,
      AgentIOSWebIntelligenceNativeToolCatalog.networkPermission] + (cache ? [AgentIOSWebIntelligenceNativeToolCatalog.cachePermission] : [])),
      grantedConsents: Set([AgentIOSWebMediaNativeToolCatalog.publicWebConsent, AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent] +
        (cache ? [AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent] : [])))
  }

  func testSourceHealthBackoffEmptyCancellationAndOverflowRules() {
    let failed = AgentIOSWebSourceReceipt(sourceID: "bing", status: "failed", durationMillis: 100, resultCount: 0)
    var health = AgentIOSWebSourceHealth(sourceID: "bing")
    for _ in 0..<3 { health = health.evolved(failed, now: 1000) }
    XCTAssertEqual(health.attempts, 3)
    XCTAssertEqual(health.circuitOpenUntilMillis, 61_000)
    XCTAssertEqual(health.circuitState(now: 2000), "open")
    XCTAssertEqual(health.circuitState(now: 61_000), "half_open")
    health = health.evolved(failed, now: 1000)
    XCTAssertEqual(health.circuitOpenUntilMillis, 121_000)
    let cancelled = health.evolved(.init(sourceID: "bing", status: "cancelled", durationMillis: 4000, resultCount: 0), now: 2000)
    XCTAssertEqual(cancelled.attempts, health.attempts)
    XCTAssertEqual(cancelled.failures, health.failures)
    XCTAssertEqual(cancelled.ewmaLatencyMillis, health.ewmaLatencyMillis)
    XCTAssertEqual(cancelled.circuitOpenUntilMillis, health.circuitOpenUntilMillis)
    let empty = cancelled.evolved(.init(sourceID: "bing", status: "empty", durationMillis: 200, resultCount: 0), now: 3000)
    XCTAssertEqual(empty.emptyResponses, 1)
    XCTAssertEqual(empty.successes, 0)
    XCTAssertEqual(empty.consecutiveFailures, 0)
    XCTAssertEqual(empty.circuitState(now: 3000), "closed")
    for _ in 0..<20 { health = health.evolved(failed, now: 1000) }
    XCTAssertEqual(health.circuitOpenUntilMillis, 1_801_000)
    health.attempts = Int64.max
    health.consecutiveFailures = Int64.max
    health = health.evolved(failed, now: Int64.max - 1)
    XCTAssertEqual(health.attempts, Int64.max)
    XCTAssertEqual(health.circuitOpenUntilMillis, Int64.max)
    XCTAssertTrue(health.routingScore.isFinite)
    XCTAssertTrue(health.isValid)
    XCTAssertEqual(AgentIOSWebSourceHealth.elapsed(from: Int64.min, to: Int64.max), 0)
  }

  func testSourceHealthRoutingSkipsOpenCircuitsButRetainsExplicitAndSpecialistChoices() {
    var failing = AgentIOSWebSourceHealth(sourceID: "bing")
    for _ in 0..<3 { failing = failing.evolved(.init(sourceID: "bing", status: "failed", durationMillis: 100, resultCount: 0), now: 1000) }
    let providers = ["bing", "baidu", "apple_developer"]
    let selected = AgentIOSWebSourceHealthRouting.select(providers: providers, preferred: ["apple_developer"],
      health: ["bing": failing], explicit: false, fanout: 3, now: 2000)
    XCTAssertEqual(selected.selected, ["apple_developer", "baidu"])
    XCTAssertEqual(selected.skipped.map(\.sourceID), ["bing"])
    XCTAssertEqual(AgentIOSWebSourceHealthRouting.select(providers: providers, preferred: [],
      health: ["bing": failing], explicit: true, fanout: 1, now: 2000).selected, ["bing"])
    XCTAssertTrue(AgentIOSWebSourceHealthRouting.select(providers: providers, preferred: [],
      health: ["bing": failing], explicit: false, fanout: 3, now: 61_000).selected.contains("bing"))
    XCTAssertEqual(AgentIOSWebSourceHealthRouting.select(providers: providers, preferred: [],
      health: [:], explicit: false, fanout: 2, now: 2000).selected, ["bing", "baidu"])
  }

  func testSourceHealthBatchAndResetCommitTruthfullyWithoutReplacingDocuments() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("health-batch-\(UUID()).json")
    defer { removeWebCacheFixture(url) }
    let secrets = InMemorySecretStore()
    var writes = 0
    var healthWrites = 0
    var reject = false
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: secrets, nowMillis: { 1000 }, healthBeforeCommit: {
      if reject { throw CocoaError(.fileWriteOutOfSpace) }
      healthWrites += 1
    }, beforeCommit: {
      if reject { throw CocoaError(.fileWriteOutOfSpace) }
      writes += 1
    })
    XCTAssertTrue(cache.putDocuments([cacheDocumentFixture("evidence")]))
    let receipts = (0..<3).map { _ in AgentIOSWebSourceReceipt(sourceID: "bing", status: "failed", durationMillis: 100, resultCount: 0) } +
      [.init(sourceID: "baidu", status: "empty", durationMillis: 200, resultCount: 0)]
    XCTAssertTrue(cache.recordSourceReceipts(receipts))
    XCTAssertEqual(writes, 2) // Cache migration and the document batch.
    XCTAssertEqual(healthWrites, 2) // Migration and one complete receipt batch.
    XCTAssertEqual(cache.sourceHealth(ids: ["bing"])?.count, 1)
    XCTAssertEqual(cache.sourceHealth(ids: ["bing"])?["bing"]?.attempts, 3)
    XCTAssertEqual(cache.stats()["source_circuits_open"], .int(1))
    let original = try Data(contentsOf: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: url))
    reject = true
    XCTAssertFalse(cache.recordSourceReceipts([.init(sourceID: "bing", status: "completed", durationMillis: 100, resultCount: 2)]))
    XCTAssertEqual(cache.resetSourceHealth()["committed"], .bool(false))
    XCTAssertEqual(try Data(contentsOf: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: url)), original)
    XCTAssertNotNil(cache.document(url: "https://cache.test/evidence", allowStale: true))
    reject = false
    XCTAssertEqual(cache.resetSourceHealth()["source_health_removed"], .int(2))
    XCTAssertNotNil(cache.document(url: "https://cache.test/evidence", allowStale: true))
    XCTAssertTrue(try XCTUnwrap(AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: secrets).sourceHealth()).isEmpty)
    XCTAssertTrue(cache.recordSourceReceipts(receipts))
    XCTAssertEqual(cache.clear(expiredOnly: false)["committed"], .bool(true))
    XCTAssertEqual(cache.sourceHealth()?.count, 2)
  }

  func testActualNativeSearchUsesScopedHealthAndCacheHealthTools() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("health-tools-\(UUID()).json")
    defer { removeWebCacheFixture(url) }
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: InMemorySecretStore(), nowMillis: { 1000 })
    XCTAssertTrue(cache.recordSourceReceipts((0..<3).map { _ in
      .init(sourceID: "bing", status: "failed", durationMillis: 100, resultCount: 0)
    }))
    let transport = SourceHealthSearchFixture()
    let media = AgentIOSURLSessionWebMediaToolProvider(transport: transport, nowMillis: { 1000 })
    let provider = AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: media, cacheStore: cache, nowMillis: { 1000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider))
    var context = AgentNativeToolInvocationContext(invocationId: "health-broad",
      grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission, AgentIOSWebIntelligenceNativeToolCatalog.cachePermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent, AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent])
    let result = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: ["query": .string("Galaxy research"), "limit": .int(2)], context: context,
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1000 }))
    XCTAssertTrue(result.isSuccess)
    XCTAssertFalse(transport.hosts.contains(where: { $0.contains("bing.com") }))
    XCTAssertEqual(result.metadata["circuits_skipped"]?.arrayValue?.first?.objectValue?["source_id"], .string("bing"))
    XCTAssertEqual(result.metadata["source_health_write_committed"], .bool(true))
    XCTAssertEqual(cache.sourceHealth()?["duckduckgo"]?.attempts, 1)
    context.invocationId = "health-explicit"
    let explicit = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: ["query": .string("Galaxy research"), "engines": .array([.string("bing")])], context: context,
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1000 }))
    XCTAssertTrue(explicit.isSuccess)
    XCTAssertTrue(transport.hosts.contains(where: { $0.contains("bing.com") }))
    context.invocationId = "health-status"
    let status = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.cache,
      input: ["action": .string("source_health"), "engines": .array([.string("bing")])], context: context,
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1000 }))
    XCTAssertTrue(status.isSuccess)
    XCTAssertEqual(status.output["metadata"]?.objectValue?["source_health"]?.arrayValue?.first?.objectValue?["circuit_state"], .string("closed"))
    context.invocationId = "health-reset"
    let reset = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.cache,
      input: ["action": .string("reset_source_health")], context: context,
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1000 }))
    XCTAssertTrue(reset.isSuccess)
    XCTAssertEqual(reset.output["cache"]?.objectValue?["source_health_count"], .int(0))
  }

  func testSearchWithoutCacheScopeOrWithFailedHealthWriteRetainsNetworkEvidence() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("health-scope-\(UUID()).json")
    defer { removeWebCacheFixture(url) }
    var reject = false
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: InMemorySecretStore(), nowMillis: { 1000 }, healthBeforeCommit: {
      if reject { throw CocoaError(.fileWriteOutOfSpace) }
    }, beforeCommit: {
      if reject { throw CocoaError(.fileWriteOutOfSpace) }
    })
    XCTAssertTrue(cache.putDocuments([cacheDocumentFixture("health-scope")]))
    XCTAssertTrue(cache.recordSourceReceipts((0..<3).map { _ in
      .init(sourceID: "bing", status: "failed", durationMillis: 100, resultCount: 0)
    }))
    let original = try Data(contentsOf: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: url))
    reject = true
    let transport = SourceHealthSearchFixture()
    let provider = AgentIOSURLSessionWebIntelligenceProvider(
      webMediaProvider: AgentIOSURLSessionWebMediaToolProvider(transport: transport, nowMillis: { 1000 }),
      cacheStore: cache, nowMillis: { 1000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider))
    var context = AgentNativeToolInvocationContext(invocationId: "health-network-only",
      grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent])
    let input: AgentMcpJSONObject = ["query": .string("Galaxy research"), "limit": .int(2)]
    let unscoped = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search, input: input, context: context,
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1000 }))
    XCTAssertTrue(unscoped.isSuccess)
    XCTAssertNil(unscoped.metadata["source_health_available"])
    XCTAssertTrue(transport.hosts.contains(where: { $0.contains("bing.com") }))
    XCTAssertEqual(try Data(contentsOf: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: url)), original)
    context.invocationId = "health-write-failed"
    context.grantedPermissions.insert(AgentIOSWebIntelligenceNativeToolCatalog.cachePermission)
    context.grantedConsents.insert(AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent)
    let failedWrite = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search, input: input, context: context,
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1000 }))
    XCTAssertTrue(failedWrite.isSuccess)
    XCTAssertEqual(failedWrite.metadata["source_health_write_committed"], .bool(false))
    XCTAssertEqual(try Data(contentsOf: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: url)), original)
  }

  func testAllOpenSearchCircuitsSkipTransportWithoutInventingAttempts() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("health-open-\(UUID()).json")
    defer { removeWebCacheFixture(url) }
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: InMemorySecretStore(), nowMillis: { 1000 })
    let providers = AgentIOSWebIntelligenceQueryRouting.select(query: "Galaxy research",
      requestedVerticals: [], requestedEngineIds: [], fanout: 32).selected.map(\.id)
    let receipts = providers.flatMap { provider in
      (0..<3).map { _ in AgentIOSWebSourceReceipt(sourceID: provider, status: "failed", durationMillis: 100, resultCount: 0) }
    }
    XCTAssertTrue(cache.recordSourceReceipts(receipts))
    let original = try XCTUnwrap(cache.sourceHealth())
    let transport = SourceHealthSearchFixture()
    let provider = AgentIOSURLSessionWebIntelligenceProvider(
      webMediaProvider: AgentIOSURLSessionWebMediaToolProvider(transport: transport, nowMillis: { 1000 }),
      cacheStore: cache, nowMillis: { 1000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider))
    let context = AgentNativeToolInvocationContext(invocationId: "health-all-open",
      grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission, AgentIOSWebIntelligenceNativeToolCatalog.cachePermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent, AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent])
    let result = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: ["query": .string("Galaxy research")], context: context,
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1000 }))
    XCTAssertEqual(result.error?.code, "search_sources_cooling_down")
    XCTAssertTrue(transport.hosts.isEmpty)
    XCTAssertEqual(result.error?.details["circuits_skipped"]?.arrayValue?.count, providers.count)
    XCTAssertEqual(cache.sourceHealth(), original)
  }

  func testSourceLearningRequiresRepeatedDiverseQueriesAndSafeDistinctHosts() throws {
    let policy = AgentIOSWebSourceLearningPolicy.self
    let results: [AgentMcpJSONObject] = [
      ["url": .string("https://www.source.example/a")], ["url": .string("https://source.example/b")],
      ["url": .string("https://learn.microsoft.com/a")], ["url": .string("https://127.0.0.1/a")],
      ["url": .string("https://private.local/a")], ["url": .string("https://user@other.example/a")],
      ["url": .string("https://-invalid.example/a")]]
    var source: AgentIOSLearnedWebSource?
    for query in ["first query", "first query", "second query", "third query"] {
      let observations = policy.observations(query: query,
        categories: ["research", "BAD TAG", "ai-models", "!!!", "\u{7814}\u{7A76}"], results: results)
      XCTAssertEqual(observations.count, 1)
      source = policy.evolve(source, observation: try XCTUnwrap(observations.first), now: 1000)
    }
    let verified = try XCTUnwrap(source)
    XCTAssertTrue(verified.isValid)
    XCTAssertEqual(verified.status, "verified")
    XCTAssertEqual(verified.observations, 4)
    XCTAssertEqual(verified.queryFingerprints.count, 3)
    XCTAssertTrue(verified.categoryTags.contains("bad tag"))
    XCTAssertTrue(verified.categoryTags.contains("ai-models"))
    XCTAssertTrue(verified.categoryTags.contains("\u{7814}\u{7A76}"))
    XCTAssertFalse(verified.categoryTags.contains("!!!"))
    XCTAssertNil(verified.publicValue()["query_fingerprints"])
    var disabled = verified
    disabled.status = "disabled"
    let imageObservation = try XCTUnwrap(policy.observations(query: "image", categories: [],
      results: [["url": .string("https://images.example/a"), "vertical": .string("image")]]).first)
    var image: AgentIOSLearnedWebSource?
    for query in ["a", "a", "b"] {
      var observation = imageObservation
      observation.queryFingerprint = policy.observations(query: query, categories: [], results: [results[0]])[0].queryFingerprint
      image = policy.evolve(image, observation: observation, now: 2000)
    }
    XCTAssertEqual(image?.status, "verified")
    let observation = try XCTUnwrap(policy.observations(query: "fourth", categories: [], results: [results[0]]).first)
    XCTAssertEqual(policy.evolve(disabled, observation: observation, now: 3000).status, "disabled")
  }

  func testSourceMaintenanceQueueIsBoundedWithoutCallerThreadFallback() {
    let operations = OperationQueue()
    operations.isSuspended = true
    let queue = AgentIOSWebMaintenanceQueue(queue: operations)
    defer { operations.cancelAllOperations(); operations.isSuspended = false }
    for _ in 0..<17 { XCTAssertTrue(queue.submit {} ) }
    XCTAssertFalse(queue.submit { XCTFail("Rejected work must not run") })
    XCTAssertEqual(operations.operationCount, 17)
    XCTAssertEqual(operations.maxConcurrentOperationCount, 1)
  }

  func testFullCacheClearInvalidatesQueuedLearningAcrossInstancesButExpiredClearDoesNot() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("learning-clear-\(UUID()).json")
    defer { removeWebCacheFixture(url) }
    let secrets = InMemorySecretStore()
    let operations = OperationQueue()
    operations.isSuspended = true
    defer { operations.cancelAllOperations(); operations.isSuspended = false }
    let first = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: secrets,
      learningQueue: AgentIOSWebMaintenanceQueue(queue: operations))
    let second = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: secrets)
    let results: [AgentMcpJSONObject] = [["url": .string("https://source.example/article")]]
    XCTAssertEqual(first.learnSourceCandidates(query: "first", categories: [], results: results)["status"], .string("queued"))
    XCTAssertEqual(second.clear(expiredOnly: false)["committed"], .bool(true))
    operations.isSuspended = false
    operations.waitUntilAllOperationsAreFinished()
    XCTAssertTrue(try XCTUnwrap(first.learnedSources()).isEmpty)
    operations.isSuspended = true
    _ = first.learnSourceCandidates(query: "second", categories: [], results: results)
    XCTAssertEqual(second.clear(expiredOnly: true)["committed"], .bool(true))
    operations.isSuspended = false
    operations.waitUntilAllOperationsAreFinished()
    XCTAssertEqual(first.learnedSources()?.count, 1)
    XCTAssertEqual(first.stats()["last_learning_status"], .string("saved"))
    XCTAssertEqual(second.clear(expiredOnly: false)["learned_sources_removed"], .int(1))
    XCTAssertTrue(try XCTUnwrap(first.learnedSources()).isEmpty)
  }

  func testLearningUsesEncryptedSnapshotAndLegacyDocumentsRemainReadable() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("learning-encrypted-\(UUID()).json")
    defer { removeWebCacheFixture(url) }
    let secrets = InMemorySecretStore()
    let operations = OperationQueue()
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: secrets,
      learningQueue: AgentIOSWebMaintenanceQueue(queue: operations))
    XCTAssertTrue(cache.putDocuments([cacheDocumentFixture("legacy")]))
    XCTAssertTrue(try XCTUnwrap(cache.learnedSources()).isEmpty)
    _ = cache.learnSourceCandidates(query: "private original query", categories: ["research"],
      results: [["url": .string("https://new-source.example/article")]])
    operations.waitUntilAllOperationsAreFinished()
    let serialized = try String(contentsOf: url, encoding: .utf8)
    XCTAssertFalse(serialized.contains("new-source.example"))
    XCTAssertFalse(serialized.contains("private original query"))
    let reopened = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: secrets)
    XCTAssertEqual(reopened.learnedSources()?.first?.host, "new-source.example")
    XCTAssertNotNil(reopened.document(url: "https://cache.test/legacy", allowStale: true))
    XCTAssertEqual(AgentIOSWebIntelligenceLearningStore(cacheStore: reopened).stats().candidateSourceCount, 1)
  }

  func testFailedOrCancelledLearningDoesNotPublishOrReplaceEvidence() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("learning-failed-\(UUID()).json")
    defer { removeWebCacheFixture(url) }
    let operations = OperationQueue()
    var reject = false
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: InMemorySecretStore(),
      learningQueue: AgentIOSWebMaintenanceQueue(queue: operations), beforeCommit: {
        if reject { throw CocoaError(.fileWriteOutOfSpace) }
      })
    XCTAssertTrue(cache.putDocuments([cacheDocumentFixture("evidence")]))
    let original = try Data(contentsOf: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: url))
    reject = true
    let results: [AgentMcpJSONObject] = [["url": .string("https://source.example/article")]]
    _ = cache.learnSourceCandidates(query: "first", categories: [], results: results)
    operations.waitUntilAllOperationsAreFinished()
    XCTAssertEqual(cache.stats()["last_learning_status"], .string("failed_write"))
    XCTAssertTrue(try XCTUnwrap(cache.learnedSources()).isEmpty)
    XCTAssertEqual(try Data(contentsOf: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: url)), original)
    reject = false
    _ = cache.learnSourceCandidates(query: "cancelled", categories: [], results: results, isCancelled: { true })
    operations.waitUntilAllOperationsAreFinished()
    XCTAssertEqual(try Data(contentsOf: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: url)), original)
  }

  func testActualSearchQueuesLearningOnlyWithCacheScopeAndCacheToolListsIt() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("learning-tool-\(UUID()).json")
    defer { removeWebCacheFixture(url) }
    let operations = OperationQueue()
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: InMemorySecretStore(),
      learningQueue: AgentIOSWebMaintenanceQueue(queue: operations))
    let provider = AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: BudgetWebMediaFixture(), cacheStore: cache)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider))
    var context = AgentNativeToolInvocationContext(invocationId: "learning-no-scope",
      grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent])
    let skipped = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search, input: ["query": .string("Galaxy research")],
      context: context, hooks: AgentNativeToolInvocationHooks(nowMillis: { 1000 }))
    XCTAssertTrue(skipped.isSuccess)
    XCTAssertEqual(skipped.output["learning"]?.objectValue?["status"], .string("skipped_cache_scope_required"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: url).path))
    context.grantedPermissions.insert(AgentIOSWebIntelligenceNativeToolCatalog.cachePermission)
    context.grantedConsents.insert(AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent)
    for (index, query) in ["Galaxy first", "Galaxy second", "Galaxy third", "Galaxy first"].enumerated() {
      context.invocationId = "learning-\(index)"
      let result = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search, input: ["query": .string(query)],
        context: context, hooks: AgentNativeToolInvocationHooks(nowMillis: { 1000 }))
      XCTAssertTrue(result.isSuccess)
      XCTAssertEqual(result.output["learning"]?.objectValue?["status"], .string("queued"))
    }
    operations.waitUntilAllOperationsAreFinished()
    context.invocationId = "learning-list"
    let listed = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.cache,
      input: ["action": .string("learned_sources"), "status": .string("verified")], context: context,
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1000 }))
    XCTAssertTrue(listed.isSuccess)
    XCTAssertEqual(listed.output["metadata"]?.objectValue?["learned_sources"]?.arrayValue?.count, 1)
    XCTAssertEqual(listed.output["cache"]?.objectValue?["verified_learned_source_count"], .int(1))
  }

  func testCorruptWebCacheCannotBeOverwrittenOrReportedAsCleared() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cache-corrupt-\(UUID()).json")
    defer { removeWebCacheFixture(url) }
    let original = Data("not an encrypted envelope".utf8)
    try original.write(to: url, options: .atomic)
    let secrets = InMemorySecretStore()
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: secrets)
    XCTAssertFalse(cache.putDocuments([cacheDocumentFixture("new")]))
    XCTAssertEqual(cache.stats()["available"], .bool(false))
    XCTAssertEqual(cache.clear(expiredOnly: false)["committed"], .bool(false))
    XCTAssertEqual(try Data(contentsOf: url), original)
    XCTAssertNil(secrets.string(account: AgentIOSWebIntelligenceCacheStore.keyAccount))
  }

  func testMissingWebCacheKeyDoesNotRotateOrReplaceExistingCiphertext() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cache-key-\(UUID()).json")
    defer { removeWebCacheFixture(url) }
    let secrets = InMemorySecretStore()
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: secrets)
    XCTAssertTrue(cache.putDocuments([cacheDocumentFixture("old")]))
    let original = try Data(contentsOf: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: url))
    secrets.delete(account: AgentIOSWebIntelligenceCacheStore.keyAccount)
    XCTAssertFalse(cache.putDocuments([cacheDocumentFixture("new")]))
    XCTAssertEqual(try Data(contentsOf: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: url)), original)
    XCTAssertNil(secrets.string(account: AgentIOSWebIntelligenceCacheStore.keyAccount))
  }

  func testWebCacheBatchCommitsOnceAndFailedReplacementPreservesSnapshot() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cache-batch-\(UUID()).json")
    defer { removeWebCacheFixture(url) }
    let secrets = InMemorySecretStore()
    var writes = 0
    var reject = false
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: secrets, beforeCommit: {
      if reject { throw CocoaError(.fileWriteOutOfSpace) }
      writes += 1
    })
    XCTAssertEqual(cache.cacheMetadata()["available"], .bool(true))
    writes = 0
    XCTAssertTrue(cache.putDocuments([cacheDocumentFixture("first"), cacheDocumentFixture("second")]))
    XCTAssertEqual(writes, 1)
    let original = try Data(contentsOf: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: url))
    reject = true
    XCTAssertFalse(cache.putDocuments([cacheDocumentFixture("third")]))
    XCTAssertEqual(cache.clear(expiredOnly: false)["documents_removed"], .int(0))
    XCTAssertNil(cache.removeWatch(id: "missing"))
    XCTAssertEqual(try Data(contentsOf: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: url)), original)
    let reopened = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: secrets)
    XCTAssertEqual(reopened.stats()["entry_count"], .int(2))
    XCTAssertNil(reopened.document(url: "https://cache.test/third", allowStale: true))
  }

  func testWebCacheInstancesSerializeOneSnapshotReadModifyWrite() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cache-shared-\(UUID()).json")
    defer { removeWebCacheFixture(url) }
    let secrets = InMemorySecretStore()
    let first = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: secrets)
    let second = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: secrets)
    let documents = (0..<20).map { cacheDocumentFixture(String($0)) }
    DispatchQueue.concurrentPerform(iterations: documents.count) { index in
      _ = (index % 2 == 0 ? first : second).putDocuments([documents[index]])
    }
    XCTAssertEqual(first.stats()["entry_count"], .int(20))
  }

  func testWebWatchAndClearToolsDoNotClaimFailedPersistenceSucceeded() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cache-watch-\(UUID()).json")
    defer { removeWebCacheFixture(url) }
    var reject = false
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: InMemorySecretStore(), beforeCommit: {
      if reject { throw CocoaError(.fileWriteOutOfSpace) }
    })
    let watch = AgentIOSWebIntelligenceCacheWatch(id: "original", url: "https://cache.test/article",
      intervalMinutes: 60, enabled: true, lastCheckedAtMillis: 0, lastChangedAtMillis: 0,
      lastSHA256: "", createdAtMillis: 1000, updatedAtMillis: 1000)
    XCTAssertTrue(cache.putWatch(watch))
    reject = true
    let provider = AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: BudgetWebMediaFixture(), cacheStore: cache)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider))
    let context = AgentNativeToolInvocationContext(invocationId: "cache-write-failure",
      grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission, AgentIOSWebIntelligenceNativeToolCatalog.cachePermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent, AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent])
    for (tool, input) in [(AgentIOSWebIntelligenceNativeToolCatalog.watch,
      ["action": AgentMcpJSONValue.string("create"), "url": .string("https://cache.test/new"), "watch_id": .string("new")]),
      (AgentIOSWebIntelligenceNativeToolCatalog.watch, ["action": .string("remove"), "watch_id": .string("original")]),
      (AgentIOSWebIntelligenceNativeToolCatalog.cache, ["action": .string("clear")])] {
      let result = registry.invoke(tool, input: input, context: context, hooks: AgentNativeToolInvocationHooks(nowMillis: { 1000 }))
      XCTAssertEqual(result.error?.code, "cache_persistence_failed")
    }
    XCTAssertEqual(cache.watch(id: "original"), watch)
  }

  private func cacheDocumentFixture(_ id: String) -> AgentIOSWebIntelligenceCacheDocument {
    .init(url: "https://cache.test/\(id)", title: id, content: "Source body", contentType: "text/plain",
      contentSHA256: String(repeating: "a", count: 64), retrievedAtMillis: 1000, expiresAtMillis: Int64.max,
      links: [], metadata: [:])
  }

  func testResearchBudgetKeepsEvidenceAndSkipsUnstartedQueriesAndPages() throws {
    let media = BudgetWebMediaFixture()
    media.spentPerSearch = 2_000
    let provider = AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: media,
      nowMillis: { 1000 }, uptimeMillis: { media.uptime })
    let result = try invokeWebBudgetFixture(provider: provider,
      input: ["query": .string("Galaxy research"), "query_plan": .array([.string("Galaxy first"), .string("Galaxy second")]),
        "timeout_ms": .int(2000)])
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(media.inputs.count, 1)
    XCTAssertEqual(result.output["status"], .string("partial"))
    XCTAssertEqual(result.output["results"]?.arrayValue?.count, 1)
    XCTAssertEqual(result.output["documents"]?.arrayValue?.count, 0)
    XCTAssertEqual(result.output["metadata"]?.objectValue?["queries_executed"], .int(1))
    XCTAssertEqual(result.output["metadata"]?.objectValue?["shared_budget_exhausted"], .bool(true))
    XCTAssertTrue(result.output["receipts"]?.arrayValue?.contains {
      $0.objectValue?["status"] == .string("skipped_budget")
    } == true)
  }

  func testResearchValidatesLaterEngineBeforeAnyEarlierSearch() throws {
    let media = BudgetWebMediaFixture()
    let provider = AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: media)
    let result = try invokeWebBudgetFixture(provider: provider,
      input: ["query": .string("Galaxy"), "query_plan": .array([
        .object(["query": .string("First"), "engines": .array([.string("bing")])]),
        .object(["query": .string("Second"), "engines": .array([.string("missing_engine")])])])])
    XCTAssertEqual(result.error?.code, "unsupported_search_engine")
    XCTAssertTrue(media.inputs.isEmpty)
  }

  func testSearchProfilesSupplyDefaultsButPreserveExplicitLimits() throws {
    let media = BudgetWebMediaFixture()
    let provider = AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: media, nowMillis: { 1000 })
    _ = try invokeWebBudgetFixture(provider: provider, tool: AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: ["query": .string("Galaxy"), "profile": .string("fast")])
    XCTAssertEqual(media.inputs.last?["timeout_ms"], .int(6000))
    XCTAssertEqual(media.inputs.last?["engine_fanout"], .int(6))
    _ = try invokeWebBudgetFixture(provider: provider, tool: AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: ["query": .string("Galaxy"), "profile": .string("deep"), "timeout_ms": .int(8500), "engine_fanout": .int(4)])
    XCTAssertEqual(media.inputs.last?["timeout_ms"], .int(8500))
    XCTAssertEqual(media.inputs.last?["engine_fanout"], .int(4))
  }

  func testMonotonicResearchBudgetCapsProgressAwareChildDeadline() throws {
    var monotonic: Int64 = 0
    var wall: Int64 = 1000
    let budget = AgentIOSWebExecutionBudget(durationMillis: 2000, now: { monotonic })
    let provider = AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: BudgetWebMediaFixture())
    var descriptor = try XCTUnwrap(AgentIOSWebIntelligenceNativeToolCatalog.definitions(provider: provider).first?.descriptor)
    descriptor.timeoutPolicy = .progressAware
    descriptor.timeoutMillis = 10_000
    let parent = AgentNativeToolInvocation(descriptor: descriptor, input: [:],
      context: AgentNativeToolInvocationContext(invocationId: "budget-child"),
      startedAtEpochMillis: 1000, deadlineEpochMillis: 11000, nowMillis: { wall },
      cancellationRequested: { false }, progressReporter: { _, _ in })
    let child = try budget.invocation(parent: parent, input: [:], timeoutMillis: 8000, nowMillis: { wall })
    wall = 1500
    try child.checkpoint()
    XCTAssertEqual(child.deadlineEpochMillis, 3000)
    monotonic = 2000
    XCTAssertTrue(budget.expired)
    XCTAssertTrue(child.isCancellationRequested)
    XCTAssertThrowsError(try budget.invocation(parent: parent, input: [:], timeoutMillis: 8000, nowMillis: { wall }))
  }

  private func invokeWebBudgetFixture(provider: AgentIOSURLSessionWebIntelligenceProvider,
    tool: String = AgentIOSWebIntelligenceNativeToolCatalog.research, input: AgentMcpJSONObject) throws -> AgentNativeToolExecutionResult {
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider))
    return registry.invoke(tool, input: input, context: AgentNativeToolInvocationContext(invocationId: "research-budget",
      grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent]),
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1000 }))
  }

  func testAgentIOSWebIntelligenceNativeToolCatalogAndExecutorUsesProviderBoundaries() throws {
    final class FakeWebIntelligenceProvider: AgentIOSWebIntelligenceToolProviding {
      var implementationId = "fake.ios.web_intelligence"
      var engineCatalogSize = 7
      var rankerId = "feature-hash-ranker-v1"
      var currentAvailability: AgentNativeToolAvailability = .available
      var invokedOperations: [AgentIOSWebIntelligenceOperation] = []

      func availability(operation: AgentIOSWebIntelligenceOperation) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func invoke(
        operation: AgentIOSWebIntelligenceOperation,
        input: AgentMcpJSONObject,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        invokedOperations.append(operation)
        return AgentNativeToolExecutionResult.success(
          output: [
            "request_id": .string("req-\(operation.rawValue)"),
            "result_count": .int(1)
          ],
          message: "",
          metadata: ["provider_operation": .string(operation.rawValue)]
        )
      }
    }

    let provider = FakeWebIntelligenceProvider()
    let definitions = AgentIOSWebIntelligenceNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider)
    )
    let networkContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent]
    )
    let cacheContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.cachePermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent]
    )

    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSWebIntelligenceNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSWebIntelligenceNativeToolCatalog.toolIds)
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSWebIntelligenceNativeToolCatalog.executorId)
      XCTAssertEqual(definition.descriptor.location, .phone)
      XCTAssertEqual(definition.descriptor.risk, .low)
      XCTAssertEqual(definition.descriptor.idempotency, .idempotent)
      XCTAssertTrue(definition.descriptor.capabilities.contains("web_intelligence.native"))
      XCTAssertTrue(definition.descriptor.capabilities.contains("source.receipts"))
      XCTAssertFalse(definition.descriptor.requiredPermissions.isEmpty)
      XCTAssertFalse(definition.descriptor.requiredConsents.isEmpty)
      XCTAssertEqual(definition.provenanceMetadata["protocol"], AgentIOSWebIntelligenceNativeToolCatalog.protocolId)
      XCTAssertEqual(definition.provenanceMetadata["engine_catalog_size"], "7")
      XCTAssertEqual(definition.provenanceMetadata["cookies"], "none")
    }
    let progressAware: Set<String> = [
      AgentIOSWebIntelligenceNativeToolCatalog.crawl,
      AgentIOSWebIntelligenceNativeToolCatalog.research,
      AgentIOSWebIntelligenceNativeToolCatalog.agent,
      AgentIOSWebIntelligenceNativeToolCatalog.watch
    ]
    definitions.forEach { definition in
      XCTAssertEqual(
        definition.descriptor.timeoutPolicy,
        progressAware.contains(definition.id) ? .progressAware : .fixed
      )
    }
    let fetch = try XCTUnwrap(definitions.first { $0.id == AgentIOSWebIntelligenceNativeToolCatalog.fetch })
    let cache = try XCTUnwrap(definitions.first { $0.id == AgentIOSWebIntelligenceNativeToolCatalog.cache })
    let research = try XCTUnwrap(definitions.first { $0.id == AgentIOSWebIntelligenceNativeToolCatalog.research })
    XCTAssertEqual(fetch.descriptor.requiredPermissions.map(\.id), [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission])
    XCTAssertEqual(fetch.descriptor.requiredConsents.map(\.id), [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent])
    XCTAssertEqual(cache.descriptor.requiredPermissions.map(\.id), [AgentIOSWebIntelligenceNativeToolCatalog.cachePermission])
    XCTAssertEqual(cache.descriptor.requiredConsents.map(\.id), [AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent])
    XCTAssertNotNil(research.descriptor.inputSchema["properties"]?.objectValue?["query_plan"])

    let denied = registry.invoke(
      AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: ["query": .string("GalaxySSI")],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission]
      )
    )
    XCTAssertEqual(denied.status, .rejected)
    XCTAssertEqual(denied.error?.code, "missing_consents")
    XCTAssertTrue(provider.invokedOperations.isEmpty)

    let search = registry.invoke(
      AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: ["query": .string("GalaxySSI"), "limit": .int(3)],
      context: networkContext
    )
    let cacheStatus = registry.invoke(
      AgentIOSWebIntelligenceNativeToolCatalog.cache,
      input: ["action": .string("status")],
      context: cacheContext
    )
    let unavailableProvider = FakeWebIntelligenceProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "Network provider missing"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(
      AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: ["query": .string("GalaxySSI")],
      context: networkContext
    )

    XCTAssertTrue(search.isSuccess)
    XCTAssertEqual(search.output["protocol"], .string(AgentIOSWebIntelligenceNativeToolCatalog.protocolId))
    XCTAssertEqual(search.output["operation"], .string("search"))
    XCTAssertEqual(search.output["status"], .string("completed"))
    XCTAssertEqual(search.metadata["source_isolation"], .bool(true))
    XCTAssertEqual(search.metadata["evidence_is_untrusted"], .bool(true))
    XCTAssertEqual(search.message, "Search across independent web sources completed")
    XCTAssertTrue(cacheStatus.isSuccess)
    XCTAssertEqual(cacheStatus.output["operation"], .string("cache"))
    XCTAssertEqual(provider.invokedOperations, [.search, .cache])
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertTrue(unavailableProvider.invokedOperations.isEmpty)
  }

  func testAgentIOSURLSessionWebIntelligenceProviderBridgesWebMediaEvidence() throws {
    final class FakeWebMediaProvider: AgentIOSWebMediaToolProviding {
      var implementationId = "fake.ios.web_media"
      var invocations: [(operation: AgentIOSWebMediaOperation, input: AgentMcpJSONObject)] = []

      func availability(operation: AgentIOSWebMediaOperation) -> AgentNativeToolAvailability {
        .available
      }

      func invoke(
        operation: AgentIOSWebMediaOperation,
        input: AgentMcpJSONObject,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        invocations.append((operation, input))
        switch operation {
        case .webSearch:
          return AgentNativeToolExecutionResult.success(
            output: [
              "results": .array([
                .object([
                  "title": .string("GalaxySSI Docs"),
                  "url": .string("https://docs.galaxyssi.example")
                ]),
                .object([
                  "title": .string("GalaxySSI Blog"),
                  "url": .string("https://blog.galaxyssi.example")
                ])
              ]),
              "result_count": .int(2)
            ],
            metadata: ["provider": .string("fake-search")]
          )
        case .webOpen:
          let url = input["url"]?.stringValue ?? "https://galaxyssi.example/page"
          return webOutput(
            url: url,
            text: "Hello ASI from fetched readable content",
            hash: String(repeating: "a", count: 64)
          )
        case .webFetch:
          let url = input["url"]?.stringValue ?? "https://galaxyssi.example/root"
          let body = url.hasSuffix("/child")
            ? "<title>Child</title><p>Child page</p>"
            : "<title>Root</title><p>Root page</p><a href=\"/child\">Child</a>"
          return webOutput(
            url: url,
            text: body,
            hash: url.hasSuffix("/child") ? String(repeating: "c", count: 64) : String(repeating: "b", count: 64)
          )
        default:
          return AgentNativeToolExecutionResult.failure(
            code: "unexpected_web_media_operation",
            message: "Unexpected fake web media operation"
          )
        }
      }

      private func webOutput(url: String, text: String, hash: String) -> AgentNativeToolExecutionResult {
        AgentNativeToolExecutionResult.success(
          output: [
            "status_code": .int(200),
            "content_type": .string("text/html"),
            "content_length_bytes": .int(Int64(text.utf8.count)),
            "retrieved_at_epoch_ms": .int(1_200),
            "text": .string(text),
            "html_sha256": .string(hash),
            "sha256": .string(hash),
            "article": .object(["title": .string("GalaxySSI")]),
            "source": .object([
              "requested_url": .string(url),
              "final_url": .string(url),
              "redirect_chain": .array([]),
              "dns_resolution": .array([])
            ])
          ],
          metadata: ["javascript": .bool(false)]
        )
      }
    }

    let webMedia = FakeWebMediaProvider()
    let provider = AgentIOSURLSessionWebIntelligenceProvider(
      webMediaProvider: webMedia,
      nowMillis: { 2_000 }
    )
    let definitions = AgentIOSWebIntelligenceNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider)
    )
    let networkContext = AgentNativeToolInvocationContext(
      invocationId: "web-intelligence-network",
      grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent]
    )
    let cacheContext = AgentNativeToolInvocationContext(
      invocationId: "web-intelligence-cache",
      grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.cachePermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent]
    )

    let searchDefinition = try XCTUnwrap(definitions.first { $0.id == AgentIOSWebIntelligenceNativeToolCatalog.search })
    let cacheDefinition = try XCTUnwrap(definitions.first { $0.id == AgentIOSWebIntelligenceNativeToolCatalog.cache })
    XCTAssertEqual(searchDefinition.descriptor.availability.status, .available)
    XCTAssertEqual(cacheDefinition.descriptor.availability.status, .available)
    XCTAssertEqual(searchDefinition.provenanceMetadata["implementation"], "galaxyssi.ios.urlsession_web_intelligence")
    XCTAssertEqual(searchDefinition.provenanceMetadata["engine_catalog_size"], "3")

    let search = registry.invoke(
      AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: ["query": .string("GalaxySSI"), "limit": .int(2)],
      context: networkContext,
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1_000 })
    )
    let fetch = registry.invoke(
      AgentIOSWebIntelligenceNativeToolCatalog.fetch,
      input: ["url": .string("https://galaxyssi.example/page")],
      context: networkContext,
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1_000 })
    )
    let extract = registry.invoke(
      AgentIOSWebIntelligenceNativeToolCatalog.extract,
      input: [
        "source_url": .string("https://supplied.galaxyssi.example"),
        "content": .string("<title>Supplied</title><main><h1>Hello</h1><p>Offline body</p></main>")
      ],
      context: cacheContext,
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1_000 })
    )
    let crawl = registry.invoke(
      AgentIOSWebIntelligenceNativeToolCatalog.crawl,
      input: [
        "url": .string("https://galaxyssi.example/root"),
        "max_pages": .int(2)
      ],
      context: networkContext,
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1_000 })
    )
    let cacheStatus = registry.invoke(
      AgentIOSWebIntelligenceNativeToolCatalog.cache,
      input: ["action": .string("status")],
      context: cacheContext,
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1_000 })
    )

    XCTAssertTrue(search.isSuccess)
    XCTAssertEqual(search.output["operation"], .string("search"))
    XCTAssertEqual(search.output["result_count"], .int(2))
    XCTAssertEqual(search.output["engine"], .string("fake-search"))
    XCTAssertEqual(search.metadata["implementation"], .string("galaxyssi.ios.urlsession_web_intelligence"))
    XCTAssertEqual(search.metadata["web_media_implementation"], .string("fake.ios.web_media"))
    let evidence = try XCTUnwrap(search.output["evidence"]?.arrayValue)
    XCTAssertEqual(evidence.count, 2)
    XCTAssertEqual(evidence.first?.objectValue?["trust"], .string("untrusted_public_web"))
    XCTAssertEqual(evidence.first?.objectValue?["url"], .string("https://docs.galaxyssi.example"))
    let receipts = try XCTUnwrap(search.output["source_receipts"]?.arrayValue)
    XCTAssertEqual(receipts.first?.objectValue?["network_policy"], .string("search_result_only"))

    XCTAssertTrue(fetch.isSuccess)
    XCTAssertEqual(fetch.output["operation"], .string("fetch"))
    XCTAssertEqual(fetch.output["url"], .string("https://galaxyssi.example/page"))
    XCTAssertNil(fetch.output["text"])
    XCTAssertEqual(fetch.output["content_sha256"], .string(String(repeating: "a", count: 64)))
    XCTAssertEqual(fetch.output["source"]?.objectValue?["status_code"], .int(200))
    let fetchPack = try XCTUnwrap(fetch.output["evidence_pack"]?.objectValue)
    let fetchItem = try XCTUnwrap(fetchPack["items"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(fetchPack["protocol"], .string(AgentIOSWebEvidencePack.protocolId))
    XCTAssertEqual(fetchItem["title"], .string("GalaxySSI"))
    XCTAssertEqual(fetchItem["excerpt"], .string("Hello ASI from fetched readable content"))
    XCTAssertNil(fetch.output["documents"]?.arrayValue?.first?.objectValue?["content"])

    XCTAssertTrue(extract.isSuccess)
    XCTAssertEqual(extract.output["operation"], .string("extract"))
    XCTAssertEqual(extract.output["title"], .string("Supplied"))
    XCTAssertEqual(extract.output["source_receipts"]?.arrayValue?.first?.objectValue?["network"], .bool(false))
    XCTAssertTrue((extract.output["text"]?.stringValue ?? "").contains("Offline body"))

    XCTAssertTrue(crawl.isSuccess)
    XCTAssertEqual(crawl.output["operation"], .string("crawl"))
    XCTAssertEqual(crawl.output["page_count"], .int(2))
    let pages = try XCTUnwrap(crawl.output["pages"]?.arrayValue)
    XCTAssertEqual(pages.last?.objectValue?["title"], .string("Child"))
    XCTAssertTrue(cacheStatus.isSuccess)
    XCTAssertEqual(cacheStatus.output["cache"]?.objectValue?["encryption"], .string("ios_keychain_aes_gcm"))
    XCTAssertEqual(webMedia.invocations.map { $0.operation }, [.webSearch, .webOpen, .webFetch, .webFetch])
    XCTAssertEqual(webMedia.invocations.first?.input["max_results"], .int(2))

    let research = registry.invoke(
      AgentIOSWebIntelligenceNativeToolCatalog.research,
      input: [
        "query": .string("Compare GalaxySSI docs and news"),
        "query_plan": .array([
          .object([
            "query": .string("GalaxySSI documentation"),
            "purpose": .string("product documentation"),
            "verticals": .array([.string("docs")])
          ]),
          .object([
            "query": .string("GalaxySSI current news"),
            "purpose": .string("current reporting"),
            "verticals": .array([.string("news")])
          ])
        ]),
        "evidence_limit": .int(2),
        "page_read_parallelism": .int(1),
        "early_complete": .bool(false)
      ],
      context: networkContext,
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1_000 })
    )

    XCTAssertTrue(research.isSuccess)
    XCTAssertEqual(research.output["research"]?.objectValue?["query_plan"]?.arrayValue?.count, 2)
    XCTAssertEqual(research.output["research"]?.objectValue?["coverage"]?.arrayValue?.count, 2)
    XCTAssertNotNil(research.output["evidence_pack"]?.objectValue?["research_context"])
    let researchSearches = webMedia.invocations.filter { $0.operation == .webSearch }.suffix(2)
    XCTAssertEqual(
      researchSearches.compactMap { $0.input["query"]?.stringValue },
      ["GalaxySSI documentation", "GalaxySSI current news"]
    )
    XCTAssertEqual(
      researchSearches.first?.input["verticals"]?.arrayValue,
      [.string("docs")]
    )
  }

}

private final class LearnedRoutingSearchFixture: AgentIOSURLSessionWebTransporting {
  private let lock = NSLock()
  private var recorded: [AgentIOSURLSessionWebRequest] = []
  var requests: [AgentIOSURLSessionWebRequest] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }
  func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
    lock.lock()
    recorded.append(request)
    lock.unlock()
    let html = #"<h2><a href="https://outside.example/article">Galaxy research external</a></h2><p>Galaxy research outside the requested host must be filtered.</p><h2><a href="https://learned.example/article">Galaxy research evidence</a></h2><p>Galaxy research has a detailed excerpt from the requested source.</p>"#
    return .init(statusCode: 200, finalURL: request.url, headers: ["content-type": "text/html; charset=utf-8"],
      body: Data(html.utf8), retrievedAtEpochMillis: 1000)
  }
}

private final class SourceHealthSearchFixture: AgentIOSURLSessionWebTransporting {
  private let lock = NSLock()
  private var requestedHosts: [String] = []
  var hosts: [String] {
    lock.lock()
    defer { lock.unlock() }
    return requestedHosts
  }
  func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
    lock.lock()
    requestedHosts.append(request.url.host ?? "")
    lock.unlock()
    let html = #"<h2><a href="https://learn.microsoft.com/galaxy">Galaxy research evidence</a></h2><p>Galaxy research has a sufficiently detailed source excerpt for this fixture.</p>"#
    return .init(statusCode: 200, finalURL: request.url, headers: ["content-type": "text/html; charset=utf-8"],
      body: Data(html.utf8), retrievedAtEpochMillis: 1000)
  }
}

private final class BudgetWebMediaFixture: AgentIOSWebMediaToolProviding {
  var implementationId = "fixture.web-budget"
  var inputs: [AgentMcpJSONObject] = []
  var uptime: Int64 = 0
  var spentPerSearch: Int64 = 0
  func availability(operation: AgentIOSWebMediaOperation) -> AgentNativeToolAvailability { .available }
  func invoke(operation: AgentIOSWebMediaOperation, input: AgentMcpJSONObject,
              invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    inputs.append(input)
    uptime += spentPerSearch
    return .success(output: ["results": .array([.object(["title": .string("Galaxy evidence"),
      "url": .string("https://source.example/article"), "snippet": .string("Galaxy research evidence")])])],
      metadata: ["provider": .string("fixture")])
  }
}
