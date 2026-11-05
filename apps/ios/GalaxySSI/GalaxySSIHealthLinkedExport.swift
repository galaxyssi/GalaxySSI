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
                      tableEvidence: [GalaxySSIHealthTableImport.Evidence] = [],
                      reportEvidence: [GalaxySSIHealthReportReview.Evidence] = []) throws -> Package {
    let listing = try store.list()
    let originals = Dictionary(uniqueKeysWithValues: listing.originals.map { ($0.id, $0) })
    let removed = Set(listing.removed.map(\.id))
    let tables = Dictionary(batches.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let tableLinks = Dictionary(grouping: tableEvidence, by: { $0.target.record })
    let reportLinks = Dictionary(grouping: reportEvidence, by: { $0.target.record })
    var bytes = 0
    var links: [Link] = []
    var files: [String: Data] = [:]
    var checks: [String: Status] = [:]
    func append(_ reading: GalaxySSIHealthReading, original: UUID, source: String, location: Int,
                expected: String, path: String?, status: Status) {
      links.append(.init(record: reading.id, revision: reading.revision, original: original, source: source,
                         location: location, status: status, sha256: expected, path: status == .included ? path : nil))
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
    for reading in readings {
      let reportSources = (reading.reportSource.map { [$0] } ?? []) + (reading.secondarySources?.reports ?? []) +
        (reportLinks[reading.id] ?? []).filter { $0.target.revision == reading.revision }.map(\.source)
      for report in reportSources {
        guard let original = originals[report.original] else {
          let status: Status
          if removed.contains(report.original) { status = .missing }
          else { status = try store.containsOriginalFile(report.original) ? .unreadable : .missing }
          append(reading, original: report.original, source: "report", location: report.page,
                 expected: report.sha256, path: nil, status: status)
          continue
        }
        let selected: Bool
        switch original.acquisition {
        case .camera?: selected = choices.camera
        case .uploaded?: selected = choices.uploaded
        case nil: selected = choices.unknown
        }
        let path = "originals/" + original.id.uuidString.lowercased() + ".pdf"
        let status: Status
        if !selected { status = .unselected }
        else if original.kind != .pdf || original.sha256 != report.sha256 { status = .mismatched }
        else { status = try verified(path, expected: report.sha256) { try store.read(original) } }
        append(reading, original: original.id, source: original.acquisition?.rawValue ?? "unknown",
               location: report.page, expected: report.sha256, path: path, status: status)
      }
      let tableSources = (reading.tableSource.map { [$0] } ?? []) + (reading.secondarySources?.tables ?? []) +
        (tableLinks[reading.id] ?? []).filter { $0.target.revision == reading.revision }.map(\.source)
      for table in tableSources {
        let batch = tables[table.batch]
        let ext = batch.map { URL(fileURLWithPath: $0.name).pathExtension.lowercased() } ?? ""
        let path = "tables/" + table.batch.uuidString.lowercased() + "." + (["csv", "json", "xlsx"].contains(ext) ? ext : "data")
        let status: Status
        if !choices.uploaded { status = .unselected }
        else if let batch, batch.undone == nil, !batch.data.isEmpty {
          status = try verified(path, expected: table.sha256) { batch.data }
        }
        else { status = .missing }
        append(reading, original: table.batch, source: "table", location: table.row,
               expected: table.sha256, path: path, status: status)
      }
    }
    return Package(links: links, files: files.keys.sorted().compactMap { path in
      files[path].map { .init(path: path, data: $0) }
    })
  }

  static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
