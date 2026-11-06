import Foundation
import os

struct AgentTeamRecoveryRetryState: Codable, Equatable {
  static let failureLimit = 10
  var failures = 0
  var retryAtMillis: Int64 = 0
  var progress: String?
  var scopeMissing = false
  var updatedAtMillis: Int64 = 0

  var stalled: Bool { scopeMissing || failures >= Self.failureLimit }

  mutating func failed(progress: String?, now: Int64) {
    guard !stalled, now >= retryAtMillis else { return }
    if let progress, let previous = self.progress, progress != previous { failures = 0 }
    if let progress { self.progress = progress }
    failures += 1
    retryAtMillis = now + min(Int64(5_000) << min(failures - 1, 3), 30_000)
    updatedAtMillis = now
  }

  static func progress(_ snapshot: AgentTeamExecutionSnapshot) -> String {
    let evidence = snapshot.members.filter {
      $0.deliveryMode != .ignore && $0.status.isTerminal && $0.status != .interrupted
    }.sorted { $0.memberId < $1.memberId }.map {
      "\($0.memberId.utf8.count):\($0.memberId):\($0.status.rawValue)"
    }
    return GlobalAgentText.privateFingerprint(evidence.joined(separator: "\n"))
  }

  static func missingScope(conversation: String, session: AgentConversation?, requiresRoster: Bool) -> Bool {
    guard let session else { return requiresRoster || conversation.hasPrefix("ios-agent-") }
    return !session.mergedIntoConversationId.isBlank || (requiresRoster && session.collaborationRoster == nil)
  }
}

@MainActor
final class AgentTeamRecoveryRetryLedger {
  static let changed = Notification.Name("GalaxySSI.AgentTeamRecoveryRetryChanged")
  private var owner = ""
  private var entries: [String: AgentTeamRecoveryRetryState] = [:]
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore

  init(defaults: UserDefaults = .standard, secrets: GalaxySSISecretStore) {
    self.defaults = defaults
    self.secrets = secrets
  }

  func state(run: String, profile: String) -> AgentTeamRecoveryRetryState {
    load(profile)
    return entries[run] ?? .init()
  }

  func observed(_ snapshot: AgentTeamExecutionSnapshot, profile: String) {
    let run = snapshot.supervisorRunId
    let existing = state(run: run, profile: profile)
    guard let prior = existing.progress, !existing.stalled,
          prior != AgentTeamRecoveryRetryState.progress(snapshot) else { return }
    set(nil, run: run)
  }

  func failure(run: String, profile: String, progress: String?, now: Int64) {
    var next = state(run: run, profile: profile)
    let previous = next
    next.failed(progress: progress, now: now)
    guard next != previous else { return }
    set(next, run: run)
    #if DEBUG
    Logger(subsystem: "com.galaxyssi.chat.ios", category: "team-recovery")
      .debug("Recovery attempt failed; consecutive failures: \(next.failures, privacy: .public)")
    #endif
  }

  func stopMissingScope(run: String, profile: String, now: Int64) -> Bool {
    var next = state(run: run, profile: profile)
    guard !next.scopeMissing else { return false }
    next.scopeMissing = true
    next.updatedAtMillis = now
    set(next, run: run)
    return true
  }

  func resume(run: String, profile: String) -> Bool {
    let current = state(run: run, profile: profile)
    guard current.stalled, !current.scopeMissing else { return false }
    set(nil, run: run)
    return true
  }

  private var key: String { "galaxyssi.team-recovery.v1." + GlobalAgentText.privateFingerprint(owner) }

  private func load(_ profile: String) {
    guard owner != profile else { return }
    owner = profile
    if let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets),
       let decoded = try? JSONDecoder().decode([String: AgentTeamRecoveryRetryState].self, from: data) {
      entries = decoded.filter { (0...AgentTeamRecoveryRetryState.failureLimit).contains($0.value.failures) }
    } else {
      entries = [:]
    }
  }

  private func set(_ entry: AgentTeamRecoveryRetryState?, run: String) {
    entries[run] = entry
    if entries.count > 256 {
      let overflow = entries.sorted { $0.value.updatedAtMillis < $1.value.updatedAtMillis }.prefix(entries.count - 256)
      for (id, _) in overflow { entries.removeValue(forKey: id) }
    }
    if let data = try? JSONEncoder().encode(entries) {
      GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: key, secrets: secrets)
    }
    NotificationCenter.default.post(name: Self.changed, object: nil)
  }
}
