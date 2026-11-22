import CryptoKit
import Foundation

enum GalaxySSIHealthReportVision {
  enum RowIssue: String, Codable, CaseIterable {
    case unsupportedMetric = "unsupported_metric", invalidUnit = "invalid_unit", invalidFields = "invalid_fields", duplicate, unreadable
    func title(count: Int, language: String) -> String {
      let fallback: String
      switch self {
      case .unsupportedMetric: fallback = "%lld rows use unsupported measurements"
      case .invalidUnit: fallback = "%lld rows have unsupported units"
      case .invalidFields: fallback = "%lld rows have invalid or unreadable fields"
      case .duplicate: fallback = "%lld repeated rows were omitted"
      case .unreadable: fallback = "%lld rows were too unclear to read"
      }
      return String(format: GalaxySSIHealthReportVision.text("rejected_" + rawValue, fallback, language), Int64(count))
    }
  }
  enum ReplyProblem: String, Error { case format, noSupportedRows, unsupportedMetrics, unreadableImage, ambiguousSample, invalidRows }
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
    var rejectedRows: [String: Int]? = nil
    enum CodingKeys: String, CodingKey { case rows, collected, partial, fasting; case rejectedRows = "rejected_rows" }
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
    guard response.utf8.count <= GalaxySSIHealthReportCodex.maximumReplyBytes, response.utf16.count <= 100_000 else { throw ReplyProblem.format }
    var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("```"), text.hasSuffix("```") {
      guard let newline = text.firstIndex(of: "\n"),
            ["```", "```json"].contains(String(text[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
      else { throw ReplyProblem.format }
      text = String(text[text.index(after: newline)...].dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard let object = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(text.utf8)) else { throw ReplyProblem.format }
    guard Set(object.keys).subtracting(["fasting", "omitted", "ambiguous_sample"]) == ["rows", "collected", "partial"], case .array(let raw)? = object["rows"],
          (0...80).contains(raw.count), let collected = object["collected"]?.strictStringValue,
          validText(collected, limit: 80), case .bool(let partial)? = object["partial"] else { throw ReplyProblem.format }
    let fasting: String?
    if let value = object["fasting"] {
      guard let text = value.strictStringValue, text.isEmpty || GalaxySSIHealthReportBatch.conditions.contains(text) else { throw ReplyProblem.format }
      fasting = text
    } else { fasting = nil }
    let ambiguous: Bool
    if let value = object["ambiguous_sample"] {
      guard case .bool(let flag) = value, !flag || raw.isEmpty else { throw ReplyProblem.format }
      ambiguous = flag
    } else { ambiguous = false }
    var rejected: [String: Int] = [:]
    if let omitted = object["omitted"] {
      guard let counts = omitted.objectValue, Set(counts.keys) == ["unsupported_metric", "unreadable"],
            case .int(let unsupported)? = counts["unsupported_metric"], case .int(let unreadable)? = counts["unreadable"],
            (0...80).contains(unsupported), (0...80).contains(unreadable), unsupported + unreadable <= 80 else { throw ReplyProblem.format }
      if unsupported > 0 { rejected[RowIssue.unsupportedMetric.rawValue] = Int(unsupported) }
      if unreadable > 0 { rejected[RowIssue.unreadable.rawValue] = Int(unreadable) }
    }
    if ambiguous { throw ReplyProblem.ambiguousSample }
    var rows: [Row] = [], seen = Set<String>()
    for value in raw {
      let issue: RowIssue?
      if let item = value.objectValue, let metricID = item["metric"]?.strictStringValue, !metricID.isBlank,
         let unit = item["unit"]?.strictStringValue {
        if let metric = GalaxySSIHealthMetric(rawValue: metricID) {
          if let canonical = canonicalUnit(unit, metric: metric) {
            var normalized = item; normalized["unit"] = .string(canonical)
            if let row = try? decodeRow(.object(normalized)) {
              if seen.insert(row.id).inserted { rows.append(row); issue = nil }
              else { issue = .duplicate }
            } else { issue = .invalidFields }
          } else { issue = .invalidUnit }
        } else { issue = .unsupportedMetric }
      } else { issue = .invalidFields }
      if let issue { rejected[issue.rawValue, default: 0] += 1 }
    }
    guard !rows.isEmpty else {
      if rejected[RowIssue.invalidFields.rawValue] != nil || rejected[RowIssue.invalidUnit.rawValue] != nil { throw ReplyProblem.invalidRows }
      if rejected[RowIssue.unreadable.rawValue] != nil { throw ReplyProblem.unreadableImage }
      if rejected[RowIssue.unsupportedMetric.rawValue] != nil { throw ReplyProblem.unsupportedMetrics }
      throw ReplyProblem.noSupportedRows
    }
    return Result(rows: rows, collected: collected, partial: partial || !rejected.isEmpty, fasting: fasting,
      rejectedRows: rejected.isEmpty ? nil : rejected)
  }

  // Stored rejection counts are trusted only after local validation; a model may never supply this field.
  static func validateStored(_ result: Result, allowLegacyEmpty: Bool = false) throws {
    let invalid = GalaxySSIHealthRecords.Failure.invalid
    let rejected = result.rejectedRows ?? [:]
    guard result.rows.count <= 80, !result.rows.isEmpty || (allowLegacyEmpty && rejected.isEmpty),
          validText(result.collected, limit: 80), result.fasting.map({ $0.isEmpty || GalaxySSIHealthReportBatch.conditions.contains($0) }) != false,
          rejected.allSatisfy({ RowIssue(rawValue: $0.key) != nil && (1...160).contains($0.value) }),
          result.rows.count + rejected.values.reduce(0, +) <= 160, rejected.isEmpty || result.partial else { throw invalid }
    let encoded = try JSONEncoder().encode(result)
    guard encoded.count <= GalaxySSIHealthReportCodex.maximumReplyBytes * 2,
          case .array(let rows)? = try JSONDecoder().decode(AgentMcpJSONObject.self, from: encoded)["rows"],
          Set(result.rows.map(\.id)).count == result.rows.count else { throw invalid }
    for (raw, row) in zip(rows, result.rows) { guard try decodeRow(raw) == row else { throw invalid } }
  }

  private static func decodeRow(_ value: AgentMcpJSONValue) throws -> Row {
    let invalid = GalaxySSIHealthRecords.Failure.invalid
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

  private static func validText(_ value: String, limit: Int) -> Bool {
    value.utf16.count <= limit && value.rangeOfCharacter(from: .controlCharacters) == nil
  }

  // Normalize spelling only: never convert a value, magnitude, specimen or measurement.
  static func canonicalUnit(_ raw: String, metric: GalaxySSIHealthMetric) -> String? {
    guard validText(raw, limit: 40) else { return nil }
    if raw.isEmpty { return "" }
    func key(_ unit: String) -> String {
      unit.replacingOccurrences(of: #"[\u00B9\u00B2\u00B3\u2070\u2074-\u2079]+"#, with: "^$0", options: .regularExpression)
        .precomposedStringWithCompatibilityMapping.filter { !$0.isWhitespace }
        .replacingOccurrences(of: "\u{03BC}", with: "u").replacingOccurrences(of: "\u{00B5}", with: "u")
        .replacingOccurrences(of: #"^[x\u00D7](?=10\^)"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?<=10)\*(?=[0-9])"#, with: "^", options: .regularExpression)
        .replacingOccurrences(of: #"/([dmu]?)l$"#, with: "/$1L", options: .regularExpression)
    }
    let candidates = metric.units.filter { !$0.isEmpty && key($0) == key(raw) }
    return candidates.count == 1 ? candidates[0] : nil
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
  func prepareReportContinuation(_ expected: GalaxySSIHealthRecognitionJobs.Job) throws -> GalaxySSIHealthRecognitionJobs.Job {
    var archive = try load()
    guard GalaxySSIHealthReportVision.eligible(expected), expected.run == nil,
          let index = archive.recognitionJobs?.firstIndex(where: { $0 == expected }) else { throw Failure.stale }
    var job = expected
    if job.pages.count == job.pageCount { job.phase = .completed }
    job.reportFailure = nil
    if job == expected { return job }
    job.version = UUID(); archive.recognitionJobs?[index] = job
    try persistReportVision(archive)
    return job
  }

  func recordReportFailure(_ expected: GalaxySSIHealthRecognitionJobs.Job, problem: GalaxySSIHealthReportFailure) throws {
    var archive = try load()
    guard GalaxySSIHealthReportVision.eligible(expected), expected.run == nil,
          let index = archive.recognitionJobs?.firstIndex(where: { $0 == expected }) else { throw Failure.stale }
    archive.recognitionJobs?[index].phase = .failed
    archive.recognitionJobs?[index].reportFailure = problem
    archive.recognitionJobs?[index].version = UUID()
    try persistReportVision(archive)
  }

  func commitReportVision(_ result: GalaxySSIHealthReportVision.Result, job: GalaxySSIHealthRecognitionJobs.Job,
      consent: GalaxySSIHealthReportVision.Consent, zone: String) throws {
    var archive = try load()
    guard try GalaxySSIHealthReportVision.Consent(archive) == consent,
          TimeZone(identifier: zone) != nil, GalaxySSIHealthReportVision.eligible(job),
          let index = archive.recognitionJobs?.firstIndex(where: { $0 == job })
    else { throw Failure.stale }
    try GalaxySSIHealthReportVision.validateStored(result)
    archive.recognitionJobs?[index].reportVision = result
    archive.recognitionJobs?[index].reportVisionZone = zone
    archive.recognitionJobs?[index].phase = .completed
    archive.recognitionJobs?[index].reportFailure = nil
    archive.recognitionJobs?[index].version = UUID()
    try persistReportVision(archive)
  }
}
