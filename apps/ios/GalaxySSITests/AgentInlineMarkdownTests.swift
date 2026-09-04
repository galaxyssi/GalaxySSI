import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentInlineMarkdownParsesBoldCodeAndLinksWithoutMarkers() {
    let segments = AgentInlineMarkdown.parse(
      "Today is **cloudy**. Run `status` and open [Shanghai Weather](https://sh.cma.gov.cn/)."
    )

    XCTAssertEqual(
      segments.map(\.text).joined(),
      "Today is cloudy. Run status and open Shanghai Weather."
    )
    XCTAssertEqual(segments.first { $0.text == "cloudy" }?.style, .bold)
    XCTAssertEqual(segments.first { $0.text == "status" }?.style, .code)
    XCTAssertEqual(
      segments.first { $0.text == "Shanghai Weather" }?.url,
      "https://sh.cma.gov.cn/"
    )
  }

  func testAgentInlineMarkdownParsesItalicAndStrikeWithoutAffectingBold() {
    let segments = AgentInlineMarkdown.parse("Use *care* and remove ~~noise~~ while **keeping this**.")

    XCTAssertEqual(segments.first { $0.text == "care" }?.style, .italic)
    XCTAssertEqual(segments.first { $0.text == "noise" }?.style, .strike)
    XCTAssertEqual(segments.first { $0.text == "keeping this" }?.style, .bold)
  }
}
