import CryptoKit
import Foundation
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
  @State private var maintenance: GalaxySSIHealthCareMaintenance.Review?
  @State private var question = ""
  @State private var provider = ""
  @State private var allowed = false
  @State private var limit = 20
  @State private var approval: GalaxySSIHealthCareDiscussion.Approval?
  @State private var active: GalaxySSIHealthCareDiscussion.Approval?
  @State private var task: Task<Void, Never>?
  @State private var failed = false
  @State private var proposesPlan = false
  @State private var allowsHistory = false
  @State private var selectedSources = Set<GalaxySSIHealthCareEvidence.PublicSource>()
  @State private var readingTask: Task<Void, Never>?
  @State private var readingID: UUID?

  private var busy: Bool { task != nil || readingTask != nil }

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
        if metric == .bloodPressure { GalaxySSIHealthCarePrioritySection(records: records, concernID: concernID) }
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
          }.disabled(busy)
          TextField(t("question", "Ask about this concern"), text: $question).disabled(busy)
          Toggle(t("request_plan", "Request a draft plan"), isOn: $proposesPlan).disabled(busy)
          Toggle(t("allow_history", "Allow this model to read measurement history"), isOn: $allowsHistory).disabled(busy)
          if proposesPlan {
            ForEach(GalaxySSIHealthCareEvidence.PublicSource.allCases) { source in
              Toggle(t("source." + source.rawValue, source.title), isOn: Binding(
                get: { selectedSources.contains(source) }, set: { enabled in
                  if enabled { selectedSources.insert(source) } else { selectedSources.remove(source) }
                })).disabled(busy)
            }
          }
          Button(t("preview", "Review data before sending"), action: preview)
            .disabled(busy || provider.isEmpty || question.isBlank || question.utf8.count > 2_048 ||
              (proposesPlan && selectedSources.isEmpty))
        }
        if readingTask != nil { ProgressView(t("reading_sources", "Reading public sources")) }
        if busy { Button(t("stop", "Cancel request"), role: .cancel) { clearRequest() } }
        GalaxySSIHealthCareComparisonSection(records: records, id: concernID, metric: metric)
        GalaxySSIHealthCareSeriesLink(records: records, id: concernID, metric: metric)
        if let maintenance { GalaxySSIHealthCareMaintenanceSection(review: maintenance) }
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
    .onChange(of: provider) { _ in approval = nil; allowsHistory = false }
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
              if review.historyVersion != nil {
                Text(t("history_scope", "For this request only: the recent page and up to four older pages for this concern, 30 measurements per page."))
              }
            }
            Section(t("data", "Data included in this request")) {
              if let payload = try? review.providerPayload() {
                Text(payload).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
              }
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
      maintenance = concern.maintenance
      allowed = archive.healthOnlinePermission != nil
    } catch { clearSensitive(); failed = true }
  }

  private func preview() {
    guard scene == .active, store.profile.identityFingerprint == records.owner, let model = models[provider],
          let key = store.apiKey(for: model), !busy else { failed = true; return }
    do {
      let pending = try records.prepareLocalCareDiscussion(id: concernID, metric: metric, question: question,
        destinationID: provider, model: model, credential: key, proposesPlan: proposesPlan, allowsHistory: allowsHistory)
      failed = false
      if !pending.proposesPlan { approval = pending; return }
      let sources = GalaxySSIHealthCareEvidence.PublicSource.allCases.filter { selectedSources.contains($0) }
      guard !sources.isEmpty else { failed = true; return }
      readingID = pending.id
      readingTask = Task {
        defer { if readingID == pending.id { readingID = nil; readingTask = nil } }
        do {
          var prepared = pending
          let binding = GalaxySSIHealthCareEvidence.Binding(pending)
          for source in sources {
            try Task.checkCancellation()
            try records.validateLocalCareDiscussionApproval(pending)
            let receipt = try await GalaxySSIHealthCareEvidence.fetch(source, binding: binding)
            try Task.checkCancellation()
            prepared.evidence.append(receipt)
          }
          guard readingID == pending.id, currentRoute(prepared) != nil else { return }
          try records.validateLocalCareDiscussionApproval(prepared)
          _ = try prepared.providerPayload()
          approval = prepared
        } catch { if readingID == pending.id, !Task.isCancelled { failed = true } }
      }
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
    allowsHistory = false
    let ledger = coordinator.healthDisclosureStore
    do {
      let sentPayload = try review.providerPayload()
      let request = try GalaxySSIHealthCareDiscussion.request(review, key: key)
      try records.beginLocalCareDiscussionTurn(review)
      let ticket = AgentDataDisclosureLedger.beginCloudRequest(store: ledger, destination: .init(contact: contact),
        text: "", purpose: review.historyVersion == nil ? "Explicit health concern discussion" :
          "Explicit health concern discussion with scoped measurement history",
        textSummary: .init(characters: sentPayload.count, kinds: [.messageText, .systemInstructions, .toolOutput]))
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
          let bytes = try await receive(review, request: request)
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

  private func receive(_ review: GalaxySSIHealthCareDiscussion.Approval, request: URLRequest) async throws -> Data {
    typealias Tool = GalaxySSIHealthCareHistoryTool
    var request = request
    var expected = review.initialHistory?.next
    var count = 0
    while true {
      try Task.checkCancellation()
      guard active?.id == review.id, currentRoute(review) != nil else { throw CancellationError() }
      try records.validateLocalCareDiscussionTurn(review)
      let bytes = try await GalaxySSIHealthSummaryTransport.responseBytes(request, limit: 65_536)
      try Task.checkCancellation()
      guard active?.id == review.id, currentRoute(review) != nil else { throw CancellationError() }
      try records.validateLocalCareDiscussionTurn(review)
      guard let version = review.historyVersion,
            let call = try Tool.call(bytes, style: review.model.apiStyle, proposesPlan: review.proposesPlan) else { return bytes }
      guard expected != nil, count < Tool.maximumPages else { throw GalaxySSIHealthRecords.Failure.permission }
      let after = try Tool.cursor(call.arguments, version: version)
      guard after == expected else { throw GalaxySSIHealthRecords.Failure.stale }
      let page = try records.readLocalCareDiscussionHistory(review, after: after)
      let output = try Tool.output(page, metric: review.metric, after: after)
      count += 1
      expected = output.next
      let canRead = expected != nil && count < Tool.maximumPages
      request = try Tool.continuing(request, with: call, output: output, style: review.model.apiStyle,
        proposesPlan: review.proposesPlan, historyAvailable: canRead, maintenanceAvailable: review.initialHistory != nil)
    }
  }

  private func clearRequest() {
    task?.cancel(); task = nil; active = nil; approval = nil
    readingTask?.cancel(); readingTask = nil; readingID = nil
  }
  private func clearSensitive() {
    clearRequest(); thread = nil; maintenance = nil; question = ""; provider = ""; allowed = false; failed = false; proposesPlan = false
    allowsHistory = false
    selectedSources = []
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.discussion." + key, fallback: fallback, language: language)
  }
}
