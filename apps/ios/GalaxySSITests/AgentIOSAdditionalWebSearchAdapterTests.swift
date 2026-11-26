import Foundation
import XCTest
@testable import GalaxySSI

final class AgentIOSAdditionalWebSearchAdapterTests: XCTestCase {
  func testAllReferenceEnginesRegisterAndGoogleRemainsExplicitOnly() throws {
    XCTAssertEqual(AgentIOSHTMLWebSearchAdapter.entries.count, 17)
    XCTAssertEqual(AgentIOSWebIntelligenceSourceCatalog.baseSearchEngineIDs.count, 41)
    XCTAssertEqual(AgentIOSWebIntelligenceSourceCatalog.sourceCount, 288)
    let automatic = AgentIOSWebIntelligenceQueryRouting.select(query: "Fixture", requestedVerticals: [.general], requestedEngineIds: [])
    XCTAssertFalse(automatic.selected.contains { $0.id == "google" })
    let explicit = AgentIOSWebIntelligenceQueryRouting.select(query: "Fixture", requestedVerticals: [], requestedEngineIds: ["google"])
    XCTAssertEqual(explicit.selected.map(\.id), ["google"])
    for entry in AgentIOSHTMLWebSearchAdapter.entries + [AgentIOSArxivSearchAdapter.entry] {
      XCTAssertTrue(AgentIOSWebSearchEnginePolicy.supported.contains(entry.id))
      let url = try AgentIOSJSONWebSearchAdapter.requestURL(entry, query: "A+B & C", limit: 2)
      XCTAssertFalse(url.absoluteString.contains("+"))
      XCTAssertTrue(url.absoluteString.contains("%2B"))
      XCTAssertTrue(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains {
        $0.value?.hasSuffix("A+B & C") ?? false
      } ?? false)
    }
    let x = try XCTUnwrap(AgentIOSHTMLWebSearchAdapter.entry("x_public"))
    let url = try AgentIOSJSONWebSearchAdapter.requestURL(x, query: "A+B", limit: 2)
    XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "site:x.com/status A+B")
  }

  func testEveryGenericHTMLAdapterUsesTheExistingPublicSearchParser() throws {
    let social = Set(["x_public", "wechat_public", "zhihu_public", "xiaohongshu_public"])
    for entry in AgentIOSHTMLWebSearchAdapter.entries where !social.contains(entry.id) {
      let url = try AgentIOSJSONWebSearchAdapter.requestURL(entry, query: "Fixture", limit: 1)
      let hits = try AgentIOSHTMLWebSearchAdapter.parse(#"<h3><a href="https://source.test/article">Fixture</a></h3>"#,
        id: entry.id, baseURL: url.absoluteString, limit: 1)
      XCTAssertEqual(hits.map(\.url), ["https://source.test/article"], entry.id)
    }
  }

  func testSocialAdaptersRejectLookalikesAndNonArticlePathsBeforeLimit() throws {
    let fixtures: [(String, String, String)] = [
      ("x_public", "https://x.com/user", "https://twitter.com/user/status/42"),
      ("zhihu_public", "https://zhihu.com.evil.test/a", "https://zhuanlan.zhihu.com/p/42"),
      ("xiaohongshu_public", "https://xiaohongshu.com/user/42", "https://xiaohongshu.com/explore/42")
    ]
    for (id, rejected, accepted) in fixtures {
      let html = "<h3><a href='\(rejected)'>Wrong</a></h3><h3><a href='\(accepted)'>Fixture</a></h3>"
      let hits = try AgentIOSHTMLWebSearchAdapter.parse(html, id: id, baseURL: "https://html.duckduckgo.com/html/", limit: 1)
      XCTAssertEqual(hits.map(\.url), [accepted], id)
    }
    let wechat = #"<a href="https://evil.test/link">Wrong</a><a href="/link?url=fixture">Fixture</a><a href="https://mp.weixin.qq.com/s/42">Original</a>"#
    let hits = try AgentIOSHTMLWebSearchAdapter.parse(wechat, id: "wechat_public", baseURL: "https://weixin.sogou.com/weixin", limit: 2)
    XCTAssertEqual(hits.count, 2)
    XCTAssertEqual(hits.last?.url, "https://mp.weixin.qq.com/s/42")
  }

  func testAtomParsesNamespacesCDATAAlternateAndIDFallbackWithoutInventedDates() throws {
    let xml = #"<a:feed xmlns:a="http://www.w3.org/2005/Atom"><a:entry><a:title>Fixture</a:title><a:id>https://arxiv.org/abs/42</a:id><a:summary><![CDATA[<b>Summary</b>]]></a:summary><a:link rel="alternate" href="https://arxiv.org/abs/43"/><a:link rel="related" href="https://arxiv.org/pdf/43"/></a:entry><a:entry><a:title>Second</a:title><a:id>https://arxiv.org/abs/44</a:id></a:entry></a:feed>"#
    let hits = try AgentIOSArxivSearchAdapter.parse(Data(xml.utf8), limit: 2)
    XCTAssertEqual(hits.map(\.url), ["https://arxiv.org/abs/43", "https://arxiv.org/abs/44"])
    XCTAssertEqual(hits.first?.excerpt, "Summary")
    XCTAssertEqual(try AgentIOSArxivSearchAdapter.parse(Data(xml.utf8), limit: 1).count, 1)
  }

  func testAtomRejectsDTDInvalidFeedOversizedFieldsAndCancellation() {
    for xml in [#"<!DOCTYPE feed [<!ENTITY x SYSTEM "file:///private/fixture">]><feed><entry><title>&x;</title></entry></feed>"#,
      "<feed><entry></feed>", "<html/>", "<feed><entry><title>" + String(repeating: "x", count: 32_769) + "</title></entry></feed>"] {
      XCTAssertThrowsError(try AgentIOSArxivSearchAdapter.parse(Data(xml.utf8), limit: 1))
    }
    XCTAssertThrowsError(try AgentIOSArxivSearchAdapter.parse(Data("<feed/>".utf8), limit: 1, isCancelled: { true }))
    XCTAssertThrowsError(try AgentIOSArxivSearchAdapter.parse(Data(repeating: 65, count: 2_097_153), limit: 1))
  }

  func testDevDocsUsesBoundedAliasesAndReturnsOnlyLocalIndexReferences() {
    let hits = AgentIOSDevDocsSearchAdapter.search("reactjs node.js", limit: 10)
    XCTAssertEqual(hits.map(\.url), ["https://devdocs.io/react", "https://devdocs.io/node"])
    XCTAssertTrue(hits.allSatisfy { $0.retrievalStatus == "local_index_reference" })
    XCTAssertFalse(AgentIOSDevDocsSearchAdapter.search("unreactive", limit: 10).contains { $0.url == "https://devdocs.io/react" })
    XCTAssertEqual(AgentIOSDevDocsSearchAdapter.search("react", limit: 0), [])
  }

  func testActualRegistryDispatchesHTMLAndAtomButNeverRequestsLocalDevDocs() throws {
    for id in ["google", "brave_news", "arxiv", "devdocs"] {
      let transport = AdditionalSearchTransport()
      let result = try invoke(id: id, transport: transport)
      XCTAssertTrue(result.isSuccess, result.error?.message ?? id)
      if id == "devdocs" {
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertEqual(result.output["retrieval_status"], .string("local_index_reference"))
        XCTAssertNil(result.output["status_code"])
        XCTAssertEqual(result.output["results"]?.arrayValue?.first?.objectValue?["retrieval_status"], .string("local_index_reference"))
      } else { XCTAssertEqual(transport.requests.count, 1) }
    }
  }

  func testIntelligenceRegistryPreservesLocalEvidenceAndDoesNotClaimNetworkAttempt() throws {
    let transport = AdditionalSearchTransport()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("devdocs-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: url, secrets: InMemorySecretStore(), nowMillis: { 1000 })
    let media = AgentIOSURLSessionWebMediaToolProvider(transport: transport, sourceHealthStore: nil,
      imageCredentials: .init(secrets: InMemorySecretStore()), nowMillis: { 1000 })
    let provider = AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: media, cacheStore: cache, nowMillis: { 1000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider))
    let result = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: ["query": .string("React"), "engines": .array([.string("devdocs")]), "limit": .int(1)],
      context: .init(grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission],
        grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent]), hooks: .init(nowMillis: { 1000 }))
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    XCTAssertTrue(transport.requests.isEmpty)
    XCTAssertEqual(result.metadata["network_attempted"], .bool(false))
    XCTAssertEqual(result.output["results"]?.arrayValue?.first?.objectValue?["retrieval_status"], .string("local_index_reference"))
    XCTAssertEqual(result.output["evidence"]?.arrayValue?.first?.objectValue?["retrieval_status"], .string("local_index_reference"))
    XCTAssertEqual(result.output["source_receipts"]?.arrayValue?.first?.objectValue?["retrieved_at_epoch_ms"], .null)
  }

  private func invoke(id: String, transport: AdditionalSearchTransport) throws -> AgentNativeToolResult {
    let provider = AgentIOSURLSessionWebMediaToolProvider(transport: transport, sourceHealthStore: nil,
      imageCredentials: .init(secrets: InMemorySecretStore()), nowMillis: { 1000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: provider))
    return registry.invoke(AgentIOSWebMediaNativeToolCatalog.webSearch,
      input: ["query": .string("React Fixture"), "engines": .array([.string(id)]), "max_results": .int(1)],
      context: .init(grantedPermissions: [AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission],
        grantedConsents: [AgentIOSWebMediaNativeToolCatalog.publicWebConsent]), hooks: .init(nowMillis: { 1000 }))
  }
}

private final class AdditionalSearchTransport: AgentIOSURLSessionWebTransporting {
  private let lock = NSLock()
  private var saved: [AgentIOSURLSessionWebRequest] = []
  var requests: [AgentIOSURLSessionWebRequest] { lock.lock(); defer { lock.unlock() }; return saved }
  func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
    lock.lock(); saved.append(request); lock.unlock()
    let atom = request.url.host == "export.arxiv.org"
    let body = atom ? "<feed xmlns='http://www.w3.org/2005/Atom'><entry><title>React Fixture</title><id>https://arxiv.org/abs/42</id></entry></feed>" :
      "<h3><a href='https://source.test/react'>React Fixture</a></h3>"
    return .init(statusCode: 200, finalURL: request.url, headers: ["content-type": atom ? "application/atom+xml" : "text/html"],
      body: Data(body.utf8), retrievedAtEpochMillis: 1000)
  }
}
