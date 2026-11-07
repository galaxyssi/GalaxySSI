import SwiftUI

@MainActor
struct GalaxySSIHealthCareView: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  @State private var allowed = false
  @State private var concerns: [GalaxySSIHealthCare.Concern] = []
  @State private var failed = false
  @State private var revision = UUID()

  var body: some View {
    List {
      if scene == .active {
        Toggle(t("permission", "Allow local health review"), isOn: Binding(get: { allowed }, set: { enabled in
          do { try records.setPrivacy(.localCare, enabled: enabled); reload() }
          catch { failed = true }
        }))
        if allowed {
          Section(t("attention", "Needs attention")) {
            rows(concerns.filter { [.verify, .evidence, .reassess].contains($0.stage) })
          }
          Section(t("follow_up", "Improvement and follow-up")) {
            rows(concerns.filter { [.reviewPlan, .waitingResults, .maintenance, .paused, .closed].contains($0.stage) })
          }
          Section(t("sources", "Trends and originals")) {
            NavigationLink(t("trends", "Measurement trends")) { GalaxySSIHealthTrendView(records: records) }
            NavigationLink(t("originals", "Health originals")) {
              GalaxySSIHealthOriginalsView(store: .init(owner: records.owner, secrets: records.secrets))
            }
          }
        }
        if failed { Text(t("unavailable", "Local health review could not be loaded.")) }
      }
    }
    .navigationTitle(t("title", "Health Care"))
    .onAppear(perform: reload)
    .onChange(of: scene) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner {
        if allowed, (try? records.load().localCareAllowed) != true { allowed = false; concerns = [] }
        revision = UUID()
      }
    }
    .task(id: revision) {
      do { try await Task.sleep(nanoseconds: 180_000_000) } catch { return }
      reload()
    }
  }

  @ViewBuilder
  private func rows(_ values: [GalaxySSIHealthCare.Concern]) -> some View {
    if values.isEmpty { Text(t("empty", "No concerns")).foregroundColor(.secondary) }
    ForEach(values) { concern in
      NavigationLink {
        GalaxySSIHealthCareDetail(records: records, id: concern.id, metric: concern.metric)
      } label: {
        VStack(alignment: .leading, spacing: 4) {
          Text(concern.metric.title(language: language))
          Text(GalaxySSIHealthCareText.stage(concern.stage, language: language)).font(.caption).foregroundColor(.secondary)
        }
      }
    }
  }

  private func reload() {
    guard scene == .active else { allowed = false; concerns = []; failed = false; return }
    do {
      allowed = try records.load().localCareAllowed == true
      if allowed { try records.reconcileLocalCare() }
      if allowed, let ledger = try records.load().localCare {
        concerns = ledger.current.values.sorted { ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString) }
      } else { concerns = [] }
      failed = false
    } catch { concerns = []; failed = true }
  }

  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthCareText.string(key, fallback, language: language) }
}

@MainActor
struct GalaxySSIHealthCareEntry: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  @State private var visible = false
  @State private var revision = UUID()

  var body: some View {
    Group {
      if scene == .active, visible {
        NavigationLink {
          GalaxySSIHealthCareView(records: records)
        } label: {
          Label(GalaxySSIHealthCareText.string("title", "Health Care", language: language), systemImage: "heart.text.square")
            .font(.footnote.weight(.semibold))
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
    .onChange(of: scene) { phase in
      if phase == .active { revision = UUID() } else { visible = false }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner {
        visible = visible && ((try? records.load().localCareAllowed) == true)
        revision = UUID()
      }
    }
    .task(id: revision) {
      guard scene == .active else { visible = false; return }
      do {
        try await Task.sleep(nanoseconds: 220_000_000)
        try records.reconcileLocalCare()
        let concerns = try records.load().localCare?.current
        visible = concerns?.values.contains(where: { [.verify, .evidence, .reassess].contains($0.stage) }) == true
      } catch { if !Task.isCancelled { visible = false } }
    }
  }
}

@MainActor
private struct GalaxySSIHealthCareDetail: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let id: UUID
  let metric: GalaxySSIHealthMetric
  @State private var concern: GalaxySSIHealthCare.Concern?
  @State private var measurement: GalaxySSIHealthReading?
  @State private var history: [GalaxySSIHealthCare.Concern] = []
  @State private var hasMore = false
  @State private var stage = GalaxySSIHealthCare.Stage.reassess
  @State private var reason = ""
  @State private var targetValue = ""
  @State private var targetSource = ""
  @State private var rationale = ""
  @State private var confirmedBy = ""
  @State private var context = GalaxySSIHealthCare.Context.Applicability.unknown
  @State private var failed = false
  @State private var confirmingDelete = false

  var body: some View {
    List {
      if scene == .active, let concern {
        Section(t("attention", "Needs attention")) {
          if concern.stage != .paused, concern.stage != .closed, concern.assessment.record != nil {
            NavigationLink(t("discuss", "Discuss this concern")) {
              GalaxySSIHealthCareDiscussionView(records: records, concernID: concern.id, metric: metric)
            }
          }
          Text(GalaxySSIHealthCareText.stage(concern.stage, language: language))
          ForEach(concern.assessment.signals, id: \.rawValue) { signal in
            Text(GalaxySSIHealthCareText.signal(signal, language: language))
          }
          if let measurement {
            LabeledCareMeasurement(measurement: measurement, result: concern.assessment.result,
              title: t("measurement", "Source measurement"))
          }
        }
        Section(t("report_reference", "Report reference interval")) {
          Text(concern.assessment.reference.ifBlank(t("none", "Not recorded")))
        }
        Section(t("guideline", "Guideline criterion")) {
          if concern.assessment.guidelineVersion != nil {
            Link(t("ada", "ADA 2026: Diagnosis and Classification"), destination: GalaxySSIHealthCare.guidelineURL)
            Text(t("ada_threshold", "Lower fasting plasma glucose screening threshold: 100 mg/dL (5.6 mmol/L)."))
          } else { Text(t("none", "Not recorded")) }
          if metric == .glucose, measurement != nil {
            Picker(t("context", "Measurement context"), selection: $context) {
              Text(t("context_unknown", "Not confirmed")).tag(GalaxySSIHealthCare.Context.Applicability.unknown)
              Text(t("context_fasting", "Adult, not pregnant, no known diabetes; laboratory plasma after at least 8 hours without calories"))
                .tag(GalaxySSIHealthCare.Context.Applicability.applicable)
              Text(t("context_excluded", "This screening context does not apply"))
                .tag(GalaxySSIHealthCare.Context.Applicability.excluded)
            }
            Button(t("save_context", "Confirm measurement context")) {
              perform { try records.setLocalCareContext(concern, applicability: context) }
            }
          }
        }
        Section(t("baseline", "Historical observation range")) {
          if let baseline = concern.assessment.baseline {
            Text("\(NSDecimalNumber(decimal: baseline.low).stringValue) - \(NSDecimalNumber(decimal: baseline.high).stringValue) \(concern.assessment.unit)")
          } else { Text(t("none", "Not recorded")) }
        }
        Section(t("target", "Confirmed individual target")) {
          if let target = concern.target {
            Text(target.value)
            Text(target.source)
            Text(target.rationale)
            Text(target.confirmedBy)
            Text(target.confirmedAt, style: .date)
          }
          TextField(t("target", "Confirmed individual target"), text: $targetValue)
          TextField(t("target_source", "Target source"), text: $targetSource)
          TextField(t("reason", "Reason"), text: $rationale)
          TextField(t("confirmed_by", "Confirmed by"), text: $confirmedBy)
          Button(t("save_target", "Save confirmed target")) {
            perform {
              try records.setLocalCareTarget(concern, target: .init(value: targetValue, source: targetSource,
                rationale: rationale, confirmedBy: confirmedBy, confirmedAt: Date()))
              targetValue = ""; targetSource = ""; rationale = ""; confirmedBy = ""
            }
          }.disabled([targetValue, targetSource, rationale, confirmedBy].contains(where: \.isBlank))
        }
        Section(t("follow_up", "Improvement and follow-up")) {
          if let note = concern.reviewNote { Text(note) }
          Picker(t("stage", "Review status"), selection: $stage) {
            ForEach([GalaxySSIHealthCare.Stage.reassess, .paused, .maintenance, .closed], id: \.rawValue) {
              Text(GalaxySSIHealthCareText.stage($0, language: language)).tag($0)
            }
          }
          TextField(t("reason", "Reason"), text: $reason)
          Button(t("save_review", "Save review")) {
            perform { try records.reviewLocalCare(concern, stage: stage, reason: reason); reason = "" }
          }.disabled(reason.isBlank)
        }
        Section(t("history", "Concern history")) {
          ForEach(history, id: \.revision) { version in
            VStack(alignment: .leading, spacing: 4) {
              Text(GalaxySSIHealthCareText.stage(version.stage, language: language))
              Text(version.updatedAt, style: .date).foregroundColor(.secondary)
              if let note = version.reviewNote { Text(note).font(.caption) }
            }
          }
          if hasMore { Button(t("more", "Show more")) { loadHistory(append: true) } }
        }
        GalaxySSIHealthCarePlansSection(records: records, concernID: id)
        GalaxySSIHealthCareFollowUpsSection(records: records, concernID: id, metric: metric)
        Button(t("remove", "Delete concern"), role: .destructive) { confirmingDelete = true }
      }
      if scene == .active, failed { Text(t("unavailable", "Local health review could not be loaded.")) }
    }
    .navigationTitle(metric.title(language: language))
    .onAppear(perform: reload)
    .onChange(of: scene) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner { reload() }
    }
    .confirmationDialog(t("remove", "Delete concern"), isPresented: $confirmingDelete, titleVisibility: .visible) {
      Button(t("remove", "Delete concern"), role: .destructive) {
        if let concern { perform { try records.deleteLocalCare(concern); dismiss() } }
      }
    }
  }

  private func reload() {
    guard scene == .active, let archive = try? records.load(), archive.localCareAllowed == true,
          let current = archive.localCare?.current[metric.rawValue], current.id == id else {
      concern = nil; history = []; measurement = nil; reason = ""; targetValue = ""; targetSource = ""
      rationale = ""; confirmedBy = ""; confirmingDelete = false; context = .unknown
      return
    }
    concern = current
    context = current.context?.applicability ?? .unknown
    measurement = archive.current.first { GalaxySSIHealthCare.Record($0) == current.assessment.record }
    loadHistory(append: false)
  }

  private func loadHistory(append: Bool) {
    do {
      let page = try records.localCareHistory(id, before: append ? history.last?.revision ?? Int.max : Int.max)
      if append { history += page } else { history = page }
      hasMore = page.count == 30
    } catch { failed = true; history = []; hasMore = false }
  }

  private func perform(_ action: () throws -> Void) {
    guard scene == .active else { return }
    do { try action(); failed = false; reload() }
    catch { failed = true; reload() }
  }

  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthCareText.string(key, fallback, language: language) }
}

private struct LabeledCareMeasurement: View {
  let measurement: GalaxySSIHealthReading
  let result: String
  let title: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.caption).foregroundColor(.secondary)
      Text(result + " " + measurement.unit)
      Text(measurement.measuredAt, style: .date).foregroundColor(.secondary)
      if !measurement.conditions.isBlank { Text(measurement.conditions) }
    }
  }
}

private enum GalaxySSIHealthCareText {
  static func string(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.care." + key, fallback: fallback, language: language)
  }
  static func stage(_ stage: GalaxySSIHealthCare.Stage, language: String) -> String {
    let label: String
    switch stage {
    case .verify: label = "Verify context"
    case .evidence: label = "Review evidence"
    case .reviewPlan: label = "Review plan"
    case .waitingResults: label = "Waiting for results"
    case .reassess: label = "Reassess"
    case .maintenance: label = "Maintenance"
    case .paused: label = "Paused"
    case .closed: label = "Closed"
    }
    return string("stage." + stage.rawValue, label, language: language)
  }
  static func signal(_ signal: GalaxySSIHealthCare.Signal, language: String) -> String {
    let label: String
    switch signal {
    case .reportLow: label = "Below the report reference"
    case .reportHigh: label = "Above the report reference"
    case .notExact: label = "The report does not give an exact numeric result"
    case .glucoseContext: label = "Confirm glucose measurement context"
    case .guidelineReview: label = "Review the screening criterion; this is not a diagnosis or individual target"
    case .guidelineScope: label = "The confirmed context is outside this screening criterion"
    case .rising: label = "Recent comparable results increased"
    case .falling: label = "Recent comparable results decreased"
    case .sourceRemoved: label = "The source measurement is unavailable"
    }
    return string("signal." + signal.rawValue, label, language: language)
  }
}
