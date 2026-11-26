import Foundation
import XCTest
@testable import GalaxySSI

final class AgentIOSJSONWebSearchAdapterTests: XCTestCase {
  func testAllSixteenNativeJSONAdaptersHaveStructuredQueryEncodingAndRegistration() throws {
    let query = "A&B # + /? GALAXYSSI_LIMIT \u{4e2d}"
    XCTAssertEqual(AgentIOSJSONWebSearchAdapter.entries.count, 16)
    for entry in AgentIOSJSONWebSearchAdapter.entries {
      XCTAssertTrue(AgentIOSWebSearchEnginePolicy.supported.contains(entry.id))
      let url = try AgentIOSJSONWebSearchAdapter.requestURL(entry, query: query, limit: 999)
      let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
      XCTAssertEqual(parts.scheme, "https")
      XCTAssertNil(parts.fragment)
      XCTAssertNil(parts.user)
      let items = parts.queryItems ?? []
      XCTAssertTrue(items.contains { $0.value == query })
      XCTAssertFalse(items.contains { $0.name == "B" })
      XCTAssertFalse(items.contains { $0.value == "999" })
    }
  }

  func testAllSixteenResponseShapesProduceNativeHits() throws {
    let fixtures: [String: String] = [
      "marginalia": #"{"results":[{"title":"A","url":"https://example.test/a","description":"D"}]}"#,
      "wikipedia": #"{"query":{"search":[{"title":"A","pageid":42,"snippet":"<b>D</b>"}]}}"#,
      "wikipedia_zh": #"{"query":{"search":[{"title":"A","pageid":42,"snippet":"D"}]}}"#,
      "github": #"{"items":[{"full_name":"org/repo","html_url":"https://github.com/org/repo","description":"D"}]}"#,
      "github_code": #"{"items":[{"path":"src/A.swift","html_url":"https://github.com/org/repo/blob/main/src/A.swift","repository":{"full_name":"org/repo","description":"D"}}]}"#,
      "gitlab": #"[{"path_with_namespace":"org/repo","web_url":"https://gitlab.com/org/repo","description":"D"}]"#,
      "stackoverflow": #"{"items":[{"title":"A &amp; B","link":"https://stackoverflow.com/questions/42","excerpt":"D"}]}"#,
      "hacker_news": #"{"hits":[{"story_title":"A","objectID":"42","comment_text":"D"}]}"#,
      "lobsters": #"[{"title":"A","url":"https://example.test/a","description":"D"}]"#,
      "reddit": #"{"data":{"children":[{"data":{"title":"A","permalink":"/r/test/comments/42/a/","selftext":"D"}}]}}"#,
      "crossref": #"{"message":{"items":[{"title":["A"],"URL":"https://doi.org/10.example/42","abstract":"<jats:p>D</jats:p>"}]}}"#,
      "semantic_scholar": #"{"data":[{"title":"A","url":"https://example.test/a","abstract":"D"}]}"#,
      "pubmed": #"{"esearchresult":{"idlist":["42"]}}"#,
      "crates_io": #"{"crates":[{"name":"fixture-crate","description":"D"}]}"#,
      "npm": #"{"objects":[{"package":{"name":"fixture","links":{"npm":"https://www.npmjs.com/package/fixture"},"description":"D"}}]}"#,
      "mdn": #"{"documents":[{"title":"A","mdn_url":"/en-US/docs/Web/API","summary":"D"}]}"#
    ]
    XCTAssertEqual(Set(fixtures.keys), Set(AgentIOSJSONWebSearchAdapter.entries.map(\.id)))
    for (source, json) in fixtures {
      let hits = try AgentIOSJSONWebSearchAdapter.parse(Data(json.utf8), source: source, limit: 2)
      XCTAssertEqual(hits.count, 1, source)
      XCTAssertFalse(hits.first?.title.isEmpty ?? true, source)
      XCTAssertTrue(hits.first?.url.hasPrefix("https://") ?? false, source)
      XCTAssertNil(hits.first?.image, source)
    }
  }

  func testInvalidEnvelopeIsFailureButValidEmptyArrayIsEmpty() throws {
    XCTAssertThrowsError(try AgentIOSJSONWebSearchAdapter.parse(Data(#"{"message":"rate limited"}"#.utf8), source: "github", limit: 3))
    XCTAssertThrowsError(try AgentIOSJSONWebSearchAdapter.parse(Data("[]".utf8), source: "unknown", limit: 3))
    XCTAssertThrowsError(try AgentIOSJSONWebSearchAdapter.parse(Data("<html>Login</html>".utf8), source: "github", limit: 3))
    XCTAssertEqual(try AgentIOSJSONWebSearchAdapter.parse(Data(#"{"items":[]}"#.utf8), source: "github", limit: 3), [])
  }

  func testInvalidURLsAndTitlesAreFilteredBeforeLimitAndDeduplication() throws {
    let json = #"{"items":[{"full_name":"bad","html_url":"https://user:pass@example.test/a"},{"full_name":"bad","html_url":"https://127.0.0.1/a"},{"full_name":"","html_url":"https://example.test/good"},{"full_name":"Good","html_url":"https://example.test/good#one"},{"full_name":"Duplicate","html_url":"https://example.test/good#two"}]}"#
    let hits = try AgentIOSJSONWebSearchAdapter.parse(Data(json.utf8), source: "github", limit: 1)
    XCTAssertEqual(hits.map(\.title), ["Good"])
    XCTAssertEqual(hits.map(\.url), ["https://example.test/good"])
    let ids = #"{"query":{"search":[{"title":"boolean","pageid":true},{"title":"negative","pageid":-1},{"title":"fraction","pageid":1.5},{"title":"Good","pageid":42}]}}"#
    XCTAssertEqual(try AgentIOSJSONWebSearchAdapter.parse(Data(ids.utf8), source: "wikipedia", limit: 1).map(\.title), ["Good"])
  }

  func testAPIRequestsUseActualRegistryAndPublicNetworkScope() throws {
    let transport = JSONAdapterTransport(status: 200)
    let result = try invoke(transport: transport, permissions: true)
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertEqual(transport.requests.first?.url.host, "api.github.com")
    XCTAssertEqual(transport.requests.first?.url.path, "/search/repositories")
    XCTAssertNil(transport.requests.first?.headers["Authorization"])
    XCTAssertEqual(result.output["results"]?.arrayValue?.count, 1)
    let denied = JSONAdapterTransport(status: 200)
    XCTAssertFalse(try invoke(transport: denied, permissions: false).isSuccess)
    XCTAssertTrue(denied.requests.isEmpty)
  }

  func testHTTPAuthenticationFailureNeverFallsBackToAnotherProvider() throws {
    let transport = JSONAdapterTransport(status: 401)
    XCTAssertFalse(try invoke(transport: transport, permissions: true).isSuccess)
    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertEqual(transport.requests.first?.url.host, "api.github.com")
  }

  func testHeadersAreScopedToExactHTTPSAPIEndpointAndRejectInvalidToken() throws {
    let policy = AgentIOSJSONWebSearchRequestPolicy(source: "github", githubToken: "fixture-token")
    XCTAssertEqual(policy.headers(for: try XCTUnwrap(URL(string: "https://api.github.com/search/repositories?q=test")))["Authorization"], "Bearer fixture-token")
    for value in ["http://api.github.com/search/repositories", "https://user@api.github.com/search/repositories",
      "https://api.github.com:8443/search/repositories", "https://api.github.com.evil.test/search/repositories",
      "https://api.github.com/search/code", "https://api.github.com/search/repositories/redirect"] {
      XCTAssertTrue(policy.headers(for: try XCTUnwrap(URL(string: value))).isEmpty)
    }
    for token in ["has space", "line\r\nbreak", String(repeating: "a", count: 8193)] {
      XCTAssertNil(AgentIOSJSONWebSearchRequestPolicy(source: "github", githubToken: token)
        .headers(for: try XCTUnwrap(URL(string: "https://api.github.com/search/repositories")))["Authorization"])
    }
    let marginalia = AgentIOSJSONWebSearchRequestPolicy(source: "marginalia", githubToken: "fixture-token")
    let headers = marginalia.headers(for: try XCTUnwrap(URL(string: "https://api2.marginalia-search.com/search?query=test")))
    XCTAssertEqual(headers["API-Key"], "public")
    XCTAssertNil(headers["Authorization"])
  }

  func testConfiguredGitHubCredentialIsNotForwardedOrPublishedAcrossRedirect() throws {
    let credentials = AgentIOSWebIntelligenceCredentials(secrets: InMemorySecretStore())
    try credentials.setCredential(.githubToken, value: "fixture-token")
    for redirect in ["https://other.test/search/repositories", "https://api.github.com/other"] {
      let transport = JSONAdapterTransport(status: 200, redirect: redirect)
      let result = try invoke(transport: transport, permissions: true, credentials: credentials)
      XCTAssertEqual(transport.requests.count, 2)
      XCTAssertEqual(transport.requests.first?.headers["Authorization"], "Bearer fixture-token")
      XCTAssertEqual(transport.requests.first?.headers["X-GitHub-Api-Version"], "2022-11-28")
      XCTAssertNil(transport.requests.last?.headers["Authorization"])
      XCTAssertNil(transport.requests.last?.headers["X-GitHub-Api-Version"])
      XCTAssertFalse(AgentMcpJSONCodec.stringify(result.output).contains("fixture-token"))
    }
  }

  private func invoke(transport: JSONAdapterTransport, permissions: Bool,
    credentials: AgentIOSWebIntelligenceCredentials = .init(secrets: InMemorySecretStore())) throws -> AgentNativeToolResult {
    let provider = AgentIOSURLSessionWebMediaToolProvider(transport: transport, sourceHealthStore: nil,
      imageCredentials: credentials, nowMillis: { 1_000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: provider))
    return registry.invoke(AgentIOSWebMediaNativeToolCatalog.webSearch,
      input: ["query": .string("Fixture repo"), "engines": .array([.string("github")]), "max_results": .int(1)],
      context: .init(grantedPermissions: permissions ? [AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission] : [],
        grantedConsents: permissions ? [AgentIOSWebMediaNativeToolCatalog.publicWebConsent] : []), hooks: .init(nowMillis: { 1_000 }))
  }
}

private final class JSONAdapterTransport: AgentIOSURLSessionWebTransporting {
  let status: Int
  let redirect: String?
  private let lock = NSLock()
  private var saved: [AgentIOSURLSessionWebRequest] = []
  var requests: [AgentIOSURLSessionWebRequest] { lock.lock(); defer { lock.unlock() }; return saved }
  init(status: Int, redirect: String? = nil) { self.status = status; self.redirect = redirect }
  func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
    lock.lock(); saved.append(request); let first = saved.count == 1; lock.unlock()
    if first, let redirect {
      return .init(statusCode: 302, finalURL: request.url, headers: ["location": redirect], body: Data(), retrievedAtEpochMillis: 1_000)
    }
    let body = #"{"items":[{"full_name":"Fixture repo","html_url":"https://github.com/fixture/repo","description":"Fixture repo"}]}"#
    return .init(statusCode: status, finalURL: request.url, headers: ["content-type": "application/json"], body: Data(body.utf8), retrievedAtEpochMillis: 1_000)
  }
}
