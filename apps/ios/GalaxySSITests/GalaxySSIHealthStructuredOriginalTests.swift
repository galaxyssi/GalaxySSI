import Foundation
import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthStructuredOriginalTests: XCTestCase {
  func testJSONPreservesRawNumbersOrderAndNestedDelimiters() throws {
    let data = Data(#"{"id":12345678901234567890123456789012345678901234567890,"n":1.2300e+04,"nested":{"s":"a,b:c","a":[1,2]},"flag":true}"#.utf8)
    let result = try GalaxySSIHealthStructuredOriginal.read(data, fileExtension: "json")
    XCTAssertEqual(result.sample.rows.map { $0[0] }, ["id", "n", "nested", "flag"])
    XCTAssertEqual(result.sample.rows[0][1], "12345678901234567890123456789012345678901234567890")
    XCTAssertEqual(result.sample.rows[1][1], "1.2300e+04")
    XCTAssertEqual(result.sample.rows[2][1], #"{"s":"a,b:c","a":[1,2]}"#)
    XCTAssertEqual(result.sample.rows[3][1], "true")
  }

  func testJSONScalarArrayEmptyAndMalformedRoots() throws {
    for scalar in ["null", "true", #""a,b:c\"d""#, "-0.00e-2"] {
      let result = try GalaxySSIHealthStructuredOriginal.read(Data(scalar.utf8), fileExtension: "json")
      XCTAssertEqual(result.sample.rows, [[scalar]])
    }
    let array = "[" + (0..<22).map(String.init).joined(separator: ",") + "]"
    let result = try GalaxySSIHealthStructuredOriginal.read(Data(array.utf8), fileExtension: "json")
    XCTAssertEqual(result.sample.rows.count, 20)
    XCTAssertTrue(result.sample.limited)
    for empty in ["[]", "{}"] {
      XCTAssertTrue(try GalaxySSIHealthStructuredOriginal.read(Data(empty.utf8), fileExtension: "json").sample.rows.isEmpty)
    }
    for malformed in ["[1,]", "{\"x\":}", "null trailing"] {
      XCTAssertThrowsError(try GalaxySSIHealthStructuredOriginal.read(Data(malformed.utf8), fileExtension: "json"))
    }
  }

  func testCSVPreviewIsNotClinicalMappingAndRetainsQuotedRecords() throws {
    let data = Data((0..<600).map { "item\($0)" }.joined(separator: "\r\n").utf8)
    let result = try GalaxySSIHealthStructuredOriginal.read(data, fileExtension: "csv")
    XCTAssertEqual(result.sample.rows.count, 20)
    XCTAssertEqual(result.sample.rows[0], ["item0"])
    XCTAssertTrue(result.sample.limited)
    XCTAssertThrowsError(try GalaxySSIHealthTableImport.parse(data, json: false))
    let quoted = Data("a,\"b\r\nc\",\"d\"\"e\"\r\n".utf8)
    XCTAssertEqual(try GalaxySSIHealthStructuredOriginal.read(quoted, fileExtension: "csv").sample.rows,
      [["a", "b\r\nc", "d\"e"]])
  }

  func testWorksheetPreviewDoesNotRequireClinicalColumnOrRowLimits() throws {
    let rows = (1...600).map { "<row r=\"\($0)\"><c r=\"A\($0)\"><v>\($0)</v></c><c r=\"N\($0)\"><v>9</v></c></row>" }.joined()
    let xml = [
      "xl/workbook.xml": #"<workbook xmlns:r="urn:test"><sheets><sheet name="Synthetic" r:id="r1"/></sheets></workbook>"#,
      "xl/_rels/workbook.xml.rels": #"<Relationships><Relationship Id="r1" Type="urn:test/worksheet" Target="worksheets/sheet1.xml"/></Relationships>"#,
      "xl/worksheets/sheet1.xml": "<worksheet><sheetData>" + rows + "</sheetData></worksheet>"
    ]
    let data = AgentRuntimeProjectArchiveBuilder.buildStoredZip(entries: xml.map { .init(path: $0.key, data: Data($0.value.utf8)) })
    let result = try GalaxySSIHealthStructuredOriginal.read(data, fileExtension: "xlsx")
    XCTAssertEqual(result.sheetID, "r1")
    XCTAssertEqual(result.sample.rows.count, 20)
    XCTAssertEqual(result.sample.rowNumbers, Array(1...20))
    XCTAssertTrue(result.sample.limited)
    XCTAssertThrowsError(try GalaxySSIHealthXLSX(data).rows("r1"))
    XCTAssertThrowsError(try GalaxySSIHealthStructuredOriginal.read(data, fileExtension: "xlsx", sheetID: "missing"))
  }

  func testUnsupportedAndOversizedSourcesFailClosed() {
    XCTAssertThrowsError(try GalaxySSIHealthStructuredOriginal.read(Data("x".utf8), fileExtension: "exe"))
    XCTAssertThrowsError(try GalaxySSIHealthStructuredOriginal.read(Data(repeating: 32,
      count: GalaxySSIHealthTableImport.maximumBytes + 1), fileExtension: "csv"))
    XCTAssertThrowsError(try GalaxySSIHealthStructuredOriginal.read(Data([0xff, 0xfe]), fileExtension: "csv"))
  }

  @MainActor
  func testRawStorageDoesNotCreateMeasurementsOrRecognitionJobs() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = StructuredOriginalSecrets(), file = root.appendingPathComponent("records")
    let records = GalaxySSIHealthRecords(owner: "structured-fixture", secrets: secrets, isolatedFile: file)
    let store = GalaxySSIHealthOriginalStore(owner: records.owner, secrets: secrets, fixtureDirectory: root,
      restoreRecordsFile: file)
    let data = Data(#"{"arbitrary":"not a measurement"}"#.utf8)
    try store.store(data, name: String(repeating: "x", count: 200) + ".json")
    let original = try XCTUnwrap(store.list().originals.first)
    XCTAssertEqual(original.kind, .structured)
    XCTAssertEqual(original.fileExtension, "json")
    XCTAssertEqual(try store.read(original), data)
    try GalaxySSIHealthOriginalStore.validateRestoreOriginal(original, data: data)
    XCTAssertThrowsError(try GalaxySSIHealthOriginalStore.validateRestoreOriginal(original, data: Data("{}".utf8)))
    XCTAssertTrue(try records.load().current.isEmpty)
    XCTAssertTrue(try records.load().tableBatches?.isEmpty ?? true)
    XCTAssertThrowsError(try records.enqueueRecognition(original: original, pageCount: 1))
    XCTAssertThrowsError(try GalaxySSIHealthRecognitionJobs.process(data, kind: .structured, page: 0))
    XCTAssertTrue(try store.withRestoreLease { try store.visitOriginals(after: nil, limit: 10, lease: $0) }.isEmpty)
    XCTAssertFalse(try store.prepareExport([original]).0.isEmpty)
    let reopened = GalaxySSIHealthOriginalStore(owner: records.owner, secrets: secrets, fixtureDirectory: root,
      restoreRecordsFile: file)
    XCTAssertEqual(try reopened.read(original), data)
  }
}

private final class StructuredOriginalSecrets: GalaxySSISecretStore {
  private var values: [String: String] = [:]
  func setString(_ value: String, account: String) throws { values[account] = value }
  func string(account: String) -> String? { values[account] }
  func delete(account: String) { values.removeValue(forKey: account) }
}
