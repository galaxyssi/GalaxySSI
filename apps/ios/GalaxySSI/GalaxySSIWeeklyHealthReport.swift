import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct GalaxySSIWeeklyHealthReport: Equatable {
  struct Link: Identifiable {
    let id = UUID()
    let interval: DateInterval
    let metrics: Set<GalaxySSIHealthMetric>
    let calendar: Calendar
    let comparison: DateInterval?
    let revisions: [String]

    init(interval: DateInterval, metrics: Set<GalaxySSIHealthMetric>, calendar: Calendar,
         compare: Bool, current: [GalaxySSIHealthReading]) {
      self.interval = interval
      self.metrics = metrics
      self.calendar = calendar
      let dayCount = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
      let start = compare && dayCount > 0 ? calendar.date(byAdding: .day, value: -dayCount, to: interval.start) : nil
      let comparison = start.map { DateInterval(start: $0, end: interval.start) }
      self.comparison = comparison
      revisions = Self.stamps(current, interval: interval, metrics: metrics, comparison: comparison)
    }

    func isCurrent(_ current: [GalaxySSIHealthReading]) -> Bool {
      revisions == Self.stamps(current, interval: interval, metrics: metrics, comparison: comparison)
    }

    private static func stamps(_ current: [GalaxySSIHealthReading], interval: DateInterval,
                               metrics: Set<GalaxySSIHealthMetric>, comparison: DateInterval?) -> [String] {
      let start = comparison?.start ?? interval.start
      return current.filter { !$0.deleted && metrics.contains($0.metric) && $0.measuredAt >= start &&
        $0.measuredAt < interval.end }.map { "\($0.id):\($0.revision)" }.sorted()
    }
  }

  struct ExportRequest: Codable {
    var at: Date
    var interval: DateInterval
    var metrics: Set<GalaxySSIHealthMetric>
    var includeRows: Bool
    var revisionCount: Int
  }

  let interval: DateInterval
  let metrics: Set<GalaxySSIHealthMetric>
  let through: Date
  let readings: [GalaxySSIHealthReading]
  let comparison: DateInterval?
  let comparisonReadings: [GalaxySSIHealthReading]

  init(current: [GalaxySSIHealthReading], interval: DateInterval, metrics: Set<GalaxySSIHealthMetric>, through: Date,
       comparison: DateInterval? = nil) {
    self.interval = interval
    self.metrics = metrics
    self.through = through
    self.comparison = comparison
    readings = current.filter {
      !$0.deleted && metrics.contains($0.metric) && $0.measuredAt >= interval.start &&
        $0.measuredAt < interval.end && $0.measuredAt <= through
    }
    comparisonReadings = current.filter {
      guard let comparison else { return false }
      return !$0.deleted && metrics.contains($0.metric) && $0.measuredAt >= comparison.start &&
        $0.measuredAt < comparison.end && $0.measuredAt <= through
    }
  }
}

@MainActor
struct GalaxySSIWeeklyHealthReportView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  @Environment(\.locale) private var locale
  let records: GalaxySSIHealthRecords
  @State private var allowed = false
  @State private var metrics = Set(GalaxySSIHealthMetric.allCases)
  @State private var preview: GalaxySSIWeeklyHealthReport?
  @State private var includeRows = false
  @State private var confirm = false
  @State private var exporting = false
  @State private var document: WeeklyHealthPDF?
  @State private var error = false
  @State private var link: GalaxySSIWeeklyHealthReport.Link?
  @State private var staleLink = false
  @State private var contributor: GalaxySSIHealthReading?
  @State private var shown = 30

  init(records: GalaxySSIHealthRecords, link: GalaxySSIWeeklyHealthReport.Link? = nil) {
    self.records = records
    _link = State(initialValue: link)
    _metrics = State(initialValue: link?.metrics ?? Set(GalaxySSIHealthMetric.allCases))
  }

  var body: some View {
    Form {
      if scenePhase == .active && !exporting {
        Toggle(t("permission", "Allow local weekly reports"), isOn: Binding(get: { allowed }, set: setPermission))
        if allowed && staleLink {
          Text(t("linked_stale", "The linked analysis has changed. Refresh this scope before reviewing or exporting."))
          Button(t("reload", "Reload report")) { reload(acceptNewEvidence: true) }
        } else if allowed, let preview {
          Section(t("metrics", "Included measurements")) {
            ForEach(GalaxySSIHealthMetric.allCases.filter { link?.metrics.contains($0) ?? true }) { metric in
              Toggle(metricTitle(metric), isOn: Binding(get: { metrics.contains(metric) }, set: { enabled in
                if enabled { metrics.insert(metric) } else { metrics.remove(metric) }
                includeRows = false
                reload()
              }))
            }
          }
          if let comparison = preview.comparison {
            Section(t("comparison", "Previous period")) {
              Text(dateRange(comparison, through: comparison.end))
              ForEach(GalaxySSIHealthMetric.allCases.filter { preview.metrics.contains($0) }) { metric in
                Text(coverage(metric, readings: preview.comparisonReadings))
              }
            }
          }
          if !preview.readings.isEmpty || !preview.comparisonReadings.isEmpty {
            Section(t("contributors", "Contributing records")) {
              ForEach((preview.readings + preview.comparisonReadings).prefix(shown)) { reading in
                Button { openContributor(reading) } label: {
                  Text(metricTitle(reading.metric) + " · " + dateTime(reading.measuredAt))
                }
              }
              if preview.readings.count + preview.comparisonReadings.count > shown {
                Button(t("more", "Show more")) { shown += 30 }
              }
            }
          }
          Section(range(preview)) {
            ForEach(GalaxySSIHealthMetric.allCases.filter { preview.metrics.contains($0) }) { metric in
              Text(coverage(metric, preview))
            }
            if preview.readings.isEmpty { Text(t("empty", "No confirmed readings in this period.")) }
          }
          if !preview.readings.isEmpty {
            Toggle(t("include_rows", "Include measurement values in PDF"), isOn: $includeRows)
            Button(t("export", "Export PDF")) { confirm = true }
          }
        }
        if error {
          Text(t("failed", "Report unavailable or changed. Review the refreshed records before exporting."))
            .foregroundColor(.secondary)
          Button(t("reload", "Reload report")) { reload() }
        }
      }
    }
    .navigationTitle(t("title", "Weekly Health Report"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { reload() }
    .onChange(of: scenePhase) { phase in
      if phase == .active { reload() }
      else {
        preview = nil
        contributor = nil
        confirm = false
        if !exporting { document = nil }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.trendInputsChanged)) { event in
      guard event.object as? String == records.owner else { return }
      contributor = nil
      confirm = false
      includeRows = false
      reload()
    }
    .sheet(item: $contributor) { reading in
      if scenePhase == .active && allowed {
        VStack(alignment: .leading, spacing: 10) {
          Text(metricTitle(reading.metric)).font(.headline)
          Text(dateTime(reading.measuredAt))
          Text((reading.reported?.raw ?? reading.value?.formatted() ?? "") + " " + reading.unit)
          Text(String(format: t("revision", "Revision %lld"), Int64(reading.revision))).foregroundColor(.secondary)
          Button(t("close", "Close")) { contributor = nil }
        }
        .padding()
      }
    }
    .confirmationDialog(t("plain_pdf", "Export an unencrypted PDF?"), isPresented: $confirm, titleVisibility: .visible) {
      Button(t("export", "Export PDF"), action: export)
    }
    .fileExporter(isPresented: $exporting, document: document, contentType: .pdf,
                  defaultFilename: "GalaxySSI-Weekly-Health") { result in
      document = nil
      reload()
      if case .failure = result { error = true }
    }
    .onChange(of: exporting) { presented in
      if !presented { document = nil }
    }
  }

  private func setPermission(_ enabled: Bool) {
    do { try records.setWeeklyReportAllowed(enabled); reload() }
    catch { allowed = false; preview = nil; error = true }
  }

  private func reload(acceptNewEvidence: Bool = false) {
    guard scenePhase == .active else { return }
    do {
      let archive = try records.load()
      allowed = archive.weeklyReportAllowed == true
      if let linked = link {
        guard archive.derivesOverview == true else { allowed = false; preview = nil; return }
        if !linked.isCurrent(archive.current) && !acceptNewEvidence {
          staleLink = true; preview = nil; includeRows = false; return
        }
        if acceptNewEvidence {
          link = .init(interval: linked.interval, metrics: linked.metrics, calendar: linked.calendar,
                       compare: linked.comparison != nil, current: archive.current)
        }
        staleLink = false
        preview = allowed ? GalaxySSIWeeklyHealthReport(current: archive.current, interval: linked.interval,
          metrics: metrics, through: Date(), comparison: linked.comparison) : nil
        error = false
        return
      }
      let now = Date()
      var local = calendar
      local.timeZone = timeZone
      let today = local.startOfDay(for: now)
      let first = local.date(byAdding: .day, value: -6, to: today) ?? today
      let next = local.date(byAdding: .day, value: 1, to: today) ?? now
      preview = allowed ? GalaxySSIWeeklyHealthReport(current: archive.current,
        interval: DateInterval(start: first, end: next), metrics: metrics, through: now) : nil
      error = false
    } catch { allowed = false; preview = nil; error = true }
  }

  private func export() {
    guard scenePhase == .active, allowed, let preview else { return }
    do {
      try records.prepareWeeklyExport(preview, includeRows: includeRows, link: link)
      var lines = [t("title", "Weekly Health Report"), range(preview)]
      lines += GalaxySSIHealthMetric.allCases.filter { preview.metrics.contains($0) }.map { coverage($0, preview) }
      if let comparison = preview.comparison {
        lines += [t("comparison", "Previous period"), dateRange(comparison, through: comparison.end)]
        lines += GalaxySSIHealthMetric.allCases.filter { preview.metrics.contains($0) }
          .map { coverage($0, readings: preview.comparisonReadings) }
      }
      if includeRows {
        lines += preview.readings.map { reading in
          let value = reading.reported?.raw ?? reading.value?.formatted(.number.locale(locale)) ?? ""
          let diastolic = reading.diastolic.map { "/" + $0.formatted(.number.locale(locale)) } ?? ""
          let pulse = reading.pulse.map { " · " + $0.formatted(.number.locale(locale)) + " bpm" } ?? ""
          return "\(dateTime(reading.measuredAt)) · \(metricTitle(reading.metric)) · \(value)\(diastolic) \(reading.unit)\(pulse)"
        }
      }
      document = WeeklyHealthPDF(data: Self.render(lines))
      exporting = true
    } catch { reload(); error = true }
  }

  private static func render(_ lines: [String]) -> Data {
    let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
      context.beginPage()
      var y: CGFloat = 36
      for line in lines {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.black]
        let text = NSAttributedString(string: line, attributes: attributes)
        let size = text.boundingRect(with: CGSize(width: 540, height: .greatestFiniteMagnitude),
                                     options: [.usesLineFragmentOrigin], context: nil)
        let height = ceil(size.height) + 8
        if y + height > 756 { context.beginPage(); y = 36 }
        text.draw(with: CGRect(x: 36, y: y, width: 540, height: height), options: [.usesLineFragmentOrigin], context: nil)
        y += height
      }
    }
  }

  private func coverage(_ metric: GalaxySSIHealthMetric, _ preview: GalaxySSIWeeklyHealthReport) -> String {
    coverage(metric, readings: preview.readings)
  }

  private func coverage(_ metric: GalaxySSIHealthMetric, readings: [GalaxySSIHealthReading]) -> String {
    let count = readings.filter { $0.metric == metric }.count
    return String(format: t("coverage", "%@: %lld confirmed"), locale: locale, metricTitle(metric), Int64(count))
  }

  private func range(_ preview: GalaxySSIWeeklyHealthReport) -> String {
    dateRange(preview.interval, through: preview.through)
  }

  private var reportZone: TimeZone { link?.calendar.timeZone ?? timeZone }

  private func dateRange(_ interval: DateInterval, through: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeZone = reportZone
    formatter.locale = locale
    return formatter.string(from: interval.start) + " – " +
      formatter.string(from: min(through, interval.end.addingTimeInterval(-1)))
  }

  private func dateTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.timeZone = reportZone
    formatter.locale = locale
    return formatter.string(from: date)
  }

  private func openContributor(_ reading: GalaxySSIHealthReading) {
    do {
      let archive = try records.load()
      guard archive.weeklyReportAllowed == true, link == nil || archive.derivesOverview == true,
            archive.current.contains(where: { $0.id == reading.id && $0.revision == reading.revision })
      else { reload(); error = true; return }
      contributor = reading
    } catch { error = true }
  }

  private func metricTitle(_ metric: GalaxySSIHealthMetric) -> String {
    metric.title(language: language)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.weekly." + key, fallback: fallback, language: language)
  }
}

private struct WeeklyHealthPDF: FileDocument {
  static var readableContentTypes: [UTType] { [.pdf] }
  let data: Data

  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
    self.data = data
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
