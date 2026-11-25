import XCTest
@testable import GalaxySSI

final class AgentIOSImageSearchAdapterTests: XCTestCase {
  func testBraveHeadersAreConfinedToExactHTTPSAPIEndpoint() {
    let policy = AgentIOSImageSearchRequestPolicy(source: "brave_image", braveKey: "fixture-secret")
    XCTAssertEqual(policy.headers(for: URL(string: "https://api.search.brave.com/res/v1/images/search?q=a")!)["X-Subscription-Token"], "fixture-secret")
    for address in ["http://api.search.brave.com/res/v1/images/search", "https://evil.test/res/v1/images/search",
      "https://api.search.brave.com.evil.test/res/v1/images/search", "https://api.search.brave.com:8443/res/v1/images/search",
      "https://api.search.brave.com/other", "https://user:pass@api.search.brave.com/res/v1/images/search"] {
      XCTAssertNil(policy.headers(for: URL(string: address)!)["X-Subscription-Token"])
    }
    for key in ["", "key\r\nInjected: header", "contains space", String(repeating: "x", count: 8193)] {
      XCTAssertFalse(AgentIOSImageSearchRequestPolicy.validBraveKey(key))
    }
  }

  func testImageJSONParsersRetainDimensionsAndRejectUnsafeSourceRatherThanInventCitation() throws {
    let data = Data(#"{"results":[{"title":"<b>Subject</b>","url":"https://source.test/page","image":"https://image.test/full.jpg","thumbnail":"https://image.test/preview.jpg","width":640,"height":480},{"title":"Unsafe","url":"https://user:pass@source.test/page","image":"https://image.test/other.jpg"}]}"#.utf8)
    let hits = try AgentIOSPublicSearchParser.imageRows(data, brave: false, limit: 20)
    XCTAssertEqual(hits.count, 1)
    XCTAssertEqual(hits.first?.title, "Subject")
    XCTAssertEqual(hits.first?.image?["width"], .int(640))
    XCTAssertEqual(hits.first?.image?["thumbnail_url"], .string("https://image.test/preview.jpg"))
    let brave = try AgentIOSPublicSearchParser.imageRows(braveData(), brave: true, limit: 20)
    XCTAssertEqual(brave.first?.image?["url"], .string("https://image.test/brave.jpg"))
    XCTAssertEqual(brave.first?.image?["height"], .int(480))
    XCTAssertThrowsError(try AgentIOSPublicSearchParser.imageRows(Data("{}".utf8), brave: false, limit: 20))
    let privateImage = Data(#"{"results":[{"title":"Private","url":"https://source.test/page","image":"https://127.0.0.1/private.jpg"}]}"#.utf8)
    XCTAssertTrue(try AgentIOSPublicSearchParser.imageRows(privateImage, brave: false, limit: 20).isEmpty)
  }

  func testDuckDuckGoTokenIsBoundedInertText() throws {
    XCTAssertEqual(try AgentIOSImageSearchRequestPolicy.duckDuckGoToken("<script>vqd = '123&x=y';</script>"), "123&x=y")
    for value in ["<script>window.location='https://evil.test'</script>", "vqd='line\nbreak'",
      "vqd='" + String(repeating: "x", count: 257) + "'"] {
      XCTAssertThrowsError(try AgentIOSImageSearchRequestPolicy.duckDuckGoToken(value))
    }
  }

  func testBraveUsesStoredCredentialAndDoesNotForwardItAcrossRedirect() throws {
    let secrets = InMemorySecretStore()
    let credentials = AgentIOSWebIntelligenceCredentials(secrets: secrets)
    try credentials.setCredential(.braveAPIKey, value: "fixture-secret")
    let transport = ImageAdapterTransport { request in
      if request.url.host == "api.search.brave.com" {
        return .init(statusCode: 302, finalURL: request.url, headers: ["location": "https://redirect.test/results"], body: Data(), retrievedAtEpochMillis: 1000)
      }
      return self.response(request, data: self.braveData())
    }
    let result = try invoke("brave_image", transport: transport, credentials: credentials)
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    XCTAssertEqual(transport.requests.count, 2)
    XCTAssertEqual(transport.requests.first?.headers["X-Subscription-Token"], "fixture-secret")
    XCTAssertNil(transport.requests.last?.headers["X-Subscription-Token"])
    XCTAssertFalse(AgentMcpJSONCodec.stringify(result.output).contains("fixture-secret"))
  }

  func testExplicitUnconfiguredBraveFailsWithoutNetworkOrFallback() throws {
    let transport = ImageAdapterTransport { request in self.response(request, data: self.braveData()) }
    let result = try invoke("brave_image", transport: transport)
    XCTAssertEqual(result.error?.code, "search_source_credential_required")
    XCTAssertTrue(transport.requests.isEmpty)
  }

  func testDuckDuckGoUsesFixedSecondEndpointAndDoesNotPublishTokenURL() throws {
    let transport = ImageAdapterTransport { request in
      self.response(request, data: request.url.path == "/i.js"
        ? Data(#"{"results":[{"title":"Subject","url":"https://source.test/page","image":"https://image.test/ddg.jpg"}]}"#.utf8)
        : Data("<script>vqd='123&x=y';</script>".utf8))
    }
    let result = try invoke("duckduckgo_image", transport: transport)
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    XCTAssertEqual(transport.requests.map { $0.url.host }, ["duckduckgo.com", "duckduckgo.com"])
    let next = try XCTUnwrap(transport.requests.last)
    XCTAssertEqual(next.url.path, "/i.js")
    let query = try XCTUnwrap(URLComponents(url: next.url, resolvingAgainstBaseURL: false)?.queryItems)
    XCTAssertEqual(query.first { $0.name == "vqd" }?.value, "123&x=y")
    XCTAssertNil(query.first { $0.name == "x" })
    XCTAssertNotNil(next.headers["Referer"])
    XCTAssertFalse(AgentMcpJSONCodec.stringify(result.output).contains("123&x=y"))
    XCTAssertEqual(result.output["results"]?.arrayValue?.first?.objectValue?["lead_image_url"], .string("https://image.test/ddg.jpg"))
  }

  func testDuckDuckGoMissingTokenAndSpentBudgetDoNotStartSecondRequest() throws {
    for expired in [false, true] {
      let clock = ImageAdapterClock()
      let transport = ImageAdapterTransport { request in
        if expired { clock.set(10_000) }
        return self.response(request, data: Data((expired ? "vqd='token';" : "No token").utf8))
      }
      let result = try invoke("duckduckgo_image", transport: transport, now: { clock.now() })
      XCTAssertFalse(result.isSuccess)
      XCTAssertEqual(transport.requests.count, 1)
      if !expired { XCTAssertEqual(result.error?.retryable, true) }
    }
  }

  private func invoke(_ engine: String, transport: ImageAdapterTransport,
                      credentials: AgentIOSWebIntelligenceCredentials = .init(secrets: InMemorySecretStore()),
                      now: @escaping () -> Int64 = { 1000 }) throws -> AgentNativeToolResult {
    let provider = AgentIOSURLSessionWebMediaToolProvider(transport: transport, sourceHealthStore: nil,
      imageCredentials: credentials, nowMillis: now)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: provider))
    return registry.invoke(AgentIOSWebMediaNativeToolCatalog.webSearch,
      input: ["query": .string("Subject"), "engines": .array([.string(engine)]), "verticals": .array([.string("image")])],
      context: .init(grantedPermissions: [AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission],
        grantedConsents: [AgentIOSWebMediaNativeToolCatalog.publicWebConsent]),
      hooks: .init(nowMillis: now))
  }
  private func braveData() -> Data {
    Data(#"{"results":[{"title":"Subject","url":"https://source.test/page","properties":{"url":"https://image.test/brave.jpg","width":640,"height":480},"thumbnail":{"src":"https://image.test/preview.jpg"}}]}"#.utf8)
  }
  private func response(_ request: AgentIOSURLSessionWebRequest, data: Data) -> AgentIOSURLSessionWebResponse {
    .init(statusCode: 200, finalURL: request.url, headers: ["content-type": "application/json"], body: data, retrievedAtEpochMillis: 1000)
  }
}

private final class ImageAdapterTransport: AgentIOSURLSessionWebTransporting {
  var requests: [AgentIOSURLSessionWebRequest] = []
  let handler: (AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse
  init(_ handler: @escaping (AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse) { self.handler = handler }
  func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
    requests.append(request)
    return try handler(request)
  }
}

private final class ImageAdapterClock {
  private let lock = NSLock()
  private var value: Int64 = 1000
  func now() -> Int64 { lock.lock(); defer { lock.unlock() }; return value }
  func set(_ value: Int64) { lock.lock(); self.value = value; lock.unlock() }
}
