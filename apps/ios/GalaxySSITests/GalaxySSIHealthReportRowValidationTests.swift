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
    expect(envelope([.object(unsupported)]), .unsupportedMetrics)
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
    var corrupt = result; corrupt.rejectedRows = ["duplicate": 160]
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

  func testOmittedCountsDistinguishUnsupportedBlurAndAmbiguousSamples() throws {
    var object = envelope([])
    object["omitted"] = .object(["unsupported_metric": .int(2), "unreadable": .int(0)])
    expect(object, .unsupportedMetrics)
    object["omitted"] = .object(["unsupported_metric": .int(0), "unreadable": .int(2)])
    expect(object, .unreadableImage)
    object["ambiguous_sample"] = .bool(true); expect(object, .ambiguousSample)
    object["rows"] = .array([.object(row)]); expect(object, .format)
    object["ambiguous_sample"] = .bool(false)
    let usable = try parse(object)
    XCTAssertEqual(usable.rows.count, 1); XCTAssertEqual(usable.rejectedRows, ["unreadable": 2])
    XCTAssertTrue(usable.partial); XCTAssertNoThrow(try Vision.validateStored(usable))
    XCTAssertEqual(try JSONDecoder().decode(Vision.Result.self, from: JSONEncoder().encode(usable)), usable)
  }

  func testOmissionCountersRequireExactBoundedIntegerSchema() {
    let invalidCounts: [AgentMcpJSONObject] = [
      ["unsupported_metric": .int(81), "unreadable": .int(0)],
      ["unsupported_metric": .int(50), "unreadable": .int(31)],
      ["unsupported_metric": .int(-1), "unreadable": .int(0)],
      ["unsupported_metric": .string("1"), "unreadable": .int(0)],
      ["unsupported_metric": .bool(false), "unreadable": .int(0)],
      ["unsupported_metric": .int(0)],
      ["unsupported_metric": .int(0), "unreadable": .int(0), "names": .array([])]
    ]
    for counts in invalidCounts {
      var object = envelope([.object(row)]); object["omitted"] = .object(counts); expect(object, .format)
    }
  }

  func testEquivalentUnitSpellingsDoNotConvertValuesOrMixMeasurements() throws {
    let entries: [(GalaxySSIHealthMetric, String, String)] = [
      (.redBloodCells, "\u{00D7}10\u{00B9}\u{00B2}/l", "10^12/L"),
      (.neutrophilCount, "10*3/\u{03BC}L", "10^3/uL"), (.neutrophilPercent, "%", "%"),
      (.totalBilirubin, "\u{00B5}mol/l", "umol/L"), (.directBilirubin, "umol/L", "umol/L"),
      (.urea, "mmol/L", "mmol/L"), (.bloodUreaNitrogen, "mg/dl", "mg/dL")]
    var rows = entries.map { metric, unit, _ -> Value in
      var item = row; item["metric"] = .string(metric.rawValue); item["unit"] = .string(unit)
      return .object(item)
    }
    var invalid = row; invalid["metric"] = .string(GalaxySSIHealthMetric.neutrophilCount.rawValue); invalid["unit"] = .string("%")
    rows.append(.object(invalid))
    let result = try parse(envelope(rows))
    XCTAssertEqual(result.rows.map(\.unit), entries.map { $0.2 })
    XCTAssertEqual(result.rows.map(\.metric), entries.map { $0.0 })
    XCTAssertTrue(result.rows.allSatisfy { $0.values["value"] == "<3.0" })
    XCTAssertEqual(result.rejectedRows, ["invalid_unit": 1])
    XCTAssertNoThrow(try Vision.validateStored(result))
    XCTAssertNil(Vision.canonicalUnit("mg/L", metric: .bloodUreaNitrogen))
    XCTAssertNil(Vision.canonicalUnit("MG/DL", metric: .glucose))
    XCTAssertNil(Vision.canonicalUnit("mg/dL\n", metric: .glucose))
  }

  func testStoredRejectionsAllowOmissionsPlusAllReturnedRows() throws {
    var object = envelope(Array(repeating: .object(row), count: 80))
    object["omitted"] = .object(["unsupported_metric": .int(40), "unreadable": .int(40)])
    let result = try parse(object)
    XCTAssertEqual(result.rows.count, 1)
    XCTAssertEqual(result.rejectedRows?.values.reduce(0, +), 159)
    XCTAssertNoThrow(try Vision.validateStored(result))
  }

  func testExpandedCatalogNamesGroupsUnitsAndSearchAreSharedWithReportPrompt() throws {
    let added: [GalaxySSIHealthMetric] = [.redBloodCells, .hematocrit, .meanCorpuscularVolume,
      .meanCorpuscularHemoglobin, .meanCorpuscularHemoglobinConcentration, .redCellDistributionWidthCV,
      .redCellDistributionWidthSD, .meanPlateletVolume, .neutrophilCount, .neutrophilPercent,
      .lymphocyteCount, .lymphocytePercent, .albumin, .totalProtein, .totalBilirubin, .directBilirubin,
      .alkalinePhosphatase, .gammaGlutamylTransferase, .urea, .bloodUreaNitrogen]
    XCTAssertEqual(GalaxySSIHealthMetric.allCases.count, 47); XCTAssertEqual(added.count, 20)
    let prompt = GalaxySSIHealthReportVisionProvider.instructions
    XCTAssertLessThanOrEqual(prompt.utf8.count, 16_384)
    XCTAssertTrue(prompt.contains("ambiguous_sample")); XCTAssertTrue(prompt.contains("unsupported_metric"))
    for metric in added {
      XCTAssertTrue(metric.laboratory); XCTAssertFalse(metric.units.isEmpty)
      XCTAssertTrue(metric.matches(metric.entry.title))
      XCTAssertNotEqual(metric.title(language: "zh-CN"), metric.entry.title)
      XCTAssertTrue(prompt.contains(metric.rawValue + " ("))
      XCTAssertEqual(try JSONDecoder().decode(GalaxySSIHealthMetric.self, from: JSONEncoder().encode(metric)), metric)
    }
    XCTAssertEqual(GalaxySSIHealthMetric.redBloodCells.entry.group, .blood)
    XCTAssertEqual(GalaxySSIHealthMetric.albumin.entry.group, .liver)
    XCTAssertEqual(GalaxySSIHealthMetric.urea.entry.group, .kidney)
    XCTAssertTrue(GalaxySSIHealthMetric.neutrophilCount.matches("ANC"))
    XCTAssertTrue(GalaxySSIHealthMetric.bloodUreaNitrogen.matches("BUN"))
  }

  func testLocalOCRRejectsSpecimenAmbiguityAndSupportsNewUnits() throws {
    for line in ["RBC 4.7 10^12/L", "ALB 40 g/L", "TP 70 g/L",
                 "\u{7EA2}\u{7EC6}\u{80DE} 4.7 10^12/L", "\u{767D}\u{86CB}\u{767D} 40 g/L"] {
      XCTAssertNil(GalaxySSIHealthOCRLabRow.parse(line), line)
    }
    let samples: [(String, GalaxySSIHealthMetric, String)] = [
      ("Red blood cell count 4.7 \u{00D7}10\u{00B9}\u{00B2}/L", .redBloodCells, "10^12/L"),
      ("Red blood cell count 4.7 10^6/uL", .redBloodCells, "10^6/uL"),
      ("HCT 0.42 L/L", .hematocrit, "L/L"), ("MCV 90 fL", .meanCorpuscularVolume, "fL"),
      ("MCH 30 pg", .meanCorpuscularHemoglobin, "pg"),
      ("NEUT# 3.2 10^9/L", .neutrophilCount, "10^9/L"),
      ("NEUT% 60 %", .neutrophilPercent, "%"),
      ("Serum albumin 40 g/L", .albumin, "g/L"), ("BUN 12 mg/dL", .bloodUreaNitrogen, "mg/dL")]
    for (line, metric, unit) in samples {
      let parsed = try XCTUnwrap(GalaxySSIHealthOCRLabRow.parse(line), line)
      XCTAssertEqual(parsed.metric, metric); XCTAssertEqual(parsed.unit, unit)
    }
    XCTAssertNil(GalaxySSIHealthOCRLabRow.parse("NEUT# 60 %"))
    XCTAssertNil(GalaxySSIHealthOCRLabRow.parse("Urine albumin 40 g/L"))
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
