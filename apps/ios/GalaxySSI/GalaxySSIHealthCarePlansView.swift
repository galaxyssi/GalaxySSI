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
              GalaxySSIHealthCareApplicabilityDetails(action: action, concern: checkedConcern)
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
            Button(t("accept", "Accept selected steps")) { resolve(selected) }.disabled(selected.isEmpty)
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
    else { visible = false; valid = false; checkedConcern = nil; selected = []; return }
    visible = true
    checkedConcern = try? records.validateLocalCarePlanReview(proposal)
    valid = checkedConcern != nil
    if let checkedConcern {
      selected = selected.intersection(Set(proposal.draft.actions.filter {
        GalaxySSIHealthCareApplicability.canAdopt($0, concern: checkedConcern)
      }.map(\.id)))
    } else { selected = [] }
  }

  private func resolve(_ selected: Set<Int>?) {
    guard scene == .active, visible else { return }
    do { try records.resolveLocalCarePlan(proposal, selected: selected); dismiss() }
    catch { failed = true; refresh() }
  }
  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthPlanText.string(key, fallback, language: language) }
}

private enum GalaxySSIHealthPlanText {
  static func string(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.plan." + key, fallback: fallback, language: language)
  }
}
