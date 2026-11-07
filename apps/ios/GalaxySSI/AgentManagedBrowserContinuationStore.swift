import Foundation

final class AgentManagedBrowserContinuationStore {
  static let changed = Notification.Name("galaxyssi.managed-browser.changed")
  enum Failure: Error, Equatable {
    case unavailable, scopeChanged, legacyLoop, busy, invalidInput, notReady, staleTicket
  }

  enum Control: String, Codable { case run, pause, stop, unavailable }
  enum Mode: Equatable { case initial, recovery }

  struct RunScope: Codable, Equatable {
    let profileID: String
    let runID: String
    let teamID: String
    let conversationID: String
    let turnID: String
    let hostContextDigest: String

    init(profileID: String, team: AgentTeamExecutionSnapshot, hostContextDigest: String) {
      self.profileID = profileID
      runID = team.supervisorRunId
      teamID = team.teamId
      conversationID = team.conversationId
      turnID = team.taskId
      self.hostContextDigest = hostContextDigest
    }

    init(_ binding: AgentManagedBrowserDispatchBinding) {
      profileID = binding.profileID
      runID = binding.owner.runId
      teamID = binding.teamID
      conversationID = binding.owner.conversationId
      turnID = binding.owner.turnId
      hostContextDigest = binding.hostContextDigest
    }

    var key: String { AgentModelLoopRecoveryIdentity.sha256(self) }
  }

  private struct Intent: Codable {
    let scope: RunScope
    let control: Control
  }

  struct Lease {
    fileprivate let key: String
    fileprivate let nonce: UUID
  }

  enum Work {
    case continueLoop(AgentManagedBrowserLoopInput)
    case settleCancellation
    case deliver(AgentManagedBrowserMemberReceipt)
    case alreadyDelivered
  }

  private struct Record: Codable {
    let binding: AgentManagedBrowserDispatchBinding
    let inputDigest: String
    var input: AgentManagedBrowserLoopInput?
    var handoffs: [String: AgentManagedBrowserHandoff] = [:]
    var activeCallID: String?
    var receipt: AgentManagedBrowserMemberReceipt?
    var delivered = false
    var deliveredReceiptID: UUID?
    var browserCookies: [String: [AgentManagedBrowserCookie]]? = nil
    var ownerStopped: Bool? = nil
  }

  private static let lock = NSLock()
  private static var leases: [String: UUID] = [:]
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let namespace: String

  init(defaults: UserDefaults = .standard, secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
       namespace: String = "galaxyssi.agent.managed-browser.v1") {
    self.defaults = defaults
    self.secrets = secrets
    self.namespace = namespace
  }

  @discardableResult
  func writeControl(_ control: Control, scope: RunScope) throws -> Bool {
    try locked {
      guard control != .unavailable else { throw Failure.invalidInput }
      let previous = try readControl(scope)
      guard previous != .stop || control == .stop else { return false }
      if previous == control { return true }
      let data = try JSONEncoder().encode(Intent(scope: scope, control: control))
      guard GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: controlKey(scope),
        keyMaterialKey: namespace, secrets: secrets) else { throw Failure.unavailable }
      return true
    }
  }

  func control(scope: RunScope) throws -> Control? {
    try locked { try readControl(scope) }
  }

  private func controlKey(_ scope: RunScope) -> String { namespace + ".control." + scope.key }

  private func readControl(_ scope: RunScope) throws -> Control? {
    let key = controlKey(scope)
    guard GalaxySSIEncryptedUserDefaultsStore.contains(defaults: defaults, key: key) else { return nil }
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key,
      keyMaterialKey: namespace, secrets: secrets),
      let intent = try? JSONDecoder().decode(Intent.self, from: data),
      intent.scope == scope, intent.control != .unavailable else { throw Failure.unavailable }
    return intent.control
  }

  func enroll(_ binding: AgentManagedBrowserDispatchBinding, input: AgentManagedBrowserLoopInput,
              legacyLoopExists: Bool) throws {
    try locked {
      guard input.isValid else { throw Failure.invalidInput }
      let digest = AgentModelLoopRecoveryIdentity.sha256(input)
      if let current = try read(binding.key) {
        guard current.binding == binding, current.inputDigest == digest else { throw Failure.scopeChanged }
        if !current.delivered { try track(binding) }
        return
      }
      guard try readControl(RunScope(binding)) != .stop else { throw Failure.notReady }
      guard !legacyLoopExists else { throw Failure.legacyLoop }
      try save(Record(binding: binding, inputDigest: digest, input: input))
      try track(binding)
    }
  }

  func withLease<T>(binding: AgentManagedBrowserDispatchBinding, mode: Mode, control: Control,
                    _ body: (Lease, Work) async throws -> T) async throws -> T {
    let (lease, work) = try locked {
      guard Self.leases[storageKey(binding.key)] == nil else { throw Failure.busy }
      var record = try owned(binding)
      guard control != .unavailable else { throw Failure.unavailable }
      let savedControl = try readControl(RunScope(binding))
      let effective = control == .stop || savedControl == .stop ? Control.stop :
        (savedControl == .pause ? .pause : control)
      if effective == .stop { try retire(&record) }
      let work = try self.work(for: record, mode: mode, control: effective)
      let lease = Lease(key: binding.key, nonce: UUID())
      Self.leases[storageKey(binding.key)] = lease.nonce
      return (lease, work)
    }
    defer {
      locked {
        if Self.leases[storageKey(lease.key)] == lease.nonce {
          Self.leases.removeValue(forKey: storageKey(lease.key))
        }
      }
    }
    return try await body(lease, work)
  }

  func requestControl(lease: Lease, binding: AgentManagedBrowserDispatchBinding, callID: String,
                      invocationID: String, address: String) throws -> AgentManagedBrowserHandoff {
    try locked {
      try requireLease(lease, binding: binding)
      var record = try owned(binding)
      try requireInteractive(record)
      guard record.receipt == nil, !callID.isBlank, callID.utf8.count <= 256,
            !invocationID.isBlank, invocationID.utf8.count <= 256,
            address.utf8.count <= 4_096, AgentManagedBrowserHandoff.url(address) != nil else { throw Failure.invalidInput }
      if let previous = record.handoffs[callID] {
        guard previous.invocationID == invocationID, previous.address == address else { throw Failure.scopeChanged }
        return previous
      }
      guard record.handoffs.count < 32,
            !record.handoffs.values.contains(where: { $0.state == .awaitingUser || $0.state == .stopped }) else {
        throw Failure.notReady
      }
      let ticket = AgentManagedBrowserHandoff.Ticket(dispatchKey: binding.key, callID: callID, generation: UUID())
      let handoff = AgentManagedBrowserHandoff(ticket: ticket, address: address, invocationID: invocationID,
                                               state: .awaitingUser, observation: nil)
      record.handoffs[callID] = handoff
      record.activeCallID = callID
      try save(record)
      return handoff
    }
  }

  func handoff(_ ticket: AgentManagedBrowserHandoff.Ticket,
               binding: AgentManagedBrowserDispatchBinding) throws -> AgentManagedBrowserHandoff {
    try locked { try exact(ticket, in: owned(binding)) }
  }

  func savedRequest(lease: Lease, binding: AgentManagedBrowserDispatchBinding, callID: String,
                    invocationID: String, address: String) throws -> AgentManagedBrowserHandoff? {
    try locked {
      try requireLease(lease, binding: binding)
      guard let handoff = try owned(binding).handoffs[callID] else { return nil }
      guard handoff.invocationID == invocationID, handoff.address == address else { throw Failure.scopeChanged }
      return handoff
    }
  }

  func awaitingHandoff(binding: AgentManagedBrowserDispatchBinding) throws -> AgentManagedBrowserHandoff? {
    try locked {
      let record = try owned(binding)
      try requireInteractive(record)
      guard record.receipt == nil, let callID = record.activeCallID,
            let handoff = record.handoffs[callID], handoff.state == .awaitingUser else { return nil }
      return handoff
    }
  }

  func cookies(_ ticket: AgentManagedBrowserHandoff.Ticket, binding: AgentManagedBrowserDispatchBinding) throws -> [HTTPCookie] {
    try locked {
      let record = try owned(binding)
      let host = try activeBrowserHost(ticket, record: record)
      return (record.browserCookies?[host] ?? []).compactMap { $0.restore(host: host) }
    }
  }

  func saveCookies(_ cookies: [HTTPCookie], ticket: AgentManagedBrowserHandoff.Ticket,
                   binding: AgentManagedBrowserDispatchBinding) throws {
    try locked {
      var record = try owned(binding)
      let host = try activeBrowserHost(ticket, record: record)
      var table = record.browserCookies ?? [:]
      guard table[host] != nil || table.count < 4 else { return }
      let selected = cookies.compactMap { AgentManagedBrowserCookie($0, host: host) }.prefix(32)
      let incoming = Array(selected)
      guard table[host] != incoming else { return }
      table[host] = incoming
      record.browserCookies = table
      try save(record)
    }
  }

  private func activeBrowserHost(_ ticket: AgentManagedBrowserHandoff.Ticket, record: Record) throws -> String {
    try requireInteractive(record)
    let handoff = try exact(ticket, in: record)
    guard record.receipt == nil, record.activeCallID == ticket.callID, handoff.state == .awaitingUser,
          let host = AgentManagedBrowserHandoff.url(handoff.address)?.host?.lowercased() else { throw Failure.staleTicket }
    return host
  }

  func pendingBindings(profileID: String, runID: String? = nil) -> [AgentManagedBrowserDispatchBinding] {
    locked {
      let prefix = namespace + "."
      return GalaxySSIEncryptedUserDefaultsStore.storedKeys(defaults: defaults, prefix: prefix).sorted().compactMap {
        let key = String($0.dropFirst(prefix.count))
        guard key.count == 64 else { return nil }
        guard let record = try? read(key), !record.delivered, record.binding.profileID == profileID,
              runID == nil || record.binding.owner.runId == runID else { return nil }
        return record.binding
      }
    }
  }

  func indexedBindings(scope: RunScope) -> [AgentManagedBrowserDispatchBinding] {
    locked {
      let prefix = indexPrefix(scope)
      let keys = GalaxySSIEncryptedUserDefaultsStore.storedKeys(defaults: defaults, prefix: prefix).sorted()
      var result: [AgentManagedBrowserDispatchBinding] = []
      for offset in stride(from: 0, to: keys.count, by: 64) {
        for key in keys[offset..<min(offset + 64, keys.count)] {
          guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key,
            keyMaterialKey: namespace, secrets: secrets),
            let hint = try? JSONDecoder().decode(AgentManagedBrowserDispatchBinding.self, from: data),
            key == prefix + hint.key, RunScope(hint) == scope,
            let record = try? owned(hint), !record.delivered else { continue }
          result.append(record.binding)
        }
      }
      return result
    }
  }

  func backfillWakeIndex(_ binding: AgentManagedBrowserDispatchBinding) throws {
    try locked {
      guard try !owned(binding).delivered else { return }
      try track(binding)
    }
  }

  private func indexPrefix(_ scope: RunScope) -> String { namespace + ".wake." + scope.key + "." }

  private func track(_ binding: AgentManagedBrowserDispatchBinding) throws {
    let key = indexPrefix(RunScope(binding)) + binding.key
    let data = try JSONEncoder().encode(binding)
    guard GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: key,
      keyMaterialKey: namespace, secrets: secrets) else { throw Failure.unavailable }
  }

  func prepareTeamDispatch(_ input: AgentManagedBrowserTeamDispatch) throws {
    try locked {
      let key = teamStorageKey(input.key)
      if let existing = try readTeamDispatch(key) {
        guard existing == input else { throw Failure.scopeChanged }
        return
      }
      let data = try JSONEncoder().encode(input)
      guard data.count <= 512 * 1_024,
            GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: key,
              keyMaterialKey: namespace, secrets: secrets) else { throw Failure.unavailable }
    }
  }

  func pendingTeamDispatches(profileID: String) -> [AgentManagedBrowserTeamDispatch] {
    locked {
      GalaxySSIEncryptedUserDefaultsStore.storedKeys(defaults: defaults, prefix: teamStorageKey("")).sorted()
        .compactMap { key in
          guard let input = try? readTeamDispatch(key), input.profileID == profileID else { return nil }
          return input
        }
    }
  }

  func finishTeamDispatch(_ input: AgentManagedBrowserTeamDispatch) throws {
    try locked {
      let key = teamStorageKey(input.key)
      guard let stored = try readTeamDispatch(key) else { return }
      guard stored == input else { throw Failure.scopeChanged }
      GalaxySSIEncryptedUserDefaultsStore.remove(defaults: defaults, key: key)
    }
  }

  private func teamStorageKey(_ key: String) -> String { namespace + ".team." + key }

  private func readTeamDispatch(_ key: String) throws -> AgentManagedBrowserTeamDispatch? {
    guard GalaxySSIEncryptedUserDefaultsStore.contains(defaults: defaults, key: key) else { return nil }
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key,
      keyMaterialKey: namespace, secrets: secrets),
      let input = try? JSONDecoder().decode(AgentManagedBrowserTeamDispatch.self, from: data),
      teamStorageKey(input.key) == key else { throw Failure.unavailable }
    return input
  }

  func returnControl(_ ticket: AgentManagedBrowserHandoff.Ticket, binding: AgentManagedBrowserDispatchBinding,
                     observation: AgentManagedBrowserHandoff.Observation) throws {
    try locked {
      var record = try owned(binding)
      try requireInteractive(record)
      var handoff = try exact(ticket, in: record)
      guard record.receipt == nil, observation.isValid else { throw Failure.invalidInput }
      guard record.activeCallID == ticket.callID else { throw Failure.staleTicket }
      if handoff.state == .returned, handoff.observation == observation { return }
      guard handoff.state == .awaitingUser else { throw Failure.staleTicket }
      handoff.state = .returned
      handoff.observation = observation
      record.handoffs[ticket.callID] = handoff
      try save(record)
    }
  }

  func stop(_ ticket: AgentManagedBrowserHandoff.Ticket, binding: AgentManagedBrowserDispatchBinding) throws {
    try locked {
      var record = try owned(binding)
      _ = try exact(ticket, in: record)
      guard record.receipt == nil, record.activeCallID == ticket.callID else { throw Failure.staleTicket }
      try retire(&record)
    }
  }

  func retireStoppedBinding(_ binding: AgentManagedBrowserDispatchBinding) throws {
    try locked {
      guard try readControl(RunScope(binding)) == .stop else { throw Failure.notReady }
      var record = try owned(binding)
      try retire(&record)
    }
  }

  private func retire(_ record: inout Record) throws {
    guard !record.delivered, record.receipt == nil, record.ownerStopped != true else { return }
    record.ownerStopped = true
    if let call = record.activeCallID, var handoff = record.handoffs[call] {
      handoff.state = .stopped
      handoff.observation = nil
      record.handoffs[call] = handoff
    }
    record.browserCookies = nil
    try save(record)
  }

  private func requireInteractive(_ record: Record) throws {
    let intent = try readControl(RunScope(record.binding))
    guard record.ownerStopped != true, intent != .stop, intent != .pause else { throw Failure.notReady }
  }

  func commit(_ state: AgentManagedBrowserMemberReceipt.State, text: String, lease: Lease,
              binding: AgentManagedBrowserDispatchBinding) throws -> AgentManagedBrowserMemberReceipt {
    try locked {
      try requireLease(lease, binding: binding)
      var record = try owned(binding)
      if let receipt = record.receipt {
        guard receipt.state == state, receipt.text == text else { throw Failure.scopeChanged }
        return receipt
      }
      if state != .cancelled { try requireInteractive(record) }
      guard text.utf8.count <= 256 * 1_024,
            state == .cancelled || (!text.isBlank &&
              record.handoffs.values.allSatisfy { $0.state == .returned }) else { throw Failure.notReady }
      let receipt = AgentManagedBrowserMemberReceipt(id: UUID(), state: state, text: text)
      record.receipt = receipt
      try save(record)
      return receipt
    }
  }

  func acknowledge(_ receipt: AgentManagedBrowserMemberReceipt, lease: Lease,
                   binding: AgentManagedBrowserDispatchBinding) throws {
    try locked {
      try requireLease(lease, binding: binding)
      var record = try owned(binding)
      if record.delivered {
        guard record.deliveredReceiptID == receipt.id else { throw Failure.staleTicket }
        return
      }
      guard record.receipt == receipt else { throw Failure.staleTicket }
      record.delivered = true
      record.deliveredReceiptID = receipt.id
      record.receipt = nil
      record.input = nil
      record.handoffs.removeAll()
      record.activeCallID = nil
      record.browserCookies = nil
      try save(record)
      GalaxySSIEncryptedUserDefaultsStore.remove(defaults: defaults, key: indexPrefix(RunScope(binding)) + binding.key)
    }
  }

  private func work(for record: Record, mode: Mode, control: Control) throws -> Work {
    guard control != .unavailable else { throw Failure.unavailable }
    if record.delivered { return .alreadyDelivered }
    guard control != .pause else { throw Failure.notReady }
    if let receipt = record.receipt { return .deliver(receipt) }
    if control == .stop || record.ownerStopped == true || record.handoffs.values.contains(where: { $0.state == .stopped }) {
      return .settleCancellation
    }
    if mode == .recovery {
      guard record.handoffs.values.allSatisfy({ $0.state == .returned }) else { throw Failure.notReady }
    } else {
      guard record.handoffs.isEmpty else { throw Failure.notReady }
    }
    guard let input = record.input, input.isValid else { throw Failure.unavailable }
    return .continueLoop(input)
  }

  private func exact(_ ticket: AgentManagedBrowserHandoff.Ticket, in record: Record) throws -> AgentManagedBrowserHandoff {
    guard ticket.dispatchKey == record.binding.key, let handoff = record.handoffs[ticket.callID],
          handoff.ticket == ticket else { throw Failure.staleTicket }
    return handoff
  }

  private func requireLease(_ lease: Lease, binding: AgentManagedBrowserDispatchBinding) throws {
    guard lease.key == binding.key, Self.leases[storageKey(lease.key)] == lease.nonce else { throw Failure.busy }
  }

  private func owned(_ binding: AgentManagedBrowserDispatchBinding) throws -> Record {
    guard let record = try read(binding.key) else { throw Failure.unavailable }
    guard record.binding == binding else { throw Failure.scopeChanged }
    return record
  }

  private func storageKey(_ key: String) -> String { namespace + "." + key }

  private func read(_ key: String) throws -> Record? {
    let storageKey = storageKey(key)
    guard GalaxySSIEncryptedUserDefaultsStore.contains(defaults: defaults, key: storageKey) else { return nil }
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: storageKey,
      keyMaterialKey: namespace, secrets: secrets),
      let record = try? JSONDecoder().decode(Record.self, from: data), record.binding.key == key else {
      throw Failure.unavailable
    }
    return record
  }

  private func save(_ record: Record) throws {
    let data = try JSONEncoder().encode(record)
    guard GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: storageKey(record.binding.key),
      keyMaterialKey: namespace, secrets: secrets) else { throw Failure.unavailable }
  }

  private func locked<T>(_ body: () throws -> T) rethrows -> T {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    return try body()
  }
}
