import SwiftUI

enum AgentConversationGoalText {
  static func get(_ key: String, _ fallback: String, _ language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.conversation_goal." + key, fallback: fallback, language: language)
  }
  static func phase(_ value: AgentConversationGoal.Phase, language: String) -> String {
    get("phase_" + value.rawValue, value.rawValue.capitalized, language)
  }
  static func issue(_ value: AgentConversationGoal.Issue, language: String) -> String {
    let fallback: String
    switch value {
    case .interrupted: fallback = "The last request was interrupted. It will not be replayed automatically."
    case .repeatedProgress: fallback = "The model repeated earlier work without new progress."
    case .invalidResponse: fallback = "The model did not return a valid text-goal result."
    case .providerFailure: fallback = "The confirmed provider could not complete this round."
    case .conversationUnavailable: fallback = "This conversation is no longer eligible."
    case .routeChanged: fallback = "The confirmed model or provider route is no longer available."
    }
    return get("issue_" + value.rawValue, fallback, language)
  }
  static func round(_ goal: AgentConversationGoal, language: String) -> String {
    String(format: get("round", "Round %lld / %@", language), Int64(goal.rounds), phase(goal.phase, language: language))
  }
  static func route(_ route: AgentConversationGoal.Route, language: String) -> String {
    route.kind == .local ? get("local", "On-device", language) + " / " + route.model : route.model + " / " + route.host
  }
}

struct AgentConversationGoalLaunch: Identifiable {
  let id = UUID()
  let owner: String
  let conversation: String
  let command: AgentConversationGoalCommand
  let draftSHA: String
}

@MainActor
struct GalaxySSIConversationGoalView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.dismiss) private var dismiss
  let launch: AgentConversationGoalLaunch
  let applied: () -> Void
  @State private var goal: AgentConversationGoal?
  @State private var objective = ""
  @State private var clarification = ""
  @State private var choices: [AgentConversationGoal.Route] = []
  @State private var selected = 0
  @State private var failed = false
  private var repository: AgentConversationGoalStore { .init(owner: launch.owner, defaults: store.defaults, secrets: store.secrets) }
  private var available: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.canReadAgentTranscript &&
      store.profile.identityFingerprint == launch.owner && store.activeAgentConversationId == launch.conversation &&
      AgentConversationGoalRuntime.eligible(store.agentSession(id: launch.conversation))
  }
  var body: some View {
    NavigationView {
      List {
        if available {
          if let goal {
            Section {
              Text(verbatim: goal.objective).textSelection(.enabled)
              Text(AgentConversationGoalText.round(goal, language: language)).font(.headline)
              Text(AgentConversationGoalText.route(goal.route, language: language)).font(.footnote).foregroundColor(.secondary)
              if goal.review { Text(t("review", "Awaiting a separate final review")) }
              if let issue = goal.issue { Text(AgentConversationGoalText.issue(issue, language: language)) }
              if let last = goal.checkpoints.last { Text(verbatim: String(last.prefix(1_500))).textSelection(.enabled) }
              if !goal.next.isEmpty { Text(verbatim: goal.next).textSelection(.enabled) }
              if goal.phase == .paused && goal.rounds >= goal.allowance {
                Text(t("budget", "The confirmed round allowance is used. Resume to authorize another six rounds."))
              }
            }
            if !goal.terminal {
              Section {
                if goal.phase == .running {
                  Button { change(.pause) } label: { Label(t("pause", "Pause"), systemImage: "pause") }
                }
                Button(role: .destructive) { change(.stop) } label: { Label(t("stop", "Stop"), systemImage: "stop") }
              }
            }
          }
          if goal == nil || goal?.terminal == true {
            Section(t("objective", "Objective")) {
              TextEditor(text: $objective).frame(minHeight: 100, maxHeight: 180).accessibilityLabel(t("objective", "Objective"))
              Text("\(objective.utf16.count)/4000").font(.caption).foregroundColor(.secondary)
              if choices.isEmpty { Text(t("no_provider", "No ready on-device or direct cloud model is available.")) }
              else {
                Picker(t("model", "Confirmed model"), selection: $selected) {
                  ForEach(Array(choices.enumerated()), id: \.offset) { index, route in
                    Text(AgentConversationGoalText.route(route, language: language)).tag(index)
                  }
                }
              }
              authorization
              Button { change(.start(objective)) } label: { Label(t("authorize", "Authorize six rounds"), systemImage: "play") }
                .disabled(objective.isBlank || objective.utf16.count > 4_000 || !choices.indices.contains(selected))
            }
          } else if let goal, [.paused, .blocked].contains(goal.phase) {
            Section(t("clarification", "Clarification")) {
              TextEditor(text: $clarification).frame(minHeight: 80, maxHeight: 160).accessibilityLabel(t("clarification", "Clarification"))
              Text("\(clarification.utf16.count)/4000").font(.caption).foregroundColor(.secondary)
              Text(verbatim: goal.objective)
              Text(AgentConversationGoalText.route(goal.route, language: language))
              authorization
              Button { change(.resume(clarification)) } label: { Label(t("resume", "Authorize six more rounds"), systemImage: "play") }
                .disabled(clarification.utf16.count > 4_000)
            }
          }
          if failed { Text(t("changed", "The goal or model changed, or the checkpoint could not be saved. Reopen this panel.")) }
        }
      }
      .navigationTitle(t("title", "Conversation goal"))
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("close", "Close")) { dismiss() } } }
    }.navigationViewStyle(.stack)
    .privacySensitive()
    .onAppear {
      if case .start(let text) = launch.command { objective = text }
      if case .resume(let note) = launch.command { clarification = note }
      reload()
      if launch.command == .pause || launch.command == .stop { change(launch.command) }
    }
    .onReceive(NotificationCenter.default.publisher(for: AgentConversationGoalStore.changed)) { _ in reload() }
    .onChange(of: scene) { if $0 != .active { clear(); dismiss() } }
    .onChange(of: store.activeAgentConversationId) { _ in clear(); dismiss() }
    .onChange(of: store.profile.identityFingerprint) { _ in clear(); dismiss() }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in clear(); dismiss() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear(); dismiss() }
    .onDisappear(perform: clear)
  }
  private var authorization: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(t("consent", "Authorize up to six text-only model rounds, including final review. Cloud requests may incur provider charges."))
      Text(t("background", "Background time is scheduled by iOS; uninterrupted execution is not guaranteed."))
        .font(.footnote).foregroundColor(.secondary)
    }
  }
  private func reload() {
    guard available else { clear(); return }
    do { goal = try repository.read(launch.conversation); choices = AgentConversationGoalInference.routes(store: store, conversation: launch.conversation) }
    catch { goal = nil; choices = []; failed = true }
  }
  private func change(_ command: AgentConversationGoalCommand) {
    guard available else { return }
    do {
      let actual = try repository.read(launch.conversation)
      guard actual?.id == goal?.id, actual?.generation == goal?.generation else { throw AgentConversationGoal.Failure.stale }
      let next: AgentConversationGoal
      let receipt: String
      switch command {
      case .start(let raw):
        guard actual == nil || actual?.terminal == true, choices.indices.contains(selected) else { throw AgentConversationGoal.Failure.stale }
        let route = choices[selected]
        guard AgentConversationGoalInference.routes(store: store, conversation: launch.conversation).contains(route) else { throw AgentConversationGoal.Failure.unavailable }
        next = .init(conversation: launch.conversation, objective: raw.trimmingCharacters(in: .whitespacesAndNewlines), route: route)
        receipt = "/goal " + next.objective
      case .resume(let note):
        guard let actual, AgentConversationGoalInference.routes(store: store, conversation: launch.conversation).contains(actual.route) else { throw AgentConversationGoal.Failure.unavailable }
        next = try actual.resume(clarification: note); receipt = "/goal resume " + note
      case .pause:
        guard let actual else { return }; next = try actual.pause(); receipt = "/goal pause"
      case .stop:
        guard let actual else { return }; next = try actual.stop(); receipt = "/goal stop"
      default: return
      }
      try repository.replace(next, expected: actual)
      AgentConversationGoalRuntime.shared.bind(store)
      AgentConversationGoalRuntime.shared.changed(conversation: launch.conversation)
      let turn = UUID().uuidString
      _ = store.appendOutgoing(receipt, to: "hermes", status: .delivered, turnId: turn, readOnlyAnalysis: true,
        conversationOverride: launch.conversation, sourceTrace: AgentConversationGoalRuntime.stage)
      _ = store.appendIncoming(AgentConversationGoalText.phase(next.phase, language: language) + " / " +
        AgentConversationGoalText.route(next.route, language: language), from: "hermes",
        remoteMessageId: "goal-command:\(next.id):\(next.generation):\(next.revision)",
        traceStage: AgentConversationGoalRuntime.stage, conversationId: launch.conversation, turnId: turn)
      failed = false; applied(); reload()
    } catch { failed = true }
  }
  private func clear() { goal = nil; objective = ""; clarification = ""; choices = []; failed = false }
  private func t(_ key: String, _ fallback: String) -> String { AgentConversationGoalText.get(key, fallback, language) }
}

extension AgentHomeView {
  func offerConversationGoal(_ text: String, hasAttachments: Bool) -> Bool {
    guard let command = AgentConversationGoalCommand.parse(text) else { return false }
    guard !hasAttachments, homeVisible, scenePhase == .active, UIApplication.shared.isProtectedDataAvailable,
      store.canReadAgentTranscript, screenAssistantRunID == nil, screenAssistantConversationID.isEmpty,
      AgentConversationGoalRuntime.eligible(activeAgentSession) else {
      attachmentError = AgentConversationGoalText.get("unavailable", "Use an active ordinary conversation without attachments for a text goal.", interfaceLanguage)
      return true
    }
    conversationGoalLaunch = .init(owner: store.profile.identityFingerprint, conversation: store.activeAgentConversationId,
      command: command, draftSHA: AgentTurnReceiptEvidence.hash(text))
    actionTrayPresented = false
    return true
  }
}
