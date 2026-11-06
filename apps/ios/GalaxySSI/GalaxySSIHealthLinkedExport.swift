import CryptoKit
import Foundation

enum GalaxySSIHealthLinkedExport {
  struct Choices: Equatable {
    var camera = false
    var uploaded = false
    var unknown = false
    var enabled: Bool { camera || uploaded || unknown }
  }

  enum Status: String, Codable, CaseIterable {
    case included, unselected, missing, unreadable, mismatched
  }

  struct Link: Codable, Equatable {
    let record: UUID
    let revision: Int
    let original: UUID
    let source: String
    let location: Int
    let region: Int?
    let evidenceKey: String?
    let worksheet: String?
    let worksheetPath: String?
    let columns: [String: Int]?
    let secondary: Bool
    let status: Status
    let sha256: String
    let path: String?
  }

  struct Package {
    let links: [Link]
    let files: [AgentRuntimeProjectArchiveEntry]

    func zip(measurements: Data, format: GalaxySSIHealthMeasurementExport.Format) throws -> Data {
      struct Manifest: Encodable {
        let version = 1
        let dataFile: String
        let links: [Link]
      }
      let path = "measurements." + format.rawValue
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let manifest = try encoder.encode(Manifest(dataFile: path, links: links))
      let entries = [AgentRuntimeProjectArchiveEntry(path: path, data: measurements),
                     .init(path: "manifest.json", data: manifest)] + files
      guard entries.reduce(0, { $0 + $1.data.count }) <= 64 * 1024 * 1024 else {
        throw GalaxySSIHealthOriginalStore.Failure.limit
      }
      return AgentRuntimeProjectArchiveBuilder.buildStoredZip(entries: entries)
    }
  }

  @MainActor
  static func prepare(_ readings: [GalaxySSIHealthReading], batches: [GalaxySSIHealthTableImport.Batch],
                      store: GalaxySSIHealthOriginalStore, choices: Choices,
                      reportEvidence: [GalaxySSIHealthReportReview.Evidence] = [],
                      tableEvidence: [GalaxySSIHealthTableImport.Evidence] = []) throws -> Package {
    try store.withRestoreLease { lease in
      try store.reconcileRestores(lease: lease)
      return try prepare(readings, batches: batches, store: store, choices: choices,
                         reportEvidence: reportEvidence, tableEvidence: tableEvidence, lease: lease)
    }
  }

  @MainActor
  private static func prepare(_ readings: [GalaxySSIHealthReading], batches: [GalaxySSIHealthTableImport.Batch],
    store: GalaxySSIHealthOriginalStore, choices: Choices, reportEvidence: [GalaxySSIHealthReportReview.Evidence],
    tableEvidence: [GalaxySSIHealthTableImport.Evidence], lease: GalaxySSIHealthOriginalStore.RestoreLease) throws -> Package {
    let listing = try store.list(lease: lease)
    let originals = Dictionary(uniqueKeysWithValues: listing.originals.map { ($0.id, $0) })
    let removed = Set(listing.removed.map(\.id)).union(listing.pendingRemovals)
    let reports = Dictionary(grouping: reportEvidence, by: \.target)
    let tables = Dictionary(grouping: tableEvidence) {
      GalaxySSIHealthReportReview.Target(record: $0.target.record, revision: $0.target.revision)
    }
    var bytes = 0
    var links: [Link] = []
    var files: [String: Data] = [:]
    var checks: [String: Status] = [:]
    func append(_ reading: GalaxySSIHealthReading, original: UUID, source: String, location: Int,
                expected: String, path: String?, status: Status, secondary: Bool, region: Int? = nil, evidenceKey: String? = nil,
                table: GalaxySSIHealthTableImport.Source? = nil) throws {
      guard links.count < 20_000 else { throw GalaxySSIHealthOriginalStore.Failure.limit }
      links.append(.init(record: reading.id, revision: reading.revision, original: original, source: source,
                         location: location, region: region, evidenceKey: evidenceKey,
                         worksheet: table?.sheet, worksheetPath: table?.worksheetPath,
                         columns: table?.columns, secondary: secondary, status: status, sha256: expected,
                         path: status == .included ? path : nil))
    }
    func verified(_ path: String, expected: String, read: () throws -> Data) throws -> Status {
      let check = path + ":" + expected
      if let status = checks[check] { return status }
      let status: Status
      if let data = try? read() {
        if digest(data) != expected { status = .mismatched }
        else {
          if files[path] == nil {
            bytes += data.count
            guard bytes <= 48 * 1024 * 1024 else { throw GalaxySSIHealthOriginalStore.Failure.limit }
            files[path] = data
          }
          status = .included
        }
      } else { status = .unreadable }
      checks[check] = status
      return status
    }
    func appendReport(_ report: GalaxySSIHealthReportReview.Source, reading: GalaxySSIHealthReading,
                      secondary: Bool) throws {
      guard let original = originals[report.original] else {
        let exists = try !removed.contains(report.original) && store.containsOriginalFile(report.original)
        try append(reading, original: report.original, source: "report", location: report.page,
                   expected: report.sha256, path: nil, status: exists ? .unreadable : .missing,
                   secondary: secondary, region: report.region, evidenceKey: report.evidenceKey)
        return
      }
      let selected: Bool
      switch original.acquisition {
      case .camera?: selected = choices.camera
      case .uploaded?: selected = choices.uploaded
      case nil: selected = choices.unknown
      }
      let path = original.entryPath
      let status: Status
      if !selected { status = .unselected }
      else if original.kind != .pdf || original.sha256 != report.sha256 { status = .mismatched }
      else { status = try verified(path, expected: report.sha256) { try store.read(original, lease: lease) } }
      try append(reading, original: original.id, source: original.acquisition?.rawValue ?? "unknown",
                 location: report.page, expected: report.sha256, path: path, status: status,
                 secondary: secondary, region: report.region, evidenceKey: report.evidenceKey)
    }
    func appendTable(_ table: GalaxySSIHealthTableImport.Source, reading: GalaxySSIHealthReading,
                     secondary: Bool) throws {
      let batch = GalaxySSIHealthTableImport.Batch.original(for: table.batch, in: batches)
      let ext = batch.map { URL(fileURLWithPath: $0.name).pathExtension.lowercased() } ?? ""
      let path = "tables/" + (batch?.id ?? table.batch).uuidString.lowercased() + "." +
        (["csv", "json", "xlsx"].contains(ext) ? ext : "data")
      let status: Status
      if !choices.uploaded { status = .unselected }
      else if let batch, !batch.data.isEmpty { status = try verified(path, expected: table.sha256) { batch.data } }
      else { status = .missing }
      try append(reading, original: table.batch, source: "table", location: table.row,
                 expected: table.sha256, path: path, status: status, secondary: secondary, table: table)
    }
    for reading in readings {
      if let report = reading.reportSource { try appendReport(report, reading: reading, secondary: false) }
      if let table = reading.tableSource { try appendTable(table, reading: reading, secondary: false) }
      let target = GalaxySSIHealthReportReview.Target(record: reading.id, revision: reading.revision)
      for evidence in reports[target] ?? [] { try appendReport(evidence.source, reading: reading, secondary: true) }
      for evidence in tables[target] ?? [] { try appendTable(evidence.source, reading: reading, secondary: true) }
    }
    return Package(links: links, files: files.keys.sorted().compactMap { path in
      files[path].map { .init(path: path, data: $0) }
    })
  }

  static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
