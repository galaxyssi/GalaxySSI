import Combine
import UIKit

@MainActor
final class AgentConversationalTeamRuntime: ObservableObject {
  static let shared = AgentConversationalTeamRuntime()
  static let stage = "conversation_text_team"
  private weak var store: GalaxySSIStore?
  private var owner = ""
  private var foreground = false
  private var grant: UUID?
  private var grace: UIBackgroundTaskIdentifier = .invalid
  private var graceToken: UUID?
  private var work: Task<Void, Never>?
  private var ticket = UUID()
  private var claimed: UUID?
  private var claimedConversation = ""
  @Published private(set) var progress: [UUID: AgentConversationalTeamEngine.Event] = [:]

  func bind(_ value: GalaxySSIStore) {
    if store !== value || owner != value.profile.identityFingerprint {
      interrupt(); store = value; owner = value.profile.identityFingerprint
    }
  }
  func setForeground(_ active: Bool, store: GalaxySSIStore) {
    bind(store); foreground = active
    if active { grant = nil; endGrace(); wake() }
    else {
      if work != nil, grant == nil, grace == .invalid {
        let token = UUID(); graceToken = token
        grace = UIApplication.shared.beginBackgroundTask(withName: "Conversation team") {
          Task { @MainActor in
            guard self.graceToken == token else { return }
            self.interrupt(); self.schedule()
          }
        }
      }
      schedule()
    }
  }
  func interrupt() {
    // Leave an uncertain running row durable. Recovery must not replay its requests.
    ticket = UUID(); work?.cancel(); work = nil; claimed = nil; claimedConversation = ""
    progress = [:]
    grant = nil; endGrace()
  }
  func changed(conversation: String) {
    if claimedConversation == conversation { interrupt() }
    wake()
  }
  func expireBackground(_ value: UUID) {
    guard grant == value else { return }
    interrupt(); schedule()
  }
  func runBackground(grant value: UUID) async -> Bool {
    guard UIApplication.shared.applicationState != .active, UIApplication.shared.isProtectedDataAvailable else { return false }
    var cold: GalaxySSIStore?
    if store == nil {
      guard GalaxySSIStore.canRestoreConversationGoalState() else { return false }
      cold = GalaxySSIStore(); if let cold { bind(cold) }
    }
    guard let store, identity(store) else { return false }
    grant = value
    defer { if grant == value { grant = nil }; _ = cold }
    wake()
    if let work { await withTaskCancellationHandler(operation: { await work.value }, onCancel: {
      Task { @MainActor in self.expireBackground(value) }
    }) }
    return !Task.isCancelled
  }
  func wake() {
    guard work == nil, let store, permits(store) else { schedule(); return }
    let epoch = UUID(); ticket = epoch
    work = Task { @MainActor [weak self, weak store] in
      guard let self, let store else { return }
      await self.run(store, epoch: epoch)
      guard self.ticket == epoch else { return }
      self.claimed = nil; self.claimedConversation = ""; self.progress = [:]; self.work = nil; self.endGrace(); self.schedule()
    }
  }
  private func repository(_ store: GalaxySSIStore) -> AgentConversationalTeamStore {
    .init(owner: owner, defaults: store.defaults, secrets: store.secrets)
  }
  private func identity(_ value: GalaxySSIStore) -> Bool {
    store === value && !owner.isBlank && owner == value.profile.identityFingerprint &&
      value.canReadAgentTranscript && UIApplication.shared.isProtectedDataAvailable
  }
  private func permits(_ value: GalaxySSIStore) -> Bool {
    identity(value) && (foreground || grant != nil || grace != .invalid)
  }
  private func current(_ original: AgentConversationalTeamJob, store: GalaxySSIStore, epoch: UUID) -> Bool {
    // Sibling calls advance the revision; authorization binds immutable job identity instead.
    guard ticket == epoch, !Task.isCancelled, permits(store),
      AgentConversationGoalRuntime.eligible(store.agentSession(id: original.conversation)),
      AgentConversationGoalInference.isCurrent(original.route, store: store),
      let actual = try? repository(store).read(original.conversation) else { return false }
    return actual.id == original.id && actual.state == .running &&
      actual.objective == original.objective && actual.route == original.route && actual.source == original.source &&
      (original.source == nil || original.source?.matches(store, conversation: original.conversation, objective: original.objective) == true)
  }
  private func ask(_ system: String, prompt: String, original: AgentConversationalTeamJob,
    store: GalaxySSIStore, epoch: UUID) async throws -> String {
    guard current(original, store: store, epoch: epoch), let previous = try repository(store).read(original.conversation) else {
      throw AgentConversationalTeamJob.Failure.stale
    }
    let next = try previous.reserveCall()
    try repository(store).replace(next, expected: previous)
    return try await AgentConversationGoalInference.text(route: original.route, conversation: original.conversation,
      taskID: original.id.uuidString, requestID: "conversation-team-\(original.id)-\(next.calls)",
      system: system, prompt: prompt, purpose: "Confirmed temporary text team", store: store,
      valid: { self.current(original, store: store, epoch: epoch) })
  }
  private func run(_ store: GalaxySSIStore, epoch: UUID) async {
    let repository = repository(store)
    do {
      for saved in try repository.jobs() {
        guard ticket == epoch, !Task.isCancelled, permits(store) else { return }
        guard let initial = try repository.read(saved.conversation), initial.id == saved.id else { continue }
        guard AgentConversationGoalRuntime.eligible(store.agentSession(id: initial.conversation)),
          initial.source == nil || initial.source?.matches(store, conversation: initial.conversation, objective: initial.objective) == true else {
          if initial.active {
            let stopped = try initial.stop(); try repository.replace(stopped, expected: initial); try repository.retire(stopped)
          } else { try repository.retire(initial) }
          continue
        }
        if !initial.active { _ = publish(initial, store: store); continue }
        if initial.state == .running {
          let interrupted = try initial.finish(text("interrupted", "This team was interrupted. Its uncertain requests were not replayed.", store))
          try repository.replace(interrupted, expected: initial); _ = publish(interrupted, store: store)
          continue
        }
        guard AgentConversationGoalInference.isCurrent(initial.route, store: store) else {
          let stopped = try initial.stop(); try repository.replace(stopped, expected: initial)
          _ = publish(stopped, store: store); continue
        }
        let running = try initial.begin()
        try repository.replace(running, expected: initial)
        claimed = running.id; claimedConversation = running.conversation
        let answer: String
        do {
          let labels = AgentTeamDraftAudit.Labels(passing: text("passing", "Pass all gates:", store),
            none: text("none", "None", store), limitation: text("limitation", "Evidence limitation:", store))
          let outcome = try await AgentConversationalTeamEngine.run(objective: running.objective, labels: labels, ask: { [weak self, weak store] system, prompt in
            guard let self, let store else { throw CancellationError() }
            return try await self.ask(system, prompt: prompt, original: running, store: store, epoch: epoch)
          }, onEvent: { event in
            guard self.ticket == epoch, self.identity(store) else { return }
            self.progress[running.id] = event
          })
          guard current(running, store: store, epoch: epoch) else { return }
          answer = outcome.publicText(disagreementsTitle: text("disagreements", "Independent disagreements", store),
            correctionTitle: text("correction", "Reviewer correction:", store)) + "\n\n" +
            String(format: text("receipt", "%lld roles / %lld model calls", store), Int64(outcome.roleCount), Int64(outcome.calls))
        } catch AgentConversationalTeamProtocol.Failure.finalAuditMissing {
          guard ticket == epoch, !Task.isCancelled, permits(store) else { return }
          answer = text("final_audit_missing", "No independent final reviewer was assigned. The team stopped before worker calls; no draft was published.", store)
        } catch let issue as AgentTeamDraftAudit.Failure {
          guard ticket == epoch, !Task.isCancelled, permits(store) else { return }
          switch issue {
          case .withheld(let objection): answer = text("withheld", "The reviewer withheld the draft:", store) + "\n" + objection
          case .tableMismatch(let verified): answer = text("table_mismatch", "The reviewer did not confirm the source table. Only the deterministic comparison is shown:", store) + "\n\n" + verified
          case .invalid: answer = text("failed", "The confirmed model could not complete this team. No requests will be retried automatically.", store)
          }
        } catch {
          guard ticket == epoch, !Task.isCancelled, permits(store) else { return }
          answer = text("failed", "The confirmed model could not complete this team. No requests will be retried automatically.", store)
        }
        // A removed/stopped/replaced row must never receive a late result.
        guard ticket == epoch, permits(store), let actual = try repository.read(running.conversation),
          actual.id == running.id, actual.state == .running else { return }
        let finished = try actual.finish(answer)
        try repository.replace(finished, expected: actual)
        _ = publish(finished, store: store)
        progress.removeValue(forKey: running.id)
        claimed = nil; claimedConversation = ""
      }
    } catch { return }
  }
  @discardableResult
  func publish(_ job: AgentConversationalTeamJob, store: GalaxySSIStore) -> Bool {
    guard !job.active, identity(store), AgentConversationGoalRuntime.eligible(store.agentSession(id: job.conversation)),
      job.source == nil || job.source?.matches(store, conversation: job.conversation, objective: job.objective) == true,
      (try? repository(store).read(job.conversation)) == job else { return false }
    let remote = "conversation-team:\(job.id):result"
    let body = job.state == .finished ? job.answer : text("stopped", "Team stopped. Late results will not be published.", store)
    do {
      // This API commits the transcript row before returning, unlike an in-memory duplicate check.
      _ = try store.persistTransportIncoming(body, from: "hermes", remoteMessageId: remote,
        conversationId: job.conversation, turnId: job.source?.turn ?? job.id.uuidString, richOutputJson: "", tracePrefix: Self.stage)
      try repository(store).retire(job)
      return true
    } catch { return false }
  }
  private func text(_ key: String, _ fallback: String, _ store: GalaxySSIStore) -> String {
    GalaxySSILocalization.string("galaxyssi.conversation_team." + key, fallback: fallback, language: store.languagePolicy.interfaceLanguage)
  }
  private func endGrace() {
    graceToken = nil
    if grace != .invalid { UIApplication.shared.endBackgroundTask(grace); grace = .invalid }
  }
  private func schedule() {
    guard let store, identity(store), let jobs = try? repository(store).jobs() else { return }
    AgentConversationalTeamBackground.schedule(pending: !jobs.isEmpty)
  }
}
