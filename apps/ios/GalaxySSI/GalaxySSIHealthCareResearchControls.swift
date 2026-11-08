import CryptoKit
import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthCareResearchControls: View {
  typealias Research = GalaxySSIHealthCareResearch
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let concern: UUID
  let metric: GalaxySSIHealthMetric
  @State private var online = false
  @State private var authorization: Research.Authorization?
  @State private var job: Research.Job?
  @State private var provider = ""
  @State private var sources = Set<GalaxySSIHealthCareEvidence.PublicSource>()
  @State private var review: Review?
  @State private var confirmed = false
  @State private var failed = false

  private struct Review: Identifiable {
    let approval: GalaxySSIHealthCareDiscussion.Approval
    let sources: Set<GalaxySSIHealthCareEvidence.PublicSource>
    var id: UUID { approval.id }
  }

  var body: some View {
    Section(t("title", "Automatic source research")) {
      if canRead {
        if let authorization {
          Text(authorization.model)
          Text(authorization.endpoint.absoluteString).font(.caption).foregroundColor(.secondary)
          if let job { Text(status(job.state)) }
          Button(t("revoke", "Revoke research authorization"), role: .destructive) {
            do { try records.revokeLocalCareResearch(concern); reload() }
            catch { failed = true }
          }
        } else if online {
          Picker(t("provider", "Provider and model"), selection: $provider) {
            Text(t("select", "Select a model")).tag("")
            ForEach(store.contacts.filter { route($0.id) != nil }) { contact in
              Text(contact.name + " / " + (contact.selectedCloudModel?.modelId ?? "")).tag(contact.id)
            }
          }
          ForEach(GalaxySSIHealthCareEvidence.PublicSource.allCases) { source in
            Toggle(source.title, isOn: Binding(get: { sources.contains(source) }, set: {
              if $0 { sources.insert(source) } else { sources.remove(source) }
            }))
          }
          Button(t("review", "Review authorization"), action: preview).disabled(provider.isEmpty || sources.isEmpty)
        } else {
          Text(t("online_off", "Online Health discussion is off.")).foregroundColor(.secondary)
        }
        if failed { Text(t("unavailable", "Research authorization is no longer available.")) }
      }
    }
    .onAppear(perform: reload)
    .onChange(of: scene) { if $0 == .active { reload() } else { clear() } }
    .onChange(of: store.profile.identityFingerprint) { _ in clear(); reload() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner { reload() }
    }
    .sheet(item: $review) { proposed in
      NavigationView {
        List {
          if canRead {
            Section(t("provider", "Provider and model")) {
              Text(proposed.approval.model.modelId)
              Text(proposed.approval.endpoint.absoluteString).font(.caption).textSelection(.enabled)
              Text(t("effort", "Model effort: provider default"))
            }
            Section(t("sources", "Allowed public sources")) {
              ForEach(GalaxySSIHealthCareEvidence.PublicSource.allCases.filter { proposed.sources.contains($0) }) {
                Text($0.title)
              }
            }
            Text(t("scope", "While GalaxySSI is active, this concern may send updated measurements, approved profile context, recent private replies and scoped plan status to this model. Research may save a reply or draft, but cannot adopt steps or schedule reminders. You can revoke access at any time."))
            Text(proposed.approval.payload).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
            Toggle(t("acknowledge", "I authorize automatic research for this concern"), isOn: $confirmed)
            Button(t("authorize", "Authorize research")) { authorize(proposed) }.disabled(!confirmed)
          }
        }
        .navigationTitle(t("review", "Review authorization"))
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button(t("cancel", "Cancel")) { review = nil } }
        }
      }.navigationViewStyle(.stack)
    }
  }

  private var canRead: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }

  private func route(_ id: String) -> (CloudModelConfig, String)? {
    guard let contact = store.contact(id: id), !contact.deleted, contact.deliveryMode == .cloudAPI,
          let model = contact.selectedCloudModel, GalaxySSIHealthCareDiscussion.endpoint(for: model) != nil,
          let key = store.apiKey(for: model), CloudModelCredentialPolicy.isStoredCredential(key),
          !coordinator.healthDisclosureStore.blockedDestinationIds().contains(id) else { return nil }
    return (model, key)
  }

  private func preview() {
    guard canRead, online, let (model, key) = route(provider), !sources.isEmpty else { return }
    do {
      _ = try records.openLocalCareDiscussion(id: concern, metric: metric)
      let approval = try records.prepareLocalCareDiscussion(id: concern, metric: metric,
        question: t("request", "Review this concern using the research handoff. State missing context. Do not adopt or schedule anything."),
        destinationID: provider, model: model, credential: key)
      confirmed = false
      review = .init(approval: approval, sources: sources)
      failed = false
    } catch { failed = true }
  }

  private func authorize(_ proposed: Review) {
    let approval = proposed.approval
    guard canRead, confirmed, review?.id == proposed.id, let (model, key) = route(approval.destinationID),
          model == approval.model, SHA256.hash(data: Data(key.utf8)) == approval.credentialDigest else {
      review = nil; failed = true; return
    }
    do {
      try records.authorizeLocalCareResearch(approval, sources: proposed.sources)
      review = nil
      confirmed = false
      reload()
    } catch { review = nil; failed = true }
  }

  private func reload() {
    guard canRead, let archive = try? records.load(), archive.localCareAllowed == true,
          archive.localCare?.current[metric.rawValue]?.id == concern else { clear(); return }
    online = archive.healthOnlinePermission != nil
    authorization = archive.localCareResearch?.authorizations[concern.uuidString]
    job = archive.localCareResearch?.jobs[concern.uuidString]
  }

  private func clear() {
    online = false; authorization = nil; job = nil; review = nil; confirmed = false; failed = false
    provider = ""; sources = []
  }

  private func status(_ state: Research.State) -> String {
    switch state {
    case .queued: return t("queued", "Waiting for research")
    case .preparing: return t("preparing", "Reading public sources")
    case .dispatched: return t("dispatched", "Waiting for the model")
    case .completed: return t("completed", "Research review available in the private discussion")
    case .interrupted: return t("interrupted", "Interrupted request was not resent")
    case .failed: return t("failed", "Research failed")
    case .sourceUnavailable: return t("source_unavailable", "The approved source could not be read. No new plan was created.")
    case .cancelled: return t("cancelled", "Research cancelled")
    case .superseded: return t("superseded", "Research no longer matches the evidence")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.research." + key, fallback: fallback, language: language)
  }
}
