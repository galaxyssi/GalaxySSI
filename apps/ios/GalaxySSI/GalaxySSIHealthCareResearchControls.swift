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
  @State private var desktopModel = ""
  @State private var desktopEffort = AgentModelReasoningEffort.automatic
  @State private var shareQuestions = false
  @State private var shareQuestionPages = false
  @State private var shareActionFeedback = false
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
          Text(authorization.endpoint?.absoluteString ?? authorization.pairedDesktop?.connector.desktopId ?? "")
            .font(.caption).foregroundColor(.secondary)
          if let job { Text(status(job.state)) }
          Button(t("revoke", "Revoke research authorization"), role: .destructive) {
            do { try records.revokeLocalCareResearch(concern); reload() }
            catch { failed = true }
          }
        } else if online {
          Picker(t("provider", "Provider and model"), selection: $provider) {
            Text(t("select", "Select a model")).tag("")
            ForEach(store.contacts.filter { route($0.id) != nil || coordinator.privateHealthDesktopRoute(contactID: $0.id) != nil }) { contact in
              Text(contact.name + " / " + (contact.selectedCloudModel?.modelId ??
                coordinator.privateHealthDesktopRoute(contactID: contact.id)?.connector.modelId ?? "")).tag(contact.id)
            }
          }
          if coordinator.privateHealthDesktopRoute(contactID: provider) != nil,
             let profile = store.contact(id: provider)?.connectorInvocationProfile {
            Picker(t("desktop_model", "Desktop model"), selection: $desktopModel) {
              Text(t("default", "Provider default")).tag("")
              ForEach(profile.models) { Text($0.displayName).tag($0.id) }
            }
            Picker(t("desktop_effort", "Reasoning effort"), selection: $desktopEffort) {
              Text(t("default", "Provider default")).tag(AgentModelReasoningEffort.automatic)
              ForEach(profile.reasoningEfforts) { Text($0.rawValue.uppercased()).tag($0) }
            }
          }
          ForEach(GalaxySSIHealthCareEvidence.PublicSource.allCases) { source in
            Toggle(source.title, isOn: Binding(get: { sources.contains(source) }, set: {
              if $0 { sources.insert(source) } else { sources.remove(source) }
            }))
          }
          Toggle(t("share_questions", "Include reviewed clarification in automatic research"), isOn: $shareQuestions)
          if shareQuestions, route(provider) != nil {
            Toggle(t("share_question_pages", "Allow the cloud model to read additional clarification pages"),
              isOn: $shareQuestionPages)
          }
          Toggle(t("share_action_feedback", "Include latest action feedback in automatic research"), isOn: $shareActionFeedback)
          Button(t("review", "Review authorization"), action: preview).disabled(provider.isEmpty || sources.isEmpty)
        } else {
          Text(t("online_off", "Online Health discussion is off.")).foregroundColor(.secondary)
        }
        if failed { Text(t("unavailable", "Research authorization is no longer available.")) }
      }
    }
    .onAppear(perform: reload)
    .onChange(of: provider) { _ in
      desktopModel = ""; desktopEffort = .automatic; shareQuestionPages = false; shareActionFeedback = false
    }
    .onChange(of: shareQuestions) { if !$0 { shareQuestionPages = false } }
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
              Text(proposed.approval.modelID)
              Text(proposed.approval.location).font(.caption).textSelection(.enabled)
              if proposed.approval.pairedDesktop != nil {
                Text(t("paired_boundary", "This sends the approved Health context to the named paired Desktop and its configured Codex provider. The task is read-only and may be retained in the Desktop task journal."))
              }
              if let paired = proposed.approval.pairedDesktop, paired.connector.reasoningEffort != .automatic {
                Text(t("desktop_effort", "Reasoning effort") + ": " + paired.connector.reasoningEffort.rawValue.uppercased())
              } else {
                Text(t("effort", "Model effort: provider default"))
              }
            }
            Section(t("sources", "Allowed public sources")) {
              ForEach(GalaxySSIHealthCareEvidence.PublicSource.allCases.filter { proposed.sources.contains($0) }) {
                Text($0.title)
              }
            }
            Text(t("scope", "While GalaxySSI is active, this concern may send updated measurements, approved profile context, recent private replies and scoped plan status to this model. Research may save a reply or draft, but cannot adopt steps or schedule reminders. You can revoke access at any time."))
            if proposed.approval.includesActionFeedback {
              Text(t("action_feedback_scope", "This model may receive the latest eligible self-reported action notes for this concern, including future notes, but not their history."))
            }
            if let questions = proposed.approval.questions {
              if proposed.approval.allowsStandingQuestionPages {
                Text(t("question_pages_scope", "Each automatic review may include the first page and read up to four more pages for this concern. A changed reviewed reply requires new authorization."))
              } else {
                Text(t("questions_scope", "Each automatic review may include the first page of this concern's clarification record. A changed reviewed reply requires new authorization."))
              }
              Text(AgentMcpJSONCodec.stringify(questions.payload)).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
            }
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
    guard canRead, online, !sources.isEmpty else { return }
    do {
      _ = try records.openLocalCareDiscussion(id: concern, metric: metric)
      let question = t("request", "Review this concern using the research handoff. State missing context. Do not adopt or schedule anything.")
      var approval: GalaxySSIHealthCareDiscussion.Approval
      if let (model, key) = route(provider) {
        approval = try records.prepareLocalCareDiscussion(id: concern, metric: metric, question: question,
          destinationID: provider, model: model, credential: key, includesQuestions: shareQuestions,
          includesActionFeedback: shareActionFeedback)
        approval.allowsStandingQuestionPages = shareQuestions && shareQuestionPages
      } else if let paired = coordinator.privateHealthDesktopRoute(contactID: provider, modelID: desktopModel,
                   effort: desktopEffort) {
        approval = try records.prepareLocalCareDesktopDiscussion(id: concern, metric: metric, question: question, route: paired,
          includesQuestions: shareQuestions, includesActionFeedback: shareActionFeedback)
      } else { throw GalaxySSIHealthRecords.Failure.permission }
      confirmed = false
      review = .init(approval: approval, sources: sources)
      failed = false
    } catch { failed = true }
  }

  private func authorize(_ proposed: Review) {
    let approval = proposed.approval
    guard canRead, confirmed, review?.id == proposed.id, destinationIsCurrent(approval) else {
      review = nil; failed = true; return
    }
    do {
      try records.authorizeLocalCareResearch(approval, sources: proposed.sources,
        sharesActionFeedback: approval.includesActionFeedback)
      review = nil
      confirmed = false
      reload()
    } catch { review = nil; failed = true }
  }

  private func destinationIsCurrent(_ approval: GalaxySSIHealthCareDiscussion.Approval) -> Bool {
    if let paired = approval.pairedDesktop {
      return coordinator.privateHealthDesktopRoute(contactID: approval.destinationID, modelID: paired.connector.modelId,
        effort: paired.connector.reasoningEffort) == paired
    }
    guard let (model, key) = route(approval.destinationID) else { return false }
    return model == approval.model && SHA256.hash(data: Data(key.utf8)) == approval.credentialDigest
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
    desktopModel = ""; desktopEffort = .automatic
    shareQuestions = false
    shareQuestionPages = false
    shareActionFeedback = false
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
