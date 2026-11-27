import XCTest
@testable import GalaxySSI

final class AgentTeamComparisonSheetTests: XCTestCase {
  private let objective = """
    Compare alternative bids; retain the unit.
    | input | gate | west | east |
    |---|---|---|---|
    | price | < 2.10 | 2.10 | 2.09 |
    | reserve | >= 3 | 4 | 3 |
    | other | - | -4 | 2 |
    Both figures are hypothetical.
    """
  func testPrintedDecimalsDetermineWinnersAndRetainSourceText() throws {
    let sheet = try XCTUnwrap(AgentTeamComparisonSheet.evaluate(objective))
    XCTAssertEqual(sheet.winners, ["east"])
    XCTAssertTrue(sheet.plannerObjective.hasPrefix("Compare alternative bids"))
    XCTAssertTrue(sheet.plannerObjective.hasSuffix("Both figures are hypothetical."))
    let first = try XCTUnwrap(sheet.evidence["rows"]?.arrayValue?.first?.objectValue?["series"]?.objectValue)
    XCTAssertEqual(first["west"]?.objectValue?["value"], .string("2.10"))
    XCTAssertEqual(first["west"]?.objectValue?["pass"], .bool(false))
    XCTAssertEqual(AgentTeamComparisonSheet.evaluate(objective.replacingOccurrences(of: "< 2.10", with: ">= 2.10"))?.winners, ["west"])
    let swapped = objective.replacingOccurrences(of: "west | east", with: "east | west")
    XCTAssertEqual(AgentTeamComparisonSheet.evaluate(swapped)?.winners, ["west"])
  }
  func testInclusiveStrictNegativeAndNineDecimalPlacesUseExactArithmetic() {
    let sheet = "|input|gate|a|b|\n|---|---|---|---|\n|precision|> 0.100000001|0.100000001|0.100000002|\n|negative|<= -2.1|-2.1|-2.100000001|"
    XCTAssertEqual(AgentTeamComparisonSheet.evaluate(sheet)?.winners, ["b"])
    XCTAssertEqual(AgentTeamComparisonSheet.evaluate(sheet.replacingOccurrences(of: "> 0.100000001", with: ">= 0.100000001"))?.winners, ["a", "b"])
    XCTAssertEqual(AgentTeamComparisonSheet.evaluate(sheet.replacingOccurrences(of: "> 0.100000001", with: "< -9"))?.winners, [])
  }
  func testAmbiguousTablesUnitsDuplicateRowsAndMissingGatesAreNotInferred() {
    for raw in [objective.replacingOccurrences(of: "2.09", with: "2.09 mg"), objective.replacingOccurrences(of: "east", with: "west"),
      objective.replacingOccurrences(of: "reserve", with: "price"), objective.replacingOccurrences(of: "< 2.10", with: "~2.10"),
      objective.replacingOccurrences(of: "< 2.10", with: "-").replacingOccurrences(of: ">= 3", with: "-"), objective + "\n" + objective,
      objective.replacingOccurrences(of: "| reserve | >= 3 | 4 | 3 |", with: "| reserve | >= 3 | 4 |") ] {
      XCTAssertNil(AgentTeamComparisonSheet.evaluate(raw), raw)
    }
  }
  func testUnboundedOrNonCanonicalNumeralsDoNotBecomeHostEvidence() {
    for value in ["NaN", "1e-2", "+2.09", "02.09", "1000000000", "0.0000000001", "2,09"] {
      XCTAssertNil(AgentTeamComparisonSheet.evaluate(objective.replacingOccurrences(of: "2.09", with: value)))
    }
    XCTAssertNil(AgentTeamComparisonSheet.evaluate(String(repeating: "x", count: 8_001)))
  }
  func testLocalizedHeadersAreResourceBackedAndKeepTheSameComparison() {
    let input = GalaxySSILocalization.string("galaxyssi.conversation_team.table_input", fallback: "input", language: LanguagePolicySettings.zhCN)
    let gate = GalaxySSILocalization.string("galaxyssi.conversation_team.table_gate", fallback: "gate", language: LanguagePolicySettings.zhCN)
    let localized = objective.replacingOccurrences(of: "input | gate", with: input + " | " + gate)
    XCTAssertEqual(AgentTeamComparisonSheet.evaluate(localized)?.winners, ["east"])
  }
}
