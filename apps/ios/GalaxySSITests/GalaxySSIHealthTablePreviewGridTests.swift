import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthTablePreviewGridTests: XCTestCase {
  func testGridBoundsAndEllipsisLeaveSourceUnchanged() {
    let text = String(repeating: "x", count: 600)
    let table = GalaxySSIHealthTableImport.Table(headers: (0..<13).map { "c\($0)" },
      rows: Array(repeating: Array(repeating: text, count: 13), count: 21))
    let sample = GalaxySSIHealthTableSourceSample(table, rowLimit: 20, cellLimit: 512)
    XCTAssertEqual(sample.rows.count, 20)
    XCTAssertEqual(sample.headers.count, 12)
    XCTAssertEqual(sample.rows[0][0].count, 512)
    XCTAssertTrue(sample.rows[0][0].hasSuffix("\u{2026}"))
    XCTAssertTrue(sample.limited)
    XCTAssertEqual(table.rows[0][0], text)
    XCTAssertEqual(table.rows.count, 21)
  }

  func testExactBoundsAreNotMarkedLimited() {
    let text = String(repeating: "x", count: 512)
    let table = GalaxySSIHealthTableImport.Table(headers: ["value", "time"],
      rows: Array(repeating: [text, ""], count: 20))
    let sample = GalaxySSIHealthTableSourceSample(table, rowLimit: 20, cellLimit: 512)
    XCTAssertFalse(sample.limited)
    XCTAssertEqual(sample.rows[0], [text, ""])
    XCTAssertEqual(sample.rowNumbers, Array(1...20))
  }

  func testSparseWorksheetKeepsPhysicalRowsAndFormulaCache() {
    let rows: [GalaxySSIHealthXLSX.SheetRow] = [
      .init(number: 3, cells: [2: "Time"], formulas: [], isoDates: [], formulaText: [:]),
      .init(number: 8, cells: [0: "61"], formulas: [0], isoDates: [], formulaText: [0: "1+60"])
    ]
    let sample = GalaxySSIHealthTableSourceSample(sheetRows: rows, rowLimit: 20, cellLimit: 512)
    XCTAssertEqual(sample.rowNumbers, [3, 8])
    XCTAssertEqual(sample.rows[0], ["", "", "Time"])
    XCTAssertEqual(sample.rows[1][0], "=1+60\n61")
    XCTAssertFalse(sample.limited)
    XCTAssertEqual(rows[1].cells[0], "61")
  }

  func testConfigurationCannotRemoveResourceBounds() {
    let table = GalaxySSIHealthTableImport.Table(headers: ["value", "time"],
      rows: Array(repeating: [String(repeating: "x", count: 700), ""], count: 40))
    let large = GalaxySSIHealthTableSourceSample(table, rowLimit: .max, cellLimit: .max)
    XCTAssertEqual(large.rows.count, 30)
    XCTAssertEqual(large.rows[0][0].count, 512)
    let small = GalaxySSIHealthTableSourceSample(table, rowLimit: 0, cellLimit: -1)
    XCTAssertEqual(small.rows.count, 1)
    XCTAssertEqual(small.rows[0][0], "x")
    XCTAssertTrue(small.limited)
  }
}
