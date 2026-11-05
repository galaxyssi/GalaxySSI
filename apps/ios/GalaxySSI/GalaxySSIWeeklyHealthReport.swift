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
  private(set) var assistantScope: GalaxySSIHealthAnalysis.ReportScope?
  private(set) var comparisonReadings: [GalaxySSIHealthReading] = []
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

  init?(current: [GalaxySSIHealthReading], assistantScope: GalaxySSIHealthAnalysis.ReportScope,
        selected: Set<GalaxySSIHealthMetric>) {
    guard assistantScope.isCurrent(current, selected: selected) else { return nil }
    interval = assistantScope.interval
    metrics = selected
    through = interval.end.addingTimeInterval(-1)
    readings = GalaxySSIHealthAnalysis.Scope(interval: interval, metrics: selected).readings(in: current)
    self.assistantScope = assistantScope
    sleepEvidence = nil
    if let comparison = assistantScope.comparison {
      comparisonReadings = GalaxySSIHealthAnalysis.Scope(interval: comparison, metrics: selected).readings(in: current)
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
  let assistantScope: GalaxySSIHealthAnalysis.ReportScope?
  let sleepEvidence: GalaxySSIHealthSleepReminder.Evidence?
  @State private var allowed = false
  @State private var metrics = Set(GalaxySSIHealthMetric.allCases)
  @State private var preview: GalaxySSIWeeklyHealthReport?
  @State private var includeRows = false
  @State private var confirm = false
  @State private var exporting = false
  @State private var document: WeeklyHealthPDF?
  @State private var error = false
  @State private var reviewedAssistantScope: GalaxySSIHealthAnalysis.ReportScope?
  @State private var assistantStale = false
  @State private var assistantVisible = true
  @State private var contributor: GalaxySSIHealthReading?
  @State private var contributorLimit = 30

  @State private var staleEvidence = false

  init(records: GalaxySSIHealthRecords, assistantScope: GalaxySSIHealthAnalysis.ReportScope? = nil,
       sleepEvidence: GalaxySSIHealthSleepReminder.Evidence? = nil) {
    self.records = records
    self.assistantScope = assistantScope
    self.sleepEvidence = sleepEvidence
    _reviewedAssistantScope = State(initialValue: assistantScope)
    _metrics = State(initialValue: assistantScope?.metrics ?? Set(GalaxySSIHealthMetric.allCases))
  }

  var body: some View {
    Form {
      if scenePhase == .active && !exporting {
        if assistantVisible {
          Toggle(t("permission", "Allow local weekly reports"), isOn: Binding(get: { allowed }, set: setPermission))
        } else {
          Text(t("assistant_permission", "Local measurement summary permission is required for this linked report."))
        }
        if assistantStale && allowed {
          Text(t("assistant_stale", "The linked analysis changed. Review updated records for the same scope before exporting."))
          Button(t("assistant_refresh", "Review updated scope"), action: refreshAssistantScope)
        }
        if staleEvidence {
          Text(t("linked_fixed_stale", "The saved sleep evidence no longer matches the contributing records."))
            .foregroundColor(.secondary)
        } else if allowed, let preview {
          if sleepEvidence == nil {
            Section(t("metrics", "Included measurements")) {
              ForEach(GalaxySSIHealthMetric.allCases.filter { assistantScope?.metrics.contains($0) ?? true }) { metric in
                Toggle(metricTitle(metric), isOn: Binding(get: { metrics.contains(metric) }, set: { enabled in
                  if enabled { metrics.insert(metric) } else { metrics.remove(metric) }
                  includeRows = false
                  reload()
                }))
                .disabled(assistantScope != nil && metrics.count == 1 && metrics.contains(metric))
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
          if preview.assistantScope != nil { assistantSections(preview) }
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
      guard assistantScope != nil || sleepEvidence != nil,
            notice.object as? String == records.owner, !exporting else { return }
      contributor = nil
      reload()
    }
    .onChange(of: scenePhase) { phase in
      if phase == .active { reload() }
      else {
        preview = nil
        contributor = nil
        confirm = false
        if !exporting { document = nil }
      }
    }
    .confirmationDialog(t("plain_pdf", "Export an unencrypted PDF?"), isPresented: $confirm, titleVisibility: .visible) {
      Button(t("export", "Export PDF"), action: export)
    }
    .sheet(item: $contributor) { reading in
      if scenePhase == .active && allowed {
        VStack(alignment: .leading, spacing: 10) {
          Text(metricTitle(reading.metric)).font(.headline)
          Text(assistantDate(reading.measuredAt, includeTime: true))
          Text((reading.reported?.raw ?? reading.value?.formatted() ?? "") + " " + reading.unit)
          if let diastolic = reading.diastolic { Text(diastolic.formatted() + " " + reading.unit) }
          if let pulse = reading.pulse { Text(pulse.formatted() + " bpm") }
          Text(String(format: t("assistant_revision", "Revision %lld"), Int64(reading.revision)))
            .foregroundColor(.secondary)
          Button(t("assistant_close", "Close")) { contributor = nil }
        }
        .padding()
      }
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
      if let link = reviewedAssistantScope ?? assistantScope {
        loadAssistantReport(link, archive: archive)
        return
      }
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
    } catch { allowed = false; preview = nil; staleEvidence = false; confirm = false; contributor = nil; error = true }
  }

  private func loadAssistantReport(_ link: GalaxySSIHealthAnalysis.ReportScope, archive: GalaxySSIHealthRecords.Archive) {
    assistantVisible = archive.derivesOverview == true
    allowed = assistantVisible && archive.weeklyReportAllowed == true
    assistantStale = allowed && !metrics.isEmpty && !link.isCurrent(archive.current, selected: metrics)
    preview = allowed && !assistantStale
      ? GalaxySSIWeeklyHealthReport(current: archive.current, assistantScope: link, selected: metrics) : nil
    if preview == nil { includeRows = false; confirm = false; contributor = nil }
    error = false
  }

  private func refreshAssistantScope() {
    guard scenePhase == .active, let link = reviewedAssistantScope ?? assistantScope else { return }
    do {
      let archive = try records.load()
      guard archive.derivesOverview == true, archive.weeklyReportAllowed == true else { reload(); return }
      let refreshed = link.refreshed(archive.current)
      reviewedAssistantScope = refreshed
      includeRows = false; confirm = false; contributor = nil; contributorLimit = 30
      loadAssistantReport(refreshed, archive: archive)
    } catch { reload() }
  }

  @ViewBuilder
  private func assistantSections(_ report: GalaxySSIWeeklyHealthReport) -> some View {
    if let comparison = report.assistantScope?.comparison {
      Section(t("assistant_comparison", "Previous period")) {
        Text(assistantRange(comparison))
        ForEach(GalaxySSIHealthMetric.allCases.filter { report.metrics.contains($0) }) { metric in
          Text(coverage(metric, readings: report.comparisonReadings))
        }
      }
    }
    let rows = report.readings + report.comparisonReadings
    if !rows.isEmpty {
      Section(t("assistant_contributors", "Contributing records")) {
        ForEach(rows.prefix(contributorLimit)) { reading in
          Button {
            openContributor(reading, report: report)
          } label: {
            Text(metricTitle(reading.metric) + " · " + assistantDate(reading.measuredAt, includeTime: true))
          }
        }
        if rows.count > contributorLimit { Button(t("assistant_more", "Show more")) { contributorLimit += 30 } }
      }
    }
  }

  private func openContributor(_ reading: GalaxySSIHealthReading, report: GalaxySSIWeeklyHealthReport) {
    guard scenePhase == .active, let link = report.assistantScope, let archive = try? records.load(),
          archive.derivesOverview == true, archive.weeklyReportAllowed == true,
          let fresh = GalaxySSIWeeklyHealthReport(current: archive.current, assistantScope: link, selected: report.metrics),
          let exact = (fresh.readings + fresh.comparisonReadings).first(where: {
            $0.id == reading.id && $0.revision == reading.revision
          }) else { reload(); return }
    contributor = exact
  }

  private func export() {
    guard scenePhase == .active, allowed, let preview else { return }
    do {
      try records.prepareWeeklyExport(preview, includeRows: includeRows)
      var lines = [t("title", "Weekly Health Report"), range(preview)]
      lines += GalaxySSIHealthMetric.allCases.filter { preview.metrics.contains($0) }.map { coverage($0, preview) }
      if let comparison = preview.assistantScope?.comparison {
        lines.append(t("assistant_comparison", "Previous period") + ": " + assistantRange(comparison))
        lines += GalaxySSIHealthMetric.allCases.filter { preview.metrics.contains($0) }.map {
          coverage($0, readings: preview.comparisonReadings)
        }
      }
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
    coverage(metric, readings: preview.readings)
  }

  private func coverage(_ metric: GalaxySSIHealthMetric, readings: [GalaxySSIHealthReading]) -> String {
    let count = readings.filter { $0.metric == metric }.count
    return String(format: t("coverage", "%@: %lld confirmed"), locale: locale, metricTitle(metric), Int64(count))
  }

  private func range(_ preview: GalaxySSIWeeklyHealthReport) -> String {
    if preview.assistantScope != nil { return assistantRange(preview.interval) }
    return "\(formatDate(preview.interval.start, report: preview)) – \(formatDate(preview.through, report: preview))"
  }

  private func assistantRange(_ interval: DateInterval) -> String {
    "\(assistantDate(interval.start)) – \(assistantDate(interval.end.addingTimeInterval(-1)))"
  }

  private func assistantDate(_ date: Date, includeTime: Bool = false) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    let scopedCalendar = (reviewedAssistantScope ?? assistantScope)?.calendar ?? calendar
    formatter.calendar = scopedCalendar
    formatter.timeZone = scopedCalendar.timeZone
    formatter.dateStyle = .medium
    formatter.timeStyle = includeTime ? .short : .none
    return formatter.string(from: date)
  }

  private func formatDate(_ date: Date, report: GalaxySSIWeeklyHealthReport, includeTime: Bool = false) -> String {
    if report.assistantScope != nil { return assistantDate(date, includeTime: includeTime) }
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
