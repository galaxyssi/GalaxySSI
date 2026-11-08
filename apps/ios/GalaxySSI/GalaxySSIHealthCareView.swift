import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthCareView: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  @State private var allowed = false
  @State private var concerns: [GalaxySSIHealthCare.Concern] = []
  @State private var priorityID: UUID?
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
          if let priorityID, let priority = concerns.first(where: { $0.id == priorityID }) {
            Section(GalaxySSILocalization.string("galaxyssi.health.priority.section", fallback: "Review first", language: language)) {
              rows([priority])
            }
          }
          Section(t("attention", "Needs attention")) {
            rows(concerns.filter { $0.id != priorityID && [.verify, .evidence, .reassess].contains($0.stage) })
          }
          Section(t("follow_up", "Improvement and follow-up")) {
            rows(concerns.filter {
              $0.id != priorityID && [.reviewPlan, .waitingResults, .maintenance, .paused, .closed].contains($0.stage)
            })
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
        priorityID = nil
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
    guard scene == .active else { allowed = false; concerns = []; priorityID = nil; failed = false; return }
    do {
      allowed = try records.load().localCareAllowed == true
      if allowed { try records.reconcileLocalCare() }
      let archive = try records.load()
      priorityID = nil
      if allowed, let ledger = archive.localCare {
        concerns = ledger.current.values.sorted { ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString) }
        if let priority = GalaxySSIHealthRecords.currentCareBloodPressureWarning(archive),
           ledger.acknowledgedBloodPressure != priority.warning.record,
           ![.paused, .closed].contains(priority.concern.stage) { priorityID = priority.concern.id }
      } else { concerns = [] }
      failed = false
    } catch { concerns = []; priorityID = nil; failed = true }
  }

  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthCareText.string(key, fallback, language: language) }
}

@MainActor
struct GalaxySSIHealthCareEntry: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let conversationID: String
  @State private var concerns: [GalaxySSIHealthCare.Concern] = []
  @State private var priority: GalaxySSIHealthCarePriority.Warning?
  @State private var priorityConcernID: UUID?
  @State private var discussion: GalaxySSIHealthCare.AgentDiscussionTarget?
  @State private var displayedPermission: UUID?
  @State private var expanded = false
  @State private var revision = UUID()

  var body: some View {
    Group {
      if canRead, let concern = concerns.first {
        VStack(alignment: .leading, spacing: 6) {
          if let priority, let priorityConcernID {
            NavigationLink {
              GalaxySSIHealthCareDetail(records: records, id: priorityConcernID, metric: .bloodPressure)
            } label: {
              GalaxySSIHealthCarePriorityNotice(warning: priority, compact: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          HStack(spacing: 8) {
            concernLink(concern, primary: true)
            Button { expanded.toggle() } label: {
              Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? t("agent.collapse", "Hide Health details") : t("agent.expand", "Show Health details"))
            .accessibilityIdentifier("agent-health-care-details")
          }
          let reason = concern.assessment.signals.first.map { GalaxySSIHealthCareText.signal($0, language: language) }
            ?? t("agent.local_follow_up", "Local health follow-up")
          summaryLine(t("agent.reason", "Reason"), reason)
            .accessibilityIdentifier("agent-health-care-reason")
          summaryLine(t("agent.next", "Next step"), nextStep(concern.stage))
            .accessibilityIdentifier("agent-health-care-next")
          if concern.assessment.record != nil {
            Button { openDiscussion(concern) } label: {
              Label(t("agent.discuss", "Private discussion"), systemImage: "bubble.left")
                .font(.footnote)
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("agent-health-care-discussion")
          }
          if expanded {
            details
          }
        }
        .padding(.bottom, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .onChange(of: scene) { phase in
      if phase != .active { clear() }
      revision = UUID()
    }
    .onChange(of: store.profile.identityFingerprint) { _ in clear() }
    .onChange(of: store.activeAgentConversationId) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
      clear()
      revision = UUID()
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
      revision = UUID()
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      guard $0.object as? String == records.owner else { return }
      guard canRead, let archive = try? records.load(), archive.localCareAllowed == true else { clear(); return }
      if let discussion, !discussion.matches(archive) { self.discussion = nil }
      setPriority(archive)
      revision = UUID()
    }
    .sheet(item: $discussion) { target in
      if canRead {
        NavigationView {
          GalaxySSIHealthCareDiscussionView(records: records, concernID: target.id, metric: target.metric)
        }
        .navigationViewStyle(.stack)
      }
    }
    .task(id: revision) {
      guard canRead else { clear(); return }
      do {
        try await Task.sleep(nanoseconds: 220_000_000)
        guard canRead else { clear(); return }
        try records.reconcileLocalCare()
        let archive = try records.load()
        let current = GalaxySSIHealthCare.agentConcerns(in: archive)
        try Task.checkCancellation()
        if current.first?.id != concerns.first?.id { expanded = false }
        displayedPermission = GalaxySSIHealthCare.AgentDiscussionTarget.permission(in: archive)
        concerns = current
        setPriority(archive)
      } catch { if !Task.isCancelled { clear() } }
    }
  }

  private var canRead: Bool {
    guard scene == .active, UIApplication.shared.isProtectedDataAvailable,
          store.profile.identityFingerprint == records.owner, store.activeAgentConversationId == conversationID,
          let session = store.agentSession(id: conversationID), session.status == .active,
          session.collaborationRoster == nil else { return false }
    return !session.privateMode && !session.trackingPaused
  }

  private func openDiscussion(_ concern: GalaxySSIHealthCare.Concern) {
    guard canRead, let archive = try? records.load() else { return }
    let target = GalaxySSIHealthCare.AgentDiscussionTarget(concern, permission: displayedPermission)
    guard target.matches(archive) else { return }
    discussion = target
  }

  private func setPriority(_ archive: GalaxySSIHealthRecords.Archive) {
    if let current = GalaxySSIHealthRecords.currentCareBloodPressureWarning(archive),
       archive.localCare?.acknowledgedBloodPressure != current.warning.record,
       ![.paused, .closed].contains(current.concern.stage) {
      priority = current.warning
      priorityConcernID = current.concern.id
    } else {
      priority = nil; priorityConcernID = nil
    }
  }

  private func clear() {
    concerns = []; expanded = false; priority = nil; priorityConcernID = nil; discussion = nil; displayedPermission = nil
  }

  private var details: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(concerns.dropFirst()) { concern in concernLink(concern, primary: false) }
        NavigationLink {
          GalaxySSIHealthCareView(records: records)
        } label: {
          Label(t("title", "Health Care"), systemImage: "heart.text.square")
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
      }
      .font(.footnote)
    }
    .frame(height: CGFloat(concerns.count) * 44)
  }

  private func concernLink(_ concern: GalaxySSIHealthCare.Concern, primary: Bool) -> some View {
    NavigationLink {
      GalaxySSIHealthCareDetail(records: records, id: concern.id, metric: concern.metric)
    } label: {
      Label(concern.metric.title(language: language), systemImage: primary ? "heart.text.square" : "chevron.right")
        .font(.footnote.weight(primary ? .semibold : .regular))
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
  }

  private func summaryLine(_ label: String, _ value: String) -> some View {
    (Text(label + ": ").fontWeight(.semibold) + Text(value))
      .font(.caption)
      .foregroundColor(.secondary)
      .lineLimit(2)
  }

  private func nextStep(_ stage: GalaxySSIHealthCare.Stage) -> String {
    switch stage {
    case .verify, .evidence, .reviewPlan, .waitingResults:
      return GalaxySSIHealthCareText.stage(stage, language: language)
    case .reassess:
      return t("agent.next_reassess", "Review what changed in the recorded results")
    case .maintenance:
      return t("agent.next_maintenance", "Review the ongoing follow-up")
    case .paused, .closed:
      return GalaxySSIHealthCareText.stage(stage, language: language)
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSIHealthCareText.string(key, fallback, language: language)
  }
}

@MainActor
private struct GalaxySSIHealthCareDetail: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let id: UUID
  let metric: GalaxySSIHealthMetric
  @State private var concern: GalaxySSIHealthCare.Concern?
  @State private var measurement: GalaxySSIHealthReading?
  @State private var bloodPressureWarning: GalaxySSIHealthCarePriority.Warning?
  @State private var warningReviewed = false
  @State private var history: [GalaxySSIHealthCare.Concern] = []
  @State private var hasMore = false
  @State private var stage = GalaxySSIHealthCare.Stage.reassess
  @State private var reason = ""
  @State private var context = GalaxySSIHealthCare.Context.Applicability.unknown
  @State private var answers = GalaxySSIHealthCare.Context.Answers()
  @State private var fastingHours = ""
  @State private var failed = false
  @State private var confirmingDelete = false
  @State private var deletionCandidate: GalaxySSIHealthCare.Concern?

  var body: some View {
    List {
      if canRead, let concern {
        if let bloodPressureWarning {
          Section {
            GalaxySSIHealthCarePriorityNotice(warning: bloodPressureWarning)
            if warningReviewed {
              Text(GalaxySSILocalization.string("galaxyssi.health.priority.reviewed",
                fallback: "Marked as reviewed for this reading", language: language)).foregroundColor(.secondary)
            } else {
              Button(GalaxySSILocalization.string("galaxyssi.health.priority.review",
                fallback: "Mark this reading as reviewed", language: language)) {
                perform { try records.acknowledgeLocalCareBloodPressure(bloodPressureWarning) }
              }
            }
          }
        }
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
        GalaxySSIHealthCareComparisonSection(records: records, id: id, metric: metric)
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
            clarificationFields
            Button(t("save_context", "Confirm measurement context")) {
              perform {
                var saved = answers
                saved.fastingHours = Int(fastingHours)
                try records.setLocalCareContext(concern, applicability: context, answers: saved)
              }
            }
            .disabled(!fastingHours.isEmpty && Int(fastingHours).map { (0...72).contains($0) } != true)
          } else if measurement != nil {
            collectionPicker
            Button(t("save_context", "Confirm measurement context")) {
              perform { try records.setLocalCareContext(concern, applicability: .unknown,
                answers: .init(collection: answers.collection)) }
            }
          }
        }
        Section(t("baseline", "Historical observation range")) {
          if let baseline = concern.assessment.baseline {
            Text("\(NSDecimalNumber(decimal: baseline.low).stringValue) - \(NSDecimalNumber(decimal: baseline.high).stringValue) \(concern.assessment.unit)")
          } else { Text(t("none", "Not recorded")) }
        }
        GalaxySSIHealthCareTargetSection(records: records, concern: concern)
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
        GalaxySSIHealthCareSeriesLink(records: records, id: id, metric: metric)
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
        Button(t("remove", "Delete concern"), role: .destructive) {
          deletionCandidate = concern
          confirmingDelete = true
        }
      }
      if scene == .active, failed { Text(t("unavailable", "Local health review could not be loaded.")) }
    }
    .navigationTitle(metric.title(language: language))
    .onAppear(perform: reload)
    .onChange(of: scene) { _ in reload() }
    .onChange(of: store.profile.identityFingerprint) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
      clearDetail()
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner { reload() }
    }
    .confirmationDialog(t("remove", "Delete concern"), isPresented: $confirmingDelete,
                        titleVisibility: .visible, presenting: deletionCandidate) { candidate in
      Button(t("remove", "Delete concern"), role: .destructive) {
        deletionCandidate = nil
        perform { try records.deleteLocalCare(candidate); dismiss() }
      }
    }
  }

  private var clarificationFields: some View {
    DisclosureGroup(t("clarification.title", "Recorded answers")) {
      collectionPicker
      truth(t("clarification.adult", "Adult"), value: $answers.adult)
      truth(t("clarification.pregnant", "Pregnant at measurement"), value: $answers.pregnant)
      truth(t("clarification.diabetes", "Diagnosed diabetes"), value: $answers.diagnosedDiabetes)
      Picker(t("clarification.specimen", "Sample type"), selection: $answers.specimen) {
        Text(t("none", "Not recorded")).tag(GalaxySSIHealthCare.Context.Answers.Specimen?.none)
        Text(t("clarification.plasma", "Laboratory plasma")).tag(Optional(GalaxySSIHealthCare.Context.Answers.Specimen.labPlasma))
        Text(t("clarification.capillary", "Home capillary")).tag(Optional(GalaxySSIHealthCare.Context.Answers.Specimen.homeCapillary))
        Text(t("clarification.interstitial", "Interstitial")).tag(Optional(GalaxySSIHealthCare.Context.Answers.Specimen.interstitial))
      }
      TextField(t("clarification.fasting", "Hours without calories (0–72)"), text: $fastingHours)
        .keyboardType(.numberPad)
      truth(t("clarification.illness", "Illness or glucose-affecting medication at measurement"), value: $answers.illnessOrMedication)
    }
  }

  private var collectionPicker: some View {
    typealias Collection = GalaxySSIHealthCare.Context.Answers.Collection
    return Picker(t("clarification.collection", "Collection condition"), selection: $answers.collection) {
      Text(t("none", "Not recorded")).tag(Collection?.none)
      Text(t("clarification.collection.fasting", "Fasting")).tag(Optional(Collection.fasting))
      Text(t("clarification.collection.after_meal", "After a meal")).tag(Optional(Collection.afterMeal))
      Text(t("clarification.collection.resting", "Resting")).tag(Optional(Collection.resting))
      Text(t("clarification.collection.after_activity", "After activity")).tag(Optional(Collection.afterActivity))
    }
  }

  private func truth(_ label: String, value: Binding<Bool?>) -> some View {
    Picker(label, selection: value) {
      Text(t("none", "Not recorded")).tag(Bool?.none)
      Text(t("clarification.yes", "Yes")).tag(Optional(true))
      Text(t("clarification.no", "No")).tag(Optional(false))
    }
  }

  private var canRead: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }

  private func clearDetail() {
    concern = nil; history = []; measurement = nil; reason = ""
    bloodPressureWarning = nil; warningReviewed = false
    confirmingDelete = false; deletionCandidate = nil; context = .unknown; answers = .init(); fastingHours = ""
  }

  private func reload() {
    bloodPressureWarning = nil
    warningReviewed = false
    guard canRead, let archive = try? records.load(), archive.localCareAllowed == true,
          let current = archive.localCare?.current[metric.rawValue], current.id == id else {
      clearDetail()
      return
    }
    if concern != current {
      let saved = current.context.flatMap { $0.record == current.assessment.record ? $0 : nil }
      context = saved?.applicability ?? .unknown
      answers = saved?.answers ?? .init()
      fastingHours = answers.fastingHours.map { String($0) } ?? ""
    }
    concern = current
    if let priority = GalaxySSIHealthRecords.currentCareBloodPressureWarning(archive), priority.concern.id == id {
      bloodPressureWarning = priority.warning
      warningReviewed = archive.localCare?.acknowledgedBloodPressure == priority.warning.record
    }
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
    guard canRead else { return }
    do { try action(); failed = false; reload() }
    catch GalaxySSIHealthRecords.Failure.stale { try? records.reconcileLocalCare(); failed = true; reload() }
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

enum GalaxySSIHealthCareText {
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
