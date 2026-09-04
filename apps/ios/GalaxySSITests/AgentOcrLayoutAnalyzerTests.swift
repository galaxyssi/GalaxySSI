import XCTest
@testable import GalaxySSI

final class AgentOcrLayoutAnalyzerTests: XCTestCase {
  func testAutoModeMergesMixedScriptsWithoutDuplicatingSpatialMatches() {
    let chinese = AgentOcrCandidate(
      script: .chinese,
      fallbackText: "GalaxySSI \u{63a7}\u{5236}\u{4e2d}\u{5fc3}",
      lines: [
        line("GalaxySSI", left: 10, top: 10, right: 150, bottom: 40, language: "zh", block: 0),
        line("\u{63a7}\u{5236}\u{4e2d}\u{5fc3}", left: 10, top: 55, right: 170, bottom: 90, language: "zh", block: 0)
      ]
    )
    let latin = AgentOcrCandidate(
      script: .latin,
      fallbackText: "GalaxySSI Ready",
      lines: [
        line("GalaxySSI", left: 12, top: 11, right: 151, bottom: 41, language: "Latn", block: 0),
        line("Ready", left: 10, top: 105, right: 100, bottom: 135, language: "Latn", block: 1)
      ]
    )

    let merged = AgentOcrLayoutAnalyzer.merge(candidates: [chinese, latin], width: 1_080, height: 1_920)

    XCTAssertEqual(merged.lines.filter { $0.text == "GalaxySSI" }.count, 1)
    XCTAssertTrue(merged.text.contains("\u{63a7}\u{5236}\u{4e2d}\u{5fc3}"))
    XCTAssertTrue(merged.text.contains("Ready"))
    XCTAssertTrue(Set(merged.languageTags).isSuperset(of: ["zh", "Latn"]))
    XCTAssertTrue(merged.warnings.contains("mixed_script"))
  }

  func testLayoutProducesBoundedBlocksAndQualitySignals() {
    let candidate = AgentOcrCandidate(
      script: .latin,
      fallbackText: "Title\nFirst line\nSecond line",
      lines: [
        line("Title", left: 20, top: 10, right: 300, bottom: 55, language: "Latn", block: 0),
        line("First line", left: 20, top: 90, right: 320, bottom: 125, language: "Latn", block: 1),
        line("Second line", left: 20, top: 130, right: 340, bottom: 165, language: "Latn", block: 1)
      ]
    )

    let merged = AgentOcrLayoutAnalyzer.merge(candidates: [candidate], width: 1_080, height: 1_920)

    XCTAssertEqual(merged.blocks.count, 2)
    XCTAssertEqual(merged.blocks.last?.lineCount, 2)
    XCTAssertEqual(merged.layoutMode, "single_column")
    XCTAssertTrue((0.0...1.0).contains(merged.qualityScore))
    XCTAssertFalse(merged.warnings.contains("low_ocr_quality"))
  }

  func testEmptyOrInvalidCandidatesReturnNoReadableTextWarning() {
    let merged = AgentOcrLayoutAnalyzer.merge(
      candidates: [
        AgentOcrCandidate(
          script: .latin,
          fallbackText: " ",
          lines: [
            line("Ignored", left: -1, top: 0, right: 10, bottom: 10, language: "Latn", block: 0)
          ]
        )
      ],
      width: 320,
      height: 240
    )

    XCTAssertEqual(merged.layoutMode, "empty")
    XCTAssertEqual(merged.qualityScore, 0.0)
    XCTAssertEqual(merged.warnings, ["no_readable_text"])
  }

  private func line(
    _ text: String,
    left: Int,
    top: Int,
    right: Int,
    bottom: Int,
    language: String,
    block: Int
  ) -> AgentOcrLine {
    AgentOcrLine(
      text: text,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      languageTag: language,
      blockIndex: block,
      lineIndex: 0
    )
  }
}
