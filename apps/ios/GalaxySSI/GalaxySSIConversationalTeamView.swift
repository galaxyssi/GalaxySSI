import SwiftUI

struct AgentConversationalTeamLaunch: Identifiable {
  let id = UUID()
  let owner: String
  let conversation: String
  let revision: UUID
  let command: AgentConversationalTeamCommand
  let selection: AgentModelSelection
  var source: AgentLocalTeamReviewSource? = nil
}

@MainActor
struct GalaxySSIConversationalTeamSheet: ViewModifier {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Binding var launch: AgentConversationalTeamLaunch?
  let valid: (AgentConversationalTeamLaunch) -> Bool
  let applied: (AgentConversationalTeamLaunch) -> Void
  func body(content: Content) -> some View {
    content.sheet(item: $launch) { item in
      GalaxySSIConversationalTeamView(launch: item, valid: { valid(item) }, applied: { applied(item) })
    }
    .onChange(of: scene) { if $0 != .active { launch = nil } }
    .onChange(of: store.profile.identityFingerprint) { _ in launch = nil }
    .onChange(of: store.activeAgentConversationId) { _ in launch = nil }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in launch = nil }
  }
}

@MainActor
struct GalaxySSIConversationalTeamView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.dismiss) private var dismiss
  let launch: AgentConversationalTeamLaunch
  let valid: () -> Bool
  let applied: () -> Void
  @State private var choices: [AgentConversationGoal.Route] = []
  @State private var selected = 0
  @State private var job: AgentConversationalTeamJob?
  @State private var failed = false
  @ObservedObject private var runtime = AgentConversationalTeamRuntime.shared
  private var repository: AgentConversationalTeamStore { .init(owner: launch.owner, defaults: store.defaults, secrets: store.secrets) }
  private var available: Bool {
    valid() && scene == .active && UIApplication.shared.isProtectedDataAvailable && store.canReadAgentTranscript &&
      launch.owner == store.profile.identityFingerprint && launch.conversation == store.activeAgentConversationId &&
      launch.selection == AgentModelSelectionSettings.selection(for: launch.conversation, defaults: store.defaults) &&
      AgentConversationGoalRuntime.eligible(store.agentSession(id: launch.conversation))
      && (launch.source == nil || {
        guard case .start(let objective) = launch.command else { return false }
        return launch.source?.matches(store, conversation: launch.conversation, objective: objective) == true
      }())
  }
  var body: some View {
    NavigationView {
      List {
        if available {
          Section {
            Text(t("help", "Use /team followed by an objective, or ask for a temporary team or independent review. /team stop stops this conversation's team."))
          }
          if let job {
            Section {
              Text(verbatim: job.objective).textSelection(.enabled)
              Text(t("state_" + job.state.rawValue, job.state.rawValue.capitalized)).font(.headline)
              Text(AgentConversationGoalText.route(job.route, language: language)).font(.footnote)
              Text(String(format: t("calls", "%lld / 12 model calls reserved"), Int64(job.calls)))
              if let event = runtime.progress[job.id] { Text(progress(event)).font(.footnote).foregroundColor(.secondary) }
              if job.active {
                Button(role: .destructive, action: stop) { Label(t("stop", "Stop team"), systemImage: "stop") }
              }
            }
          }
          if case .start(let objective) = launch.command, job?.active != true {
            Section(t("objective", "Full objective")) { Text(verbatim: objective).textSelection(.enabled) }
            Section(t("model", "Confirmed model")) {
              if choices.isEmpty { Text(t("no_provider", "The selected model is not ready for direct text requests. No other provider will be substituted.")) }
              else {
                Picker(t("model", "Confirmed model"), selection: $selected) {
                  ForEach(Array(choices.enumerated()), id: \.offset) { index, route in
                    Text(AgentConversationGoalText.route(route, language: language)).tag(index)
                  }
                }
              }
              Text(t("consent", "Authorize planning, up to 10 text-only roles (3 at a time), and synthesis: at most 12 model calls. The full objective and public role reports go only to this model. Cloud charges may apply. No tools, other chats, private health records or Desktop actions are allowed."))
              Text(t("background", "iOS controls background time. Interrupted requests will not restart automatically. Model agreement is not experimental or clinical validation."))
                .font(.footnote).foregroundColor(.secondary)
              Button(action: start) { Label(t("authorize", "Authorize team"), systemImage: "play") }
                .disabled(!choices.indices.contains(selected))
            }
          }
          if failed { Text(t("changed", "The input, conversation or model changed, or the job could not be saved. Reopen this panel.")) }
        }
      }
      .navigationTitle(t("title", "Temporary Agent team"))
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("close", "Close")) { dismiss() } } }
    }.navigationViewStyle(.stack).privacySensitive()
    .onAppear { reload(); if launch.command == .stop { stop() } }
    .onReceive(NotificationCenter.default.publisher(for: AgentConversationalTeamStore.changed)) { _ in reload() }
    .onChange(of: scene) { if $0 != .active { clear(); dismiss() } }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear(); dismiss() }
    .onDisappear(perform: clear)
  }
  private func routes() -> [AgentConversationGoal.Route] {
    let all = AgentConversationGoalInference.routes(store: store, conversation: launch.conversation)
    guard launch.selection.mode == .manual else { return all }
    let target = launch.selection.targetId
    return all.filter { $0.target == target && (launch.selection.modelId.isBlank || $0.model == launch.selection.modelId) }
  }
  private func reload() {
    guard available else { clear(); return }
    do { job = try repository.read(launch.conversation); choices = routes() }
    catch { failed = true; choices = [] }
  }
  private func start() {
    guard available, case .start(let objective) = launch.command,
      choices.indices.contains(selected), GalaxySSIHealthAgentLab.intent(objective, following: false, language: language) == nil else { return }
    do {
      let route = choices[selected]
      guard routes().contains(route), AgentConversationGoalInference.isCurrent(route, store: store) else { throw AgentConversationalTeamJob.Failure.unavailable }
      AgentConversationalTeamRuntime.shared.bind(store)
      if let actual = try repository.read(launch.conversation) {
        guard !actual.active, AgentConversationalTeamRuntime.shared.publish(actual, store: store) else { throw AgentConversationalTeamJob.Failure.stale }
      }
      guard available else { throw AgentConversationalTeamJob.Failure.stale }
      var next = AgentConversationalTeamJob(conversation: launch.conversation, objective: objective, route: route)
      next.source = launch.source
      try repository.replace(next, expected: nil)
      if launch.source == nil {
        _ = store.appendOutgoing(objective, to: "hermes", status: .delivered, turnId: next.id.uuidString, readOnlyAnalysis: true,
          conversationOverride: launch.conversation, sourceTrace: AgentConversationalTeamRuntime.stage)
      }
      _ = store.appendIncoming(t("queued", "Team queued on the confirmed model.") + " / " + AgentConversationGoalText.route(route, language: language),
        from: "hermes", remoteMessageId: "conversation-team:\(next.id):queued", traceStage: AgentConversationalTeamRuntime.stage,
        conversationId: launch.conversation, turnId: next.source?.turn ?? next.id.uuidString)
      AgentConversationalTeamRuntime.shared.setForeground(true, store: store)
      applied(); dismiss()
    } catch { failed = true }
  }
  private func stop() {
    guard available else { return }
    do {
      guard let actual = try repository.read(launch.conversation), actual.active else { return }
      let stopped = try actual.stop()
      try repository.replace(stopped, expected: actual)
      AgentConversationalTeamRuntime.shared.bind(store)
      AgentConversationalTeamRuntime.shared.changed(conversation: launch.conversation)
      _ = AgentConversationalTeamRuntime.shared.publish(stopped, store: store)
      applied(); dismiss()
    } catch { failed = true }
  }
  private func clear() { choices = []; job = nil; failed = false }
  private func progress(_ event: AgentConversationalTeamEngine.Event) -> String {
    switch event {
    case .planning: return t("planning", "Planning the temporary team")
    case .planAccepted(let total): return String(format: t("planned", "%lld text roles planned"), Int64(total))
    case .roleStarted(let index, let total, _): return String(format: t("role_started", "Role %lld / %lld started"), Int64(index), Int64(total))
    case .roleCompleted(let index, let total, _): return String(format: t("role_completed", "Role %lld / %lld completed"), Int64(index), Int64(total))
    case .synthesizing: return t("synthesizing", "Synthesizing public reports")
    case .auditing(let index, let total): return String(format: t("auditing", "Role %lld / %lld is auditing the final draft"), Int64(index), Int64(total))
    case .completed: return t("state_finished", "Finished")
    case .interrupted: return t("interrupted", "This team was interrupted. Its uncertain requests were not replayed.")
    case .stopped: return t("state_stopped", "Stopped")
    }
  }
  private func t(_ key: String, _ fallback: String) -> String { AgentConversationalTeamCommand.text(key, fallback, language: language) }
}

extension AgentHomeView {
  func bindModelTeamReview(_ outgoing: ChatMessage, expectedRevision: UUID, hasExtras: Bool) {
    guard expectedRevision == teamDraftRevision, !hasExtras, outgoing.contactId == "hermes", !outgoing.readOnlyAnalysis,
      outgoing.sourceConversationId.isBlank, homeVisible, scenePhase == .active, draft.isBlank, attachments.isEmpty,
      AgentConversationGoalRuntime.eligible(activeAgentSession),
      AgentConversationalTeamCommand.allowsModelReview(outgoing.content, language: interfaceLanguage) else { return }
    let candidate = AgentLocalTeamReviewWindow.Candidate(owner: store.profile.identityFingerprint,
      conversation: outgoing.conversationId, source: .init(message: outgoing.id, turn: outgoing.turnId.ifBlank(outgoing.id.uuidString)),
      objective: outgoing.content, revision: expectedRevision,
      selection: AgentModelSelectionSettings.selection(for: outgoing.conversationId, defaults: store.defaults))
    modelTeamReview.bind(candidate) {
      homeVisible && scenePhase == .active && store.canReadAgentTranscript && UIApplication.shared.isProtectedDataAvailable &&
        expectedRevision == teamDraftRevision && draft.isBlank && attachments.isEmpty &&
        candidate.owner == store.profile.identityFingerprint && candidate.conversation == store.activeAgentConversationId &&
        candidate.selection == AgentModelSelectionSettings.selection(for: candidate.conversation, defaults: store.defaults) &&
        AgentConversationGoalRuntime.eligible(activeAgentSession) &&
        candidate.source.matches(store, conversation: candidate.conversation, objective: candidate.objective)
    }
  }
  func offerModelTeamReview() {
    guard let candidate = modelTeamReview.claim(), conversationalTeamLaunch == nil, conversationGoalLaunch == nil,
      localLabLaunch == nil, healthCareSubmission == nil else { return }
    conversationalTeamLaunch = .init(owner: candidate.owner, conversation: candidate.conversation,
      revision: candidate.revision, command: .start(candidate.objective), selection: candidate.selection, source: candidate.source)
  }
  func teamLaunchIsCurrent(_ launch: AgentConversationalTeamLaunch) -> Bool {
    homeVisible && scenePhase == .active && launch.revision == teamDraftRevision && attachments.isEmpty &&
      launch.owner == store.profile.identityFingerprint && launch.conversation == store.activeAgentConversationId &&
      screenAssistantRunID == nil && screenAssistantConversationID.isEmpty
  }
  func offerConversationalTeam(_ text: String, hasAttachments: Bool) -> Bool {
    guard let command = AgentConversationalTeamCommand.parse(text) else { return false }
    let targets = AgentCallableTargetCatalog.build(contacts: store.visibleContacts, apiKey: { store.apiKey(for: $0) })
    guard !hasAttachments, attachments.isEmpty, homeVisible, scenePhase == .active, store.canReadAgentTranscript,
      UIApplication.shared.isProtectedDataAvailable, screenAssistantRunID == nil, screenAssistantConversationID.isEmpty,
      AgentConversationGoalRuntime.eligible(activeAgentSession),
      AgentMentionText.parse(text, targets: targets).requestedMembers.isEmpty else {
      attachmentError = AgentConversationalTeamCommand.text("unavailable", "Use an active ordinary conversation without attachments or Agent mentions.", language: interfaceLanguage)
      return true
    }
    if command == .tooLong || command == .privateObjective ||
      GalaxySSIHealthAgentLab.intent(text, following: false, language: interfaceLanguage) != nil {
      attachmentError = AgentConversationalTeamCommand.text("refused", "Use a non-private text objective of at most 4000 characters. Personal health requests belong in the private Health workflow.", language: interfaceLanguage)
      return true
    }
    conversationalTeamLaunch = .init(owner: store.profile.identityFingerprint, conversation: store.activeAgentConversationId,
      revision: teamDraftRevision, command: command,
      selection: AgentModelSelectionSettings.selection(for: store.activeAgentConversationId, defaults: store.defaults))
    actionTrayPresented = false
    return true
  }
}
