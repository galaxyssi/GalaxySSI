import CryptoKit
import Foundation

struct AgentModelLoopScope: Codable, Equatable, Hashable {
  var sessionId: String
  var conversationId: String
  var turnId: String
  var taskId: String
  var workspaceId: String
  var callerId: String
  var loopId: String

  init(request: AgentModelToolLoopRequest) {
    precondition(!request.loopId.isBlank, "A durable model loop requires a stable loop id")
    sessionId = request.sessionId
    conversationId = request.conversationId
    turnId = request.turnId
    taskId = request.taskId
    workspaceId = request.workspaceId
    callerId = request.callerId
    loopId = request.loopId
  }

  var digest: String {
    AgentModelLoopCodec.sha256(self)
  }

  enum CodingKeys: String, CodingKey {
    case sessionId = "session_id"
    case conversationId = "conversation_id"
    case turnId = "turn_id"
    case taskId = "task_id"
    case workspaceId = "workspace_id"
    case callerId = "caller_id"
    case loopId = "loop_id"
  }
}

struct AgentModelLoopRecoveryError: Error, LocalizedError, Equatable {
  var code: String

  var errorDescription: String? { code }
}

enum AgentModelLoopRecoveryIdentity {
  static func sha256<T: Encodable>(_ value: T) -> String {
    AgentModelLoopCodec.sha256(value)
  }
}

protocol AgentModelLoopRecords: AnyObject {
  func read(_ operation: String) throws -> Data?
  func write(_ operation: String, data: Data) throws
}

protocol AgentModelLoopJournal: AnyObject {
  func hasRecords(scope: AgentModelLoopScope) throws -> Bool
  func withLease<T>(
    scope: AgentModelLoopScope,
    _ operation: (AgentModelLoopRecords) async throws -> T
  ) async throws -> T
}

final class InMemoryAgentModelLoopJournal: AgentModelLoopJournal {
  private let lock = NSLock()
  private var activeScopes: Set<AgentModelLoopScope> = []
  private var records: [AgentModelLoopScope: [String: Data]] = [:]

  func hasRecords(scope: AgentModelLoopScope) throws -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return records[scope]?["initial"] != nil
  }

  func withLease<T>(
    scope: AgentModelLoopScope,
    _ operation: (AgentModelLoopRecords) async throws -> T
  ) async throws -> T {
    guard acquire(scope) else { throw AgentModelLoopRecoveryError(code: "model_loop_busy") }
    defer { release(scope) }
    return try await operation(ScopedRecords(owner: self, scope: scope))
  }

  private func acquire(_ scope: AgentModelLoopScope) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return activeScopes.insert(scope).inserted
  }

  private func release(_ scope: AgentModelLoopScope) {
    lock.lock()
    activeScopes.remove(scope)
    lock.unlock()
  }

  private final class ScopedRecords: AgentModelLoopRecords {
    private unowned let owner: InMemoryAgentModelLoopJournal
    private let scope: AgentModelLoopScope

    init(owner: InMemoryAgentModelLoopJournal, scope: AgentModelLoopScope) {
      self.owner = owner
      self.scope = scope
    }

    func read(_ operation: String) throws -> Data? {
      owner.lock.lock()
      defer { owner.lock.unlock() }
      return owner.records[scope]?[operation]
    }

    func write(_ operation: String, data: Data) throws {
      owner.lock.lock()
      defer { owner.lock.unlock() }
      if let previous = owner.records[scope]?[operation] {
        guard previous == data else {
          throw AgentModelLoopRecoveryError(code: "model_loop_record_changed")
        }
        return
      }
      owner.records[scope, default: [:]][operation] = data
    }
  }
}

final class EncryptedAgentModelLoopJournal: AgentModelLoopJournal {
  private struct Store: Codable {
    var recordsByScope: [String: [String: Data]] = [:]
  }

  private static let processLock = NSLock()
  private static var activeScopes: Set<String> = []

  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let storageKey: String

  init(
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    storageKey: String = "galaxyssi.agent.model-loop-journal.v1"
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.storageKey = storageKey
  }

  func hasRecords(scope: AgentModelLoopScope) throws -> Bool {
    try load().recordsByScope[scope.digest]?["initial"] != nil
  }

  func withLease<T>(
    scope: AgentModelLoopScope,
    _ operation: (AgentModelLoopRecords) async throws -> T
  ) async throws -> T {
    let leaseKey = storageKey + ":" + scope.digest
    guard Self.acquire(leaseKey) else { throw AgentModelLoopRecoveryError(code: "model_loop_busy") }
    defer { Self.release(leaseKey) }
    return try await operation(ScopedRecords(owner: self, scopeDigest: scope.digest))
  }

  private static func acquire(_ scope: String) -> Bool {
    processLock.lock()
    defer { processLock.unlock() }
    return activeScopes.insert(scope).inserted
  }

  private static func release(_ scope: String) {
    processLock.lock()
    activeScopes.remove(scope)
    processLock.unlock()
  }

  private final class ScopedRecords: AgentModelLoopRecords {
    private unowned let owner: EncryptedAgentModelLoopJournal
    private let scopeDigest: String

    init(owner: EncryptedAgentModelLoopJournal, scopeDigest: String) {
      self.owner = owner
      self.scopeDigest = scopeDigest
    }

    func read(_ operation: String) throws -> Data? {
      EncryptedAgentModelLoopJournal.processLock.lock()
      defer { EncryptedAgentModelLoopJournal.processLock.unlock() }
      return try owner.load().recordsByScope[scopeDigest]?[operation]
    }

    func write(_ operation: String, data: Data) throws {
      EncryptedAgentModelLoopJournal.processLock.lock()
      defer { EncryptedAgentModelLoopJournal.processLock.unlock() }
      var store = try owner.load()
      if let previous = store.recordsByScope[scopeDigest]?[operation] {
        guard previous == data else {
          throw AgentModelLoopRecoveryError(code: "model_loop_record_changed")
        }
        return
      }
      store.recordsByScope[scopeDigest, default: [:]][operation] = data
      try owner.persist(store)
    }
  }

  private func load() throws -> Store {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: storageKey,
      secrets: secrets
    ) else {
      if defaults.object(forKey: "\(storageKey).encrypted.v1") != nil {
        throw AgentModelLoopRecoveryError(code: "model_loop_record_unreadable")
      }
      return Store()
    }
    guard let store = try? JSONDecoder().decode(Store.self, from: data) else {
      throw AgentModelLoopRecoveryError(code: "model_loop_record_unreadable")
    }
    return store
  }

  private func persist(_ store: Store) throws {
    guard let data = try? JSONEncoder().encode(store),
          GalaxySSIEncryptedUserDefaultsStore.write(
            data,
            defaults: defaults,
            key: storageKey,
            secrets: secrets
          ) else {
      throw AgentModelLoopRecoveryError(code: "model_loop_journal_unavailable")
    }
  }
}

final class AgentModelLoopCheckpoint {
  struct Invocation {
    var operation: String
    var bindingSha256: String
    var invocationId: String
    var result: AgentNativeToolResult?
    var eventSequence: Int64
  }

  private struct InitialBinding: Codable, Equatable {
    var inputIdentity: String
    var manifestSha256: String
    var permissions: [String]
    var consents: [String]
    var budget: AgentModelToolLoopBudget
  }

  private struct InitialRecord: Codable {
    var binding: InitialBinding
    var messages: [AgentModelMessage]
  }

  private struct ModelBinding: Codable, Equatable {
    var round: Int
    var messages: [AgentModelMessage]
    var manifestSha256: String
  }

  private struct ModelRecord: Codable {
    var binding: ModelBinding
    var response: AgentModelResponse
  }

  private struct InvocationBinding: Codable {
    var round: Int
    var call: AgentModelToolCall
    var toolVersion: String
    var attempt: Int
    var idempotencyKey: String?
  }

  private struct InvocationOperation: Codable {
    var round: Int
    var callId: String
    var attempt: Int
  }

  private struct InvocationStart: Codable {
    var bindingSha256: String
    var invocationId: String
  }

  private struct InvocationResult: Codable {
    var bindingSha256: String
    var result: AgentNativeToolResult
    var eventSequence: Int64
  }

  private struct CancellationRecord: Codable {
    var cancelled: Bool
  }

  private let records: AgentModelLoopRecords
  private(set) var restored = false
  private(set) var failure: AgentModelLoopRecoveryError?

  init(records: AgentModelLoopRecords) {
    self.records = records
  }

  var cancelled: Bool {
    decode(CancellationRecord.self, operation: "cancelled")?.cancelled == true
  }

  func markCancelled() {
    write(CancellationRecord(cancelled: true), operation: "cancelled")
  }

  func initial(request: AgentModelToolLoopRequest, manifestSha256: String) throws -> [AgentModelMessage] {
    let binding = InitialBinding(
      inputIdentity: request.recoveryInputIdentity.ifBlank(AgentModelLoopCodec.sha256(request.messages)),
      manifestSha256: manifestSha256,
      permissions: request.grantedPermissions.sorted(),
      consents: request.grantedConsents.sorted(),
      budget: request.budget
    )
    if let existing = try records.read("initial") {
      let record = try AgentModelLoopCodec.decode(InitialRecord.self, data: existing)
      guard record.binding == binding else {
        throw AgentModelLoopRecoveryError(code: "model_loop_checkpoint_binding_changed")
      }
      restored = true
      return record.messages
    }
    try records.write("initial", data: AgentModelLoopCodec.encode(InitialRecord(
      binding: binding,
      messages: request.messages
    )))
    return request.messages
  }

  func response(_ request: AgentModelRequest) -> AgentModelResponse? {
    let operation = "model:\(request.round)"
    guard let record = decode(ModelRecord.self, operation: operation) else { return nil }
    guard record.binding == modelBinding(request) else {
      fail("model_loop_checkpoint_binding_changed")
      return nil
    }
    return record.response
  }

  func recordResponse(_ response: AgentModelResponse, request: AgentModelRequest) {
    write(ModelRecord(binding: modelBinding(request), response: response), operation: "model:\(request.round)")
  }

  func invocation(
    round: Int,
    call: AgentModelToolCall,
    toolVersion: String,
    attempt: Int,
    idempotencyKey: String?,
    makeInvocationId: () -> String
  ) -> Invocation? {
    let operation = "tool:" + AgentModelLoopCodec.sha256(InvocationOperation(
      round: round,
      callId: call.callId,
      attempt: attempt
    ))
    let bindingSha256 = AgentModelLoopCodec.sha256(InvocationBinding(
      round: round,
      call: call,
      toolVersion: toolVersion,
      attempt: attempt,
      idempotencyKey: idempotencyKey
    ))
    let startOperation = operation + ":start"
    let start: InvocationStart
    if let retained = decode(InvocationStart.self, operation: startOperation) {
      guard retained.bindingSha256 == bindingSha256 else {
        fail("model_loop_checkpoint_binding_changed")
        return nil
      }
      start = retained
    } else {
      guard failure == nil else { return nil }
      start = InvocationStart(bindingSha256: bindingSha256, invocationId: makeInvocationId())
      write(start, operation: startOperation)
      guard failure == nil else { return nil }
    }
    let result = decode(InvocationResult.self, operation: operation + ":result")
    if let result {
      guard result.bindingSha256 == bindingSha256,
            result.result.receipt.invocationId == start.invocationId else {
        fail("model_loop_invocation_changed")
        return nil
      }
    }
    return Invocation(
      operation: operation,
      bindingSha256: bindingSha256,
      invocationId: start.invocationId,
      result: result?.result,
      eventSequence: result?.eventSequence ?? 0
    )
  }

  func recordResult(_ result: AgentNativeToolResult, invocation: Invocation, eventSequence: Int64) {
    guard result.receipt.invocationId == invocation.invocationId else {
      fail("model_loop_invocation_changed")
      return
    }
    write(InvocationResult(
      bindingSha256: invocation.bindingSha256,
      result: result,
      eventSequence: eventSequence
    ), operation: invocation.operation + ":result")
  }

  private func modelBinding(_ request: AgentModelRequest) -> ModelBinding {
    ModelBinding(
      round: request.round,
      messages: request.messages,
      manifestSha256: request.toolManifestSha256
    )
  }

  private func decode<T: Decodable>(_ type: T.Type, operation: String) -> T? {
    guard failure == nil else { return nil }
    do {
      guard let data = try records.read(operation) else { return nil }
      return try AgentModelLoopCodec.decode(type, data: data)
    } catch let error as AgentModelLoopRecoveryError {
      failure = error
    } catch {
      fail("model_loop_record_invalid")
    }
    return nil
  }

  private func write<T: Encodable>(_ value: T, operation: String) {
    guard failure == nil else { return }
    do {
      try records.write(operation, data: AgentModelLoopCodec.encode(value))
    } catch let error as AgentModelLoopRecoveryError {
      failure = error
    } catch {
      fail("model_loop_journal_unavailable")
    }
  }

  private func fail(_ code: String) {
    if failure == nil { failure = AgentModelLoopRecoveryError(code: code) }
  }
}

private enum AgentModelLoopCodec {
  static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
  }

  static func decode<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      throw AgentModelLoopRecoveryError(code: "model_loop_record_invalid")
    }
  }

  static func sha256<T: Encodable>(_ value: T) -> String {
    guard let data = try? encode(value) else { return "" }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
