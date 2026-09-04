import XCTest
@testable import SignalASI

final class AgentIOSDynamicWebRendererTests: XCTestCase {
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
    renderer: AgentIOSDynamicWebRendering
  ) throws -> AgentNativeToolResult {
    let provider = AgentIOSURLSessionWebMediaToolProvider(
      transport: transport,
      dynamicRenderer: renderer,
      nowMillis: { 1_000 }
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

  init(result: Result<AgentIOSDynamicWebRenderedPage, AgentIOSDynamicWebRenderError>) {
    renderResult = result
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
    return try renderResult.get()
  }
}
