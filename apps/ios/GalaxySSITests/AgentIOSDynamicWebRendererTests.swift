import XCTest
@testable import GalaxySSI

final class AgentIOSDynamicWebRendererTests: XCTestCase {
  func testSpecialUseAddressRangesMatchAndroidIncludingWholeSubnetEdges() {
    for prefix in ["192.0.0", "192.0.2", "192.88.99", "198.51.100", "203.0.113"] {
      for suffix in [0, 1, 127, 254, 255] {
        let host = "\(prefix).\(suffix)"
        XCTAssertTrue(AgentIOSPublicAddressPolicy.blocksHost(host), host)
        XCTAssertTrue(AgentIOSPublicAddressPolicy.blocksHost(host + "."), host)
      }
    }
    for host in ["2001:db8::", "2001:db8::1", "2001:db8:ffff:ffff:ffff:ffff:ffff:ffff",
                 "2001:0DB8:0000:0000:0000:0000:0000:0001"] {
      XCTAssertTrue(AgentIOSPublicAddressPolicy.blocksHost(host), host)
      XCTAssertTrue(AgentIOSPublicAddressPolicy.blocksHost("[\(host)]"), host)
    }
  }

  func testSpecialUseAddressRulesPreserveAdjacentPublicRanges() {
    for host in ["191.255.255.255", "192.0.1.255", "192.0.3.0", "192.88.98.255", "192.88.100.0",
                 "198.51.99.255", "198.51.101.0", "203.0.112.255", "203.0.114.0",
                 "2001:db7:ffff::1", "2001:db9::1", "2001:4860:4860::8888"] {
      XCTAssertFalse(AgentIOSPublicAddressPolicy.blocksHost(host), host)
    }
    for host in ["192.0.2.example.com", "documentation.example", "db8.example.com"] {
      XCTAssertFalse(AgentIOSPublicAddressPolicy.blocksHost(host), host)
    }
  }

  func testSpecialUseIPv4CannotBypassClassificationThroughMappedOrNAT64Forms() {
    for host in ["::ffff:192.0.0.1", "::ffff:192.0.2.1", "::ffff:c058:6301", "::ffff:c633:6401",
                 "::ffff:cb00:7101", "64:ff9b::c000:1", "64:ff9b::c000:201", "64:ff9b::c058:6301",
                 "64:ff9b::c633:6401", "64:ff9b::cb00:7101"] {
      XCTAssertTrue(AgentIOSPublicAddressPolicy.blocksHost(host), host)
    }
    for host in ["::ffff:8.8.8.8", "64:ff9b::808:808"] {
      XCTAssertFalse(AgentIOSPublicAddressPolicy.blocksHost(host), host)
    }
  }

  func testSpecialUseAddressesAreRejectedByRendererSubresourceAndImagePolicies() throws {
    for host in ["192.0.0.1", "192.0.2.1", "192.88.99.1", "198.51.100.1", "203.0.113.1",
                 "[2001:db8::1]", "[::ffff:192.0.2.1]", "[64:ff9b::cb00:7101]"] {
      let url = "https://\(host)/image.png"
      XCTAssertFalse(AgentIOSWebRenderURLPolicy.allows(url), url)
      XCTAssertFalse(AgentIOSWebRenderURLPolicy.allowsSubresource(url), url)
      XCTAssertFalse(AgentIOSWebRenderURLPolicy.resolvesToPublicAddress(url), url)
      XCTAssertThrowsError(try AgentMarkdownImageStore.publicURL(XCTUnwrap(URL(string: url))), url)
    }
  }

  func testSpecialUseLiteralRequestsNeverReachInjectedTransportOrRenderer() throws {
    var calls = 0
    let transport = StubTransport { request in
      calls += 1
      return self.response(url: request.url, body: self.html("Unexpected transport"))
    }
    let renderer = StubRenderer(result: .success(rendered("Unexpected renderer")))
    let provider = AgentIOSURLSessionWebMediaToolProvider(transport: transport, dynamicRenderer: renderer,
      sourceHealthStore: nil, nowMillis: { 1_000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: provider))
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission],
      grantedConsents: [AgentIOSWebMediaNativeToolCatalog.publicWebConsent])
    for tool in [AgentIOSWebMediaNativeToolCatalog.webFetch, AgentIOSWebMediaNativeToolCatalog.webOpen] {
      for host in ["192.0.0.1", "192.0.2.1", "192.88.99.1", "198.51.100.1", "203.0.113.1", "[2001:db8::1]"] {
        let result = registry.invoke(tool, input: ["url": .string("https://\(host)/page")], context: context,
          hooks: AgentNativeToolInvocationHooks(nowMillis: { 1_000 }))
        XCTAssertFalse(result.isSuccess, host)
        XCTAssertEqual(result.error?.code, "local_host_blocked", host)
      }
    }
    XCTAssertEqual(calls, 0)
    XCTAssertEqual(renderer.calls, 0)
  }

  func testSpecialUseRedirectStopsBeforeSecondTransportRequest() throws {
    for host in ["192.0.2.1", "192.88.99.1", "198.51.100.1", "203.0.113.1", "[2001:db8::1]"] {
      var calls = 0
      let transport = StubTransport { request in
        calls += 1
        return AgentIOSURLSessionWebResponse(statusCode: 302, finalURL: request.url,
          headers: ["location": "https://\(host)/private"], body: Data(), retrievedAtEpochMillis: 1_000)
      }
      let provider = AgentIOSURLSessionWebMediaToolProvider(transport: transport, sourceHealthStore: nil, nowMillis: { 1_000 })
      let registry = try AgentNativeToolRegistry().registerExecutables(
        AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: provider))
      let result = registry.invoke(AgentIOSWebMediaNativeToolCatalog.webFetch,
        input: ["url": .string("https://example.com/start")],
        context: AgentNativeToolInvocationContext(
          grantedPermissions: [AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission],
          grantedConsents: [AgentIOSWebMediaNativeToolCatalog.publicWebConsent]),
        hooks: AgentNativeToolInvocationHooks(nowMillis: { 1_000 }))
      XCTAssertFalse(result.isSuccess, host)
      XCTAssertEqual(result.error?.code, "local_host_blocked", host)
      XCTAssertEqual(calls, 1, host)
    }
  }

  func testPublicAddressClassificationRejectsEquivalentAndScopedIPv6Forms() throws {
    for host in ["::", "::1", "0:0:0:0:0:0:0:1", "fe80::1", "fe90::1", "febf::1", "fec0::1", "feff::1",
      "fc00::1", "fdab::1", "ff02::1", "::ffff:127.0.0.1", "::ffff:7f00:1", "0:0:0:0:0:ffff:a00:1",
      "::127.0.0.1", "64:ff9b::7f00:1", "fe80::1%en0"] {
      XCTAssertTrue(AgentIOSPublicAddressPolicy.blocksHost(host), host)
      let url = "https://[\(host)]/image.png"
      XCTAssertFalse(AgentIOSWebRenderURLPolicy.allows(url), url)
      if let parsed = URL(string: url) { XCTAssertThrowsError(try AgentMarkdownImageStore.publicURL(parsed), url) }
    }
  }

  func testPublicAddressClassificationPreservesPublicIPv6AndDNS64() throws {
    for host in ["2606:4700:4700::1111", "2001:4860:4860::8888", "::ffff:8.8.8.8", "64:ff9b::808:808"] {
      XCTAssertFalse(AgentIOSPublicAddressPolicy.blocksHost(host), host)
      XCTAssertTrue(AgentIOSPublicAddressPolicy.isNumericHost(host))
      let url = "https://[\(host)]/image.png"
      XCTAssertTrue(AgentIOSWebRenderURLPolicy.allows(url), url)
      // Numeric literals use no DNS or transport; this is not a live fetch.
      XCTAssertTrue(AgentIOSWebRenderURLPolicy.resolvesToPublicAddress(url), url)
      XCTAssertNoThrow(try AgentMarkdownImageStore.publicURL(XCTUnwrap(URL(string: url))))
    }
  }

  func testPublicAddressClassificationDoesNotConfuseDomainPrefixesWithIPv6() {
    for host in ["fc.example.com", "fd.example.com", "fc2.com", "fdic.gov", "example.com."] {
      XCTAssertFalse(AgentIOSPublicAddressPolicy.blocksHost(host), host)
      XCTAssertTrue(AgentIOSWebRenderURLPolicy.allows("https://\(host)/article"), host)
    }
    for host in ["localhost.", "x.localhost.", "printer.local.", "127.1", "2130706433", "0177.0.0.1", "0x7f000001",
      "0x7f.0.0.1", "256.1.1.1", "::not-an-address", "[::1", "example.com\u{0}.invalid"] {
      XCTAssertTrue(AgentIOSPublicAddressPolicy.blocksHost(host), host)
    }
  }

  func testPublicAddressClassificationPreservesExistingIPv4Restrictions() {
    for host in ["0.0.0.0", "10.1.1.1", "127.0.0.1", "100.64.0.1", "100.127.255.255", "169.254.1.1",
      "172.16.0.1", "172.31.255.255", "192.168.1.1", "198.18.0.1", "198.19.255.255", "224.0.0.1", "255.255.255.255"] {
      XCTAssertTrue(AgentIOSPublicAddressPolicy.blocksHost(host), host)
    }
    for host in ["8.8.8.8", "1.1.1.1", "100.63.255.255", "100.128.0.1", "172.15.255.255", "172.32.0.1"] {
      XCTAssertFalse(AgentIOSPublicAddressPolicy.blocksHost(host), host)
    }
  }

  func testRendererHealthUsesSharedCooldownWithoutExtendingRejectedChecks() throws {
    var now: UInt64 = 100
    let health = AgentIOSWebRendererHealth(cooldownNanoseconds: 30, now: { now })
    try health.checkAvailable()
    health.failed()
    XCTAssertThrowsError(try health.checkAvailable())
    now = 129
    XCTAssertThrowsError(try health.checkAvailable())
    now = 130
    XCTAssertNoThrow(try health.checkAvailable())
    health.failed()
    health.succeeded()
    XCTAssertNoThrow(try health.checkAvailable())
  }

  func testRendererHealthDoesNotPoisonAvailabilityForPageOrCallerFailures() {
    for error in [AgentIOSDynamicWebRenderError.contentProcessTerminated, .startupTimeout, .unavailable] {
      XCTAssertTrue(AgentIOSWebRendererHealth.isProcessFailure(error))
    }
    for error in [AgentIOSDynamicWebRenderError.cancelled, .timedOut, .capacityTimeout, .invalidURL,
                  .privateAddress, .navigationBlocked, .navigationFailed("page error"), .emptyDocument,
                  .temporarilyUnavailable, .responseTooLarge(10, 5)] {
      XCTAssertFalse(AgentIOSWebRendererHealth.isProcessFailure(error))
    }
  }

  func testRendererPreflightRejectsCancellationCheckpointAndDeadlineBeforeResolver() {
    var resolved = false
    XCTAssertThrowsError(try AgentIOSWebRenderPreflight.resolve(deadline: .now() + .seconds(1),
      isCancellationRequested: { true }, checkpoint: {}, resolver: { resolved = true; return true }))
    XCTAssertThrowsError(try AgentIOSWebRenderPreflight.resolve(deadline: .now() + .seconds(1),
      isCancellationRequested: { false }, checkpoint: { throw AgentIOSDynamicWebRenderError.cancelled },
      resolver: { resolved = true; return true }))
    XCTAssertThrowsError(try AgentIOSWebRenderPreflight.resolve(deadline: .now(),
      isCancellationRequested: { false }, checkpoint: {}, resolver: { resolved = true; return true }))
    XCTAssertFalse(resolved)
  }

  func testRendererPreflightUsesCompletedResolutionWithoutNetwork() throws {
    XCTAssertTrue(try AgentIOSWebRenderPreflight.resolve(deadline: .now() + .seconds(2),
      isCancellationRequested: { false }, checkpoint: {}, resolver: { true }))
    XCTAssertFalse(try AgentIOSWebRenderPreflight.resolve(deadline: .now() + .seconds(2),
      isCancellationRequested: { false }, checkpoint: {}, resolver: { false }))
  }

  func testFallbackPolicyDetectsJavaScriptShellsAndChallenges() {
    XCTAssertEqual(
      AgentIOSDynamicWebFallbackPolicy.reason(
        contentType: "text/html",
        body: html("<p>Please enable JavaScript to continue.</p>")
      ),
      "javascript_required"
    )
    XCTAssertEqual(
      AgentIOSDynamicWebFallbackPolicy.reason(
        contentType: "text/html",
        body: html("<script src='/cf-chl-runtime.js'></script>")
      ),
      "managed_challenge"
    )
    XCTAssertEqual(
      AgentIOSDynamicWebFallbackPolicy.reason(
        contentType: "text/html",
        body: html("<div id='root'></div><script src='/application.js'></script>")
      ),
      "thin_javascript_shell"
    )
  }

  func testMeaningfulServerRenderedPageDoesNotTriggerFallback() {
    let content = String(repeating: "A server-rendered article with useful evidence. ", count: 30)
    XCTAssertNil(
      AgentIOSDynamicWebFallbackPolicy.reason(
        contentType: "text/html",
        body: html("<main><h1>Title</h1><p>\(content)</p></main><script src='/enhance.js'></script>")
      )
    )
  }

  func testThinShellUsesRendererExactlyOnce() throws {
    let transport = StubTransport { request in
      self.response(
        url: request.url,
        body: self.html("<div id='app'></div><script src='/bundle.js'></script>")
      )
    }
    let renderer = StubRenderer(result: .success(rendered("<article><h1>Rendered</h1><p>Dynamic body</p></article>")))
    let result = try invokeOpen(transport: transport, renderer: renderer)

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(renderer.calls, 1)
    XCTAssertEqual(result.output["render_mode"], .string("isolated_wkwebview"))
    XCTAssertEqual(result.output["dynamic_fallback_reason"], .string("thin_javascript_shell"))
    XCTAssertTrue((result.output["text"]?.stringValue ?? "").contains("Dynamic body"))
    XCTAssertEqual(result.metadata["javascript"], .bool(true))
  }

  func testRendererFailurePreservesStaticEvidenceAndDiagnostic() throws {
    let source = html("<div id='__next'></div><script src='/bundle.js'></script>")
    let transport = StubTransport { request in self.response(url: request.url, body: source) }
    let renderer = StubRenderer(result: .failure(.navigationFailed("browser unavailable")))
    let result = try invokeOpen(transport: transport, renderer: renderer)

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(renderer.calls, 1)
    XCTAssertEqual(result.output["render_mode"], .string("bounded_http"))
    XCTAssertEqual(result.output["dynamic_fallback_reason"], .string("thin_javascript_shell"))
    XCTAssertTrue((result.output["dynamic_fallback_error"]?.stringValue ?? "").contains("browser unavailable"))
    XCTAssertEqual(result.metadata["javascript"], .bool(false))
  }

  func testRecoverableStaticFailureUpgradesToRenderer() throws {
    let transport = StubTransport { _ in throw AgentIOSURLSessionWebError.transportFailed("offline") }
    let renderer = StubRenderer(result: .success(rendered("<article><p>Recovered dynamically</p></article>")))
    let result = try invokeOpen(transport: transport, renderer: renderer)

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(renderer.calls, 1)
    XCTAssertEqual(result.output["dynamic_fallback_reason"], .string("static_fetch_failed"))
    XCTAssertEqual(result.output["render_mode"], .string("isolated_wkwebview"))
    XCTAssertTrue((result.output["text"]?.stringValue ?? "").contains("Recovered dynamically"))
  }

  func testFailedDynamicFallbackDurationIncludesBothAttemptsWithoutChangingStaticTimestamp() throws {
    var tick: UInt64 = 100_000_000
    let transport = StubTransport { request in
      tick += 50_000_000
      return self.response(url: request.url, body: self.html("<div id='__next'></div><script src='/bundle.js'></script>"))
    }
    let renderer = StubRenderer(result: .failure(.navigationFailed("unavailable")), onRender: { tick += 200_000_000 })
    let result = try invokeOpen(transport: transport, renderer: renderer, monotonicNow: { tick })
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.output["duration_millis"], .int(250))
    XCTAssertEqual(result.metadata["duration_millis"], .int(250))
    XCTAssertEqual(result.output["retrieved_at_epoch_ms"], .int(1_000))
    XCTAssertNil(result.output["dynamic_render_duration_millis"])
    XCTAssertEqual(result.output["render_mode"], .string("bounded_http"))
  }

  func testSuccessfulFallbackKeepsRendererDurationSeparateFromTotalDuration() throws {
    var tick: UInt64 = 100_000_000
    let transport = StubTransport { request in
      tick += 10_000_000
      return self.response(url: request.url, body: self.html("<div id='app'></div><script src='/bundle.js'></script>"))
    }
    let renderer = StubRenderer(result: .success(rendered("<p>Rendered body</p>")), onRender: { tick += 25_000_000 })
    let result = try invokeOpen(transport: transport, renderer: renderer, monotonicNow: { tick })
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.output["duration_millis"], .int(35))
    XCTAssertEqual(result.output["dynamic_render_duration_millis"], .int(20))
    XCTAssertEqual(result.metadata["duration_millis"], .int(35))
  }

  func testUnavailableRendererPreservesStaticDurationAndSkipsRendering() throws {
    var tick: UInt64 = 100_000_000
    let transport = StubTransport { request in
      tick += 15_000_000
      return self.response(url: request.url, body: self.html("<div id='root'></div><script src='/bundle.js'></script>"))
    }
    let renderer = StubRenderer(result: .failure(.unavailable))
    renderer.isAvailable = false
    let result = try invokeOpen(transport: transport, renderer: renderer, monotonicNow: { tick })
    XCTAssertEqual(result.output["duration_millis"], .int(15))
    XCTAssertEqual(renderer.calls, 0)
    XCTAssertEqual(result.metadata["dynamic_fallback_attempted"], .bool(false))
    XCTAssertEqual(result.output["dynamic_fallback_error"], .string("renderer_unavailable"))
  }

  func testRenderURLPolicyRequiresPublicHTTPSAndSameOriginNavigation() {
    XCTAssertTrue(AgentIOSWebRenderURLPolicy.allows("https://example.com/article"))
    XCTAssertFalse(AgentIOSWebRenderURLPolicy.allows("http://example.com/article"))
    XCTAssertFalse(AgentIOSWebRenderURLPolicy.allows("https://localhost/article"))
    XCTAssertFalse(AgentIOSWebRenderURLPolicy.allows("https://127.0.0.1/article"))
    XCTAssertFalse(AgentIOSWebRenderURLPolicy.allows("https://100.64.0.1/article"))
    XCTAssertFalse(AgentIOSWebRenderURLPolicy.allows("https://198.18.0.1/article"))
    XCTAssertFalse(AgentIOSWebRenderURLPolicy.allows("https://[::1]/article"))
    XCTAssertFalse(AgentIOSWebRenderURLPolicy.allows("https://user@example.com/article"))
    XCTAssertTrue(AgentIOSWebRenderURLPolicy.allowsSubresource("data:text/plain,hello"))
    XCTAssertFalse(AgentIOSWebRenderURLPolicy.allowsSubresource("file:///tmp/page.html"))
    XCTAssertTrue(
      AgentIOSWebRenderURLPolicy.sameOrigin(
        initial: "https://example.com/article",
        candidate: "https://example.com/other?q=1"
      )
    )
    XCTAssertFalse(
      AgentIOSWebRenderURLPolicy.sameOrigin(
        initial: "https://example.com/article",
        candidate: "https://cdn.example.com/other"
      )
    )
    XCTAssertFalse(
      AgentIOSWebRenderURLPolicy.sameOrigin(
        initial: "https://example.com/article",
        candidate: "https://example.com:8443/other"
      )
    )
  }

  private func invokeOpen(
    transport: AgentIOSURLSessionWebTransporting,
    renderer: AgentIOSDynamicWebRendering,
    monotonicNow: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
  ) throws -> AgentNativeToolResult {
    let provider = AgentIOSURLSessionWebMediaToolProvider(
      transport: transport,
      dynamicRenderer: renderer,
      nowMillis: { 1_000 },
      monotonicNowNanoseconds: monotonicNow
    )
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: provider)
    )
    return registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.webOpen,
      input: ["url": .string("https://example.com/article")],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission],
        grantedConsents: [AgentIOSWebMediaNativeToolCatalog.publicWebConsent]
      ),
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1_000 })
    )
  }

  private func response(url: URL, body: Data) -> AgentIOSURLSessionWebResponse {
    AgentIOSURLSessionWebResponse(
      statusCode: 200,
      finalURL: url,
      headers: ["content-type": "text/html; charset=utf-8"],
      body: body,
      retrievedAtEpochMillis: 1_000
    )
  }

  private func rendered(_ body: String) -> AgentIOSDynamicWebRenderedPage {
    AgentIOSDynamicWebRenderedPage(
      finalURL: "https://example.com/article",
      contentType: "text/html; charset=utf-8",
      body: html(body),
      durationMillis: 20
    )
  }

  private func html(_ body: String) -> Data {
    Data("<!doctype html><html><body>\(body)</body></html>".utf8)
  }
}

private final class StubTransport: AgentIOSURLSessionWebTransporting {
  private let handler: (AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse

  init(handler: @escaping (AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse) {
    self.handler = handler
  }

  func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
    try handler(request)
  }
}

private final class StubRenderer: AgentIOSDynamicWebRendering {
  var isAvailable = true
  private(set) var calls = 0
  private let renderResult: Result<AgentIOSDynamicWebRenderedPage, AgentIOSDynamicWebRenderError>
  private let onRender: () -> Void

  init(result: Result<AgentIOSDynamicWebRenderedPage, AgentIOSDynamicWebRenderError>, onRender: @escaping () -> Void = {}) {
    renderResult = result
    self.onRender = onRender
  }

  func render(
    url: URL,
    maxBytes: Int64,
    timeoutMillis: Int64,
    isCancellationRequested: @escaping () -> Bool,
    checkpoint: @escaping () throws -> Void
  ) throws -> AgentIOSDynamicWebRenderedPage {
    calls += 1
    try checkpoint()
    onRender()
    return try renderResult.get()
  }
}
