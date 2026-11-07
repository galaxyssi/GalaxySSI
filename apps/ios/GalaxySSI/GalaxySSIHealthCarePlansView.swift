import SwiftUI

@MainActor
struct GalaxySSIHealthCarePlansSection: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let concernID: UUID
  @State private var plans: [GalaxySSIHealthCarePlan.Proposal] = []
  @State private var reviewing: GalaxySSIHealthCarePlan.Proposal?
  @State private var limit = 20

  var body: some View {
    Group {
      if scene == .active, !plans.isEmpty {
        Section(t("title", "Health plans")) {
          ForEach(plans.prefix(limit)) { plan in
            Button {
              reviewing = plan
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(title(plan.state))
                Text(plan.createdAt, style: .date).foregroundColor(.secondary)
              }
            }
          }
          if plans.count > limit { Button(t("more", "Show more")) { limit += 20 } }
        }
      }
    }
    .onAppear(perform: reload)
    .onChange(of: scene) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner { reload() }
    }
    .sheet(item: $reviewing) { proposal in
      NavigationView {
        GalaxySSIHealthCarePlanReviewView(records: records, proposal: proposal)
      }.navigationViewStyle(.stack)
    }
  }

  private func reload() {
    guard scene == .active, let archive = try? records.load(), archive.localCareAllowed == true,
          archive.localCare?.current.values.contains(where: { $0.id == concernID }) == true else {
      plans = []; reviewing = nil
      return
    }
    plans = (archive.localCarePlans ?? [:]).values.filter { $0.concernID == concernID }
      .sorted { ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString) }
  }

  private func title(_ state: GalaxySSIHealthCarePlan.State) -> String {
    switch state {
    case .pending: return t("pending", "Review draft")
    case .accepted: return t("accepted", "Accepted plan")
    case .dismissed: return t("dismissed", "Discarded draft")
    }
  }
  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthPlanText.string(key, fallback, language: language) }
}

@MainActor
private struct GalaxySSIHealthCarePlanReviewView: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let proposal: GalaxySSIHealthCarePlan.Proposal
  @State private var selected = Set<Int>()
  @State private var valid = false
  @State private var visible = false
  @State private var checkedConcern: GalaxySSIHealthCare.Concern?
  @State private var selectedTarget = false
  @State private var selectedMaintenance = false
  @State private var maintenanceGaps: Set<GalaxySSIHealthCareMaintenance.Gap> = []
  @State private var maintenanceSamples: [GalaxySSIHealthCareComparison.Sample] = []
  @State private var retainedReview: GalaxySSIHealthCareMaintenance.Review?
  @State private var failed = false
  private var legacyPending: Bool { proposal.state == .pending && proposal.draft.sources.contains { $0.provenance == nil } }

  var body: some View {
    List {
      if scene == .active, visible {
        if valid || proposal.state != .pending || legacyPending {
          Section(t("uncertainty", "Uncertainty")) {
            Text(proposal.draft.uncertainty)
            Text(proposal.modelID).foregroundColor(.secondary)
            Text(proposal.endpoint.absoluteString).font(.caption).foregroundColor(.secondary)
          }
          Section(t("source_review", "Source reads (applicability not verified)")) {
            ForEach(Array(proposal.draft.sources.indices), id: \.self) { index in
              let source = proposal.draft.sources[index]
              VStack(alignment: .leading, spacing: 4) {
                Text(String(format: t("numbered_source", "Source %lld"), Int64(index) + 1) + ": " + source.title)
                Text(source.version).font(.caption)
                Text(source.url.absoluteString).font(.caption)
                Text(source.applicability).foregroundColor(.secondary)
                if let proof = source.provenance {
                  Text(proof.quote).textSelection(.enabled)
                  Text(t("retrieved", "Retrieved")).font(.caption)
                  Text(proof.retrievedAt, format: .dateTime).font(.caption)
                  Text(t("observed", "Recorded on this device")).font(.caption)
                  Text(proof.observedAt, format: .dateTime).font(.caption)
                } else {
                  Text(t("legacy_source", "No native read receipt")).font(.caption).foregroundColor(.secondary)
                }
              }
            }
          }
          Section(t("actions", "Suggested steps")) {
            ForEach(proposal.draft.actions) { action in
              if valid, let checkedConcern, GalaxySSIHealthCareApplicability.canAdopt(action, concern: checkedConcern) {
                Toggle(isOn: Binding(get: { selected.contains(action.id) }, set: { checked in
                  if checked { selected.insert(action.id) } else { selected.remove(action.id) }
                })) { actionLabel(action) }
              } else {
                actionLabel(action)
                if proposal.selected.contains(action.id) { Text(t("adopted", "Adopted")).font(.caption) }
              }
              GalaxySSIHealthCareApplicabilityDetails(review: action.applicability, concern: checkedConcern)
            }
          }
          if let target = proposal.draft.target {
            Section(GalaxySSIHealthCareTargetText.text("proposed", "Proposed individual target", language: language)) {
              GalaxySSIHealthCareTargetSummary(component: target.component, bounds: target.bounds, unit: target.unit)
              Text(target.rationale)
              Text(String(format: t("numbered_source", "Source %lld"), Int64(target.sourceIndex) + 1))
                .foregroundColor(.secondary)
              GalaxySSIHealthCareApplicabilityDetails(review: target.applicability, concern: checkedConcern)
              if canSelectTarget {
                Toggle(GalaxySSIHealthCareTargetText.text("select", "Confirm this target", language: language),
                  isOn: $selectedTarget)
                Text(GalaxySSIHealthCareTargetText.text("user_approval", "User confirmation is not clinician approval.",
                  language: language)).font(.caption).foregroundColor(.secondary)
              } else if proposal.targetAccepted == true {
                Text(GalaxySSIHealthCareTargetText.text("confirmed", "Confirmed by user", language: language))
              } else if valid {
                Text(GalaxySSIHealthCareTargetText.text("cannot_confirm", "Review the component, unit and applicability first.",
                  language: language)).foregroundColor(.secondary)
              }
            }
          }
          if let review = retainedReview {
            GalaxySSIHealthCareMaintenanceSection(review: review)
          } else if let draft = proposal.draft.maintenance {
            Section(maintenanceText("proposal", "Proposed maintenance review")) {
              Text(draft.rationale)
              Text(String(format: t("numbered_source", "Source %lld"), Int64(draft.sourceIndex) + 1))
              if proposal.draft.actions.indices.contains(draft.recheckIndex),
                 let due = proposal.draft.actions[draft.recheckIndex].dueFrom {
                Text(due, format: .dateTime)
              }
              GalaxySSIHealthCareApplicabilityDetails(review: draft.applicability, concern: checkedConcern)
              GalaxySSIHealthCareMaintenanceRows(samples: maintenanceSamples)
              ForEach(GalaxySSIHealthCareMaintenance.Gap.allCases.filter { maintenanceGaps.contains($0) }, id: \.rawValue) {
                Text(GalaxySSIHealthCareMaintenanceSection.gap($0, language: language)).foregroundColor(.secondary)
              }
              if valid && maintenanceGaps.isEmpty {
                Toggle(maintenanceText("confirm", "Confirm this maintenance review"), isOn: $selectedMaintenance)
                Text(maintenanceText("separate", "Also select the next reassessment action above. This does not schedule a notification."))
                  .font(.caption).foregroundColor(.secondary)
              }
            }
          }
        }
        if proposal.state == .pending {
          if !valid {
            if legacyPending {
              Text(t("legacy_pending", "This draft has no native read receipts. Request a new draft."))
            } else { Text(t("stale", "The measurement, concern or permission changed.")) }
          }
          if valid {
            Button(t("accept_selection", "Confirm selection")) {
              resolve(selected, acceptTarget: selectedTarget, acceptMaintenance: selectedMaintenance)
            }
            .disabled((selected.isEmpty && !selectedTarget) ||
              (selectedMaintenance && proposal.draft.maintenance.map { !selected.contains($0.recheckIndex) } != false))
            Text(t("not_scheduled", "Accepting steps does not schedule reminders.")).foregroundColor(.secondary)
          }
          Button(t("discard", "Discard draft"), role: .destructive) { resolve(nil) }
        }
        if failed { Text(t("failed", "The plan could not be updated.")) }
      }
    }
    .navigationTitle(t("title", "Health plans"))
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button(t("close", "Close")) { dismiss() } }
    }
    .onAppear(perform: refresh)
    .onChange(of: scene) { _ in refresh() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner { refresh() }
    }
  }

  private func actionLabel(_ action: GalaxySSIHealthCarePlan.Action) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(action.description)
      Text(action.rationale).foregroundColor(.secondary)
      if let from = action.dueFrom, let until = action.dueUntil {
        Text(t("window", "Suggested review window")).font(.caption)
        Text(from, format: .dateTime)
        Text(until, format: .dateTime)
      }
    }
  }

  private func refresh() {
    guard scene == .active, let archive = try? records.load(), archive.localCareAllowed == true,
          archive.localCarePlans?[proposal.id.uuidString] == proposal,
          archive.localCare?.current[proposal.metric.rawValue]?.id == proposal.concernID
    else {
      visible = false; valid = false; checkedConcern = nil; selected = []; selectedTarget = false
      selectedMaintenance = false; maintenanceGaps = []; maintenanceSamples = []; retainedReview = nil
      return
    }
    visible = true
    checkedConcern = try? records.validateLocalCarePlanReview(proposal)
    valid = checkedConcern != nil
    if let checkedConcern {
      selected = selected.intersection(Set(proposal.draft.actions.filter {
        GalaxySSIHealthCareApplicability.canAdopt($0, concern: checkedConcern)
      }.map(\.id)))
    } else { selected = [] }
    if !canSelectTarget { selectedTarget = false }
    let preview = valid && proposal.draft.maintenance != nil ? (try? records.localCareMaintenancePreview(proposal)) : nil
    maintenanceGaps = proposal.draft.maintenance == nil ? [] : preview?.gaps ?? [.history]
    maintenanceSamples = preview?.samples ?? []
    if !valid || !maintenanceGaps.isEmpty { selectedMaintenance = false }
    let current = archive.localCare?.current[proposal.metric.rawValue]?.maintenance
    retainedReview = current?.proposalID == proposal.id ? current :
      archive.localCare?.history[proposal.concernID.uuidString]?.reversed()
        .compactMap(\.maintenance).first { $0.proposalID == proposal.id }
  }

  private var canSelectTarget: Bool {
    guard valid, let target = proposal.draft.target, let checkedConcern else { return false }
    return GalaxySSIHealthCareTarget.canConfirm(target, concern: checkedConcern)
  }

  private func resolve(_ selected: Set<Int>?, acceptTarget: Bool = false, acceptMaintenance: Bool = false) {
    guard scene == .active, visible else { return }
    do {
      try records.resolveLocalCarePlan(proposal, selected: selected, acceptTarget: acceptTarget,
        acceptMaintenance: acceptMaintenance)
      dismiss()
    }
    catch { failed = true; refresh() }
  }
  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthPlanText.string(key, fallback, language: language) }
  private func maintenanceText(_ key: String, _ fallback: String) -> String {
    GalaxySSIHealthCareMaintenanceSection.text(key, fallback, language: language)
  }
}

struct GalaxySSIHealthCareMaintenanceSection: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let review: GalaxySSIHealthCareMaintenance.Review

  var body: some View {
    Section(Self.text("retained", "Confirmed maintenance evidence", language: language)) {
      Text(review.rationale)
      Text(review.basis == .currentTarget
        ? Self.text("target_basis", "Existing individual target", language: language)
        : Self.text("risk_basis", "Source-backed risk review", language: language))
      Text(Self.text("next", "Next reassessment", language: language)).foregroundColor(.secondary)
      Text(review.due, format: .dateTime)
      Link(review.source.title, destination: review.source.url)
      if let proof = review.source.provenance { Text(proof.quote).font(.footnote).textSelection(.enabled) }
      GalaxySSIHealthCareMaintenanceRows(samples: review.samples)
      Text(Self.text("not_stable", "Maintenance review is not confirmation of clinical stability.", language: language))
        .font(.caption).foregroundColor(.secondary)
    }
  }

  static func gap(_ gap: GalaxySSIHealthCareMaintenance.Gap, language: String) -> String {
    let fallback: String
    switch gap {
    case .target: fallback = "The existing target or risk basis does not match."
    case .history: fallback = "A complete consecutive history window is required."
    case .comparability: fallback = "The selected records are not comparable."
    case .applicability: fallback = "The source requirements do not match the confirmed context."
    case .openActions: fallback = "Review existing actions first."
    case .recheck: fallback = "A future, applicable reassessment action is required."
    case .priority: fallback = "Review the recorded priority warning first."
    }
    return text("gap." + gap.rawValue, fallback, language: language)
  }

  static func text(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.maintenance." + key, fallback: fallback, language: language)
  }
}

private struct GalaxySSIHealthCareMaintenanceRows: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let samples: [GalaxySSIHealthCareComparison.Sample]

  var body: some View {
    ForEach(samples, id: \.record.id) { sample in
      VStack(alignment: .leading, spacing: 3) {
        Text(sample.result + " " + sample.unit)
        Text(sample.measuredAt, format: .dateTime)
        Text(String(format: GalaxySSIHealthCareMaintenanceSection.text("revision", "Revision %lld", language: language),
          Int64(sample.record.revision)))
      }.font(.footnote)
    }
  }
}

private enum GalaxySSIHealthPlanText {
  static func string(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.plan." + key, fallback: fallback, language: language)
  }
}
