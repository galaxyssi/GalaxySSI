import XCTest
import SwiftSoup
@testable import GalaxySSI

final class AgentIOSPhonePublicHTMLAttachmentTests: XCTestCase {
  func testOriginalPageAssetLoaderKeepsPermissionDeadlineAndByteBounds() throws {
    final class Transport: AgentIOSURLSessionWebTransporting {
      var requests: [AgentIOSURLSessionWebRequest] = []
      func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
        requests.append(request)
        return .init(statusCode: 200, finalURL: request.url, headers: ["content-type": "image/png"],
          body: Data([1]), retrievedAtEpochMillis: 1_000)
      }
    }
    let transport = Transport()
    let provider = AgentIOSURLSessionWebMediaToolProvider(transport: transport, nowMillis: { 1_000 })
    let definition = try XCTUnwrap(AgentIOSWebIntelligenceNativeToolCatalog.definitions().first {
      $0.id == AgentIOSWebIntelligenceNativeToolCatalog.fetch
    })
    func invocation(allowed: Bool, deadline: Int64 = 1_500, cancelled: Bool = false) -> AgentNativeToolInvocation {
      .init(descriptor: definition.descriptor, input: [:], context: .init(
        grantedPermissions: allowed ? [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission] : [],
        grantedConsents: allowed ? [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent] : []),
        startedAtEpochMillis: 0, deadlineEpochMillis: deadline, nowMillis: { 1_000 },
        cancellationRequested: { cancelled }, progressReporter: { _, _ in })
    }
    for context in [invocation(allowed: false), invocation(allowed: true, deadline: 1_000),
      invocation(allowed: true, cancelled: true)] {
      XCTAssertThrowsError(try provider.originalPageAsset("https://example.com/image", maxBytes: 10, invocation: context))
    }
    XCTAssertTrue(transport.requests.isEmpty)
    XCTAssertThrowsError(try provider.originalPageAsset("https://127.0.0.1/image", maxBytes: 10, invocation: invocation(allowed: true)))
    XCTAssertTrue(transport.requests.isEmpty)
    let asset = try provider.originalPageAsset("https://example.com/image", maxBytes: 10, invocation: invocation(allowed: true))
    XCTAssertEqual(asset.data, Data([1]))
    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertEqual(transport.requests.first?.maxBodyBytes, 10)
    XCTAssertEqual(transport.requests.first?.timeoutMillis, 500)
  }

  func testOriginalPageRetainsOrderAndEmbedsLazyImages() throws {
    var requests: [String] = []
    let source = Data("<p>Before</p><img data-src='/image.png'><p>After</p>".utf8)
    let built = try AgentIOSOriginalPageDocument.build(source: source, url: "https://example.com/article", language: "en") { url, limit in
      requests.append(url)
      XCTAssertGreaterThan(limit, 0)
      return .init(contentType: "image/png", data: Data([1, 2, 3]), finalURL: url)
    }
    let doc = try SwiftSoup.parse(String(decoding: built.data, as: UTF8.self))
    XCTAssertEqual(try doc.select("body > p,body > img").array().prefix(3).map { $0.tagName() }, ["p", "img", "p"])
    XCTAssertEqual(try doc.select("img").first()?.attr("src"), "data:image/png;base64,AQID")
    XCTAssertEqual(requests, ["https://example.com/image.png"])
    XCTAssertEqual(built.embeddedImages, 1)
    XCTAssertEqual(built.missingAssets, 0)
  }

  func testOriginalPageRemovesActiveContentAndNetworkSideChannels() throws {
    let source = Data("""
      <meta http-equiv='refresh' content='0;url=https://bad.invalid'><base href='https://bad.invalid'>
      <script>throw 1</script><iframe src='https://bad.invalid'></iframe><svg onload='bad()'></svg>
      <form action='https://bad.invalid'><p onclick='bad()'>Keep</p><input></form>
      <a href='javascript:bad()' ping='https://bad.invalid'>No</a><a href='/ok'>Yes</a>
      <video src='https://bad.invalid/video'></video><img src='data:image/svg+xml;base64,PHN2Zz4='>
      """.utf8)
    let built = try AgentIOSOriginalPageDocument.build(source: source, url: "https://example.com/article", language: "en") { _, _ in nil }
    let doc = try SwiftSoup.parse(String(decoding: built.data, as: UTF8.self))
    XCTAssertTrue(try doc.select("script,iframe,svg,form,input,video,base,[onclick],[ping]").isEmpty())
    XCTAssertFalse(try doc.select("a").first()?.hasAttr("href") ?? true)
    XCTAssertEqual(try doc.select("a").array().last?.attr("href"), "https://example.com/ok")
    XCTAssertTrue(try doc.select("meta[http-equiv]").first()?.attr("content").contains("default-src 'none'") == true)
    XCTAssertFalse(try doc.select("img").first()?.hasAttr("src") ?? true)
    XCTAssertGreaterThan(built.missingAssets, 0)
  }

  func testOriginalPageStylesUseRedirectedBaseAndKeepCascadeOrder() throws {
    var requested: [String] = []
    let built = try AgentIOSOriginalPageDocument.build(source: Data("""
      <head><style>p{color:red}</style><link rel='stylesheet' href='/main.css'><style>p{color:green}</style></head>
      <body><p>Article</p></body>
      """.utf8), url: "https://example.com/article", language: "en") { address, _ in
      requested.append(address)
      if address.hasSuffix(".css") {
        return .init(contentType: "text/css", data: Data("p{color:blue;background:url(image.png)}".utf8), finalURL: "https://cdn.example.com/styles/main.css")
      }
      return .init(contentType: "image/png", data: Data([1]), finalURL: address)
    }
    let doc = try SwiftSoup.parse(String(decoding: built.data, as: UTF8.self))
    let styles = try doc.select("style").array().map { $0.data() }
    XCTAssertEqual(styles.count, 3)
    XCTAssertTrue(styles[0].contains("red"))
    XCTAssertTrue(styles[1].contains("blue"))
    XCTAssertTrue(styles[1].contains("data:image/png;base64,AQ=="))
    XCTAssertTrue(styles[2].contains("green"))
    XCTAssertEqual(requested, ["https://example.com/main.css", "https://cdn.example.com/styles/image.png"])
  }

  func testOriginalPageAssetFailuresAreDeduplicatedAndBounded() throws {
    var calls = 0
    let images = String(repeating: "<img src='/same.png'>", count: 10)
      + (0..<140).map { "<img src='/\($0).png'>" }.joined()
    let built = try AgentIOSOriginalPageDocument.build(source: Data(images.utf8), url: "https://example.com/article", language: "en") { _, limit in
      calls += 1
      XCTAssertLessThanOrEqual(limit, 8 * 1_024 * 1_024)
      return nil
    }
    XCTAssertEqual(calls, 128)
    XCTAssertEqual(built.embeddedImages, 0)
    XCTAssertEqual(built.missingAssets, 141)
  }

  func testOriginalPageRejectsInvalidSourceAndURLWithoutLoading() throws {
    var loaded = false
    for (data, url) in [(Data(), "https://example.com"), (Data([0xff]), "https://example.com"),
      (Data("<p>Test</p>".utf8), "file:///private/source"),
      (Data("<p>Test</p>".utf8), "https://user@example.com")] {
      XCTAssertThrowsError(try AgentIOSOriginalPageDocument.build(source: data, url: url, language: "en") { _, _ in loaded = true; return nil })
    }
    XCTAssertFalse(loaded)
  }

  @MainActor
  func testWeChatBrowserKeepsArticleNavigationSeparateFromCDNFrames() {
    XCTAssertNotNil(GalaxySSIWeChatBrowserSession.articleURL("https://mp.weixin.qq.com/s/article"))
    XCTAssertNil(GalaxySSIWeChatBrowserSession.articleURL("https://mp.weixin.qq.com:443/s/article"))
    XCTAssertNil(GalaxySSIWeChatBrowserSession.articleURL("https://mp.weixin.qq.com.evil.test/s/article"))
    let cdn = URL(string: "https://mmbiz.qpic.cn/image")
    XCTAssertFalse(GalaxySSIWeChatBrowserSession.allows(cdn, mainFrame: true))
    XCTAssertTrue(GalaxySSIWeChatBrowserSession.allows(cdn, mainFrame: false))
    XCTAssertFalse(GalaxySSIWeChatBrowserSession.allows(URL(string: "file:///test"), mainFrame: false))
  }

  func testWeChatPDFKeepsImageOrderAndRejectsVerificationPage() throws {
    let url = try XCTUnwrap(AgentIOSWeChatArticlePDF.articleURL("https://mp.weixin.qq.com/s/example"))
    let source = """
    <h1 id="activity-name">Article</h1><div id="js_content"><p>Before</p>
    <img data-src="https://mmbiz.qpic.cn/example"><p>After</p></div>
    """
    let (title, blocks) = try XCTUnwrap(AgentIOSPublicArticleParser.weChatPDFBlocks(url: url, source: source))
    XCTAssertEqual(title, "Article")
    XCTAssertEqual(blocks.count, 3)
    guard case .text("Before") = blocks.first,
          case .image("https://mmbiz.qpic.cn/example") = blocks.dropFirst().first,
          case .text("After") = blocks.last else { return XCTFail("Unexpected article block order") }
    XCTAssertNil(AgentIOSPublicArticleParser.weChatPDFBlocks(url: url, source: "<div id='js_verify'>Verify</div>"))
    XCTAssertNil(AgentIOSWeChatArticlePDF.articleURL("https://mp.weixin.qq.com.example.org/s/example"))
  }

  @MainActor
  func testScreenSourceValidatesWeChatArticleLinksWithoutRewritingQuery() {
    let url = "https://mp.weixin.qq.com/s?__biz=abc&mid=123&sn=xyz"
    XCTAssertEqual(GalaxySSIScreenAnalysisLinkPicker.validatedLink(" \(url)\n", weChatOnly: true), url)
    XCTAssertNotNil(GalaxySSIScreenAnalysisLinkPicker.validatedLink(
      "https://mp.weixin.qq.com/s/articleID", weChatOnly: true))
    for invalid in ["http://mp.weixin.qq.com/s/a", "https://mp.weixin.qq.com.evil.test/s/a",
      "https://user@mp.weixin.qq.com/s/a", "https://mp.weixin.qq.com:8443/s/a",
      "https://mp.weixin.qq.com/not-an-article"] {
      XCTAssertNil(GalaxySSIScreenAnalysisLinkPicker.validatedLink(invalid, weChatOnly: true))
    }
    XCTAssertNotNil(GalaxySSIScreenAnalysisLinkPicker.validatedLink(
      "https://example.com/article", weChatOnly: false))
  }

  @MainActor
  func testWeChatPasteRequiresExactlyOneVerifiedArticleAndPreservesQuery() throws {
    let article = "https://mp.weixin.qq.com/s?__biz=abc&mid=123&sn=%2Fopaque%2Bvalue"
    let other = "https://mp.weixin.qq.com/s/another"
    XCTAssertEqual(try GalaxySSIWeChatLinkPaste.resolve(["Article title\n\(article)\n", article]).get(), article)
    XCTAssertEqual(try GalaxySSIWeChatLinkPaste.resolve(["unrelated item", other]).get(), other)
    XCTAssertEqual(GalaxySSIWeChatLinkPaste.resolve([article, other]), .failure(.ambiguous))
    XCTAssertEqual(GalaxySSIWeChatLinkPaste.resolve(["\(article)\n\(other)"]), .failure(.ambiguous))
    for value in ["", "Copied to clipboard", "https://mp.weixin.qq.com.attacker.invalid/s/example",
      "https://mp.weixin.qq.com@attacker.invalid/s/example", "http://mp.weixin.qq.com/s/unsafe",
      "https://mp.weixin.qq.com/s", "https://mp.weixin.qq.com/s/example\u{0000}extra",
      String(repeating: "a", count: 16_385)] {
      XCTAssertEqual(GalaxySSIWeChatLinkPaste.resolve([value]), .failure(.invalid))
    }
  }

  func testSourceArchivePreservesBytesWithoutPublishingExecutableHTML() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = Data("<html><script>throw 1</script><p>Original</p></html>".utf8)
    let file = try AgentIOSOriginalHTMLSourceArchive.save(source, applicationSupport: root)
    XCTAssertEqual(file.pathExtension, "txt")
    XCTAssertEqual(file.deletingLastPathComponent(), GalaxySSIPrivateChatFiles.directory("OriginalWebSources", applicationSupport: root))
    XCTAssertEqual(try Data(contentsOf: file), source)
    XCTAssertEqual(try AgentIOSOriginalHTMLSourceArchive.save(source, applicationSupport: root), file)
    XCTAssertThrowsError(try AgentIOSOriginalHTMLSourceArchive.save(Data(), applicationSupport: root))
  }

  func testSeparatesASCIIURLFromAdjacentChineseInstruction() {
    let url = "https://mp.weixin.qq.com/s/sRAngxDkA5FNRteEhAUPVQ"
    let instruction = "\u{7406}\u{89e3}\u{548c}\u{603b}\u{7ed3}\u{4e00}\u{4e0b}\u{ff0c}" +
      "\u{4e3a}\u{5565}\u{5b83}\u{80fd}\u{81ea}\u{5df1}\u{8fdb}\u{5316}"

    XCTAssertEqual(AgentIOSPhonePublicHTMLAttachment.explicitPublicURLs(url + instruction), [url])
    XCTAssertEqual(AgentIOSPhonePublicHTMLAttachment.preferredPublicURL(url + instruction), url)
  }

  func testPreservesPercentEncodedInternationalURLPath() {
    XCTAssertEqual(
      AgentIOSPhonePublicHTMLAttachment.explicitPublicURLs(
        "Read https://example.com/%E4%B8%AD%E6%96%87?lang=zh-CN " +
          "\u{5e76}\u{603b}\u{7ed3}"
      ),
      ["https://example.com/%E4%B8%AD%E6%96%87?lang=zh-CN"]
    )
  }
}
