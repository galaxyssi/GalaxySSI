import CryptoKit
import Foundation

enum AgentNativeResourceLockMode: Equatable {
  case read
  case write
}

struct AgentNativeResourceLockRequest: Equatable {
  var key: String
  var mode: AgentNativeResourceLockMode
}

struct AgentNativeResourceLockPlan: Equatable {
  var requests: [AgentNativeResourceLockRequest]
  var resourceScoped: Bool

  func conflicts(with other: AgentNativeResourceLockPlan) -> Bool {
    let right = Dictionary(uniqueKeysWithValues: other.requests.map { ($0.key, $0.mode) })
    return requests.contains { left in
      guard let matching = right[left.key] else { return false }
      return left.mode == .write || matching == .write
    }
  }
}

enum AgentNativeToolResourcePolicy {
  static func resolve(
    descriptor: AgentNativeToolDescriptor,
    input: AgentMcpJSONObject,
    fallbackWorkspaceId: String = ""
  ) -> AgentNativeResourceLockPlan {
    let operationMode: AgentNativeResourceLockMode = descriptor.concurrency == .parallelReadOnly
      ? .read
      : .write
    if requiresExclusiveVerification(input) || exclusiveGlobalMutationToolIds.contains(descriptor.id) {
      return globalPlan(.write)
    }
    guard supportsWorkspaceScoping(descriptor) else {
      return globalPlan(operationMode)
    }
    let workspaceId = workspaceIdentity(
      descriptor: descriptor,
      input: input,
      fallbackWorkspaceId: fallbackWorkspaceId
    )
    guard !workspaceId.isEmpty else { return globalPlan(operationMode) }

    let workspaceSegment = stableSegment(workspaceId)
    let workspaceKey = "workspace:\(workspaceSegment)"
    let pathAccesses = descriptor.capabilities.contains(where: { $0.contains("workspace") })
      ? collectPathAccesses(descriptor: descriptor, input: input, operationMode: operationMode)
      : []
    var requests = [AgentNativeResourceLockRequest(key: globalKey, mode: .read)]
    if pathAccesses.isEmpty {
      requests.append(AgentNativeResourceLockRequest(key: workspaceKey, mode: operationMode))
    } else {
      requests.append(AgentNativeResourceLockRequest(key: workspaceKey, mode: .read))
      for access in pathAccesses {
        let components = normalizePath(access.path)
        if components.isEmpty {
          requests.append(AgentNativeResourceLockRequest(key: workspaceKey, mode: access.mode))
          continue
        }
        for index in components.indices {
          let prefix = components.prefix(index + 1).joined(separator: "/")
          requests.append(AgentNativeResourceLockRequest(
            key: "path:\(workspaceSegment):\(stableSegment(prefix))",
            mode: index == components.index(before: components.endIndex) ? access.mode : .read
          ))
        }
      }
    }
    return AgentNativeResourceLockPlan(requests: normalizeRequests(requests), resourceScoped: true)
  }

  static func resolveAction(
    descriptor: AgentNativeToolDescriptor,
    action: AgentAction,
    fallbackWorkspaceId: String = ""
  ) -> AgentNativeResourceLockPlan? {
    let raw = (action.parameters["input_json"] ?? "").ifBlank("{}")
    guard let data = raw.data(using: .utf8),
          let input = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data) else {
      return nil
    }
    return resolve(descriptor: descriptor, input: input, fallbackWorkspaceId: fallbackWorkspaceId)
  }

  private static func supportsWorkspaceScoping(_ descriptor: AgentNativeToolDescriptor) -> Bool {
    descriptor.capabilities.contains { capability in
      capability.contains("workspace") || capability.hasPrefix("runtime.") || capability.hasPrefix("project.")
    }
  }

  private static func workspaceIdentity(
    descriptor: AgentNativeToolDescriptor,
    input: AgentMcpJSONObject,
    fallbackWorkspaceId: String
  ) -> String {
    let explicit = clean(input["workspace_id"]?.stringValue ?? "", limit: maxIdentifierCharacters)
    if !explicit.isEmpty { return "\(descriptor.location.rawValue):\(explicit)" }
    let desktopId = clean(input["desktop_id"]?.stringValue ?? "", limit: maxIdentifierCharacters)
    if !desktopId.isEmpty {
      return "\(descriptor.location.rawValue):\(desktopId):\(fallbackWorkspaceId.ifBlank("default"))"
    }
    let fallback = clean(fallbackWorkspaceId, limit: maxIdentifierCharacters)
    return fallback.isEmpty ? "" : "\(descriptor.location.rawValue):\(fallback)"
  }

  private static func collectPathAccesses(
    descriptor: AgentNativeToolDescriptor,
    input: AgentMcpJSONObject,
    operationMode: AgentNativeResourceLockMode
  ) -> [PathAccess] {
    var accesses: [PathAccess] = []
    func visit(key: String, value: AgentMcpJSONValue) {
      switch value {
      case .string(let path) where isPathKey(key):
        accesses.append(PathAccess(
          path: path,
          mode: pathMode(toolId: descriptor.id, key: key, input: input, operationMode: operationMode)
        ))
      case .object(let object):
        object.forEach { visit(key: $0.key, value: $0.value) }
      case .array(let values):
        for value in values {
          if isPathCollectionKey(key), case .string(let path) = value {
            accesses.append(PathAccess(
              path: path,
              mode: pathMode(toolId: descriptor.id, key: key, input: input, operationMode: operationMode)
            ))
          } else {
            visit(key: key, value: value)
          }
        }
      default:
        break
      }
    }
    input.forEach { visit(key: $0.key, value: $0.value) }
    return accesses.filter { !$0.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }

  private static func pathMode(
    toolId: String,
    key: String,
    input: AgentMcpJSONObject,
    operationMode: AgentNativeResourceLockMode
  ) -> AgentNativeResourceLockMode {
    guard operationMode == .write else { return .read }
    let normalized = key.lowercased()
    if normalized == "source_path" || normalized == "source_paths" {
      return toolId.hasSuffix(".move") ? .write : .read
    }
    if normalized == "paths" { return .read }
    if normalized == "archive_path", toolId.hasSuffix(".zip.extract") || toolId.hasSuffix(".zip.list") {
      return .read
    }
    if normalized == "path", input["output_path"] != nil { return .read }
    return .write
  }

  private static func normalizePath(_ value: String) -> [String] {
    var normalized: [String] = []
    for raw in value.replacingOccurrences(of: "\\", with: "/").split(separator: "/", omittingEmptySubsequences: false) {
      let component = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
      switch component {
      case "", ".":
        continue
      case "..":
        if !normalized.isEmpty { normalized.removeLast() }
      default:
        normalized.append(String(component.prefix(maxPathComponentCharacters)))
      }
      if normalized.count == maxPathComponents { break }
    }
    return normalized
  }

  private static func normalizeRequests(
    _ requests: [AgentNativeResourceLockRequest]
  ) -> [AgentNativeResourceLockRequest] {
    Dictionary(grouping: requests, by: \.key).map { key, grouped in
      AgentNativeResourceLockRequest(
        key: key,
        mode: grouped.contains(where: { $0.mode == .write }) ? .write : .read
      )
    }.sorted { $0.key < $1.key }
  }

  private static func requiresExclusiveVerification(_ input: AgentMcpJSONObject) -> Bool {
    let verification = clean(input["verification_kind"]?.stringValue ?? "", limit: maxIdentifierCharacters)
      .lowercased()
    return !verification.isEmpty && verification != "none"
  }

  private static func globalPlan(_ mode: AgentNativeResourceLockMode) -> AgentNativeResourceLockPlan {
    AgentNativeResourceLockPlan(
      requests: [AgentNativeResourceLockRequest(key: globalKey, mode: mode)],
      resourceScoped: false
    )
  }

  private static func stableSegment(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
  }

  private static func clean(_ value: String, limit: Int) -> String {
    String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }

  private struct PathAccess {
    var path: String
    var mode: AgentNativeResourceLockMode
  }

  private static let globalKey = "global"
  private static let maxIdentifierCharacters = 512
  private static let maxPathComponents = 256
  private static let maxPathComponentCharacters = 512
  private static let exclusiveGlobalMutationToolIds: Set<String> = [
    AgentIOSProjectRepositoryMutationToolCatalog.commit,
    AgentIOSProjectRepositoryMutationToolCatalog.push
  ]
}

enum AgentNativeToolResourceLockTable {
  private static let tableLock = NSLock()
  private static var entries: [String: Entry] = [:]

  static func execute<T>(
    plan: AgentNativeResourceLockPlan,
    checkpoint: () throws -> Void,
    operation: () throws -> T
  ) rethrows -> T {
    let reservations = reserve(plan.requests)
    var acquired: [EntryLock] = []
    defer {
      acquired.reversed().forEach { $0.release() }
      release(reservations)
    }
    for reservation in reservations {
      try reservation.entry.lock.acquire(mode: reservation.request.mode, checkpoint: checkpoint)
      acquired.append(reservation.entry.lock)
    }
    try checkpoint()
    return try operation()
  }

  private static func reserve(_ requests: [AgentNativeResourceLockRequest]) -> [Reservation] {
    tableLock.lock()
    defer { tableLock.unlock() }
    return requests.map { request in
      let entry = entries[request.key] ?? Entry()
      entries[request.key] = entry
      entry.references += 1
      return Reservation(request: request, entry: entry)
    }
  }

  private static func release(_ reservations: [Reservation]) {
    tableLock.lock()
    defer { tableLock.unlock() }
    for reservation in reservations {
      reservation.entry.references -= 1
      precondition(reservation.entry.references >= 0, "Resource lock reference count underflow")
      if reservation.entry.references == 0, entries[reservation.request.key] === reservation.entry {
        entries.removeValue(forKey: reservation.request.key)
      }
    }
  }

  private final class Entry {
    let lock = EntryLock()
    var references = 0
  }

  private final class EntryLock {
    private let condition = NSCondition()
    private var readers = 0
    private var writerActive = false
    private var waitingWriters = 0

    func acquire(mode: AgentNativeResourceLockMode, checkpoint: () throws -> Void) rethrows {
      condition.lock()
      if mode == .write { waitingWriters += 1 }
      defer {
        if mode == .write { waitingWriters = max(waitingWriters - 1, 0) }
        condition.unlock()
      }
      while mode == .read
        ? (writerActive || waitingWriters > 0)
        : (writerActive || readers > 0) {
        _ = condition.wait(until: Date().addingTimeInterval(0.1))
        condition.unlock()
        defer { condition.lock() }
        try checkpoint()
      }
      if mode == .read { readers += 1 } else { writerActive = true }
    }

    func release() {
      condition.lock()
      if writerActive {
        writerActive = false
      } else {
        precondition(readers > 0, "Resource read lock released without an owner")
        readers -= 1
      }
      condition.broadcast()
      condition.unlock()
    }
  }

  private struct Reservation {
    var request: AgentNativeResourceLockRequest
    var entry: Entry
  }
}
