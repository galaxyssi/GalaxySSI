import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthCarePlansSection: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let concernID: UUID
  @State private var plans: [GalaxySSIHealthCarePlan.Proposal] = []
  @State private var reviewing: GalaxySSIHealthCarePlan.Proposal?
  @State private var limit = 20

  var body: some View {
    Group {
      if scene == .active, store.profile.identityFingerprint == records.owner, !plans.isEmpty {
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
    .onChange(of: store.profile.identityFingerprint) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
      plans = []; reviewing = nil
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in reload() }
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
    guard scene == .active, UIApplication.shared.isProtectedDataAvailable,
          store.profile.identityFingerprint == records.owner,
          let archive = try? records.load(), archive.localCareAllowed == true,
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
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
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
  @State private var maintenance: GalaxySSIHealthCareMaintenance.Evaluation?
  @State private var confirmingMaintenance = false
  private var legacyPending: Bool { proposal.state == .pending && proposal.draft.sources.contains { $0.provenance == nil } }

  var body: some View {
    List {
      if scene == .active, visible, store.profile.identityFingerprint == records.owner {
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
          if let draft = proposal.draft.maintenance {
            Section(t("maintenance", "Maintenance review")) {
              Text(draft.rationale)
              if let maintenance {
                ForEach(maintenance.samples, id: \.record.id) { sample in
                  Text(sample.measuredAt, format: .dateTime) + Text("  " + sample.result + " " + sample.unit)
                }
                ForEach(GalaxySSIHealthCareMaintenance.Gap.allCases.filter { maintenance.gaps.contains($0) }, id: \.self) {
                  Text(maintenanceGap($0)).foregroundColor(.secondary)
                }
              }
              if proposal.maintenanceAccepted == true { Text(t("maintenance_accepted", "Maintenance review confirmed")) }
              Text(t("maintenance_boundary", "This review does not establish clinical stability or schedule a reminder."))
                .foregroundColor(.secondary)
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
            if let draft = proposal.draft.maintenance, maintenance?.gaps.isEmpty == true {
              Button(t("maintenance_review", "Review maintenance and next assessment")) { confirmingMaintenance = true }
                .disabled(!selected.contains(draft.recheckIndex))
            }
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
    .onChange(of: currentDestination) { _ in refresh() }
    .confirmationDialog(t("maintenance_review", "Review maintenance and next assessment"),
      isPresented: $confirmingMaintenance, titleVisibility: .visible) {
      Button(t("maintenance_confirm", "Confirm maintenance and selected steps")) {
        resolve(selected, acceptMaintenance: true)
      }
    } message: {
      Text(t("maintenance_boundary", "This review does not establish clinical stability or schedule a reminder."))
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner { refresh() }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.profileInputsChanged)) {
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
    guard scene == .active, UIApplication.shared.isProtectedDataAvailable,
          store.profile.identityFingerprint == records.owner,
          let archive = try? records.load(), archive.localCareAllowed == true,
          archive.localCarePlans?[proposal.id.uuidString] == proposal,
          archive.localCare?.current[proposal.metric.rawValue]?.id == proposal.concernID
    else { visible = false; valid = false; checkedConcern = nil; selected = []; maintenance = nil; return }
    visible = true
    checkedConcern = currentDestination == nil ? nil : (try? records.validateLocalCarePlanReview(proposal))
    valid = checkedConcern != nil
    maintenance = valid && proposal.draft.maintenance != nil ? (try? records.localCareMaintenancePreview(proposal)) : nil
    if let checkedConcern {
      selected = selected.intersection(Set(proposal.draft.actions.filter {
        GalaxySSIHealthCareApplicability.canAdopt($0, concern: checkedConcern)
      }.map(\.id)))
    } else { selected = [] }
  }

  private func resolve(_ selected: Set<Int>?, acceptMaintenance: Bool = false) {
    guard scene == .active, visible, UIApplication.shared.isProtectedDataAvailable,
          store.profile.identityFingerprint == records.owner else { return }
    do {
      try records.resolveLocalCarePlan(proposal, selected: selected, currentDestination: currentDestination,
        acceptMaintenance: acceptMaintenance)
      dismiss()
    }
    catch { failed = true; refresh() }
  }

  private func maintenanceGap(_ gap: GalaxySSIHealthCareMaintenance.Gap) -> String {
    switch gap {
    case .target: return t("maintenance_gap_target", "The saved target does not match this review.")
    case .history: return t("maintenance_gap_history", "The consecutive history window is incomplete or changed.")
    case .comparability: return t("maintenance_gap_comparability", "The measurements are not comparable.")
    case .applicability: return t("maintenance_gap_applicability", "Source applicability is unresolved.")
    case .openActions: return t("maintenance_gap_openActions", "Previous actions are still open.")
    case .recheck: return t("maintenance_gap_recheck", "A separate future reassessment is required.")
    case .priority: return t("maintenance_gap_priority", "A priority warning requires review first.")
    }
  }

  private var currentDestination: String? {
    guard let contact = store.contact(id: proposal.contactID), !contact.deleted, contact.deliveryMode == .cloudAPI,
          let model = contact.selectedCloudModel, let key = store.apiKey(for: model),
          !coordinator.healthDisclosureStore.blockedDestinationIds().contains(contact.id) else { return nil }
    return GalaxySSIHealthCarePlan.currentDestination(proposal, contactID: contact.id, model: model, credential: key)
  }
  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthPlanText.string(key, fallback, language: language) }
}

struct GalaxySSIHealthMaintenanceEvidenceView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let review: GalaxySSIHealthCareMaintenance.Review

  var body: some View {
    DisclosureGroup(GalaxySSIHealthPlanText.string("maintenance", "Maintenance review", language: language)) {
      Text(review.rationale)
      Text(review.source.title)
      if let quote = review.source.provenance?.quote { Text(quote).textSelection(.enabled) }
      Text(review.due, format: .dateTime)
      ForEach(review.samples, id: \.record.id) { sample in
        Text(sample.measuredAt, format: .dateTime) + Text("  " + sample.result + " " + sample.unit)
      }
    }
  }
}

private enum GalaxySSIHealthPlanText {
  static func string(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.plan." + key, fallback: fallback, language: language)
  }
}
