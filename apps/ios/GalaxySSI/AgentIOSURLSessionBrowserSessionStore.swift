import Foundation

struct AgentIOSURLSessionBrowserSessionScope: Hashable {
  var ownerId: String
  var contextId: String
  var turnId: String
  var taskId: String
  let sessionId: String
  let collaborationOwnerKey: String?
  let ownershipIsValid: Bool

  init(context: AgentNativeToolInvocationContext) {
    let owner = context.callerId.trimmingCharacters(in: .whitespacesAndNewlines)
    let conversation = context.conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    let session = context.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    let caller = owner.isEmpty ? "galaxyssi.mobile_agent" : owner
    ownerId = caller
    sessionId = session
    contextId = conversation.isEmpty ? session : conversation
    turnId = context.turnId
    let workspace = context.attributes["workspace_id"] ?? ""
    if let managed = context.collaborationOwner {
      ownershipIsValid = managed.matchesBrowserInvocation(conversation: conversation, turn: context.turnId) &&
        !session.isEmpty && !workspace.isBlank
      collaborationOwnerKey = AgentMcpJSONCodec.sha256([
        "member": .string(managed.ownershipDigest), "session": .string(session),
        "conversation": .string(conversation), "workspace": .string(workspace), "caller": .string(caller)
      ])
      taskId = context.attributes["task_id"] ?? managed.sourceId
    } else {
      ownershipIsValid = true
      collaborationOwnerKey = nil
      taskId = context.attributes["recovery_task_id"] ?? context.attributes["task_id"] ?? ""
    }
  }
}

struct AgentIOSURLSessionBrowserSessionSnapshot: Equatable {
  var browserId: String
  var currentURL: String
  var historyCount: Int
  var expiresAtEpochMillis: Int64
  var revision: Int64
}

enum AgentIOSURLSessionBrowserSessionStoreError: Error, Equatable {
  case toolHandleNotFound
  case toolHandleExpired
  case toolHandleOwnerMismatch
  case toolHandleContextMismatch
  case noPreviousPage
  case revisionChanged
  case invalidRequestID
  case requestAlreadyDispatched
  case operationCapacityReached
}

final class AgentIOSURLSessionBrowserSessionStore {
  static let toolHandleContract = "galaxyssi.tool-handle/1.0"
  static let defaultTTLMillis: Int64 = 30 * 60 * 1_000
  static let defaultIdleTimeoutMillis: Int64 = 10 * 60 * 1_000
  static let maxHistoryCount = 256
  static let operationRetentionMillis: Int64 = 10 * 60 * 1_000
  static let operationHistoryCapacity = 1_024

  private struct Record {
    var browserId: String
    var ownerId: String
    var contextId: String
    let collaborationOwnerKey: String?
    var currentURL: String
    var history: [String]
    var createdAtEpochMillis: Int64
    var lastUsedAtEpochMillis: Int64
    var expiresAtEpochMillis: Int64
    var revision: Int64

    func snapshot() -> AgentIOSURLSessionBrowserSessionSnapshot {
      AgentIOSURLSessionBrowserSessionSnapshot(
        browserId: browserId,
        currentURL: currentURL,
        historyCount: history.count,
        expiresAtEpochMillis: expiresAtEpochMillis, revision: revision
      )
    }
  }

  private let lock = NSLock()
  private let ttlMillis: Int64
  private let idleTimeoutMillis: Int64
  private let maxSessions: Int
  private var records: [String: Record] = [:]
  private let operationTTLMillis: Int64
  private let operationCapacity: Int
  private var operations: [OperationKey: Operation] = [:]
  private var finishSequence: UInt64 = 0

  fileprivate struct OperationKey: Hashable {
    let id: String
    let scope: AgentIOSURLSessionBrowserSessionScope
  }

  struct OperationTicket {
    fileprivate let key: OperationKey
    fileprivate let nonce: UUID
  }

  enum OperationName: String { case create, navigate, back, close }

  private struct Operation {
    let nonce: UUID
    let name: OperationName
    let startedAt: Int64
    var finishedAt: Int64?
    var finishOrder: UInt64 = 0
    var errorCode: String?
    var outcomeUnknown = false
  }

  init(
    ttlMillis: Int64 = AgentIOSURLSessionBrowserSessionStore.defaultTTLMillis,
    idleTimeoutMillis: Int64 = AgentIOSURLSessionBrowserSessionStore.defaultIdleTimeoutMillis,
    maxSessions: Int = 512,
    operationTTLMillis: Int64 = AgentIOSURLSessionBrowserSessionStore.operationRetentionMillis,
    operationCapacity: Int = AgentIOSURLSessionBrowserSessionStore.operationHistoryCapacity
  ) {
    self.ttlMillis = max(1, min(ttlMillis, AgentIOSURLSessionBrowserSessionStore.defaultTTLMillis))
    self.idleTimeoutMillis = max(0, min(idleTimeoutMillis, self.ttlMillis))
    self.maxSessions = max(1, maxSessions)
    self.operationTTLMillis = max(1, min(operationTTLMillis, Self.operationRetentionMillis))
    self.operationCapacity = max(1, min(operationCapacity, Self.operationHistoryCapacity))
  }

  func create(
    scope: AgentIOSURLSessionBrowserSessionScope,
    currentURL: String,
    nowMillis: Int64
  ) throws -> AgentIOSURLSessionBrowserSessionSnapshot {
    lock.lock()
    defer { lock.unlock() }
    guard scope.ownershipIsValid else { throw AgentIOSURLSessionBrowserSessionStoreError.toolHandleOwnerMismatch }
    pruneLocked(nowMillis: nowMillis)
    evictIfNeededLocked()
    let browserId = Self.newHandleId()
    let history = currentURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [currentURL]
    let record = Record(
      browserId: browserId,
      ownerId: clean(scope.ownerId, maxLength: 240).nilIfEmpty ?? "galaxyssi.mobile_agent",
      contextId: clean(scope.contextId, maxLength: 240),
      collaborationOwnerKey: scope.collaborationOwnerKey,
      currentURL: String(currentURL.prefix(Int(AgentIOSWebMediaNativeToolCatalog.maxUrlCharacters))),
      history: history,
      createdAtEpochMillis: nowMillis,
      lastUsedAtEpochMillis: nowMillis,
      expiresAtEpochMillis: nowMillis + ttlMillis,
      revision: currentURL.isEmpty ? 0 : 1
    )
    records[browserId] = record
    return record.snapshot()
  }

  func navigate(
    browserId: String,
    scope: AgentIOSURLSessionBrowserSessionScope,
    currentURL: String,
    nowMillis: Int64,
    backFromRevision: Int64? = nil
  ) throws -> AgentIOSURLSessionBrowserSessionSnapshot {
    lock.lock()
    defer { lock.unlock() }
    let key = clean(browserId, maxLength: 240)
    var record = try resolvedLocked(browserId: key, scope: scope, nowMillis: nowMillis)
    if let backFromRevision {
      guard record.revision == backFromRevision else { throw AgentIOSURLSessionBrowserSessionStoreError.revisionChanged }
      guard record.history.count >= 2 else { throw AgentIOSURLSessionBrowserSessionStoreError.noPreviousPage }
      record.history.removeLast(2)
    }
    record.currentURL = String(currentURL.prefix(Int(AgentIOSWebMediaNativeToolCatalog.maxUrlCharacters)))
    if record.history.last != record.currentURL {
      record.history.append(record.currentURL)
      if record.history.count > Self.maxHistoryCount {
        record.history.removeFirst(record.history.count - Self.maxHistoryCount)
      }
    }
    record.lastUsedAtEpochMillis = nowMillis
    record.revision += 1
    records[key] = record
    return record.snapshot()
  }

  func previousPage(
    browserId: String, scope: AgentIOSURLSessionBrowserSessionScope, nowMillis: Int64
  ) throws -> (url: String, revision: Int64) {
    lock.lock()
    defer { lock.unlock() }
    let record = try resolvedLocked(browserId: clean(browserId, maxLength: 240), scope: scope, nowMillis: nowMillis)
    guard record.history.count >= 2 else { throw AgentIOSURLSessionBrowserSessionStoreError.noPreviousPage }
    return (record.history[record.history.count - 2], record.revision)
  }

  func validate(
    browserId: String,
    scope: AgentIOSURLSessionBrowserSessionScope,
    nowMillis: Int64
  ) throws {
    lock.lock()
    defer { lock.unlock() }
    _ = try resolvedLocked(
      browserId: clean(browserId, maxLength: 240),
      scope: scope,
      nowMillis: nowMillis
    )
  }

  func close(
    browserId: String,
    scope: AgentIOSURLSessionBrowserSessionScope,
    nowMillis: Int64
  ) throws -> AgentIOSURLSessionBrowserSessionSnapshot {
    lock.lock()
    defer { lock.unlock() }
    let key = clean(browserId, maxLength: 240)
    let record = try resolvedLocked(browserId: key, scope: scope, nowMillis: nowMillis)
    records.removeValue(forKey: key)
    return AgentIOSURLSessionBrowserSessionSnapshot(
      browserId: record.browserId,
      currentURL: record.currentURL,
      historyCount: record.history.count,
      expiresAtEpochMillis: nowMillis, revision: record.revision
    )
  }

  static func validOperationID(_ id: String) -> Bool {
    (1...Int(AgentIOSWebMediaNativeToolCatalog.maxBrowserHandleCharacters)).contains(id.utf8.count) &&
      id.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) ||
        (97...122).contains($0) || $0 == 45 || $0 == 95 }
  }

  func beginOperation(requestId: String, scope: AgentIOSURLSessionBrowserSessionScope,
                      name: OperationName, nowMillis: Int64) throws -> OperationTicket {
    lock.lock()
    defer { lock.unlock() }
    guard scope.ownershipIsValid else { throw AgentIOSURLSessionBrowserSessionStoreError.toolHandleOwnerMismatch }
    guard Self.validOperationID(requestId) else { throw AgentIOSURLSessionBrowserSessionStoreError.invalidRequestID }
    pruneOperations(nowMillis: nowMillis)
    let key = OperationKey(id: requestId, scope: scope)
    guard operations[key] == nil else { throw AgentIOSURLSessionBrowserSessionStoreError.requestAlreadyDispatched }
    guard operations.values.lazy.filter({ $0.finishedAt == nil }).prefix(Self.operationHistoryCapacity).count <
      Self.operationHistoryCapacity else { throw AgentIOSURLSessionBrowserSessionStoreError.operationCapacityReached }
    let nonce = UUID()
    operations[key] = Operation(nonce: nonce, name: name, startedAt: nowMillis)
    return OperationTicket(key: key, nonce: nonce)
  }

  func finishOperation(_ ticket: OperationTicket, nowMillis: Int64, errorCode: String? = nil,
                       outcomeUnknown: Bool = false) {
    lock.lock()
    defer { lock.unlock() }
    guard var operation = operations[ticket.key], operation.nonce == ticket.nonce,
          operation.finishedAt == nil else { return }
    operation.finishedAt = max(operation.startedAt, nowMillis)
    finishSequence &+= 1
    operation.finishOrder = finishSequence
    operation.errorCode = errorCode
    operation.outcomeUnknown = errorCode != nil && outcomeUnknown
    operations[ticket.key] = operation
    pruneOperations(nowMillis: nowMillis)
  }

  func observeOperation(requestId: String, scope: AgentIOSURLSessionBrowserSessionScope,
                        nowMillis: Int64) -> AgentMcpJSONObject? {
    lock.lock()
    defer { lock.unlock() }
    pruneOperations(nowMillis: nowMillis)
    guard scope.ownershipIsValid, !scope.contextId.isEmpty, !scope.turnId.isEmpty,
          let operation = operations[OperationKey(id: requestId, scope: scope)] else { return nil }
    let running = operation.finishedAt == nil
    var output: AgentMcpJSONObject = [
      "request_id": .string(requestId), "operation": .string(operation.name.rawValue),
      "state": .string(running ? "running" : (operation.errorCode == nil ? "completed" : "failed")),
      "started_at_epoch_ms": .int(operation.startedAt), "observed_at_epoch_ms": .int(nowMillis),
      "outcome_unknown": .bool(running || operation.outcomeUnknown),
      "business_success_verified": .bool(false), "verification_required": .bool(true),
      "missing_receipt_means_not_executed": .bool(false),
      "receipt_retention_ms": .int(operationTTLMillis),
      "next_action": .string(running ? "observe_or_wait" : "observe")
    ]
    if let finished = operation.finishedAt {
      output["finished_at_epoch_ms"] = .int(finished)
      if !operation.outcomeUnknown { output["executed"] = .bool(operation.errorCode == nil) }
    }
    if let error = operation.errorCode { output["error_code"] = .string(error) }
    return output
  }

  private func pruneOperations(nowMillis: Int64) {
    let completed = operations.compactMap { key, operation in
      operation.finishedAt.map { (key, $0, operation.finishOrder) }
    }
    let retained = completed.filter { nowMillis < $0.1 || nowMillis - $0.1 < operationTTLMillis }
      .sorted { $0.2 < $1.2 }
    let retainedKeys = Set(retained.suffix(operationCapacity).map { $0.0 })
    for (key, _, _) in completed where !retainedKeys.contains(key) {
      operations.removeValue(forKey: key)
    }
  }

  private func resolvedLocked(
    browserId: String,
    scope: AgentIOSURLSessionBrowserSessionScope,
    nowMillis: Int64
  ) throws -> Record {
    guard let record = records[browserId] else {
      throw AgentIOSURLSessionBrowserSessionStoreError.toolHandleNotFound
    }
    if expired(record, nowMillis: nowMillis) {
      records.removeValue(forKey: browserId)
      throw AgentIOSURLSessionBrowserSessionStoreError.toolHandleExpired
    }
    let ownerId = clean(scope.ownerId, maxLength: 240).nilIfEmpty ?? "galaxyssi.mobile_agent"
    let contextId = clean(scope.contextId, maxLength: 240)
    guard scope.ownershipIsValid, record.ownerId == ownerId,
          record.collaborationOwnerKey == scope.collaborationOwnerKey else {
      throw AgentIOSURLSessionBrowserSessionStoreError.toolHandleOwnerMismatch
    }
    if !record.contextId.isEmpty, record.contextId != contextId {
      throw AgentIOSURLSessionBrowserSessionStoreError.toolHandleContextMismatch
    }
    return record
  }

  private func pruneLocked(nowMillis: Int64) {
    records.values
      .filter { expired($0, nowMillis: nowMillis) }
      .map(\.browserId)
      .forEach { records.removeValue(forKey: $0) }
  }

  private func evictIfNeededLocked() {
    while records.count >= maxSessions {
      guard let oldest = records.values.min(by: { $0.lastUsedAtEpochMillis < $1.lastUsedAtEpochMillis }) else {
        break
      }
      records.removeValue(forKey: oldest.browserId)
    }
  }

  private func expired(_ record: Record, nowMillis: Int64) -> Bool {
    nowMillis >= record.expiresAtEpochMillis ||
      (idleTimeoutMillis > 0 && nowMillis >= record.lastUsedAtEpochMillis + idleTimeoutMillis)
  }

  private static func newHandleId() -> String {
    "browser_session-\(UUID().uuidString.lowercased())"
  }

  private func clean(_ value: String, maxLength: Int) -> String {
    String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
  }
}
