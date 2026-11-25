import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testCorruptWebCacheCannotBeOverwrittenOrReportedAsCleared() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cache-corrupt-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
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
    defer { try? FileManager.default.removeItem(at: url) }
    let secrets = InMemorySecretStore()
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: secrets)
    XCTAssertTrue(cache.putDocuments([cacheDocumentFixture("old")]))
    let original = try Data(contentsOf: url)
    secrets.delete(account: AgentIOSWebIntelligenceCacheStore.keyAccount)
    XCTAssertFalse(cache.putDocuments([cacheDocumentFixture("new")]))
    XCTAssertEqual(try Data(contentsOf: url), original)
    XCTAssertNil(secrets.string(account: AgentIOSWebIntelligenceCacheStore.keyAccount))
  }

  func testWebCacheBatchCommitsOnceAndFailedReplacementPreservesSnapshot() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cache-batch-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let secrets = InMemorySecretStore()
    var writes = 0
    var reject = false
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: secrets, writeFile: { data, url in
      if reject { throw CocoaError(.fileWriteOutOfSpace) }
      writes += 1
      try data.write(to: url, options: .atomic)
    })
    XCTAssertTrue(cache.putDocuments([cacheDocumentFixture("first"), cacheDocumentFixture("second")]))
    XCTAssertEqual(writes, 1)
    let original = try Data(contentsOf: url)
    reject = true
    XCTAssertFalse(cache.putDocuments([cacheDocumentFixture("third")]))
    XCTAssertEqual(cache.clear(expiredOnly: false)["documents_removed"], .int(0))
    XCTAssertNil(cache.removeWatch(id: "missing"))
    XCTAssertEqual(try Data(contentsOf: url), original)
    let reopened = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: secrets)
    XCTAssertEqual(reopened.stats()["entry_count"], .int(2))
    XCTAssertNil(reopened.document(url: "https://cache.test/third", allowStale: true))
  }

  func testWebCacheInstancesSerializeOneSnapshotReadModifyWrite() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cache-shared-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
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
    defer { try? FileManager.default.removeItem(at: url) }
    var reject = false
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: InMemorySecretStore(), writeFile: { data, url in
      if reject { throw CocoaError(.fileWriteOutOfSpace) }
      try data.write(to: url, options: .atomic)
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
