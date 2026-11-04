import SwiftUI
import UniformTypeIdentifiers

enum GalaxySSIHealthMeasurementExport {
  enum Format: String, CaseIterable, Identifiable {
    case csv, json
    var id: String { rawValue }
    var contentType: UTType { self == .csv ? .commaSeparatedText : .json }
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
    let rows: [[String]] = readings.map { reading in
      var row = [reading.id.uuidString, String(reading.revision), reading.metric.rawValue,
                 clock.string(from: reading.measuredAt), decimal(reading.value), reading.metric.unit,
                 reading.diastolic.map(decimal) ?? "", reading.pulse.map(decimal) ?? ""]
      if includeNotes { row += [reading.conditions, reading.notes] }
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

  private struct Snapshot {
    var scope: GalaxySSIHealthMeasurementExport.Scope
    var format: GalaxySSIHealthMeasurementExport.Format
    var revisions: [String]
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
        Button(t("prepare", "Prepare export"), action: prepare).disabled(metrics.isEmpty)
        if failure {
          Text(t("failed", "Unable to export. Check the dates, narrow the range, or prepare again."))
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle(t("title", "Export Measurements"))
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog(t("confirm", "Save an unencrypted file?"), isPresented: $confirming, titleVisibility: .visible) {
      Button(t("save", "Choose save location"), action: save)
    } message: {
      if let snapshot {
        Text(String(format: t("count", "%lld confirmed measurements"), Int64(snapshot.revisions.count)))
      }
    }
    .fileExporter(isPresented: $exporting, document: document, contentType: document?.type ?? format.contentType,
                  defaultFilename: "GalaxySSI-Health-Measurements") { result in
      document = nil
      if case .failure = result { failure = true }
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
    var local = calendar
    local.timeZone = timeZone
    let start = local.startOfDay(for: from)
    let last = local.startOfDay(for: to)
    guard start <= last, let end = local.date(byAdding: .day, value: 1, to: last) else { failure = true; return }
    let scope = GalaxySSIHealthMeasurementExport.Scope(interval: DateInterval(start: start, end: end),
                                                        metrics: metrics, includeNotes: notes)
    do {
      let readings = scope.select(try records.load().current)
      guard !readings.isEmpty, readings.count <= GalaxySSIHealthMeasurementExport.maximumRows
      else { failure = true; return }
      snapshot = Snapshot(scope: scope, format: format, revisions: stamps(readings))
      confirming = true
    } catch { failure = true }
  }

  private func save() {
    guard scene == .active, let snapshot else { return }
    self.snapshot = nil
    do {
      let live = snapshot.scope.select(try records.load().current)
      guard stamps(live) == snapshot.revisions else { failure = true; return }
      let data = try GalaxySSIHealthMeasurementExport.encode(live, as: snapshot.format,
                                                              includeNotes: snapshot.scope.includeNotes)
      document = HealthMeasurementDocument(data: data, type: snapshot.format.contentType)
      exporting = true
    } catch { failure = true }
  }

  private func stamps(_ readings: [GalaxySSIHealthReading]) -> [String] {
    readings.map { "\($0.id.uuidString):\($0.revision)" }
  }

  private func metricTitle(_ metric: GalaxySSIHealthMetric) -> String {
    let label: (String, String)
    switch metric {
    case .bloodPressure: label = ("blood_pressure", "Blood pressure")
    case .glucose: label = ("glucose", "Blood glucose")
    case .weight: label = ("weight", "Weight")
    case .heartRate: label = ("heart_rate", "Heart rate")
    }
    return GalaxySSILocalization.string("galaxyssi.health." + label.0, fallback: label.1, language: language)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.export." + key, fallback: fallback, language: language)
  }
}

private struct HealthMeasurementDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.commaSeparatedText, .json] }
  let data: Data
  let type: UTType

  init(data: Data, type: UTType) { self.data = data; self.type = type }
  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
    self.init(data: data, type: configuration.contentType)
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
