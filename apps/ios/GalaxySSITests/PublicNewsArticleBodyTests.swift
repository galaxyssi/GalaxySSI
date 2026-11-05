import XCTest
@testable import GalaxySSI

final class PublicNewsArticleBodyTests: XCTestCase {
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
