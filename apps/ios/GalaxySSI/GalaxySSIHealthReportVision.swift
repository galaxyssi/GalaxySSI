import CryptoKit
import Foundation

enum GalaxySSIHealthReportVision {
  struct Row: Codable, Equatable, Identifiable {
    let metric: GalaxySSIHealthMetric
    let values: [String: String]
    let unit: String
    let reference: String
    let source: String
    var id: String { AgentModelLoopRecoveryIdentity.sha256(self) }
  }
  struct Result: Codable, Equatable {
    let rows: [Row]
    let collected: String
    let partial: Bool
    var fasting: String? = nil
  }
  struct Consent: Equatable {
    let online: UUID
    let metrics: UUID?
    init(_ archive: GalaxySSIHealthRecords.Archive) throws {
      guard archive.derivesOverview == true, let online = archive.healthOnlinePermission else { throw GalaxySSIHealthRecords.Failure.permission }
      self.online = online
      metrics = archive.privacyEvents?.last(where: { $0.scope == .overview })?.id
    }
  }

  static func eligible(_ job: GalaxySSIHealthRecognitionJobs.Job) -> Bool {
    job.original.kind == .image && job.pageCount == 1 && job.captureSource?.mode != .device &&
      [.completed, .failed].contains(job.phase) && job.reportVision == nil
  }

  static func parse(_ response: String) throws -> Result {
    let invalid = GalaxySSIHealthRecords.Failure.invalid
    guard response.utf8.count <= 131_072 else { throw invalid }
    var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("```json\n"), text.hasSuffix("\n```") { text = String(text.dropFirst(8).dropLast(4)) }
    let object = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(text.utf8))
    guard Set(object.keys).subtracting(["fasting"]) == ["rows", "collected", "partial"], case .array(let raw)? = object["rows"],
          (0...80).contains(raw.count), let collected = object["collected"]?.strictStringValue,
          validText(collected, limit: 80), case .bool(let partial)? = object["partial"] else { throw invalid }
    let fasting: String?
    if let value = object["fasting"] {
      guard let text = value.strictStringValue, text.isEmpty || GalaxySSIHealthReportBatch.conditions.contains(text) else { throw invalid }
      fasting = text
    } else { fasting = nil }
    let rows = try raw.map { value -> Row in
      guard let row = value.objectValue, Set(row.keys) == ["metric", "values", "unit", "reference", "source"],
            let name = row["metric"]?.strictStringValue, let metric = GalaxySSIHealthMetric(rawValue: name),
            let fields = row["values"]?.objectValue,
            Set(fields.keys) == (metric == .bloodPressure ? ["value", "diastolic"] : ["value"]),
            let unit = row["unit"]?.strictStringValue, unit.isEmpty || metric.units.contains(unit),
            let reference = row["reference"]?.strictStringValue, validText(reference, limit: 200),
            let source = row["source"]?.strictStringValue, validText(source, limit: 400), !source.isBlank else { throw invalid }
      var values: [String: String] = [:]
      for (key, value) in fields {
        guard let text = value.strictStringValue, validText(text, limit: 128), !text.isBlank else { throw invalid }
        if metric.laboratory {
          let parsed = GalaxySSIHealthReportedResult.parse(text, metric: metric)
          guard parsed.map({ ($0.kind == .qualitative) == (metric.form == .qualitative) }) ??
                (metric.form == .laboratory && GalaxySSIHealthReportedResult.number(text) != nil) else { throw invalid }
        } else {
          guard let number = GalaxySSIHealthReportedResult.number(text), number >= 0,
                metric.form != .positive || number > 0,
                metric.form != .count || NSDecimalNumber(decimal: number).doubleValue.rounded() == NSDecimalNumber(decimal: number).doubleValue
          else { throw invalid }
        }
        values[key] = text
      }
      return Row(metric: metric, values: values, unit: unit, reference: reference, source: source)
    }
    guard Set(rows.map(\.id)).count == rows.count else { throw invalid }
    return Result(rows: rows, collected: collected, partial: partial, fasting: fasting)
  }

  private static func validText(_ value: String, limit: Int) -> Bool {
    value.utf16.count <= limit && value.rangeOfCharacter(from: .controlCharacters) == nil
  }

  static func source(_ row: Row, job: GalaxySSIHealthRecognitionJobs.Job) -> GalaxySSIHealthReportReview.Source {
    .init(original: job.original.id, sha256: job.original.sha256, page: 0, region: 0, fromOCR: false,
      evidenceKey: AgentModelLoopRecoveryIdentity.sha256(["kind": "model", "row": row.id, "job": job.id.uuidString,
        "collected": job.reportVision?.collected ?? "", "crop": job.captureSource?.cropRevision?.uuidString ?? ""]),
      captureSource: job.captureSource, recognition: .model)
  }

  static func text(_ key: String, _ fallback: String, _ language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.report_vision." + key, fallback: fallback, language: language)
  }
}

extension GalaxySSIHealthRecords {
  func commitReportVision(_ result: GalaxySSIHealthReportVision.Result, job: GalaxySSIHealthRecognitionJobs.Job,
      consent: GalaxySSIHealthReportVision.Consent, zone: String) throws {
    var archive = try load()
    guard try GalaxySSIHealthReportVision.Consent(archive) == consent,
          TimeZone(identifier: zone) != nil, GalaxySSIHealthReportVision.eligible(job),
          let index = archive.recognitionJobs?.firstIndex(where: { $0 == job })
    else { throw Failure.stale }
    let encoded = try JSONEncoder().encode(result)
    _ = try GalaxySSIHealthReportVision.parse(String(decoding: encoded, as: UTF8.self))
    archive.recognitionJobs?[index].reportVision = result
    archive.recognitionJobs?[index].reportVisionZone = zone
    archive.recognitionJobs?[index].version = UUID()
    try persistReportVision(archive)
  }
}
