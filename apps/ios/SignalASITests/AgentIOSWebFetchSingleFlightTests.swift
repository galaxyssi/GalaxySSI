import XCTest
@testable import SignalASI

final class AgentIOSWebFetchSingleFlightTests: XCTestCase {
  private final class FakeIntelligenceProvider: AgentIOSWebIntelligenceToolProviding {
    var implementationId = "fake.phone.public-html"
    var engineCatalogSize = 1
    var rankerId = "fake"
    private let lock = NSLock()
    private var active = 0
    private(set) var maxActive = 0

    func availability(operation: AgentIOSWebIntelligenceOperation) -> AgentNativeToolAvailability {
      .available
    }

    func invoke(
      operation: AgentIOSWebIntelligenceOperation,
      input: AgentMcpJSONObject,
      invocation: AgentNativeToolInvocation
    ) -> AgentNativeToolExecutionResult {
      let url = input["url"]?.stringValue ?? ""
      lock.lock()
      active += 1
      maxActive = max(maxActive, active)
      lock.unlock()
      defer {
        lock.lock()
        active -= 1
        lock.unlock()
      }
      Thread.sleep(forTimeInterval: 0.04)
      if url.contains("failed") {
        return .failure(code: "source_failed", message: "Source failed")
      }
      return .success(output: [
        "url": .string(url),
        "title": .string(URL(string: url)?.host ?? "Page"),
        "text": .string("Readable public evidence for \(url)"),
        "source": .object(["final_url": .string(url)]),
        "metadata": .object(["challenge_detected": .string("false")])
      ])
    }
  }

  private final class FakeWebMediaProvider: AgentIOSWebMediaToolProviding {
    var implementationId = "fake.single-flight.web-media"
    private let lock = NSLock()
    private(set) var invocationCount = 0

    func availability(operation: AgentIOSWebMediaOperation) -> AgentNativeToolAvailability {
      .available
    }

    func invoke(
      operation: AgentIOSWebMediaOperation,
      input: AgentMcpJSONObject,
      invocation: AgentNativeToolInvocation
    ) -> AgentNativeToolExecutionResult {
      lock.lock()
      invocationCount += 1
      lock.unlock()
      let url = input["url"]?.stringValue ?? ""
      Thread.sleep(forTimeInterval: 0.08)
      let text = "<html><title>Cached page</title><main>Durable readable content</main></html>"
      return .success(output: [
        "status_code": .int(200),
        "content_type": .string("text/html"),
        "content_length_bytes": .int(Int64(text.utf8.count)),
        "retrieved_at_epoch_ms": .int(2_000),
        "text": .string(text),
        "html_sha256": .string(String(repeating: "a", count: 64)),
        "source": .object([
          "requested_url": .string(url),
          "final_url": .string(url),
          "redirect_chain": .array([]),
          "dns_resolution": .array([])
        ])
      ])
    }
  }

  func testCoalescesConcurrentFetchesForOneCanonicalURL() {
    let ownerStarted = DispatchSemaphore(value: 0)
    let releaseOwner = DispatchSemaphore(value: 0)
    let group = DispatchGroup()
    let lock = NSLock()
    var fetchCount = 0
    var results: [AgentIOSWebFetchFlightResult] = []
    let key = "https://single-flight-\(UUID().uuidString).example/"

    group.enter()
    DispatchQueue.global().async {
      defer { group.leave() }
      let result = try? AgentIOSWebFetchSingleFlight.execute(
        canonicalURL: key,
        timeoutMillis: 2_000,
        isCancellationRequested: { false },
        checkpoint: {}
      ) {
        lock.lock()
        fetchCount += 1
        lock.unlock()
        ownerStarted.signal()
        _ = releaseOwner.wait(timeout: .now() + 1)
        return .success(output: ["value": .string("shared")])
      }
      if let result {
        lock.lock()
        results.append(result)
        lock.unlock()
      }
    }
    XCTAssertEqual(ownerStarted.wait(timeout: .now() + 1), .success)
    group.enter()
    DispatchQueue.global().async {
      defer { group.leave() }
      let result = try? AgentIOSWebFetchSingleFlight.execute(
        canonicalURL: key,
        timeoutMillis: 2_000,
        isCancellationRequested: { false },
        checkpoint: {}
      ) {
        lock.lock()
        fetchCount += 1
        lock.unlock()
        return .success(output: ["value": .string("unexpected")])
      }
      if let result {
        lock.lock()
        results.append(result)
        lock.unlock()
      }
    }
    Thread.sleep(forTimeInterval: 0.05)
    releaseOwner.signal()
    XCTAssertEqual(group.wait(timeout: .now() + 3), .success)

    XCTAssertEqual(fetchCount, 1)
    XCTAssertEqual(results.count, 2)
    XCTAssertEqual(results.filter { $0.shared }.count, 1)
    XCTAssertTrue(results.allSatisfy { $0.value.output["value"] == .string("shared") })
  }

  func testExplicitPagesPrefetchFourInParallelAndPreserveRequestOrder() {
    let provider = FakeIntelligenceProvider()
    let request = [
      "https://one.example/page",
      "https://failed.example/page",
      "https://three.example/page",
      "https://four.example/page",
      "https://ignored.example/page"
    ].joined(separator: " ")

    let preparations = AgentIOSPhonePublicHTMLAttachment.prepareAll(
      turnId: "turn-1",
      currentRequest: request,
      provider: provider
    )

    XCTAssertGreaterThanOrEqual(provider.maxActive, 3)
    XCTAssertEqual(
      preparations.map(\.sourceURL),
      [
        "https://one.example/page",
        "https://three.example/page",
        "https://four.example/page"
      ]
    )
    XCTAssertFalse(preparations.contains { $0.sourceURL.contains("ignored") })
    XCTAssertEqual(
      AgentIOSPhonePublicHTMLAttachment.instruction(for: preparations)
        .components(separatedBy: AgentIOSPhonePublicHTMLAttachment.promptMarker).count - 1,
      3
    )
  }

  func testWebFetchSharesEncryptedCacheAcrossProviderInstances() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("signalasi-web-cache-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = AgentIOSWebIntelligenceCacheStore(
      fileURL: root,
      secrets: InMemorySecretStore(),
      nowMillis: { 2_500 }
    )
    let webMedia = FakeWebMediaProvider()
    let first = AgentIOSURLSessionWebIntelligenceProvider(
      webMediaProvider: webMedia,
      cacheStore: cache,
      nowMillis: { 2_500 }
    )
    let second = AgentIOSURLSessionWebIntelligenceProvider(
      webMediaProvider: webMedia,
      cacheStore: cache,
      nowMillis: { 2_500 }
    )
    let definition = try XCTUnwrap(
      AgentIOSWebIntelligenceNativeToolCatalog.definitions(provider: first)
        .first { $0.id == AgentIOSWebIntelligenceNativeToolCatalog.fetch }
    )
    let invocation = AgentNativeToolInvocation(
      descriptor: definition.descriptor,
      input: [:],
      context: AgentNativeToolInvocationContext(),
      startedAtEpochMillis: 2_000,
      deadlineEpochMillis: 32_000,
      nowMillis: { 2_500 },
      cancellationRequested: { false },
      progressReporter: { _, _ in }
    )
    let input: AgentMcpJSONObject = [
      "url": .string("https://cache.example/page"),
      "timeout_ms": .int(30_000)
    ]

    let network = first.invoke(operation: .fetch, input: input, invocation: invocation)
    let cached = second.invoke(operation: .fetch, input: input, invocation: invocation)

    XCTAssertTrue(network.isSuccess)
    XCTAssertTrue(cached.isSuccess)
    XCTAssertEqual(webMedia.invocationCount, 1)
    XCTAssertEqual(cached.output["cache"]?.objectValue?["hit"], .bool(true))
    XCTAssertEqual(cached.output["source"]?.objectValue?["source_id"], .string("local_cache"))
  }
}
