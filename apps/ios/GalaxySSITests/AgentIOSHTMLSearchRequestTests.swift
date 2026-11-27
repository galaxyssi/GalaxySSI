import Foundation
import XCTest
@testable import GalaxySSI

final class AgentIOSHTMLSearchRequestTests: XCTestCase {
  func testDesktopRepresentationIsConfinedToExactBaiduSearchEndpoint() throws {
    let policy = AgentIOSHTMLSearchRequestPolicy(source: "baidu")
    for value in ["https://www.baidu.com/s?wd=fixture", "https://www.baidu.com:443/s?wd=fixture"] {
      XCTAssertEqual(policy.headers(for: try XCTUnwrap(URL(string: value))), ["User-Agent": AgentIOSHTMLSearchRequestPolicy.baiduUserAgent])
    }
    for value in ["http://www.baidu.com/s", "https://www.baidu.com:8443/s", "https://user@www.baidu.com/s",
      "https://www.baidu.com.evil.test/s", "https://baidu.com/s", "https://www.baidu.com/", "https://www.baidu.com/s/",
      "https://www.baidu.com/%73", "https://www.baidu.com/link?url=fixture"] {
      XCTAssertTrue(policy.headers(for: try XCTUnwrap(URL(string: value))).isEmpty, value)
    }
    XCTAssertTrue(AgentIOSHTMLSearchRequestPolicy(source: "bing").headers(for: try XCTUnwrap(URL(string: "https://www.baidu.com/s"))).isEmpty)
  }
  func testActualRegistrySearchRequestsBaiduCardsAndPreservesQueryEncoding() throws {
    let transport = HTMLSearchRequestTransport()
    let result = try invoke(transport)
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    XCTAssertEqual(transport.requests.count, 1)
    let request = try XCTUnwrap(transport.requests.first)
    XCTAssertEqual(request.url.host, "www.baidu.com"); XCTAssertEqual(request.url.path, "/s")
    XCTAssertEqual(request.headers["User-Agent"], AgentIOSHTMLSearchRequestPolicy.baiduUserAgent)
    let parts = try XCTUnwrap(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
    XCTAssertTrue(parts.queryItems?.contains { $0.name == "wd" && $0.value == "Fixture & + / question" } == true)
    XCTAssertEqual(result.output["results"]?.arrayValue?.first?.objectValue?["url"], .string("https://public.example.test/article"))
    XCTAssertNil(request.headers["Authorization"]); XCTAssertNil(request.headers["X-Subscription-Token"])
  }
  func testCrossOriginAndDifferentPathRedirectsDoNotRetainSearchUserAgent() throws {
    for location in ["https://other.example.test/search", "https://www.baidu.com/link?url=fixture"] {
      let transport = HTMLSearchRequestTransport(redirect: location)
      _ = try invoke(transport)
      XCTAssertEqual(transport.requests.count, 2)
      XCTAssertEqual(transport.requests.first?.headers["User-Agent"], AgentIOSHTMLSearchRequestPolicy.baiduUserAgent)
      XCTAssertNil(transport.requests.last?.headers["User-Agent"])
    }
  }
  func testSameSearchEndpointRedirectReevaluatesThePolicyAndKeepsTheOriginalDeadline() throws {
    let transport = HTMLSearchRequestTransport(redirect: "https://www.baidu.com/s?wd=other")
    _ = try invoke(transport)
    XCTAssertEqual(transport.requests.count, 2)
    XCTAssertTrue(transport.requests.allSatisfy { $0.headers["User-Agent"] == AgentIOSHTMLSearchRequestPolicy.baiduUserAgent })
    XCTAssertLessThanOrEqual(transport.requests.last?.timeoutMillis ?? .max, transport.requests.first?.timeoutMillis ?? 0)
  }
  func testOrdinaryFetchToBaiduDoesNotAcquireSearchHeaders() throws {
    let transport = HTMLSearchRequestTransport()
    let registry = try registry(transport)
    _ = registry.invoke(AgentIOSWebMediaNativeToolCatalog.webFetch, input: ["url": .string("https://www.baidu.com/s?wd=article")],
      context: context(permissions: true), hooks: .init(nowMillis: { 1_000 }))
    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertNil(transport.requests.first?.headers["User-Agent"])
  }
  func testSearchPermissionDenialStillPreventsEveryRequest() throws {
    let transport = HTMLSearchRequestTransport()
    XCTAssertFalse(try invoke(transport, permissions: false).isSuccess)
    XCTAssertTrue(transport.requests.isEmpty)
  }
  private func registry(_ transport: HTMLSearchRequestTransport) throws -> AgentNativeToolRegistry {
    let provider = AgentIOSURLSessionWebMediaToolProvider(transport: transport, sourceHealthStore: nil, nowMillis: { 1_000 })
    return try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: provider))
  }
  private func context(permissions: Bool) -> AgentNativeToolInvocationContext {
    .init(grantedPermissions: permissions ? [AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission] : [],
      grantedConsents: permissions ? [AgentIOSWebMediaNativeToolCatalog.publicWebConsent] : [])
  }
  private func invoke(_ transport: HTMLSearchRequestTransport, permissions: Bool = true) throws -> AgentNativeToolResult {
    try registry(transport).invoke(AgentIOSWebMediaNativeToolCatalog.webSearch,
      input: ["query": .string("Fixture & + / question"), "engines": .array([.string("baidu")]), "max_results": .int(1)],
      context: context(permissions: permissions), hooks: .init(nowMillis: { 1_000 }))
  }
}

private final class HTMLSearchRequestTransport: AgentIOSURLSessionWebTransporting {
  let redirect: String?
  private let lock = NSLock()
  private var saved: [AgentIOSURLSessionWebRequest] = []
  var requests: [AgentIOSURLSessionWebRequest] { lock.lock(); defer { lock.unlock() }; return saved }
  init(redirect: String? = nil) { self.redirect = redirect }
  func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
    lock.lock(); saved.append(request); let first = saved.count == 1; lock.unlock()
    if first, let redirect {
      return .init(statusCode: 302, finalURL: request.url, headers: ["location": redirect], body: Data(), retrievedAtEpochMillis: 1_000)
    }
    let html = #"<html><body><div class="c-container" mu="https://public.example.test/article"><h3><a href="https://public.example.test/article">Fixture question</a></h3><div class="c-abstract">A synthetic result card with source and excerpt.</div></div></body></html>"#
    return .init(statusCode: 200, finalURL: request.url, headers: ["content-type": "text/html"], body: Data(html.utf8), retrievedAtEpochMillis: 1_000)
  }
}
