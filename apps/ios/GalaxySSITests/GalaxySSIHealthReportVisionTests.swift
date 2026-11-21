import XCTest
import UIKit
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthReportVisionTests: XCTestCase {
  typealias Vision = GalaxySSIHealthReportVision
  private let response = #"{"rows":[{"metric":"glucose","values":{"value":"<3.0"},"unit":"mmol/L","reference":"3.9-6.1","source":"GLU <3.0 mmol/L"}],"collected":"2026-11-20 08:10:00+08:00","partial":false}"#

  func testPreservesReportedQualifierReferenceAndCollectionTime() throws {
    let parsed = try Vision.parse(response)
    XCTAssertEqual(parsed.rows.first?.values["value"], "<3.0")
    XCTAssertEqual(parsed.rows.first?.reference, "3.9-6.1")
    XCTAssertEqual(parsed.collected, "2026-11-20 08:10:00+08:00")
    XCTAssertFalse(parsed.partial)
    XCTAssertEqual(try Vision.parse("```json\n" + response + "\n```"), parsed)
  }

  func testPlainNumericLabResultsAreAcceptedWithoutInventingQualifiers() throws {
    let parsed = try Vision.parse(response.replacingOccurrences(of: "<3.0", with: "3.0"))
    XCTAssertEqual(parsed.rows.first?.values["value"], "3.0")
    XCTAssertEqual(parsed.rows.first?.reference, "3.9-6.1")
  }

  func testRejectsUnknownFieldsWrongTypesDuplicateAndEmptyRows() throws {
    var object = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(response.utf8))
    object["approved"] = .bool(true)
    XCTAssertThrowsError(try parse(object))
    object.removeValue(forKey: "approved")
    object["partial"] = .int(1)
    XCTAssertThrowsError(try parse(object))
    object["partial"] = .bool(false)
    let row = try XCTUnwrap(object["rows"]?.arrayValue?.first)
    object["rows"] = .array([row, row])
    XCTAssertThrowsError(try parse(object))
    object["rows"] = .array([])
    XCTAssertThrowsError(try parse(object))
    XCTAssertThrowsError(try Vision.parse(response + " trailing"))
  }

  func testRejectsUnsupportedUnitMissingValueAndControlText() throws {
    for (key, value) in [("unit", AgentMcpJSONValue.string("invented")), ("source", .string("row\nsecret")),
                         ("metric", .string("unsupported")), ("values", .object(["diastolic": .string("80")]))] {
      var object = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(response.utf8))
      var row = try XCTUnwrap(object["rows"]?.arrayValue?.first?.objectValue)
      row[key] = value; object["rows"] = .array([.object(row)])
      XCTAssertThrowsError(try parse(object))
    }
  }

  func testUnknownUnitCanRemainEmptyForUserReview() throws {
    let result = try Vision.parse(response.replacingOccurrences(of: #""unit":"mmol/L""#, with: #""unit":"""#))
    XCTAssertEqual(result.rows.first?.unit, "")
  }

  func testImageOnlineAndMeasurementPermissionsAreIndependentlyRequired() throws {
    var archive = GalaxySSIHealthRecords.Archive()
    XCTAssertThrowsError(try Vision.Consent(archive))
    archive.healthOnlinePermission = UUID()
    XCTAssertThrowsError(try Vision.Consent(archive))
    archive.reportImagePermission = UUID()
    XCTAssertThrowsError(try Vision.Consent(archive))
    archive.derivesOverview = true
    XCTAssertNoThrow(try Vision.Consent(archive))
  }

  func testEncryptedResultRetainsOCRAndDoesNotConfirmMeasurements() throws {
    let f = try Fixture()
    let job = try f.completed()
    let result = try Vision.parse(response)
    try f.records.commitReportVision(result, job: job, consent: f.consent(), zone: "Asia/Shanghai")
    let saved = try XCTUnwrap(f.records.load().recognitionJobs?.first)
    XCTAssertEqual(saved.pages, job.pages)
    XCTAssertEqual(saved.reportVision, result)
    XCTAssertEqual(saved.reportVisionZone, "Asia/Shanghai")
    XCTAssertNotEqual(saved.version, job.version)
    XCTAssertTrue(try f.records.load().current.isEmpty)
    XCTAssertTrue(try f.records.load().reportReview?.isEmpty ?? true)
    XCTAssertFalse(String(decoding: try Data(contentsOf: f.file), as: UTF8.self).contains("GLU <3.0"))
    XCTAssertThrowsError(try f.records.commitReportVision(result, job: job, consent: f.consent(), zone: "Asia/Shanghai"))
  }

  func testRenewedImagePermissionDoesNotAuthorizeOldSnapshot() throws {
    let f = try Fixture()
    let job = try f.completed()
    let old = try f.consent()
    try f.records.setPrivacy(.reportImages, enabled: false)
    try f.records.setPrivacy(.reportImages, enabled: true)
    XCTAssertNotEqual(old, try f.consent())
    XCTAssertThrowsError(try f.records.commitReportVision(Vision.parse(response), job: job, consent: old, zone: "UTC"))
  }

  func testOnlineAndMeasurementRevocationBlockCommit() throws {
    for online in [true, false] {
      let f = try Fixture()
      let job = try f.completed()
      let old = try f.consent()
      if online { try f.records.setHealthOnlinePermission(false) }
      else { try f.records.setPrivacy(.overview, enabled: false) }
      XCTAssertThrowsError(try f.records.commitReportVision(Vision.parse(response), job: job, consent: old, zone: "UTC"))
    }
  }

  func testModelEvidenceIsSeparateFromLocalOCRAndRetainsSourceHash() throws {
    let f = try Fixture()
    let job = try f.completed()
    let row = try XCTUnwrap(Vision.parse(response).rows.first)
    let source = Vision.source(row, job: job)
    XCTAssertEqual(source.original, job.original.id)
    XCTAssertEqual(source.sha256, job.original.sha256)
    XCTAssertEqual(source.recognition, .model)
    XCTAssertFalse(source.fromOCR)
    XCTAssertTrue(source.evidenceKey.map(GalaxySSIHealthRecognitionJobs.validDigest) == true)
    let decoded = try JSONDecoder().decode(GalaxySSIHealthReportReview.Source.self, from: JSONEncoder().encode(source))
    XCTAssertEqual(decoded.recognition, .model)
    XCTAssertEqual(decoded, source)
  }

  func testReviewedModelDraftCanStageButDeletedJobCannotStageItAgain() throws {
    let f = try Fixture()
    let originalJob = try f.completed()
    let result = try Vision.parse(response)
    try f.records.commitReportVision(result, job: originalJob, consent: f.consent(), zone: "UTC")
    let job = try XCTUnwrap(f.records.load().recognitionJobs?.first)
    let row = try XCTUnwrap(result.rows.first)
    let source = Vision.source(row, job: job)
    let reading = GalaxySSIHealthReading(metric: .glucose, measuredAt: Date().addingTimeInterval(-60),
      reported: GalaxySSIHealthReportedResult.parse("<3.0", metric: .glucose), reportedNotation: "<3.0",
      unitOverride: "mmol/L", reportSource: source)
    let item = GalaxySSIHealthReportReview.Item(version: UUID(), source: source, excerpt: row.source, reading: reading)
    try f.records.stageReportItem(item, replacing: nil)
    XCTAssertTrue(try f.records.load().current.isEmpty)
    try f.records.removeRecognitionJob(id: job.id, expected: job.version)
    let changed = GalaxySSIHealthReportReview.Item(version: UUID(), source: source, excerpt: row.source, reading: reading)
    XCTAssertThrowsError(try f.records.stageReportItem(changed, replacing: item.version))
  }

  func testLegacySourcesAndJobsDecodeWithoutVisionFields() throws {
    let f = try Fixture()
    let job = try f.completed()
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as? [String: Any])
    object.removeValue(forKey: "reportVision"); object.removeValue(forKey: "reportVisionZone")
    let decoded = try JSONDecoder().decode(GalaxySSIHealthRecognitionJobs.Job.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertNil(decoded.reportVision)
    XCTAssertEqual(decoded, job)
    let source = GalaxySSIHealthReportReview.Source(original: job.original.id, sha256: job.original.sha256,
      page: 0, region: 0, fromOCR: true)
    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
    legacy.removeValue(forKey: "recognition")
    let oldSource = try JSONDecoder().decode(GalaxySSIHealthReportReview.Source.self,
      from: JSONSerialization.data(withJSONObject: legacy))
    XCTAssertNil(oldSource.recognition)
    XCTAssertEqual(oldSource, source)
  }

  func testImagePreparationIsBoundedAndRejectsNonImages() throws {
    XCTAssertThrowsError(try GalaxySSIHealthReportVisionProvider.jpeg(Data("not an image".utf8)))
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { context in
      UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    let encoded = try GalaxySSIHealthReportVisionProvider.jpeg(XCTUnwrap(image.pngData()))
    XCTAssertTrue((1...GalaxySSIHealthReportCodex.maximumImageBytes).contains(encoded.count))
    XCTAssertTrue(encoded.starts(with: [0xff, 0xd8]))
  }

  private func parse(_ object: AgentMcpJSONObject) throws -> Vision.Result {
    try Vision.parse(String(decoding: JSONEncoder().encode(object), as: UTF8.self))
  }

  @MainActor private final class Fixture {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let records: GalaxySSIHealthRecords
    init() throws {
      records = .init(owner: "vision-fixture", secrets: InMemorySecretStore(), isolatedFile: file)
      try records.setPrivacy(.overview, enabled: true)
      try records.setPrivacy(.reportImages, enabled: true)
      try records.setHealthOnlinePermission(true)
    }
    deinit { try? FileManager.default.removeItem(at: file) }
    func consent() throws -> Vision.Consent { try .init(records.load()) }
    func completed() throws -> GalaxySSIHealthRecognitionJobs.Job {
      let original = GalaxySSIHealthOriginalStore.Original(id: UUID(), name: "fixture.png", kind: .image,
        fileExtension: "png", importedAt: Date(), bytes: 4, sha256: String(repeating: "a", count: 64))
      let job = try records.enqueueRecognition(original: original, pageCount: 1)
      let run = try records.beginRecognitionJob(id: job.id, expected: job.version)
      try records.commitRecognitionPage(id: job.id, run: run, page: .init(index: 0, fromOCR: true, lines: []))
      return try XCTUnwrap(records.load().recognitionJobs?.first)
    }
  }
}
