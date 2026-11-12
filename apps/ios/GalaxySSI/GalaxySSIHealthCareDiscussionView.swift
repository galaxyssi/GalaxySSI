import CryptoKit
import SwiftUI
import UIKit

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
  @State private var archived: [GalaxySSIHealthCareDiscussion.Thread] = []
  @State private var archiveLimit = 10
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
  @State private var includesQuestions = false
  @State private var includesFeedbackHistory = false
  @State private var asksQuestions = false
  @State private var allowsAnswerDraft = false
  @State private var selectedSources = Set<GalaxySSIHealthCareEvidence.PublicSource>()
  @State private var readingTask: Task<Void, Never>?
  @State private var readingID: UUID?

  private var busy: Bool { task != nil || readingTask != nil }
  private var canRead: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }

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
      if canRead, let thread {
        if thread.turns.count > limit {
          Button(t("more", "Show earlier messages")) { limit += 20 }
        }
        ForEach(thread.turns.suffix(limit)) { turn in
          VStack(alignment: .leading, spacing: 8) {
            Text(turn.question).font(.body.weight(.semibold))
            if let answer = turn.answer { Text(answer).textSelection(.enabled) }
            else if turn.proposalID != nil { Text(t("plan_retained", "Draft available in Health plans")) }
            else if turn.questionsRetained == true { Text(q("retained", "Questions are available in Personal Health.")) }
            else if turn.answerDraftStaged == true { Text(q("draft_staged", "Clarification answer draft created")) }
            else if active?.id == turn.id { ProgressView() }
            else { Text(t("unanswered", "No saved reply")).foregroundColor(.secondary) }
          }
        }
        NavigationLink(q("answer_drafts", "Review clarification answers")) {
          List { GalaxySSIHealthCareAnswerDraftsView(records: records, concern: concernID, metric: metric) }
            .navigationTitle(q("answer_drafts", "Review clarification answers"))
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
          Toggle(q("request", "Request clarification questions"), isOn: $asksQuestions).disabled(busy)
          if !asksQuestions {
            Toggle(q("include", "Include reviewed questions in this request"), isOn: $includesQuestions).disabled(busy)
            if includesQuestions && !proposesPlan && !allowsHistory && !includesFeedbackHistory {
              Toggle(q("stage_answer", "Extract an answer from this message for my review"), isOn: $allowsAnswerDraft).disabled(busy)
            }
            Toggle(t("request_plan", "Request a draft plan"), isOn: $proposesPlan).disabled(busy || allowsAnswerDraft)
            Toggle(t("allow_history", "Include measurement history for this request"), isOn: $allowsHistory)
              .disabled(busy || allowsAnswerDraft)
            Toggle(t("allow_feedback_history", "Allow action feedback history for this request"),
              isOn: $includesFeedbackHistory).disabled(busy || allowsAnswerDraft)
          }
          if proposesPlan && !asksQuestions {
            ForEach(GalaxySSIHealthCareEvidence.PublicSource.allCases) { source in
              Toggle(t("source." + source.rawValue, source.title), isOn: Binding(
                get: { selectedSources.contains(source) }, set: { enabled in
                  if enabled { selectedSources.insert(source) } else { selectedSources.remove(source) }
                })).disabled(busy)
            }
          }
          Button(t("preview", "Review data before sending"), action: preview)
            .disabled(busy || provider.isEmpty || question.isBlank || question.utf8.count > 2_048 ||
              (proposesPlan && !asksQuestions && selectedSources.isEmpty))
        }
        if readingTask != nil { ProgressView(t("reading_sources", "Reading public sources")) }
        if busy { Button(t("stop", "Cancel request"), role: .cancel) { clearRequest() } }
        if !archived.isEmpty {
          Section(scopeText("archived", "Earlier private discussions")) {
            ForEach(archived.prefix(archiveLimit)) { previous in
              DisclosureGroup {
                ForEach(previous.turns) { turn in
                  VStack(alignment: .leading, spacing: 4) {
                    Text(turn.question).font(.body.weight(.semibold))
                    if let answer = turn.answer { Text(answer).textSelection(.enabled) }
                  }
                }
              } label: {
                if let date = previous.archivedAt { Text(date, format: .dateTime) }
                else { Text(scopeText("archived", "Earlier private discussions")) }
              }
            }
            if archived.count > archiveLimit {
              Button(scopeText("older", "Show more discussions")) { archiveLimit += 10 }
            }
          }
        }
        GalaxySSIHealthCarePlansSection(records: records, concernID: concernID)
        GalaxySSIHealthCareResearchControls(records: records, concern: concernID, metric: metric)
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
    .onChange(of: includesQuestions) { if !$0 { allowsAnswerDraft = false } }
    .onChange(of: asksQuestions) { if $0 { allowsAnswerDraft = false } }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
      clearSensitive()
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
      refresh(open: true)
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.profileInputsChanged)) {
      if $0.object as? String == records.owner {
        validateVisibleApprovals()
        refresh(open: true)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner {
        validateVisibleApprovals()
        refresh(open: false)
      }
    }
    .sheet(item: $approval) { review in
      NavigationView {
        List {
          if canRead {
            Section(t("provider", "Provider and model")) {
              Text(review.modelID)
              Text(review.location).font(.footnote).textSelection(.enabled)
              if review.proposesPlan { Text(t("request_plan", "Request a draft plan")) }
              if review.questions != nil {
                Text(q("disclosure", "Includes up to eight current questions and reviewed replies for this concern."))
                  .font(.footnote)
                if review.questionCursor != nil {
                  Text(q("page_disclosure", "The model may read up to four more pages for this request only."))
                    .font(.footnote)
                }
                if review.allowsAnswerDraft {
                  Text(q("draft_disclosure", "The model may quote this message to propose one answer. Nothing is saved as your answer until you confirm it in Health."))
                    .font(.footnote)
                }
              }
              if review.profileScope != nil {
                Text(scopeText("preview", "Includes only the saved profile fields and entries selected for this concern."))
                  .font(.footnote)
              }
              if review.history != nil {
                Text(t("history_scope", "Includes the 30 most recent measurements for this concern at most. This model can request up to four older pages of 30 measurements each for this request only."))
                  .font(.footnote)
              }
              if review.feedbackCursor != nil {
                Text(t("feedback_history_scope", "This model may request up to four pages of past action feedback for this concern, only for this request."))
                  .font(.footnote)
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
    guard canRead else { clearSensitive(); return }
    do {
      if open { _ = try records.openLocalCareDiscussion(id: concernID, metric: metric) }
      let archive = try records.load()
      guard archive.localCareAllowed == true, let concern = archive.localCare?.current[metric.rawValue],
            concern.id == concernID, concern.stage != .paused, concern.stage != .closed,
            concern.assessment.record != nil else { throw GalaxySSIHealthRecords.Failure.permission }
      let next = archive.localCareDiscussions?[concernID.uuidString]
      if thread != nil, thread?.id != next?.id {
        clearRequest(); question = ""; allowsHistory = false; includesQuestions = false; asksQuestions = false
        allowsAnswerDraft = false; includesFeedbackHistory = false; limit = 20
      }
      thread = next
      archived = (archive.archivedCareDiscussions ?? [:]).values.filter { $0.concernID == concernID }
        .sorted { ($0.archivedAt ?? .distantPast, $0.id.uuidString) > ($1.archivedAt ?? .distantPast, $1.id.uuidString) }
      allowed = archive.healthOnlinePermission != nil
    } catch { clearSensitive(); failed = true }
  }

  private func preview() {
    guard canRead, let model = models[provider],
          let key = store.apiKey(for: model), !busy else { failed = true; return }
    do {
      let pending = try records.prepareLocalCareDiscussion(id: concernID, metric: metric, question: question,
        destinationID: provider, model: model, credential: key, proposesPlan: proposesPlan && !asksQuestions,
        allowsHistory: allowsHistory && !asksQuestions, includesQuestions: includesQuestions, asksQuestions: asksQuestions,
        allowsAnswerDraft: allowsAnswerDraft && includesQuestions && !asksQuestions,
        feedbackHistoryAllowed: includesFeedbackHistory && !asksQuestions)
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
    guard canRead, review.owner == records.owner,
          let contact = contacts.first(where: { $0.id == review.destinationID }),
          let model = review.model, contact.selectedCloudModel == model,
          GalaxySSIHealthCareDiscussion.endpoint(for: model) == review.endpoint,
          let key = store.apiKey(for: model), CloudModelCredentialPolicy.isStoredCredential(key),
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
    guard let style = review.model?.apiStyle else { return }
    guard approval?.id == review.id, task == nil, let (contact, key) = currentRoute(review)
    else { approval = nil; failed = true; return }
    approval = nil
    let ledger = coordinator.healthDisclosureStore
    do {
      let sentPayload = try review.providerPayload()
      let request = try GalaxySSIHealthCareDiscussion.request(review, key: key)
      try records.validateLocalCareDiscussionApproval(review)
      let ticket = AgentDataDisclosureLedger.beginCloudRequest(store: ledger, destination: .init(contact: contact),
        text: "", purpose: review.history == nil ? "Explicit health concern discussion" :
          "Explicit health concern discussion with scoped measurement history",
        textSummary: .init(characters: sentPayload.count, kinds: [.messageText, .systemInstructions, .toolOutput]))
      guard ticket.allowed else { failed = true; return }
      do {
        try records.beginLocalCareDiscussionTurn(review)
      } catch {
        AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: .failed,
          failureReason: "health_discussion_approval_changed")
        throw error
      }
      active = review
      question = ""
      allowsHistory = false
      includesQuestions = false
      includesFeedbackHistory = false
      asksQuestions = false
      allowsAnswerDraft = false
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
          var bytes = try await GalaxySSIHealthSummaryTransport.responseBytes(request, limit: 65_536)
          status = .sent
          if !review.allowsAnswerDraft && (review.history != nil || review.questions != nil || review.feedbackCursor != nil) {
            bytes = try await GalaxySSIHealthScopedReadTransport.finish(review, records: records, initial: bytes,
              request: request, style: style, ledger: ledger, currentDestination: {
                active?.id == review.id ? currentRoute(review)?.0 : nil
              })
          }
          guard active?.id == review.id, !Task.isCancelled, currentRoute(review) != nil else { return }
          active = nil
          defer { task = nil }
          if review.allowsAnswerDraft {
            let draft = try GalaxySSIHealthCareAnswerDraft.argumentsIfPresent(bytes, style: style)
            if let draft {
              try records.stageLocalCareAnswerDraft(review, arguments: draft)
            } else {
              let answer = try GalaxySSIHealthFollowUpTransport.output(bytes, style: style)
              try records.finishLocalCareDiscussionTurn(review, answer: answer)
            }
          } else if review.asksQuestions {
            let arguments = try GalaxySSIHealthCarePlan.arguments(bytes, style: style,
              toolName: GalaxySSIHealthCareQuestions.tool)
            try records.saveLocalCareQuestionProposals(review, arguments: arguments)
          } else if review.proposesPlan {
            let arguments = try GalaxySSIHealthCarePlan.arguments(bytes, style: style)
            try records.saveLocalCarePlan(review, arguments: arguments)
          } else {
            let answer = try GalaxySSIHealthFollowUpTransport.output(bytes, style: style)
            try records.finishLocalCareDiscussionTurn(review, answer: answer)
          }
        } catch { if !Task.isCancelled { failed = true } }
      }
    } catch { failed = true }
  }

  private func clearRequest() {
    task?.cancel(); task = nil; active = nil; approval = nil
    readingTask?.cancel(); readingTask = nil; readingID = nil
  }
  private func clearSensitive() {
    clearRequest(); thread = nil; question = ""; provider = ""; allowed = false; failed = false; proposesPlan = false
    archived = []; archiveLimit = 10
    selectedSources = []; allowsHistory = false
    includesQuestions = false; asksQuestions = false; allowsAnswerDraft = false; includesFeedbackHistory = false
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.discussion." + key, fallback: fallback, language: language)
  }

  private func q(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.questions." + key, fallback: fallback, language: language)
  }

  private func scopeText(_ key: String, _ fallback: String) -> String {
    GalaxySSIHealthCareProfileScopeView.text(key, fallback, language: language)
  }
}
