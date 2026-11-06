import Foundation

struct AgentIOSURLSessionBrowserSessionScope: Equatable {
  var ownerId: String
  var contextId: String
  var turnId: String
  var taskId: String

  init(context: AgentNativeToolInvocationContext) {
    let owner = context.callerId.trimmingCharacters(in: .whitespacesAndNewlines)
    let conversation = context.conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    let session = context.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    ownerId = owner.isEmpty ? "galaxyssi.mobile_agent" : owner
    contextId = conversation.isEmpty ? session : conversation
    turnId = context.turnId
    taskId = context.attributes["recovery_task_id"] ?? ""
  }
}

struct AgentIOSURLSessionBrowserSessionSnapshot: Equatable {
  var browserId: String
  var currentURL: String
  var historyCount: Int
  var expiresAtEpochMillis: Int64
}

enum AgentIOSURLSessionBrowserSessionStoreError: Error, Equatable {
  case toolHandleNotFound
  case toolHandleExpired
  case toolHandleOwnerMismatch
  case toolHandleContextMismatch
}

final class AgentIOSURLSessionBrowserSessionStore {
  static let toolHandleContract = "galaxyssi.tool-handle/1.0"
  static let defaultTTLMillis: Int64 = 30 * 60 * 1_000
  static let defaultIdleTimeoutMillis: Int64 = 10 * 60 * 1_000
  static let maxHistoryCount = 256

  private struct Record {
    var browserId: String
    var ownerId: String
    var contextId: String
    var currentURL: String
    var history: [String]
    var createdAtEpochMillis: Int64
    var lastUsedAtEpochMillis: Int64
    var expiresAtEpochMillis: Int64
    var useCount: Int64

    func snapshot() -> AgentIOSURLSessionBrowserSessionSnapshot {
      AgentIOSURLSessionBrowserSessionSnapshot(
        browserId: browserId,
        currentURL: currentURL,
        historyCount: history.count,
        expiresAtEpochMillis: expiresAtEpochMillis
      )
    }
  }

  private let lock = NSLock()
  private let ttlMillis: Int64
  private let idleTimeoutMillis: Int64
  private let maxSessions: Int
  private var records: [String: Record] = [:]
  private var operations: [Operation] = []

  private struct Operation {
    let id: String
    let scope: AgentIOSURLSessionBrowserSessionScope
    let name: String
    let time: Int64
  }

  init(
    ttlMillis: Int64 = AgentIOSURLSessionBrowserSessionStore.defaultTTLMillis,
    idleTimeoutMillis: Int64 = AgentIOSURLSessionBrowserSessionStore.defaultIdleTimeoutMillis,
    maxSessions: Int = 512
  ) {
    self.ttlMillis = max(1, min(ttlMillis, AgentIOSURLSessionBrowserSessionStore.defaultTTLMillis))
    self.idleTimeoutMillis = max(0, min(idleTimeoutMillis, self.ttlMillis))
    self.maxSessions = max(1, maxSessions)
  }

  func create(
    scope: AgentIOSURLSessionBrowserSessionScope,
    resourceId: String,
    currentURL: String,
    nowMillis: Int64
  ) -> AgentIOSURLSessionBrowserSessionSnapshot {
    lock.lock()
    defer { lock.unlock() }
    pruneLocked(nowMillis: nowMillis)
    evictIfNeededLocked()
    let browserId = Self.newHandleId()
    let history = currentURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [currentURL]
    let record = Record(
      browserId: browserId,
      ownerId: clean(scope.ownerId, maxLength: 240).nilIfEmpty ?? "galaxyssi.mobile_agent",
      contextId: clean(scope.contextId, maxLength: 240),
      currentURL: String(currentURL.prefix(Int(AgentIOSWebMediaNativeToolCatalog.maxUrlCharacters))),
      history: history,
      createdAtEpochMillis: nowMillis,
      lastUsedAtEpochMillis: nowMillis,
      expiresAtEpochMillis: nowMillis + ttlMillis,
      useCount: 0
    )
    records[browserId] = record
    recordOperation(resourceId, scope: scope, name: "create", now: nowMillis)
    return record.snapshot()
  }

  func navigate(
    browserId: String,
    scope: AgentIOSURLSessionBrowserSessionScope,
    currentURL: String,
    nowMillis: Int64,
    requestId: String = ""
  ) throws -> AgentIOSURLSessionBrowserSessionSnapshot {
    lock.lock()
    defer { lock.unlock() }
    let key = clean(browserId, maxLength: 240)
    var record = try resolvedLocked(browserId: key, scope: scope, nowMillis: nowMillis)
    record.currentURL = String(currentURL.prefix(Int(AgentIOSWebMediaNativeToolCatalog.maxUrlCharacters)))
    if record.history.last != record.currentURL {
      record.history.append(record.currentURL)
      if record.history.count > Self.maxHistoryCount {
        record.history.removeFirst(record.history.count - Self.maxHistoryCount)
      }
    }
    record.lastUsedAtEpochMillis = nowMillis
    record.useCount += 1
    records[key] = record
    recordOperation(requestId, scope: scope, name: "navigate", now: nowMillis)
    return record.snapshot()
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
    nowMillis: Int64,
    requestId: String = ""
  ) throws -> AgentIOSURLSessionBrowserSessionSnapshot {
    lock.lock()
    defer { lock.unlock() }
    let key = clean(browserId, maxLength: 240)
    let record = try resolvedLocked(browserId: key, scope: scope, nowMillis: nowMillis)
    records.removeValue(forKey: key)
    recordOperation(requestId, scope: scope, name: "close", now: nowMillis)
    return AgentIOSURLSessionBrowserSessionSnapshot(
      browserId: record.browserId,
      currentURL: record.currentURL,
      historyCount: record.history.count,
      expiresAtEpochMillis: nowMillis
    )
  }

  func observeOperation(
    requestId: String, scope: AgentIOSURLSessionBrowserSessionScope, nowMillis: Int64
  ) -> AgentMcpJSONObject? {
    lock.lock()
    defer { lock.unlock() }
    guard !scope.contextId.isEmpty, !scope.turnId.isEmpty, !scope.taskId.isEmpty,
          let operation = operations.last(where: { $0.id == requestId && $0.scope == scope }),
          operation.time <= nowMillis, nowMillis - operation.time < ttlMillis else { return nil }
    return ["request_id": .string(operation.id), "operation": .string(operation.name),
            "observed_at_epoch_ms": .int(nowMillis)]
  }

  private func recordOperation(_ id: String, scope: AgentIOSURLSessionBrowserSessionScope, name: String, now: Int64) {
    guard !id.isEmpty, !scope.contextId.isEmpty, !scope.turnId.isEmpty, !scope.taskId.isEmpty else { return }
    operations.removeAll { $0.id == id && $0.scope == scope }
    operations.append(Operation(id: id, scope: scope, name: name, time: now))
    if operations.count > 512 { operations.removeFirst(operations.count - 512) }
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
    guard record.ownerId == ownerId else {
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
