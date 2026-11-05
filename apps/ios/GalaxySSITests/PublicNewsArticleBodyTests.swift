import XCTest
@testable import GalaxySSI

final class PublicNewsArticleBodyTests: XCTestCase {
  @MainActor
  func testVisualExtractionPreservesSourceOrderAndRejectsUntrustedImageHosts() async throws {
    let text = String(repeating: "The publisher includes an original report with figures and detailed measurements. ", count: 4)
    let html = """
      <meta property="og:image" content="/images/cover.png">
      <main><article><h1>Report</h1><h2>Section heading</h2>
        <p><strong>Important result</strong> \(text)</p>
        <figure><img src="/images/report.png"><figcaption>Original caption</figcaption></figure>
        <blockquote><p>\(text)</p></blockquote>
        <img src="https://tracker.example/pixel">
      </article></main>
      """
    let url = URL(string: "https://github.blog/article/")!
    let body = try await PublicNewsArticleBody.extract(html, articleURL: url)
    let presentation = try XCTUnwrap(body.presentation)
    XCTAssertEqual(presentation.styles.map(\.role), [.heading, .text, .quote])
    XCTAssertEqual(presentation.styles[1].emphasis, ["Important result"])
    XCTAssertEqual(presentation.figures.map(\.beforeParagraph), [2])
    XCTAssertEqual(presentation.figures.first?.caption, "Original caption")
    XCTAssertEqual(presentation.cover?.absoluteString, "https://github.blog/images/cover.png")
  }

  func testTranslatedSegmentsReassembleIntoOriginalParagraphPositions() {
    let original = PublicNewsOriginalBody(title: "Title",
      paragraphs: [String(repeating: "Long paragraph. ", count: 100), "Last paragraph"])
    var checkpoint = PublicNewsBodyCheckpoint(articleID: "fixture", source: original)
    checkpoint.translated = checkpoint.segments.indices.map { "part \($0)" }
    XCTAssertEqual(checkpoint.translatedDocument?.title, "part 0")
    XCTAssertEqual(checkpoint.translatedDocument?.paragraphs.count, 2)
    XCTAssertEqual(checkpoint.translatedDocument?.paragraphs.last, "part \(checkpoint.segments.count - 1)")
  }

  func testVisualEnrichmentKeepsValidatedTranslationCheckpoint() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PublicNewsBodyStore(root: root)
    var original = PublicNewsOriginalBody(title: "Publisher report", paragraphs: ["First paragraph."])
    let id = "https://github.blog/fixture"
    let staged = try await store.install(original, articleID: id)
    let translated = "\u{53D1}\u{5E03}\u{62A5}\u{544A}"
    _ = try await store.record(translated, index: 0, articleID: id, fingerprint: staged.fingerprint)
    original.presentation = .init(styles: [.init(role: .quote, emphasis: [])], figures: [], cover: nil)
    let enriched = try await store.install(original, articleID: id)
    XCTAssertEqual(enriched.fingerprint, staged.fingerprint)
    XCTAssertEqual(enriched.translated.first ?? nil, translated)
    XCTAssertEqual(enriched.source.presentation?.styles.first?.role, .quote)
  }

  func testRSSCoverUsesOnlyValidatedPublisherImageMetadata() throws {
    let source = PublicNewsSource(publisher: "GitHub", url: URL(string: "https://github.blog/feed/")!)
    let xml = """
      <rss xmlns:media="http://search.yahoo.com/mrss/"><channel>
        <item><title>Report</title><link>https://github.blog/article/</link>
          <media:thumbnail url="https://github.blog/images/report.png"/></item>
        <item><title>Report 2</title><link>https://github.blog/another/</link>
          <media:thumbnail url="https://untrusted.example/tracker.png"/></item>
      </channel></rss>
      """
    let items = try PublicNewsFeedParser.parse(Data(xml.utf8), source: source, now: Date())
    XCTAssertEqual(items.first?.coverURL?.absoluteString, "https://github.blog/images/report.png")
    XCTAssertNil(items.last?.coverURL)
  }

  func testNumericDriftAndUntranslatedOutputsAreRejected() {
    let source = "The sample contained 1,000 units and measured -2.5 degrees."
    XCTAssertTrue(PublicNewsTranslation.valid(
      "\u{6837}\u{54C1}\u{542B}\u{6709} 1000 \u{4E2A}\u{5355}\u{4F4D}\u{FF0C}\u{6D4B}\u{5F97} -2.5 \u{5EA6}\u{3002}", for: source
    ))
    XCTAssertFalse(PublicNewsTranslation.valid(
      "\u{6837}\u{54C1}\u{542B}\u{6709} 1000 \u{4E2A}\u{5355}\u{4F4D}\u{FF0C}\u{6D4B}\u{5F97} 2.5 \u{5EA6}\u{3002}", for: source
    ))
    XCTAssertFalse(PublicNewsTranslation.valid(source, for: source))
  }

  func testCheckpointResumesAndRejectsWriteFromChangedSource() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = PublicNewsBodyStore(root: root)
    let id = "https://github.blog/fixture"
    let original = PublicNewsOriginalBody(title: "Test title", paragraphs: ["First paragraph 7.", "Second paragraph."])
    let staged = try await first.install(original, articleID: id)
    _ = try await first.record("\u{6D4B}\u{8BD5}\u{6807}\u{9898}", index: 0, articleID: id, fingerprint: staged.fingerprint)
    let reopened = PublicNewsBodyStore(root: root)
    let resumed = try await reopened.install(original, articleID: id)
    XCTAssertEqual(resumed.translated.compactMap { $0 }.count, 1)
    XCTAssertNil(resumed.completed)
    _ = try await reopened.record("\u{7B2C}\u{4E00}\u{6BB5} 7\u{3002}", index: 1, articleID: id, fingerprint: staged.fingerprint)
    let complete = try await reopened.record(
      "\u{7B2C}\u{4E8C}\u{6BB5}\u{3002}", index: 2, articleID: id, fingerprint: staged.fingerprint
    )
    XCTAssertEqual(complete.completed?.count, 3)
    let replaced = try await reopened.install(
      .init(title: original.title, paragraphs: ["Changed article."]), articleID: id
    )
    XCTAssertNotEqual(replaced.fingerprint, staged.fingerprint)
    XCTAssertNil(replaced.completed)
    do {
      _ = try await reopened.record("\u{6D4B}\u{8BD5}", index: 0, articleID: id, fingerprint: staged.fingerprint)
      XCTFail("An old source must not update its replacement")
    } catch PublicNewsArticleBodyError.changedSource {}
  }

  @MainActor
  func testStaticArticleExtractionIgnoresNavigationAndRejectsPaywall() async throws {
    let para = String(repeating: "The original publisher paragraph reports a measurable outcome. ", count: 3)
    let html = "<main><article><h1>Fixture</h1><nav><p>Ignore menu</p></nav><p>\(para)</p><p>\(para)</p></article></main>"
    let body = try await PublicNewsArticleBody.extract(html)
    XCTAssertEqual(body.title, "Fixture")
    XCTAssertEqual(body.paragraphs.count, 2)
    do {
      _ = try await PublicNewsArticleBody.extract("<meta itemprop='isAccessibleForFree' content='false'>" + html)
      XCTFail("Paywalled articles must not be staged")
    } catch {
      // No document may be staged from this response.
    }
    XCTAssertFalse(PublicNewsArticleBody.supports(URL(string: "https://github.blog.example/a")!))
  }
}
