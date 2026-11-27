import Foundation

final class AgentTurnReceiptStore {
  struct Key: Hashable {
    let owner: String, conversation: String, turn: String
    var valid: Bool { [owner, conversation, turn].allSatisfy { !$0.isBlank && $0.utf8.count <= 512 } }
    var prefix: String { AgentTurnReceiptStore.prefix + AgentTurnReceiptEvidence.hash(owner) + "." + AgentTurnReceiptEvidence.hash(conversation) + "." }
    var row: String { prefix + AgentTurnReceiptEvidence.hash(turn) }
  }
  static let prefix = "galaxyssi.turn-receipt."
  static let materialKey = "galaxyssi.turn-receipts.material"
  private struct Live { let started: UInt64; var painted = false }
  private let lock = NSRecursiveLock()
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private var live: [Key: Live] = [:]
  private var order: [Key] = []

  init(defaults: UserDefaults, secrets: GalaxySSISecretStore) { self.defaults = defaults; self.secrets = secrets }
  private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
  func read(_ key: Key) -> AgentTurnReceipt? {
    locked {
      guard key.valid, let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key.row,
        keyMaterialKey: Self.materialKey, secrets: secrets), data.count <= 16_384 else { return nil }
      return try? JSONDecoder().decode(AgentTurnReceipt.self, from: data)
    }
  }
  @discardableResult private func write(_ row: AgentTurnReceipt, _ key: Key) -> Bool {
    guard let data = try? JSONEncoder().encode(row), data.count <= 16_384 else { return false }
    return GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: key.row,
      keyMaterialKey: Self.materialKey, secrets: secrets)
  }
  private func change(_ key: Key, _ body: (inout AgentTurnReceipt) -> Void) {
    locked {
      guard var row = read(key) else { return }
      let previous = row; body(&row)
      if row != previous { _ = write(row, key) }
    }
  }
  func begin(_ key: Key, choice: AgentModelSelection, wall: Int64 = AgentControlPlaneClock.nowMillis(),
             uptime: UInt64 = DispatchTime.now().uptimeNanoseconds) {
    locked {
      guard key.valid, wall > 0, !GalaxySSIEncryptedUserDefaultsStore.contains(defaults: defaults, key: key.row),
            !GalaxySSIEncryptedUserDefaultsStore.contains(defaults: defaults, key: key.prefix + "deleted") else { return }
      var row = AgentTurnReceipt(); row.sent = wall; row.mode = choice.mode.rawValue
      row.requested = AgentTurnReceiptEvidence.identifier(choice.modelId)
      row.effort = AgentTurnReceiptEvidence.identifier(choice.reasoningEffort.rawValue)
      guard write(row, key) else { return }
      if order.count >= 256 { live.removeValue(forKey: order.removeFirst()) }
      order.append(key); live[key] = Live(started: uptime)
    }
  }
  func visible(_ key: Key, wall: Int64 = AgentControlPlaneClock.nowMillis(), uptime: UInt64 = DispatchTime.now().uptimeNanoseconds) {
    locked {
      guard var observation = live[key], !observation.painted, uptime >= observation.started, wall > 0,
            let elapsed = Int64(exactly: (uptime - observation.started) / 1_000_000) else { return }
      observation.painted = true; live[key] = observation
      change(key) { if $0.body == nil { $0.body = wall; $0.bodyMillis = elapsed } }
    }
  }
  func outbound(_ key: Key, task: String, model: String, effort: String) {
    guard !task.isBlank else { return }
    change(key) {
      let digest = AgentTurnReceiptEvidence.hash(task)
      if $0.taskSHA != digest { $0.clearSubmission(); $0.generation = nil; $0.taskSHA = digest }
      $0.wire = AgentTurnReceiptEvidence.identifier(model); $0.wireEffort = AgentTurnReceiptEvidence.identifier(effort)
    }
  }
  func recordInputOrigin(_ key: Key, voice: Bool) {
    change(key) { if $0.voiceInput == nil { $0.voiceInput = voice } }
  }
  func authenticated(_ key: Key, payload: [String: Any], wall: Int64 = AgentControlPlaneClock.nowMillis()) {
    guard let evidence = AgentTurnReceiptEvidence.desktop(payload), let task = payload["task_id"] as? String,
          payload["conversation_id"] as? String == key.conversation, payload["turn_id"] as? String == key.turn else { return }
    change(key) {
      guard $0.taskSHA == AgentTurnReceiptEvidence.hash(task) else { return }
      if evidence.generation > ($0.generation ?? 0) { $0.clearSubmission(); $0.generation = evidence.generation }
      guard $0.generation == evidence.generation else { return }
      if $0.desktopReceived == nil { $0.desktopReceived = evidence.received }
      if evidence.attempt > 0, evidence.attempt >= ($0.attempt ?? 0) {
        $0.attempt = evidence.attempt; $0.provider = evidence.provider
        $0.submitted = evidence.model; $0.submittedEffort = evidence.effort
      }
      if evidence.terminal, $0.resultAt == nil, wall > 0 { $0.resultAt = wall }
    }
  }
  func cloudStarted(_ key: Key, model: String) -> String {
    let attempt = UUID().uuidString
    change(key) { $0.cloudAttempt = attempt; $0.cloudRequested = AgentTurnReceiptEvidence.identifier(model); $0.cloudActual = nil; $0.cloudEffort = nil }
    return attempt
  }
  func cloudResponse(_ key: Key, attempt: String, actual: String?, effort: String? = nil) {
    change(key) {
      guard $0.cloudAttempt == attempt else { return }
      $0.cloudActual = AgentTurnReceiptEvidence.identifier(actual); $0.cloudEffort = AgentTurnReceiptEvidence.identifier(effort)
    }
  }
  func localModel(_ key: Key, profile: String) { change(key) { $0.localProfile = AgentTurnReceiptEvidence.identifier(profile) } }
  func toolFinished(_ key: Key, context: AgentNativeToolInvocationContext, tool: String, result: AgentNativeToolResult) {
    locked {
      guard live[key] != nil, context.conversationId == key.conversation, context.turnId == key.turn,
            result.isSuccess, result.receipt.status == result.status, !result.receipt.replayed,
            result.provenance.toolId == tool, result.receipt.invocationId == context.invocationId else { return }
      switch result.provenance.location {
      case .phone, .androidSystem, .accessibilityService: change(key) { $0.phoneExecuted = true }
      case .desktop: change(key) { $0.desktopExecuted = true }
      default: break
      }
    }
  }
  func invalidateLive() { locked { live.removeAll(); order.removeAll() } }
  func shouldObserve(_ key: Key) -> Bool { locked { live[key].map { !$0.painted } ?? false } }
  func delete(owner: String, conversation: String) {
    locked {
      let key = Key(owner: owner, conversation: conversation, turn: "deleted")
      guard key.valid else { return }
      live = live.filter { $0.key.owner != owner || $0.key.conversation != conversation }
      order.removeAll { $0.owner == owner && $0.conversation == conversation }
      let rows = GalaxySSIEncryptedUserDefaultsStore.storedKeys(defaults: defaults, prefix: key.prefix)
      guard GalaxySSIEncryptedUserDefaultsStore.write(Data("true".utf8), defaults: defaults,
        key: key.prefix + "deleted", keyMaterialKey: Self.materialKey, secrets: secrets) else { return }
      for row in rows where row != key.prefix + "deleted" { GalaxySSIEncryptedUserDefaultsStore.remove(defaults: defaults, key: row) }
    }
  }
  func clear() {
    locked {
      invalidateLive()
      for key in GalaxySSIEncryptedUserDefaultsStore.storedKeys(defaults: defaults, prefix: Self.prefix) {
        GalaxySSIEncryptedUserDefaultsStore.remove(defaults: defaults, key: key)
      }
      GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: Self.materialKey, secrets: secrets)
    }
  }
}

extension GalaxySSIStore {
  func turnReceiptKey(conversation: String, turn: String) -> AgentTurnReceiptStore.Key? {
    guard canReadAgentTranscript else { return nil }
    let key = AgentTurnReceiptStore.Key(owner: profile.identityFingerprint, conversation: conversation, turn: turn)
    return key.valid ? key : nil
  }
}
