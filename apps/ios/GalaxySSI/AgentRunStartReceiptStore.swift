import Foundation

enum AgentRunStartReceiptStatus: String, Codable, CaseIterable, Identifiable {
  case reserved = "RESERVED"
  case accepted = "ACCEPTED"
  case outcomeUnknown = "OUTCOME_UNKNOWN"
  case cancelled = "CANCELLED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentRunStartReceiptStatus? {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    guard let status = Self.fromWireValue(try container.decode(String.self)) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown run start receipt status")
    }
    self = status
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentRunStartReceipt: Codable, Equatable, Identifiable {
  var agentId: String
  var installationId: String
  var idempotencyKey: String
  var requestDigest: String
  var runId: String
  var taskId: String
  var status: AgentRunStartReceiptStatus
  var handle: AgentRunHandle?
  var error: String
  var createdAtMillis: Int64
  var updatedAtMillis: Int64

  var id: String { "\(agentId)|\(idempotencyKey)" }

  init(
    agentId: String,
    installationId: String,
    idempotencyKey: String,
    requestDigest: String,
    runId: String,
    taskId: String,
    status: AgentRunStartReceiptStatus,
    handle: AgentRunHandle? = nil,
    error: String = "",
    createdAtMillis: Int64,
    updatedAtMillis: Int64
  ) {
    self.agentId = agentId
    self.installationId = installationId
    self.idempotencyKey = idempotencyKey
    self.requestDigest = requestDigest
    self.runId = runId
    self.taskId = taskId
    self.status = status
    self.handle = handle
    self.error = error
    self.createdAtMillis = max(createdAtMillis, 0)
    self.updatedAtMillis = max(updatedAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case agentId = "agent_id"
    case installationId = "installation_id"
    case idempotencyKey = "idempotency_key"
    case requestDigest = "request_digest"
    case runId = "run_id"
    case taskId = "task_id"
    case status
    case handle
    case error
    case createdAtMillis = "created_at_millis"
    case updatedAtMillis = "updated_at_millis"
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(agentId, forKey: .agentId)
    try container.encode(installationId, forKey: .installationId)
    try container.encode(idempotencyKey, forKey: .idempotencyKey)
    try container.encode(requestDigest, forKey: .requestDigest)
    try container.encode(runId, forKey: .runId)
    try container.encode(taskId, forKey: .taskId)
    try container.encode(status, forKey: .status)
    if let handle {
      try container.encode(handle, forKey: .handle)
    } else {
      try container.encodeNil(forKey: .handle)
    }
    try container.encode(error, forKey: .error)
    try container.encode(createdAtMillis, forKey: .createdAtMillis)
    try container.encode(updatedAtMillis, forKey: .updatedAtMillis)
  }
}

struct AgentRunStartReceiptError: Error, Equatable {
  var message: String
}

protocol AgentRunStartReceiptStore: AnyObject {
  func find(agentId: String, idempotencyKey: String) -> AgentRunStartReceipt?
  func reserve(registration: AgentRegistration, request: AgentRunRequest) throws -> AgentRunStartReceipt
  func accept(agentId: String, idempotencyKey: String, handle: AgentRunHandle) throws -> AgentRunStartReceipt
  func markOutcomeUnknown(agentId: String, idempotencyKey: String, error: String) -> AgentRunStartReceipt?
  func markCancelledByRun(agentId: String, runId: String) -> Int
  func list() -> [AgentRunStartReceipt]
  func clear()
}

class BaseAgentRunStartReceiptStore: AgentRunStartReceiptStore {
  private let lock = NSRecursiveLock()
  private let clock: () -> Int64
  private var cachedReceipts: [AgentRunStartReceipt]?

  init(clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }) {
    self.clock = clock
  }

  func readPersisted() -> [AgentRunStartReceipt] {
    []
  }

  func writePersisted(_ receipts: [AgentRunStartReceipt]) {}

  func clearPersisted() {}

  final func find(agentId: String, idempotencyKey: String) -> AgentRunStartReceipt? {
    lock.lock()
    defer { lock.unlock() }
    let agentId = agentId.trimmingCharacters(in: .whitespacesAndNewlines)
    let idempotencyKey = idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines)
    return loadReceipts().first { receipt in
      receipt.agentId == agentId && receipt.idempotencyKey == idempotencyKey
    }
  }

  final func reserve(registration: AgentRegistration, request: AgentRunRequest) throws -> AgentRunStartReceipt {
    lock.lock()
    defer { lock.unlock() }
    let agentId = try required(registration.agentId, label: "agent id")
    let installationId = try required(registration.installationId, label: "installation id")
    let key = try required(request.idempotencyKey, label: "idempotency key")
    let digest = AgentRunStartIdentity.requestDigest(request)
    var receipts = loadReceipts()
    if let existing = receipts.first(where: { $0.agentId == agentId && $0.idempotencyKey == key }) {
      guard existing.installationId == installationId else {
        throw AgentRunStartReceiptError(message: "Run idempotency key belongs to a different Agent installation")
      }
      guard existing.requestDigest == digest else {
        throw AgentRunStartReceiptError(message: "Run idempotency key was reused with different request content")
      }
      return existing
    }
    let now = self.now()
    let receipt = AgentRunStartReceipt(
      agentId: agentId,
      installationId: installationId,
      idempotencyKey: key,
      requestDigest: digest,
      runId: try required(request.runId, label: "run id"),
      taskId: try required(request.taskId, label: "task id"),
      status: .reserved,
      createdAtMillis: now,
      updatedAtMillis: now
    )
    receipts.append(receipt)
    persist(bound(receipts))
    return receipt
  }

  final func accept(agentId: String, idempotencyKey: String, handle: AgentRunHandle) throws -> AgentRunStartReceipt {
    lock.lock()
    defer { lock.unlock() }
    let agentId = agentId.trimmingCharacters(in: .whitespacesAndNewlines)
    let idempotencyKey = idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines)
    var receipts = loadReceipts()
    guard let index = receipts.firstIndex(where: { $0.agentId == agentId && $0.idempotencyKey == idempotencyKey }) else {
      throw AgentRunStartReceiptError(message: "Run start was not reserved")
    }
    let current = receipts[index]
    guard current.runId == handle.runId && current.taskId == handle.taskId else {
      throw AgentRunStartReceiptError(message: "Agent returned a handle for a different Run")
    }
    guard handle.agentId == current.agentId else {
      throw AgentRunStartReceiptError(message: "Agent returned a handle for a different identity")
    }
    let accepted = AgentRunStartReceipt(
      agentId: current.agentId,
      installationId: current.installationId,
      idempotencyKey: current.idempotencyKey,
      requestDigest: current.requestDigest,
      runId: current.runId,
      taskId: current.taskId,
      status: .accepted,
      handle: handle,
      error: "",
      createdAtMillis: current.createdAtMillis,
      updatedAtMillis: now()
    )
    receipts[index] = accepted
    persist(bound(receipts))
    return accepted
  }

  final func markOutcomeUnknown(agentId: String, idempotencyKey: String, error: String) -> AgentRunStartReceipt? {
    update(agentId: agentId, idempotencyKey: idempotencyKey) { current in
      if current.status == .accepted || current.status == .cancelled {
        return current
      }
      var copy = current
      copy.status = .outcomeUnknown
      copy.error = String(error.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxErrorCharacters))
      copy.updatedAtMillis = now()
      return copy
    }
  }

  final func markCancelledByRun(agentId: String, runId: String) -> Int {
    lock.lock()
    defer { lock.unlock() }
    let agentId = agentId.trimmingCharacters(in: .whitespacesAndNewlines)
    let runId = runId.trimmingCharacters(in: .whitespacesAndNewlines)
    let now = self.now()
    var changed = 0
    let receipts = loadReceipts().map { receipt -> AgentRunStartReceipt in
      guard receipt.agentId == agentId && receipt.runId == runId && receipt.status != .cancelled else {
        return receipt
      }
      changed += 1
      var copy = receipt
      copy.status = .cancelled
      copy.updatedAtMillis = now
      return copy
    }
    if changed > 0 {
      persist(bound(receipts))
    }
    return changed
  }

  final func list() -> [AgentRunStartReceipt] {
    lock.lock()
    defer { lock.unlock() }
    return loadReceipts().sorted {
      if $0.updatedAtMillis != $1.updatedAtMillis {
        return $0.updatedAtMillis > $1.updatedAtMillis
      }
      return $0.idempotencyKey < $1.idempotencyKey
    }
  }

  final func clear() {
    lock.lock()
    defer { lock.unlock() }
    clearPersisted()
    cachedReceipts = []
  }

  private func update(
    agentId: String,
    idempotencyKey: String,
    transform: (AgentRunStartReceipt) -> AgentRunStartReceipt
  ) -> AgentRunStartReceipt? {
    lock.lock()
    defer { lock.unlock() }
    let agentId = agentId.trimmingCharacters(in: .whitespacesAndNewlines)
    let idempotencyKey = idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines)
    var receipts = loadReceipts()
    guard let index = receipts.firstIndex(where: { $0.agentId == agentId && $0.idempotencyKey == idempotencyKey }) else {
      return nil
    }
    let updated = transform(receipts[index])
    receipts[index] = updated
    persist(bound(receipts))
    return updated
  }

  private func loadReceipts() -> [AgentRunStartReceipt] {
    if let cachedReceipts {
      return cachedReceipts
    }
    let persisted = readPersisted()
    cachedReceipts = persisted
    return persisted
  }

  private func persist(_ receipts: [AgentRunStartReceipt]) {
    writePersisted(receipts)
    cachedReceipts = receipts
  }

  private func required(_ value: String, label: String) throws -> String {
    let clean = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxIdCharacters))
    guard !clean.isEmpty else {
      throw AgentRunStartReceiptError(message: "Run \(label) must not be blank")
    }
    return clean
  }

  private func bound(_ receipts: [AgentRunStartReceipt]) -> [AgentRunStartReceipt] {
    Array(receipts.sorted {
      if $0.updatedAtMillis != $1.updatedAtMillis {
        return $0.updatedAtMillis < $1.updatedAtMillis
      }
      return $0.idempotencyKey < $1.idempotencyKey
    }.suffix(Self.maxReceipts))
  }

  private func now() -> Int64 {
    max(clock(), 0)
  }

  private static let maxReceipts = 4_000
  private static let maxIdCharacters = 512
  private static let maxErrorCharacters = 2_048
}

final class InMemoryAgentRunStartReceiptStore: BaseAgentRunStartReceiptStore {
  private var document: String

  init(
    serialized: String = "[]",
    clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.document = serialized
    super.init(clock: clock)
  }

  override func readPersisted() -> [AgentRunStartReceipt] {
    AgentRunStartReceiptJsonCodec.decode(document)
  }

  override func writePersisted(_ receipts: [AgentRunStartReceipt]) {
    document = AgentRunStartReceiptJsonCodec.encode(receipts)
  }

  override func clearPersisted() {
    document = "[]"
  }

  func serializedSnapshot() -> String {
    document
  }
}

enum AgentRunStartIdentity {
  static func requestDigest(_ request: AgentRunRequest) -> String {
    AgentMcpJSONCodec.sha256([
      "conversation_id": .string(request.conversationId),
      "message_id": .string(request.messageId),
      "task_id": .string(request.taskId),
      "parent_run_id": .string(request.parentRunId),
      "goal": .string(request.goal),
      "delivery_mode": .string(request.deliveryMode.rawValue),
      "required_capabilities": .array(request.requiredCapabilities.map { .string($0.rawValue) }.sortedByStringValue()),
      "context": .object(request.context),
      "idempotency_key": .string(request.idempotencyKey)
    ])
  }
}

enum AgentRunStartReceiptJsonCodec {
  static func encode(_ receipts: [AgentRunStartReceipt]) -> String {
    guard let data = try? JSONEncoder().encode(receipts) else {
      return "[]"
    }
    return String(decoding: data, as: UTF8.self)
  }

  static func decode(_ raw: String) -> [AgentRunStartReceipt] {
    guard let data = raw.data(using: .utf8),
      let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      return []
    }
    return array.compactMap(decodeReceipt)
  }

  private static func decodeReceipt(_ object: [String: Any]) -> AgentRunStartReceipt? {
    guard let status = AgentRunStartReceiptStatus.fromWireValue(string(object["status"])) else {
      return nil
    }
    return AgentRunStartReceipt(
      agentId: string(object["agent_id"]),
      installationId: string(object["installation_id"]),
      idempotencyKey: string(object["idempotency_key"]),
      requestDigest: string(object["request_digest"]),
      runId: string(object["run_id"]),
      taskId: string(object["task_id"]),
      status: status,
      handle: decodeHandle(object["handle"] as? [String: Any]),
      error: string(object["error"]),
      createdAtMillis: int64(object["created_at_millis"]),
      updatedAtMillis: int64(object["updated_at_millis"])
    )
  }

  private static func decodeHandle(_ object: [String: Any]?) -> AgentRunHandle? {
    guard let object else {
      return nil
    }
    return AgentRunHandle(
      runId: string(object["run_id"]),
      taskId: string(object["task_id"]),
      agentId: string(object["agent_id"]),
      remoteRunId: string(object["remote_run_id"]),
      acceptedAtMillis: int64(object["accepted_at_millis"])
    )
  }

  private static func string(_ value: Any?) -> String {
    (value as? String) ?? ""
  }

  private static func int64(_ value: Any?) -> Int64 {
    if let value = value as? NSNumber {
      return value.int64Value
    }
    return Int64(value as? String ?? "") ?? 0
  }
}

private extension Array where Element == AgentMcpJSONValue {
  func sortedByStringValue() -> [AgentMcpJSONValue] {
    sorted { AgentMcpJSONCodec.stringify($0) < AgentMcpJSONCodec.stringify($1) }
  }
}
