import UIKit

@MainActor
final class AgentConversationGoalRuntime {
  static let shared = AgentConversationGoalRuntime()
  static let stage = "conversation_text_goal"
  private weak var store: GalaxySSIStore?
  private var owner = ""
  private var foreground = false
  private var backgroundGrant = false
  private var grace: UIBackgroundTaskIdentifier = .invalid
  private var work: Task<Void, Never>?
  private var ticket = UUID()
  private var claimed: AgentConversationGoal?
  static func eligible(_ session: AgentConversation?) -> Bool {
    guard let session else { return false }
    return session.status == .active && !session.privateMode && !session.trackingPaused &&
      session.globalTopicKey.isBlank && session.mergedIntoConversationId.isBlank && session.collaborationRoster == nil
  }
  func bind(_ value: GalaxySSIStore) {
    if store !== value || owner != value.profile.identityFingerprint {
      interrupt(); store = value; owner = value.profile.identityFingerprint
    }
  }
  func setForeground(_ active: Bool, store value: GalaxySSIStore) {
    bind(value); foreground = active
    if active { endGrace(); wake() }
    else {
      if work != nil, !backgroundGrant, grace == .invalid {
        grace = UIApplication.shared.beginBackgroundTask(withName: "Conversation text goal") {
          Task { @MainActor in self.interrupt(); self.schedule() }
        }
      }
      schedule()
    }
  }
  func wake() {
    guard work == nil, let store, permits(store) else { schedule(); return }
    let run = UUID(); ticket = run
    work = Task { @MainActor [weak self, weak store] in
      guard let self, let store else { return }
      let pendingSlice = await self.runSlice(store: store, ticket: run)
      guard self.ticket == run else { return }
      self.claimed = nil; self.work = nil; self.endGrace(); self.schedule()
      if pendingSlice, self.foreground {
        self.wake()
      }
    }
  }
  func interrupt() {
    let previous = claimed
    ticket = UUID(); work?.cancel(); work = nil; claimed = nil; endGrace()
    if let previous, let store, owner == store.profile.identityFingerprint,
      UIApplication.shared.isProtectedDataAvailable {
      let repository = repository(store)
      if let blocked = try? previous.halt(.interrupted) { try? repository.replace(blocked, expected: previous) }
    }
  }
  func changed(conversation: String) {
    if claimed?.conversation == conversation { interrupt() }
    wake()
  }
  func runBackground() async -> Bool {
    guard UIApplication.shared.applicationState != .active, UIApplication.shared.isProtectedDataAvailable else { return false }
    var cold: GalaxySSIStore?
    if store == nil {
      guard GalaxySSIEncryptedStateStore.load(defaults: .standard, secrets: KeychainSecretStore.shared) != nil else { return false }
      cold = GalaxySSIStore(); if let cold { bind(cold) }
    }
    guard let store, permitsIdentity(store) else { return false }
    backgroundGrant = true
    defer { backgroundGrant = false; _ = cold }
    wake()
    if let work { await withTaskCancellationHandler(operation: { await work.value }, onCancel: {
      Task { @MainActor in self.interrupt() }
    }) }
    return !Task.isCancelled
  }
  private func repository(_ store: GalaxySSIStore) -> AgentConversationGoalStore {
    .init(owner: owner, defaults: store.defaults, secrets: store.secrets)
  }
  private func permitsIdentity(_ value: GalaxySSIStore) -> Bool {
    store === value && !owner.isBlank && owner == value.profile.identityFingerprint &&
      value.canReadAgentTranscript && UIApplication.shared.isProtectedDataAvailable
  }
  private func permits(_ value: GalaxySSIStore) -> Bool {
    permitsIdentity(value) && (foreground || backgroundGrant || grace != .invalid)
  }
  private func current(_ goal: AgentConversationGoal, store: GalaxySSIStore, ticket: UUID) -> Bool {
    self.ticket == ticket && !Task.isCancelled && permits(store) && Self.eligible(store.agentSession(id: goal.conversation)) &&
      AgentConversationGoalInference.isCurrent(goal.route, store: store) &&
      (try? repository(store).read(goal.conversation)) == goal
  }
  private func runSlice(store: GalaxySSIStore, ticket: UUID) async -> Bool {
    let repository = repository(store), started = ProcessInfo.processInfo.systemUptime
    defer {
      if self.ticket == ticket, let pending = claimed, permitsIdentity(store),
        (try? repository.read(pending.conversation)) == pending {
        let issue: AgentConversationGoal.Issue = AgentConversationGoalInference.isCurrent(pending.route, store: store) ? .interrupted : .routeChanged
        if let blocked = try? pending.halt(issue) { try? repository.replace(blocked, expected: pending); _ = publish(blocked, store: store) }
      }
    }
    do {
      for queued in try repository.goals() {
        guard self.ticket == ticket, !Task.isCancelled, permits(store) else { return false }
        guard let initial = try repository.read(queued.conversation) else { continue }
        if initial.phase != .running { _ = publish(initial, store: store); continue }
        var goal = initial
        while self.ticket == ticket, !Task.isCancelled, permits(store) {
          guard try repository.read(goal.conversation) == goal else { break }
          guard Self.eligible(store.agentSession(id: goal.conversation)) else {
            try repository.replace(goal.halt(.conversationUnavailable), expected: goal)
            break
          }
          if goal.inFlight {
            let blocked = try goal.halt(.interrupted)
            try repository.replace(blocked, expected: goal); _ = publish(blocked, store: store)
            break
          }
          guard publish(goal, store: store) else { return false }
          guard goal.phase == .running else { break }
          if ProcessInfo.processInfo.systemUptime - started >= 180 { return true }
          guard AgentConversationGoalInference.isCurrent(goal.route, store: store) else {
            let blocked = try goal.halt(.routeChanged)
            try repository.replace(blocked, expected: goal); _ = publish(blocked, store: store)
            break
          }
          let next = try goal.claim()
          try repository.replace(next, expected: goal); claimed = next
          let result: AgentConversationGoal
          do {
            let raw = try await AgentConversationGoalInference.step(next, store: store,
              valid: { self.current(next, store: store, ticket: ticket) })
            guard current(next, store: store, ticket: ticket) else { return false }
            do { result = try next.accept(raw) } catch { result = try next.halt(.invalidResponse) }
          } catch {
            guard current(next, store: store, ticket: ticket) else { return false }
            result = try next.halt(.providerFailure)
          }
          guard current(next, store: store, ticket: ticket) else { return false }
          try repository.replace(result, expected: next)
          claimed = nil; goal = result
        }
      }
    } catch { return false }
    return (try? repository.goals().contains { $0.phase == .running && !$0.inFlight }) ?? false
  }
  private func publish(_ goal: AgentConversationGoal, store: GalaxySSIStore) -> Bool {
    guard goal.revision > 0, !(goal.review && goal.phase == .running) else { return true }
    guard permitsIdentity(store), Self.eligible(store.agentSession(id: goal.conversation)),
      (try? repository(store).read(goal.conversation)) == goal else { return false }
    let remote = "conversation-goal:\(goal.id.uuidString):\(goal.revision)"
    let body = [AgentConversationGoalText.round(goal, language: store.languagePolicy.interfaceLanguage),
      goal.checkpoints.last ?? "", goal.next, goal.issue.map { AgentConversationGoalText.issue($0, language: store.languagePolicy.interfaceLanguage) } ?? "",
      goal.phase == .paused && goal.rounds >= goal.allowance ? AgentConversationGoalText.get("budget", "The confirmed round allowance is used. Resume to authorize another six rounds.", store.languagePolicy.interfaceLanguage) : ""]
      .filter { !$0.isEmpty }.joined(separator: "\n\n")
    if store.hasIncomingDuplicate(body, from: "hermes", remoteMessageId: remote) { return true }
    _ = store.appendIncoming(body, from: "hermes", remoteMessageId: remote, traceStage: Self.stage,
      conversationId: goal.conversation, turnId: AgentTeamDispatchIds.nameBasedUUID("goal:\(goal.id):\(goal.rounds)").uuidString)
    return true
  }
  private func endGrace() {
    if grace != .invalid { UIApplication.shared.endBackgroundTask(grace); grace = .invalid }
  }
  private func schedule() {
    guard let store, permitsIdentity(store) else { return }
    guard let goals = try? repository(store).goals() else { return }
    AgentConversationGoalBackground.schedule(pending: goals.contains { $0.phase == .running })
  }
}
