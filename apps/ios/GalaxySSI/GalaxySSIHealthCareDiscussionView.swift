import CryptoKit
import SwiftUI

@MainActor
struct GalaxySSIHealthCareDiscussionView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let concernID: UUID
  let metric: GalaxySSIHealthMetric
  @State private var thread: GalaxySSIHealthCareDiscussion.Thread?
  @State private var question = ""
  @State private var provider = ""
  @State private var allowed = false
  @State private var limit = 20
  @State private var approval: GalaxySSIHealthCareDiscussion.Approval?
  @State private var active: GalaxySSIHealthCareDiscussion.Approval?
  @State private var task: Task<Void, Never>?
  @State private var failed = false
  @State private var proposesPlan = false

  private var contacts: [GalaxySSIContact] {
    store.contacts.filter {
      !$0.deleted && $0.deliveryMode == .cloudAPI &&
        $0.selectedCloudModel.flatMap(GalaxySSIHealthCareDiscussion.endpoint(for:)) != nil
    }
  }
  private var models: [String: CloudModelConfig] {
    contacts.reduce(into: [:]) { $0[$1.id] = $1.selectedCloudModel }
  }

  var body: some View {
    List {
      if scene == .active, let thread {
        if thread.turns.count > limit {
          Button(t("more", "Show earlier messages")) { limit += 20 }
        }
        ForEach(thread.turns.suffix(limit)) { turn in
          VStack(alignment: .leading, spacing: 8) {
            Text(turn.question).font(.body.weight(.semibold))
            if let answer = turn.answer { Text(answer).textSelection(.enabled) }
            else if turn.proposalID != nil { Text(t("plan_retained", "Draft available in Health plans")) }
            else if active?.id == turn.id { ProgressView() }
            else { Text(t("unanswered", "No saved reply")).foregroundColor(.secondary) }
          }
        }
        Toggle(t("online_permission", "Allow approved online health questions"), isOn: Binding(
          get: { allowed }, set: { enable in
            do { try records.setHealthOnlinePermission(enable); refresh(open: false) }
            catch { failed = true }
          }))
        if allowed {
          Picker(t("provider", "Provider and model"), selection: $provider) {
            Text(t("select_provider", "Select a model")).tag("")
            ForEach(contacts) { contact in
              Text(contact.name + " / " + (contact.selectedCloudModel?.modelId ?? "")).tag(contact.id)
            }
          }.disabled(task != nil)
          TextField(t("question", "Ask about this concern"), text: $question).disabled(task != nil)
          Toggle(t("request_plan", "Request a draft plan"), isOn: $proposesPlan).disabled(task != nil)
          Button(t("preview", "Review data before sending"), action: preview)
            .disabled(task != nil || provider.isEmpty || question.isBlank || question.utf8.count > 2_048)
        }
        if task != nil { Button(t("stop", "Cancel request"), role: .cancel) { clearRequest() } }
        GalaxySSIHealthCarePlansSection(records: records, concernID: concernID)
        GalaxySSIHealthCareFollowUpsSection(records: records, concernID: concernID, metric: metric)
      }
      if scene == .active, failed { Text(t("unavailable", "This discussion or request is no longer available.")) }
    }
    .navigationTitle(t("title", "Private Health Discussion"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { refresh(open: true) }
    .onDisappear { clearSensitive() }
    .onChange(of: scene) { phase in
      if phase == .active { refresh(open: true) } else { clearSensitive() }
    }
    .onChange(of: store.profile.identityFingerprint) { _ in clearSensitive() }
    .onChange(of: models) { _ in validateVisibleApprovals() }
    .onChange(of: provider) { _ in approval = nil }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner {
        validateVisibleApprovals()
        refresh(open: false)
      }
    }
    .sheet(item: $approval) { review in
      NavigationView {
        List {
          if scene == .active {
            Section(t("provider", "Provider and model")) {
              Text(review.model.modelId)
              Text(review.endpoint.absoluteString).font(.footnote).textSelection(.enabled)
              if review.proposesPlan { Text(t("request_plan", "Request a draft plan")) }
            }
            Section(t("data", "Data included in this request")) {
              Text(review.payload).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
            }
            Button(t("send", "Send approved data")) { send(review) }
          }
        }
        .navigationTitle(t("preview", "Review data before sending"))
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(t("close", "Close")) { approval = nil }
          }
        }
      }.navigationViewStyle(.stack)
    }
  }

  private func refresh(open: Bool) {
    guard scene == .active, store.profile.identityFingerprint == records.owner else { clearSensitive(); return }
    do {
      if open { thread = try records.openLocalCareDiscussion(id: concernID, metric: metric) }
      let archive = try records.load()
      guard archive.localCareAllowed == true, let concern = archive.localCare?.current[metric.rawValue],
            concern.id == concernID, concern.stage != .paused, concern.stage != .closed,
            concern.assessment.record != nil else { throw GalaxySSIHealthRecords.Failure.permission }
      thread = archive.localCareDiscussions?[concernID.uuidString]
      allowed = archive.healthOnlinePermission != nil
    } catch { clearSensitive(); failed = true }
  }

  private func preview() {
    guard scene == .active, store.profile.identityFingerprint == records.owner, let model = models[provider],
          let key = store.apiKey(for: model), task == nil else { failed = true; return }
    do {
      approval = try records.prepareLocalCareDiscussion(id: concernID, metric: metric, question: question,
        destinationID: provider, model: model, credential: key, proposesPlan: proposesPlan)
      failed = false
    } catch { failed = true }
  }

  private func currentRoute(_ review: GalaxySSIHealthCareDiscussion.Approval) -> (GalaxySSIContact, String)? {
    guard scene == .active, store.profile.identityFingerprint == records.owner, review.owner == records.owner,
          let contact = contacts.first(where: { $0.id == review.destinationID }),
          contact.selectedCloudModel == review.model,
          GalaxySSIHealthCareDiscussion.endpoint(for: review.model) == review.endpoint,
          let key = store.apiKey(for: review.model), CloudModelCredentialPolicy.isStoredCredential(key),
          SHA256.hash(data: Data(key.utf8)) == review.credentialDigest,
          !coordinator.healthDisclosureStore.blockedDestinationIds().contains(contact.id)
    else { return nil }
    return (contact, key)
  }

  private func validateVisibleApprovals() {
    if let approval, currentRoute(approval) == nil ||
        (try? records.validateLocalCareDiscussionApproval(approval)) == nil {
      self.approval = nil; failed = true
    }
    if let active, currentRoute(active) == nil || (try? records.validateLocalCareDiscussionTurn(active)) == nil {
      clearRequest(); failed = true
    }
  }

  private func send(_ review: GalaxySSIHealthCareDiscussion.Approval) {
    guard approval?.id == review.id, task == nil, let (contact, key) = currentRoute(review)
    else { approval = nil; failed = true; return }
    approval = nil
    let ledger = coordinator.healthDisclosureStore
    do {
      let request = try GalaxySSIHealthCareDiscussion.request(review, key: key)
      try records.beginLocalCareDiscussionTurn(review)
      let ticket = AgentDataDisclosureLedger.beginCloudRequest(store: ledger, destination: .init(contact: contact),
        text: "", purpose: "Explicit health concern discussion",
        textSummary: .init(characters: review.payload.count, kinds: [.messageText, .systemInstructions, .toolOutput]))
      guard ticket.allowed else { failed = true; return }
      active = review
      question = ""
      failed = false
      task = Task {
        var status: AgentDisclosureStatus = .failed
        defer {
          AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: status,
            failureReason: status == .failed ? "health_discussion_not_completed" : "")
          if active?.id == review.id { active = nil; task = nil }
        }
        do {
          guard active?.id == review.id, !Task.isCancelled, currentRoute(review) != nil else { return }
          try records.validateLocalCareDiscussionTurn(review)
          let bytes = try await GalaxySSIHealthSummaryTransport.responseBytes(request, limit: 65_536)
          status = .sent
          guard active?.id == review.id, !Task.isCancelled, currentRoute(review) != nil else { return }
          active = nil
          defer { task = nil }
          if review.proposesPlan {
            let arguments = try GalaxySSIHealthCarePlan.arguments(bytes, style: review.model.apiStyle)
            try records.saveLocalCarePlan(review, arguments: arguments)
          } else {
            let answer = try GalaxySSIHealthFollowUpTransport.output(bytes, style: review.model.apiStyle)
            try records.finishLocalCareDiscussionTurn(review, answer: answer)
          }
        } catch { if !Task.isCancelled { failed = true } }
      }
    } catch { failed = true }
  }

  private func clearRequest() { task?.cancel(); task = nil; active = nil; approval = nil }
  private func clearSensitive() {
    clearRequest(); thread = nil; question = ""; provider = ""; allowed = false; failed = false; proposesPlan = false
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.discussion." + key, fallback: fallback, language: language)
  }
}
