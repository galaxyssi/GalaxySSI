import SwiftUI
import UniformTypeIdentifiers

enum GalaxySSIHealthReportReview {
  struct Source: Codable, Equatable {
    let original: UUID
    let sha256: String
    let page: Int
    let region: Int
    let fromOCR: Bool
    var evidenceKey: String?
    var documentOrder: Int?
    var cropRevision: UUID?

    static func == (lhs: Self, rhs: Self) -> Bool {
      guard lhs.original == rhs.original, lhs.sha256 == rhs.sha256, lhs.page == rhs.page,
            lhs.fromOCR == rhs.fromOCR, lhs.cropRevision == rhs.cropRevision else { return false }
      if lhs.evidenceKey != nil || rhs.evidenceKey != nil { return lhs.evidenceKey == rhs.evidenceKey }
      return lhs.region == rhs.region
    }
  }

  struct Item: Codable, Identifiable {
    var id: UUID { version }
    let version: UUID
    let source: Source
    let excerpt: String
    let reading: GalaxySSIHealthReading
  }

  struct Target: Codable, Equatable {
    let record: UUID
    let revision: Int
  }

  struct Evidence: Codable, Equatable {
    let target: Target
    let source: Source
    let excerpt: String
  }

  static func exactTarget(for item: Item, current: [GalaxySSIHealthReading]) -> Target? {
    let matches = current.filter { !$0.deleted && $0.revision > 0 &&
      $0.measuredAt == item.reading.measuredAt && $0.sameMeasurement(as: item.reading) }
    guard matches.count == 1, let match = matches.first else { return nil }
    return Target(record: match.id, revision: match.revision)
  }

  struct Linked: Equatable, Identifiable {
    let reading: GalaxySSIHealthReading
    let source: Source
    let secondary: Bool
    var id: String { "\(reading.id):\(reading.revision):\(source.page):\(source.region):\(source.fromOCR):\(secondary)" }
  }

  static func linked(original: GalaxySSIHealthOriginalStore.Original, revisions: [GalaxySSIHealthReading],
                     current: [GalaxySSIHealthReading], evidence: [Evidence]) -> [Linked] {
    let live = Set(current.map(\.id))
    func belongs(_ source: Source) -> Bool {
      source.original == original.id && source.sha256 == original.sha256
    }
    var seen = Set<UUID>()
    let primary = revisions.compactMap { reading -> Linked? in
      guard live.contains(reading.id), !reading.deleted, let source = reading.reportSource, belongs(source),
            seen.insert(reading.id).inserted else { return nil }
      return .init(reading: reading, source: source, secondary: false)
    }
    let secondary = evidence.compactMap { link -> Linked? in
      guard belongs(link.source), live.contains(link.target.record),
            let reading = revisions.last(where: {
              $0.id == link.target.record && $0.revision == link.target.revision && !$0.deleted
            }) else { return nil }
      return .init(reading: reading, source: link.source, secondary: true)
    }
    return (primary + secondary).sorted { ($0.source.page, $0.source.region, $0.id) < ($1.source.page, $1.source.region, $1.id) }
  }

  static func export(_ linked: [Linked], pdf: Data) throws -> Data {
    struct Entry: Encodable { let target: Target; let source: Source; let secondary: Bool }
    struct Manifest: Encodable { let version = 1; let links: [Entry] }
    var seen = Set<String>()
    let readings = linked.map(\.reading).filter { seen.insert("\($0.id):\($0.revision)").inserted }
    let csv = try GalaxySSIHealthMeasurementExport.encode(readings, as: .csv, includeNotes: false)
    let links = linked.map { Entry(target: .init(record: $0.reading.id, revision: $0.reading.revision),
                                  source: $0.source, secondary: $0.secondary) }
    return AgentRuntimeProjectArchiveBuilder.buildStoredZip(entries: [
      .init(path: "measurements.csv", data: csv), .init(path: "original.pdf", data: pdf),
      .init(path: "manifest.json", data: try JSONEncoder().encode(Manifest(links: links)))
    ])
  }

  static func text(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.report_review." + key, fallback: fallback, language: language)
  }
}

@MainActor
struct GalaxySSIHealthReportEvidenceView: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let store: GalaxySSIHealthOriginalStore
  let original: GalaxySSIHealthOriginalStore.Original
  @State private var rows: [GalaxySSIHealthReportReview.Linked] = []
  @State private var limit = 30
  @State private var confirming = false
  @State private var exporting = false
  @State private var failed = false
  @State private var document: ArchiveDocument?

  var body: some View {
    List {
      if scene == .active {
        ForEach(rows.prefix(limit)) { item in
          VStack(alignment: .leading, spacing: 4) {
            Text(item.reading.metric.title(language: language))
            Text(String(format: t("source_revision", "Page %lld · revision %lld"),
                        Int64(min(item.source.page, Int.max - 1) + 1), Int64(item.reading.revision)))
            Text(item.secondary ? t("secondary", "Additional source") : t("primary", "Primary source"))
              .foregroundColor(.secondary)
          }
        }
        if rows.count > limit { Button(t("more_links", "Show more links")) { limit += 30 } }
        if !rows.isEmpty { Button(t("export_links", "Export linked measurements and PDF")) { confirming = true } }
        else if !failed { Text(t("no_links", "No linked measurements")) }
        if failed { Text(t("batch_error", "Nothing was saved. Check for duplicate or changed measurements.")) }
      }
    }
    .navigationTitle(t("evidence", "Linked report evidence"))
    .onAppear(perform: reload)
    .onChange(of: scene) {
      if $0 == .active { reload() } else { rows = []; confirming = false; if !exporting { document = nil } }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.trendInputsChanged)) {
      if $0.object as? String == records.owner { confirming = false; reload() }
    }
    .confirmationDialog(t("plain_export", "Save an unencrypted ZIP?"), isPresented: $confirming, titleVisibility: .visible) {
      Button(t("export_links", "Export linked measurements and PDF"), action: export)
    }
    .fileExporter(isPresented: $exporting, document: document, contentType: .zip,
                  defaultFilename: "GalaxySSI-Health-Report.zip") { result in
      document = nil
      if case .failure = result { failed = true }
    }
    .onChange(of: exporting) { if !$0 { document = nil } }
  }

  private func linked() throws -> [GalaxySSIHealthReportReview.Linked] {
    let archive = try records.load()
    return GalaxySSIHealthReportReview.linked(original: original, revisions: archive.revisions,
      current: archive.current, evidence: archive.reportEvidence ?? [])
  }

  private func reload() {
    guard scene == .active else { return }
    do { rows = try linked(); failed = false }
    catch { rows = []; failed = true }
  }

  private func export() {
    guard scene == .active else { return }
    do {
      let fresh = try linked()
      guard !fresh.isEmpty, fresh == rows else { throw GalaxySSIHealthRecords.Failure.stale }
      document = ArchiveDocument(data: try GalaxySSIHealthReportReview.export(fresh, pdf: store.read(original)))
      exporting = true
    } catch { reload(); failed = true }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSIHealthReportReview.text(key, fallback, language: language)
  }

  private struct ArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
      guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
      self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
  }
}

@MainActor
struct GalaxySSIHealthReportItemEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  @Environment(\.locale) private var locale
  let records: GalaxySSIHealthRecords
  let source: GalaxySSIHealthReportReview.Source
  let excerpt: String
  @State private var existing: GalaxySSIHealthReportReview.Item?
  @State private var metric: GalaxySSIHealthMetric?
  @State private var unit = ""
  @State private var value = ""
  @State private var lower = ""
  @State private var date = Date()
  @State private var dateConfirmed = false
  @State private var ownership = false
  @State private var failed = false

  var body: some View {
    Form {
      if scene == .active {
        Text(excerpt)
        Picker(t("metric", "Measurement"), selection: $metric) {
          Text(t("choose", "Choose")).tag(nil as GalaxySSIHealthMetric?)
          ForEach(GalaxySSIHealthMetric.allCases.filter { !$0.units.isEmpty }) { item in
            Text(item.title(language: language)).tag(Optional(item))
          }
        }
        if let metric {
          Picker(t("unit", "Unit"), selection: $unit) {
            Text(t("choose", "Choose")).tag("")
            ForEach(metric.units, id: \.self) { Text($0).tag($0) }
          }
          TextField(t("value", "Verified value"), text: $value).keyboardType(.numbersAndPunctuation)
          if metric == .bloodPressure {
            TextField(t("diastolic", "Verified diastolic value"), text: $lower).keyboardType(.decimalPad)
          }
        }
        DatePicker(t("time", "Measurement time"), selection: $date, in: ...Date())
        Toggle(t("time_confirm", "I verified the measurement time"), isOn: $dateConfirmed)
        Toggle(t("owner", "This measurement belongs to me"), isOn: $ownership)
        Button(t("stage", "Save reviewed item to draft"), action: stage)
          .disabled(!dateConfirmed || !ownership || metric == nil || unit.isEmpty || value.isEmpty)
        if failed { Text(t("error", "Could not save. Check values or reopen the review.")).foregroundColor(.secondary) }
      }
    }
    .navigationTitle(t("item", "Review measurement"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: load)
    .onChange(of: scene) { if $0 == .background { dismiss() } }
  }

  private func load() {
    do {
      existing = try records.load().reportReview?.first { $0.source == source }
      if let reading = existing?.reading {
        metric = reading.metric
        unit = reading.unit
        value = reading.value?.formatted(.number.locale(locale).grouping(.never)) ?? ""
        lower = reading.diastolic?.formatted(.number.locale(locale).grouping(.never)) ?? ""
        date = reading.measuredAt
      }
    } catch { failed = true }
  }

  private func stage() {
    guard scene == .active, dateConfirmed, ownership, let metric, metric.units.contains(unit),
          let parsed = decimal(value), date <= Date() else { failed = true; return }
    let reading = GalaxySSIHealthReading(id: existing?.reading.id ?? UUID(), metric: metric, measuredAt: date,
      value: parsed, diastolic: metric == .bloodPressure ? decimal(lower) : nil,
      unitOverride: unit, reportSource: source)
    do {
      try records.stageReportItem(.init(version: UUID(), source: source, excerpt: excerpt, reading: reading),
                                  replacing: existing?.version)
      dismiss()
    } catch { failed = true }
  }

  private func decimal(_ input: String) -> Decimal? {
    let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
    guard normalized.count <= 40,
          normalized.range(of: #"^[+-]?[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil
    else { return nil }
    return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSIHealthReportReview.text(key, fallback, language: language)
  }
}

@MainActor
struct GalaxySSIHealthReportBatchView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let records: GalaxySSIHealthRecords
  let store: GalaxySSIHealthOriginalStore
  let original: GalaxySSIHealthOriginalStore.Original
  @State private var items: [GalaxySSIHealthReportReview.Item] = []
  @State private var selected: Set<UUID> = []
  @State private var confirmation: Set<UUID> = []
  @State private var duplicateTargets: [UUID: GalaxySSIHealthReportReview.Target] = [:]
  @State private var linkedSelection: Set<UUID> = []
  @State private var linkConfirmation: [UUID: GalaxySSIHealthReportReview.Target] = [:]
  @State private var confirmingLinks = false
  @State private var confirming = false
  @State private var failed = false

  var body: some View {
    List {
      if scene == .active {
        if items.isEmpty { Text(t("empty", "No reviewed measurements to save.")) }
        ForEach(items) { item in
          let duplicate = duplicateTargets[item.version] != nil
          Toggle(isOn: Binding(get: { duplicate ? linkedSelection.contains(item.version) : selected.contains(item.version) }, set: { enabled in
            if duplicate {
              if enabled { linkedSelection.insert(item.version) } else { linkedSelection.remove(item.version) }
            } else {
              if enabled { selected.insert(item.version) } else { selected.remove(item.version) }
            }
          })) {
            VStack(alignment: .leading, spacing: 4) {
              Text(item.reading.metric.title(language: language))
              Text((item.reading.value?.formatted() ?? "") + " " + item.reading.unit)
              Text(item.reading.measuredAt, format: .dateTime).foregroundColor(.secondary)
              Text(item.excerpt).lineLimit(2).foregroundColor(.secondary)
              if duplicate { Text(t("duplicate_link", "Link to existing measurement")).foregroundColor(.secondary) }
            }
          }
          .swipeActions {
            Button(role: .destructive) {
              do { try records.discardReportItem(source: item.source, version: item.version); reload() }
              catch { failed = true }
            } label: { Label(t("discard", "Discard"), systemImage: "trash") }
          }
        }
        Button(t("save", "Save selected measurements")) {
          confirmation = selected
          confirming = true
        }.disabled(selected.isEmpty)
        if !duplicateTargets.isEmpty {
          Button(t("link_selected", "Link selected report items")) {
            linkConfirmation = duplicateTargets.filter { linkedSelection.contains($0.key) }
            confirmingLinks = !linkConfirmation.isEmpty
          }.disabled(linkedSelection.isEmpty)
        }
        if failed { Text(t("batch_error", "Nothing was saved. Check for duplicate or changed measurements.")).foregroundColor(.secondary) }
      }
    }
    .navigationTitle(t("batch", "Reviewed measurements"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onChange(of: scene) {
      if $0 == .active { reload() }
      else {
        items = []; confirmation = []; confirming = false
        duplicateTargets = [:]; linkedSelection = []; linkConfirmation = [:]; confirmingLinks = false
      }
    }
    .confirmationDialog(t("confirm", "Confirm these measurements?"), isPresented: $confirming, titleVisibility: .visible) {
      Button(t("save", "Save selected measurements"), action: save)
    }
    .confirmationDialog(t("confirm_links", "Add report evidence without adding measurements?"),
                        isPresented: $confirmingLinks, titleVisibility: .visible) {
      Button(t("link_selected", "Link selected report items"), action: saveLinks)
    }
  }

  private func reload() {
    guard scene == .active else { return }
    do {
      let archive = try records.load()
      items = archive.reportReview?.filter {
        $0.source.original == original.id && $0.source.sha256 == original.sha256
      } ?? []
      let current = archive.current
      let fresh: [UUID: GalaxySSIHealthReportReview.Target] = Dictionary(uniqueKeysWithValues: items.compactMap { item in
        GalaxySSIHealthReportReview.exactTarget(for: item, current: current).map { (item.version, $0) }
      })
      linkedSelection = linkedSelection.filter { fresh[$0] != nil && fresh[$0] == duplicateTargets[$0] }
      duplicateTargets = fresh
      selected.formIntersection(items.map(\.version).filter { fresh[$0] == nil })
    } catch { items = []; selected = []; duplicateTargets = [:]; linkedSelection = []; failed = true }
  }

  private func saveLinks() {
    guard scene == .active, !linkConfirmation.isEmpty else { return }
    defer { linkConfirmation = [] }
    do {
      _ = try store.read(original)
      try records.linkReportDuplicates(linkConfirmation, original: original)
      failed = false
      reload()
    } catch { failed = true; reload() }
  }

  private func save() {
    guard scene == .active, !confirmation.isEmpty else { return }
    defer { confirmation = [] }
    do {
      _ = try store.read(original)
      try records.confirmReportItems(confirmation, original: original)
      failed = false
      reload()
    } catch { failed = true; reload() }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSIHealthReportReview.text(key, fallback, language: language)
  }
}
