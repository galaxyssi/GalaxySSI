import SwiftUI
import UniformTypeIdentifiers

enum GalaxySSIHealthMeasurementExport {
  enum Format: String, CaseIterable, Identifiable {
    case csv, json, xlsx
    var id: String { rawValue }
    var contentType: UTType {
      switch self {
      case .csv: return .commaSeparatedText
      case .json: return .json
      case .xlsx: return UTType(filenameExtension: "xlsx") ?? .spreadsheet
      }
    }
  }

  struct Scope: Equatable {
    var interval: DateInterval
    var metrics: Set<GalaxySSIHealthMetric>
    var includeNotes: Bool

    func select(_ current: [GalaxySSIHealthReading]) -> [GalaxySSIHealthReading] {
      current.filter {
        !$0.deleted && metrics.contains($0.metric) &&
          $0.measuredAt >= interval.start && $0.measuredAt < interval.end
      }
    }
  }

  static let maximumRows = 5_000

  static func encode(_ readings: [GalaxySSIHealthReading], as format: Format, includeNotes: Bool) throws -> Data {
    guard !readings.isEmpty, readings.count <= maximumRows else {
      throw CocoaError(.fileWriteUnknown)
    }
    let clock = ISO8601DateFormatter()
    clock.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var columns = ["id", "revision", "metric", "measured_at", "value", "unit", "diastolic", "pulse_bpm"]
    if includeNotes { columns += ["conditions", "notes"] }
    columns += ["result_kind", "reported_notation", "reference_interval"]
    let rows: [[String]] = readings.map { reading in
      var row = [reading.id.uuidString, String(reading.revision), reading.metric.rawValue,
                 clock.string(from: reading.measuredAt), reading.value.map(decimal) ?? reading.reported?.raw ?? "", reading.unit,
                 reading.diastolic.map(decimal) ?? "", reading.pulse.map(decimal) ?? ""]
      if includeNotes { row += [reading.conditions, reading.notes] }
      row += [reading.resultKind, reading.reportedNotation ?? reading.reported?.raw ?? "", reading.referenceInterval ?? ""]
      return row
    }
    switch format {
    case .csv:
      let body = rows.map { $0.map(csvCell).joined(separator: ",") }.joined(separator: "\r\n")
      return Data((columns.joined(separator: ",") + "\r\n" + body + "\r\n").utf8)
    case .json:
      let objects = rows.map { Dictionary(uniqueKeysWithValues: zip(columns, $0)) }
      return try JSONSerialization.data(withJSONObject: ["format": "galaxyssi.ios.health.measurements.v1",
                                                        "measurements": objects], options: [.sortedKeys])
    case .xlsx:
      return try GalaxySSIHealthXLSXExport.encode(headers: columns, rows: rows)
    }
  }

  private static func decimal(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).description(withLocale: Locale(identifier: "en_US_POSIX"))
  }

  private static func csvCell(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
    let dangerous = trimmed.first.map { "=+-@".contains($0) } == true ||
      value.first == "\t" || value.first == "\r" || value.first == "\n"
    return "\"" + (dangerous ? "'" : "") + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }
}

@MainActor
struct GalaxySSIHealthMeasurementExportView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  let records: GalaxySSIHealthRecords
  @State private var metrics = Set(GalaxySSIHealthMetric.allCases)
  @State private var from = Date()
  @State private var to = Date()
  @State private var notes = false
  @State private var format = GalaxySSIHealthMeasurementExport.Format.csv
  @State private var snapshot: Snapshot?
  @State private var confirming = false
  @State private var exporting = false
  @State private var document: HealthMeasurementDocument?
  @State private var failure = false
  @State private var originals = GalaxySSIHealthLinkedExport.Choices()
  @State private var destinationProof: GalaxySSIHealthOriginalStore.ExportAttempt?
  @State private var verifying = false
  @State private var saved = false
  @State private var manifestLimit = 30

  private struct Snapshot {
    var scope: GalaxySSIHealthMeasurementExport.Scope
    var format: GalaxySSIHealthMeasurementExport.Format
    var revisions: [String]
    var originals: GalaxySSIHealthLinkedExport.Choices
    var manifest: [GalaxySSIHealthLinkedExport.Link]
  }

  var body: some View {
    Form {
      if scene == .active && !exporting {
        Picker(t("format", "Format"), selection: $format) {
          ForEach(GalaxySSIHealthMeasurementExport.Format.allCases) { item in
            Text(item.rawValue.uppercased()).tag(item)
          }
        }
        DatePicker(t("from", "From"), selection: $from, in: ...Date(), displayedComponents: .date)
        DatePicker(t("to", "Through"), selection: $to, in: ...Date(), displayedComponents: .date)
        Section(t("metrics", "Measurements")) {
          ForEach(GalaxySSIHealthMetric.allCases) { metric in
            Toggle(metricTitle(metric), isOn: Binding(get: { metrics.contains(metric) }, set: { enabled in
              if enabled { metrics.insert(metric) } else { metrics.remove(metric) }
            }))
          }
        }
        Toggle(t("notes", "Include conditions and notes"), isOn: $notes)
        Section(t("linked_originals", "Linked originals")) {
          Toggle(t("include_camera", "Include camera originals"), isOn: $originals.camera)
          Toggle(t("include_uploaded", "Include uploaded originals and tables"), isOn: $originals.uploaded)
          Toggle(t("include_unknown", "Include older originals with unknown origin"), isOn: $originals.unknown)
        }
        Button(t("prepare", "Prepare export"), action: prepare).disabled(metrics.isEmpty || verifying)
        if let snapshot, snapshot.originals.enabled {
          manifestSection(snapshot)
        }
        if verifying { ProgressView(t("verify", "Verifying saved file")) }
        if saved { Text(t("verified", "Saved file verified")) }
        if failure {
          Text(t("failed", "Unable to export. Check the dates, narrow the range, or prepare again."))
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle(t("title", "Export Measurements"))
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: originals) { _ in snapshot = nil }
    .onChange(of: format) { _ in snapshot = nil }
    .onChange(of: metrics) { _ in snapshot = nil }
    .onChange(of: from) { _ in snapshot = nil }
    .onChange(of: to) { _ in snapshot = nil }
    .onChange(of: notes) { _ in snapshot = nil }
    .confirmationDialog(t("confirm", "Save an unencrypted file?"), isPresented: $confirming, titleVisibility: .visible) {
      Button(t("save", "Choose save location"), action: save)
    } message: {
      if let snapshot {
        Text(confirmationText(snapshot))
      }
    }
    .fileExporter(isPresented: $exporting, document: document, contentType: document?.type ?? format.contentType,
                  defaultFilename: "GalaxySSI-Health-Measurements") { result in
      document = nil
      guard let proof = destinationProof else { return }
      destinationProof = nil
      if case .success(let url) = result {
        verifying = true
        Task {
          let match = await Task.detached(priority: .utility) {
            (try? GalaxySSIHealthOriginalStore.verifyDestination(url, for: proof)) == true
          }.value
          verifying = false
          saved = match
          failure = !match
        }
      } else { failure = true }
    }
    .onChange(of: exporting) { if !$0 { document = nil } }
    .onChange(of: scene) { phase in
      if phase != .active {
        snapshot = nil
        confirming = false
        if !exporting { document = nil }
      }
    }
  }

  private func prepare() {
    guard scene == .active else { return }
    snapshot = nil
    failure = false
    saved = false
    destinationProof = nil
    manifestLimit = 30
    var local = calendar
    local.timeZone = timeZone
    let start = local.startOfDay(for: from)
    let last = local.startOfDay(for: to)
    guard start <= last, let end = local.date(byAdding: .day, value: 1, to: last) else { failure = true; return }
    let scope = GalaxySSIHealthMeasurementExport.Scope(interval: DateInterval(start: start, end: end),
                                                        metrics: metrics, includeNotes: notes)
    do {
      let archive = try records.load()
      let readings = scope.select(archive.current)
      guard !readings.isEmpty, readings.count <= GalaxySSIHealthMeasurementExport.maximumRows
      else { failure = true; return }
      let manifest = originals.enabled ? try linked(readings, archive: archive, choices: originals).links : []
      snapshot = Snapshot(scope: scope, format: format, revisions: stamps(readings), originals: originals,
                          manifest: manifest)
      confirming = !originals.enabled
    } catch { failure = true }
  }

  private func save() {
    guard scene == .active, let snapshot else { return }
    self.snapshot = nil
    do {
      let archive = try records.load()
      let live = snapshot.scope.select(archive.current)
      guard stamps(live) == snapshot.revisions else { failure = true; return }
      let recordsData = try GalaxySSIHealthMeasurementExport.encode(live, as: snapshot.format,
                                                              includeNotes: snapshot.scope.includeNotes)
      let data: Data
      let type: UTType
      if snapshot.originals.enabled {
        let package = try linked(live, archive: archive, choices: snapshot.originals)
        guard package.links == snapshot.manifest else { failure = true; return }
        data = try package.zip(measurements: recordsData, format: snapshot.format)
        type = .zip
      } else { data = recordsData; type = snapshot.format.contentType }
      destinationProof = .init(id: UUID(), at: Date(), originals: [], bytes: data.count,
                               sha256: GalaxySSIHealthLinkedExport.digest(data), outcome: .prepared)
      document = HealthMeasurementDocument(data: data, type: type)
      exporting = true
    } catch { failure = true }
  }

  private func stamps(_ readings: [GalaxySSIHealthReading]) -> [String] {
    readings.map { "\($0.id.uuidString):\($0.revision)" }
  }

  private func linked(_ readings: [GalaxySSIHealthReading], archive: GalaxySSIHealthRecords.Archive,
                      choices: GalaxySSIHealthLinkedExport.Choices) throws -> GalaxySSIHealthLinkedExport.Package {
    let store = GalaxySSIHealthOriginalStore(owner: records.owner, secrets: records.secrets)
    return try GalaxySSIHealthLinkedExport.prepare(readings, batches: archive.tableBatches ?? [], store: store,
      choices: choices, tableEvidence: archive.tableEvidence ?? [], reportEvidence: archive.reportEvidence ?? [])
  }

  private func confirmationText(_ snapshot: Snapshot) -> String {
    let count = String(format: t("count", "%lld confirmed measurements"), Int64(snapshot.revisions.count))
    guard snapshot.originals.enabled else { return count }
    let counts = Dictionary(grouping: snapshot.manifest, by: \.status).mapValues(\.count)
    return count + "\n" + String(format: t("linked_counts",
      "%lld included links, %lld unselected, %lld missing, %lld unreadable, %lld mismatched"),
      Int64(counts[.included] ?? 0), Int64(counts[.unselected] ?? 0), Int64(counts[.missing] ?? 0),
      Int64(counts[.unreadable] ?? 0), Int64(counts[.mismatched] ?? 0))
  }

  private func manifestSection(_ snapshot: Snapshot) -> some View {
    Section(t("manifest", "Source manifest")) {
      Text(confirmationText(snapshot))
      ForEach(Array(snapshot.manifest.prefix(manifestLimit).enumerated()), id: \.offset) { _, link in
        VStack(alignment: .leading, spacing: 4) {
          Text(link.path ?? String(link.original.uuidString.prefix(8)))
          Text(statusTitle(link.status)).foregroundColor(.secondary)
        }
      }
      if snapshot.manifest.count > manifestLimit {
        Button(t("manifest_more", "Show more source links")) { manifestLimit += 30 }
      }
      Button(t("save", "Choose save location")) { confirming = true }.disabled(verifying)
    }
  }

  private func statusTitle(_ status: GalaxySSIHealthLinkedExport.Status) -> String {
    switch status {
    case .included: return t("link_included", "Included")
    case .unselected: return t("link_unselected", "Unselected")
    case .missing: return t("link_missing", "Missing")
    case .unreadable: return t("link_unreadable", "Unreadable")
    case .mismatched: return t("link_mismatched", "Mismatched")
    }
  }

  private func metricTitle(_ metric: GalaxySSIHealthMetric) -> String {
    metric.title(language: language)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.export." + key, fallback: fallback, language: language)
  }
}

private struct HealthMeasurementDocument: FileDocument {
  static var readableContentTypes: [UTType] { GalaxySSIHealthMeasurementExport.Format.allCases.map(\.contentType) + [.zip] }
  let data: Data
  let type: UTType

  init(data: Data, type: UTType) { self.data = data; self.type = type }
  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
    self.init(data: data, type: configuration.contentType)
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
