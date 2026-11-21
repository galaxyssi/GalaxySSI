import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthReportRowValidationTests: XCTestCase {
  typealias Vision = GalaxySSIHealthReportVision
  typealias Value = AgentMcpJSONValue

  func testValidRowsSurviveUnsupportedMeasurementsUnitsFieldsAndDuplicates() throws {
    var unsupported = row; unsupported["metric"] = .string("unsupported")
    var unit = row; unit["unit"] = .string("invented")
    var fields = row; fields["values"] = .object(["value": .int(5)])
    let result = try parse(envelope([.object(row), .object(unsupported), .object(unit), .object(fields), .object(row)]))
    XCTAssertEqual(result.rows.count, 1); XCTAssertTrue(result.partial)
    XCTAssertEqual(result.rows.first?.values["value"], "<3.0")
    XCTAssertEqual(result.rejectedRows, ["unsupported_metric": 1, "invalid_unit": 1, "invalid_fields": 1, "duplicate": 1])
    XCTAssertNoThrow(try Vision.validateStored(result))
  }

  func testBadSourceControlTextDoesNotDiscardAnotherValidRow() throws {
    var bad = row; bad["source"] = .string("not\nallowed")
    let result = try parse(envelope([.object(row), .object(bad)]))
    XCTAssertEqual(result.rows.count, 1)
    XCTAssertEqual(result.rejectedRows?[Vision.RowIssue.invalidFields.rawValue], 1)
  }

  func testPrimitiveRowIsRejectedWithoutDiscardingGoodRow() throws {
    let result = try parse(envelope([.bool(true), .object(row)]))
    XCTAssertEqual(result.rows.count, 1)
    XCTAssertEqual(result.rejectedRows?[Vision.RowIssue.invalidFields.rawValue], 1)
  }

  func testNoSupportedRowsAndInvalidRowsAreDifferentFailures() {
    var unsupported = row; unsupported["metric"] = .string("unknown")
    expect(envelope([]), .noSupportedRows)
    expect(envelope([.object(unsupported)]), .noSupportedRows)
    var invalid = row; invalid["unit"] = .string("not a unit")
    expect(envelope([.object(invalid)]), .invalidRows)
    expect(envelope([.object(unsupported), .object(invalid)]), .invalidRows)
  }

  func testMalformedEnvelopeCannotBePartiallyAccepted() {
    var object = envelope([.object(row)])
    object["partial"] = .int(0); expect(object, .format)
    object["partial"] = .bool(false); object["extra"] = .string("not allowed"); expect(object, .format)
    object.removeValue(forKey: "extra"); object["collected"] = .string("time\ncontrol"); expect(object, .format)
  }

  func testModelCannotForgeRejectionCounts() {
    var object = envelope([.object(row)])
    object["rejected_rows"] = .object(["duplicate": .int(1)])
    expect(object, .format)
  }

  func testFencedJsonWithCaseAndPlainFenceIsAcceptedButOtherLanguagesAreNot() throws {
    let text = try encoded(envelope([.object(row)]))
    let result = try Vision.parse(text)
    XCTAssertEqual(try Vision.parse("```JSON\r\n" + text + "\r\n```"), result)
    XCTAssertEqual(try Vision.parse("```\n" + text + "\n```"), result)
    XCTAssertThrowsError(try Vision.parse("```javascript\n" + text + "\n```"))
    XCTAssertThrowsError(try Vision.parse(text + " trailing"))
  }

  func testOverLimitRowBatchFailsBeforeAcceptingRows() {
    expect(envelope(Array(repeating: .object(row), count: 81)), .format)
  }

  func testGoodRowIdentityAndPrintedContextAreUnchangedByRejectedNeighbors() throws {
    let first = try parse(envelope([.object(row)]))
    var bad = row; bad["metric"] = .string("unknown")
    let mixed = try parse(envelope([.object(bad), .object(row)]))
    XCTAssertEqual(first.rows, mixed.rows)
    XCTAssertEqual(first.rows.first?.id, mixed.rows.first?.id)
    XCTAssertEqual(first.collected, mixed.collected); XCTAssertEqual(first.fasting, mixed.fasting)
  }

  func testStoredCountersRoundTripOnlyThroughLocalValidation() throws {
    let result = try parse(envelope([.object(row), .object(row)]))
    let bytes = try JSONEncoder().encode(result)
    let restored = try JSONDecoder().decode(Vision.Result.self, from: bytes)
    XCTAssertEqual(restored, result)
    XCTAssertNoThrow(try Vision.validateStored(restored))
    XCTAssertThrowsError(try Vision.parse(String(decoding: bytes, as: UTF8.self)))
    var corrupt = result; corrupt.rejectedRows = ["duplicate": 80]
    XCTAssertThrowsError(try Vision.validateStored(corrupt))
    corrupt.rejectedRows = ["duplicate": 0]
    XCTAssertThrowsError(try Vision.validateStored(corrupt))
    corrupt.rejectedRows = ["not_a_reason": 1]
    XCTAssertThrowsError(try Vision.validateStored(corrupt))
  }

  func testLegacyEmptyStoredResultsRemainReadableButNewModelEmptyRepliesFail() throws {
    let old = Data(#"{"rows":[],"collected":"","partial":true}"#.utf8)
    let result = try JSONDecoder().decode(Vision.Result.self, from: old)
    XCTAssertNoThrow(try Vision.validateStored(result, allowLegacyEmpty: true))
    XCTAssertThrowsError(try Vision.validateStored(result))
    XCTAssertThrowsError(try Vision.parse(String(decoding: old, as: UTF8.self)))
  }

  private var row: AgentMcpJSONObject {
    ["metric": .string("glucose"), "values": .object(["value": .string("<3.0")]), "unit": .string("mmol/L"),
      "reference": .string("3.9-6.1"), "source": .string("GLU <3.0 mmol/L")]
  }
  private func envelope(_ rows: [Value]) -> AgentMcpJSONObject {
    ["rows": .array(rows), "collected": .string("2020-01-02 08:30:00Z"), "fasting": .string("fasting"), "partial": .bool(false)]
  }
  private func encoded(_ object: AgentMcpJSONObject) throws -> String { String(decoding: try JSONEncoder().encode(object), as: UTF8.self) }
  private func parse(_ object: AgentMcpJSONObject) throws -> Vision.Result { try Vision.parse(encoded(object)) }
  private func expect(_ object: AgentMcpJSONObject, _ problem: Vision.ReplyProblem) {
    XCTAssertThrowsError(try parse(object)) { XCTAssertEqual($0 as? Vision.ReplyProblem, problem) }
  }
}
