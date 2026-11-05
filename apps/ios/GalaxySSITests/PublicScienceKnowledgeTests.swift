import XCTest
@testable import GalaxySSI

final class PublicScienceKnowledgeTests: XCTestCase {
  func testKnownBookAndImageOriginsAreEnforced() {
    let biology = PublicScienceSource.biology
    XCTAssertTrue(biology.acceptsArticle(URL(string: "https://openstax.org/books/biology-2e/pages/3-4-proteins")!))
    XCTAssertFalse(biology.acceptsArticle(URL(string: "https://openstax.org/books/microbiology/pages/3-4-proteins")!))
    XCTAssertFalse(biology.acceptsArticle(URL(string: "https://openstax.org/books/biology-2e/pages/3-4-proteins?redirect=1")!))
    XCTAssertFalse(biology.acceptsArticle(URL(string: "https://openstax.org.evil.test/books/biology-2e/pages/3-4-proteins")!))
    XCTAssertTrue(biology.acceptsImage(URL(string: "https://openstax.org/apps/archive/version/resources/figure")!))
    XCTAssertFalse(biology.acceptsImage(URL(string: "https://openstax.org/tracking/figure")!))
    XCTAssertTrue(PublicScienceSource.molecule.acceptsImage(URL(string: "https://cdn.rcsb.org/pdb101/motm/1/figure.png")!))
    XCTAssertFalse(PublicScienceSource.molecule.acceptsImage(URL(string: "https://cdn.rcsb.org/pdb101/common/logo.png")!))
  }

  @MainActor
  func testCatalogUsesMatchingPublisherJSONAndOnlyNumberedSections() async throws {
    let html = """
      <script>window.__PRELOADED_STATE__ = {"content":{"book":{"slug":"biology-2e","tree":{"contents":[
        {"toc_target_type":"numbered-section","slug":"3-4-proteins","title":"Proteins &amp; folding"},
        {"toc_target_type":"numbered-section","slug":"../escape","title":"Invalid"},
        {"toc_target_type":"index","slug":"3-5-index","title":"Index"}
      ]}}}};</script>
      <a href="/books/biology-2e/pages/5-1-untrusted">Unrelated link</a>
      """
    let result = try await PublicScienceDOM().catalog(html: html, source: .biology)
    XCTAssertEqual(result.map(\.title), ["Proteins & folding"])
    XCTAssertEqual(result.first?.url.path, "/books/biology-2e/pages/3-4-proteins")
  }

  @MainActor
  func testArticleKeepsFigureWrappedByZoomButtonAndDoesNotLoadPublisherMarkup() async throws {
    let html = """
      <div id="main-content"><div data-type="page">
        <h1>Protein structure</h1>
        <nav><p>Navigation should not appear</p></nav>
        <script>document.body.innerHTML = '<h1>Injected</h1>';</script>
        <h2>Secondary structure</h2><p>Evidence in the article.</p>
        <figure><button class="image-button-wrapper">
          <img src="/apps/archive/build/resources/protein">
        </button><figcaption>Figure 3. Protein structure.</figcaption></figure>
        <img src="https://tracker.example/figure.png">
      </div></div>
      <script>window.__PRELOADED_STATE__ = {"content":{"book":{"slug":"biology-2e","title":"Biology 2e",
        "authors":[{"value":{"name":"Fixture author","display_at_top":true}}],
        "license":{"url":"http://creativecommons.org/licenses/by/4.0/","name":"CC BY 4.0"}}}};</script>
      """
    let url = URL(string: "https://openstax.org/books/biology-2e/pages/3-4-proteins")!
    let result = try await PublicScienceDOM().article(html: html, source: .biology, url: url)
    XCTAssertEqual(result.title, "Protein structure")
    XCTAssertEqual(result.sections.map(\.text), ["Secondary structure", "Evidence in the article."])
    XCTAssertEqual(result.figures.map(\.caption), ["Figure 3. Protein structure."])
    XCTAssertEqual(result.attribution, ["OpenStax", "Biology 2e", "Fixture author", "CC BY 4.0"])
    XCTAssertEqual(result.license?.scheme, "https")
  }
}
