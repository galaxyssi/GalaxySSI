import SwiftUI

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

  static func text(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.report_review." + key, fallback: fallback, language: language)
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
  @State private var confirming = false
  @State private var failed = false

  var body: some View {
    List {
      if scene == .active {
        if items.isEmpty { Text(t("empty", "No reviewed measurements to save.")) }
        ForEach(items) { item in
          Toggle(isOn: Binding(get: { selected.contains(item.version) }, set: { enabled in
            if enabled { selected.insert(item.version) } else { selected.remove(item.version) }
          })) {
            VStack(alignment: .leading, spacing: 4) {
              Text(item.reading.metric.title(language: language))
              Text((item.reading.value?.formatted() ?? "") + " " + item.reading.unit)
              Text(item.reading.measuredAt, format: .dateTime).foregroundColor(.secondary)
              Text(item.excerpt).lineLimit(2).foregroundColor(.secondary)
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
        if failed { Text(t("batch_error", "Nothing was saved. Check for duplicate or changed measurements.")).foregroundColor(.secondary) }
      }
    }
    .navigationTitle(t("batch", "Reviewed measurements"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onChange(of: scene) {
      if $0 == .active { reload() }
      else { items = []; confirmation = []; confirming = false }
    }
    .confirmationDialog(t("confirm", "Confirm these measurements?"), isPresented: $confirming, titleVisibility: .visible) {
      Button(t("save", "Save selected measurements"), action: save)
    }
  }

  private func reload() {
    guard scene == .active else { return }
    do {
      items = try records.load().reportReview?.filter {
        $0.source.original == original.id && $0.source.sha256 == original.sha256
      } ?? []
      selected.formIntersection(items.map(\.version))
    } catch { items = []; selected = []; failed = true }
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
