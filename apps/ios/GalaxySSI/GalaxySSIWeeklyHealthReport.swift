import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct GalaxySSIWeeklyHealthReport: Equatable {
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
  let sleepEvidence: GalaxySSIHealthSleepReminder.Evidence?

  init(current: [GalaxySSIHealthReading], interval: DateInterval, metrics: Set<GalaxySSIHealthMetric>, through: Date) {
    self.interval = interval
    self.metrics = metrics
    self.through = through
    sleepEvidence = nil
    readings = current.filter {
      !$0.deleted && metrics.contains($0.metric) && $0.measuredAt >= interval.start &&
        $0.measuredAt < interval.end && $0.measuredAt <= through
    }
  }

  init?(current: [GalaxySSIHealthReading], sleepEvidence: GalaxySSIHealthSleepReminder.Evidence) {
    guard let windows = sleepEvidence.windows, let rows = sleepEvidence.contributors(current, baseline: false)
    else { return nil }
    interval = windows.recent
    metrics = [.sleepDuration]
    through = windows.recent.end.addingTimeInterval(-1)
    readings = rows
    self.sleepEvidence = sleepEvidence
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
  var sleepEvidence: GalaxySSIHealthSleepReminder.Evidence? = nil
  @State private var allowed = false
  @State private var metrics = Set(GalaxySSIHealthMetric.allCases)
  @State private var preview: GalaxySSIWeeklyHealthReport?
  @State private var includeRows = false
  @State private var confirm = false
  @State private var exporting = false
  @State private var document: WeeklyHealthPDF?
  @State private var error = false
  @State private var staleEvidence = false

  var body: some View {
    Form {
      if scenePhase == .active && !exporting {
        Toggle(t("permission", "Allow local weekly reports"), isOn: Binding(get: { allowed }, set: setPermission))
        if staleEvidence {
          Text(t("linked_fixed_stale", "The saved sleep evidence no longer matches the contributing records."))
            .foregroundColor(.secondary)
        } else if allowed, let preview {
          if sleepEvidence == nil {
            Section(t("metrics", "Included measurements")) {
              ForEach(GalaxySSIHealthMetric.allCases) { metric in
                Toggle(metricTitle(metric), isOn: Binding(get: { metrics.contains(metric) }, set: { enabled in
                  if enabled { metrics.insert(metric) } else { metrics.remove(metric) }
                  reload()
                }))
              }
            }
          }
          Section(range(preview)) {
            ForEach(GalaxySSIHealthMetric.allCases.filter { preview.metrics.contains($0) }) { metric in
              Text(coverage(metric, preview))
            }
            if preview.readings.isEmpty { Text(t("empty", "No confirmed readings in this period.")) }
            ForEach(sleepComparison(preview), id: \.self) { Text($0) }
          }
          if !preview.readings.isEmpty {
            Toggle(t("include_rows", "Include measurement values in PDF"), isOn: $includeRows)
            Button(t("export", "Export PDF")) { confirm = true }
          }
        }
        if error {
          Text(t("failed", "Report unavailable or changed. Review the refreshed records before exporting."))
            .foregroundColor(.secondary)
          Button(t("reload", "Reload report"), action: reload)
        }
      }
    }
    .navigationTitle(t("title", "Weekly Health Report"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { notice in
      if sleepEvidence != nil, notice.object as? String == records.owner, !exporting { reload() }
    }
    .onChange(of: scenePhase) { phase in
      if phase == .active { reload() }
      else {
        preview = nil
        confirm = false
        if !exporting { document = nil }
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

  private func reload() {
    guard scenePhase == .active else { return }
    do {
      let archive = try records.load()
      allowed = archive.weeklyReportAllowed == true
      staleEvidence = false
      if let sleepEvidence {
        guard archive.derivesOverview == true else {
          allowed = false; preview = nil; includeRows = false; confirm = false
          return
        }
        preview = allowed ? GalaxySSIWeeklyHealthReport(current: archive.current, sleepEvidence: sleepEvidence) : nil
        staleEvidence = allowed && preview == nil
        if preview == nil { includeRows = false; confirm = false }
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
    } catch { allowed = false; preview = nil; staleEvidence = false; confirm = false; error = true }
  }

  private func export() {
    guard scenePhase == .active, allowed, let preview else { return }
    do {
      try records.prepareWeeklyExport(preview, includeRows: includeRows)
      var lines = [t("title", "Weekly Health Report"), range(preview)]
      lines += GalaxySSIHealthMetric.allCases.filter { preview.metrics.contains($0) }.map { coverage($0, preview) }
      lines += sleepComparison(preview, includeAverages: includeRows)
      if includeRows {
        lines += preview.readings.map { reading in
          let value = reading.reported?.raw ?? reading.value?.formatted(.number.locale(locale)) ?? ""
          let diastolic = reading.diastolic.map { "/" + $0.formatted(.number.locale(locale)) } ?? ""
          let pulse = reading.pulse.map { " · " + $0.formatted(.number.locale(locale)) + " bpm" } ?? ""
          return "\(formatDate(reading.measuredAt, report: preview, includeTime: true)) · \(metricTitle(reading.metric)) · \(value)\(diastolic) \(reading.unit)\(pulse)"
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
    let count = preview.readings.filter { $0.metric == metric }.count
    return String(format: t("coverage", "%@: %lld confirmed"), locale: locale, metricTitle(metric), Int64(count))
  }

  private func range(_ preview: GalaxySSIWeeklyHealthReport) -> String {
    "\(formatDate(preview.interval.start, report: preview)) – \(formatDate(preview.through, report: preview))"
  }

  private func formatDate(_ date: Date, report: GalaxySSIWeeklyHealthReport, includeTime: Bool = false) -> String {
    guard let calendar = report.sleepEvidence?.windows?.calendar else {
      return includeTime ? date.formatted() : date.formatted(date: .abbreviated, time: .omitted)
    }
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateStyle = .medium
    formatter.timeStyle = includeTime ? .short : .none
    return formatter.string(from: date)
  }

  private func sleepComparison(_ report: GalaxySSIWeeklyHealthReport, includeAverages: Bool = true) -> [String] {
    guard let evidence = report.sleepEvidence, let windows = evidence.windows else { return [] }
    let baselineDates = "\(formatDate(windows.baseline.start, report: report)) – \(formatDate(windows.baseline.end.addingTimeInterval(-1), report: report))"
    var lines = [String(format: t("sleep_baseline_coverage", "Baseline (%@): %lld of 14 days"),
      baselineDates, Int64(evidence.days.prefix(14).compactMap(\.minutes).count))]
    guard includeAverages else { return lines }
    let baseline = evidence.baselineMean.formatted(.number.locale(locale).precision(.fractionLength(0...1)))
    let recent = evidence.currentMean.formatted(.number.locale(locale).precision(.fractionLength(0...1)))
    lines.append(String(format: t("sleep_baseline", "Baseline daily average: %@ min"), baseline))
    lines.append(String(format: t("sleep_recent", "Recent daily average: %@ min"), recent))
    return lines
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
