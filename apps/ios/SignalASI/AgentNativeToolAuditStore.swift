import CryptoKit
import Foundation

struct AgentNativeToolAuditRecord: Codable, Equatable, Identifiable {
  var auditId: String
  var invocationId: String
  var toolId: String
  var toolVersion: String
  var location: AgentNativeToolLocation
  var risk: AgentNativeToolRisk
  var callerId: String
  var identityHashes: [String: String]
  var startedAtEpochMillis: Int64
  var finishedAtEpochMillis: Int64
  var durationMillis: Int64
  var status: AgentNativeToolResultStatus
  var errorCode: String
  var inputSha256: String
  var outputSha256: String
  var replayed: Bool
  var originalInvocationId: String?
  var recordSha256: String

  var id: String { auditId }

  init(
    auditId: String = UUID().uuidString,
    invocationId: String,
    toolId: String,
    toolVersion: String,
    location: AgentNativeToolLocation,
    risk: AgentNativeToolRisk,
    callerId: String,
    identityHashes: [String: String],
    startedAtEpochMillis: Int64,
    finishedAtEpochMillis: Int64,
    durationMillis: Int64,
    status: AgentNativeToolResultStatus,
    errorCode: String,
    inputSha256: String,
    outputSha256: String,
    replayed: Bool,
    originalInvocationId: String?,
    recordSha256: String
  ) {
    self.auditId = auditId
    self.invocationId = invocationId
    self.toolId = toolId
    self.toolVersion = toolVersion
    self.location = location
    self.risk = risk
    self.callerId = callerId
    self.identityHashes = identityHashes
    self.startedAtEpochMillis = startedAtEpochMillis
    self.finishedAtEpochMillis = finishedAtEpochMillis
    self.durationMillis = durationMillis
    self.status = status
    self.errorCode = errorCode
    self.inputSha256 = inputSha256
    self.outputSha256 = outputSha256
    self.replayed = replayed
    self.originalInvocationId = originalInvocationId
    self.recordSha256 = recordSha256
  }

  enum CodingKeys: String, CodingKey {
    case auditId = "audit_id"
    case invocationId = "invocation_id"
    case toolId = "tool_id"
    case toolVersion = "tool_version"
    case location
    case risk
    case callerId = "caller_id"
    case identityHashes = "identity_hashes"
    case startedAtEpochMillis = "started_at_epoch_ms"
    case finishedAtEpochMillis = "finished_at_epoch_ms"
    case durationMillis = "duration_ms"
    case status
    case errorCode = "error_code"
    case inputSha256 = "input_sha256"
    case outputSha256 = "output_sha256"
    case replayed
    case originalInvocationId = "original_invocation_id"
    case recordSha256 = "record_sha256"
  }

  static func from(
    result: AgentNativeToolResult,
    context: AgentNativeToolInvocationContext,
    risk: AgentNativeToolRisk
  ) -> AgentNativeToolAuditRecord {
    let caller = String(context.callerId.prefix(160))
    let errorCode = String((result.error?.code ?? "").prefix(160))
    let hashes = identityHashes(context)
    let canonical: AgentMcpJSONObject = [
      "invocation_id": .string(result.receipt.invocationId),
      "tool_id": .string(result.provenance.toolId),
      "tool_version": .string(result.provenance.toolVersion),
      "location": .string(result.provenance.location.rawValue),
      "risk": .string(risk.rawValue),
      "caller_id": .string(caller),
      "identity_hashes": .object(hashes.reduce(into: AgentMcpJSONObject()) { object, entry in
        object[entry.key] = .string(entry.value)
      }),
      "started_at_epoch_ms": .int(result.receipt.startedAtEpochMillis),
      "finished_at_epoch_ms": .int(result.receipt.finishedAtEpochMillis),
      "duration_ms": .int(result.receipt.durationMillis),
      "status": .string(result.status.rawValue),
      "error_code": .string(errorCode),
      "input_sha256": .string(result.receipt.inputSha256),
      "output_sha256": .string(result.receipt.outputSha256),
      "replayed": .bool(result.receipt.replayed),
      "original_invocation_id": result.receipt.originalInvocationId.map(AgentMcpJSONValue.string) ?? .null
    ]
    return AgentNativeToolAuditRecord(
      invocationId: result.receipt.invocationId,
      toolId: result.provenance.toolId,
      toolVersion: result.provenance.toolVersion,
      location: result.provenance.location,
      risk: risk,
      callerId: caller,
      identityHashes: hashes,
      startedAtEpochMillis: result.receipt.startedAtEpochMillis,
      finishedAtEpochMillis: result.receipt.finishedAtEpochMillis,
      durationMillis: result.receipt.durationMillis,
      status: result.status,
      errorCode: errorCode,
      inputSha256: result.receipt.inputSha256,
      outputSha256: result.receipt.outputSha256,
      replayed: result.receipt.replayed,
      originalInvocationId: result.receipt.originalInvocationId,
      recordSha256: AgentMcpJSONCodec.sha256(canonical)
    )
  }

  private static func identityHashes(_ context: AgentNativeToolInvocationContext) -> [String: String] {
    var hashes: [String: String] = [:]
    hash("session_id", context.sessionId, into: &hashes)
    hash("conversation_id", context.conversationId, into: &hashes)
    hash("turn_id", context.turnId, into: &hashes)
    if let taskId = context.attributes["task_id"] {
      hash("task_id", taskId, into: &hashes)
    }
    return hashes
  }

  private static func hash(_ key: String, _ value: String, into hashes: inout [String: String]) {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    hashes["\(key)_sha256"] = sha256(clean)
  }

  private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

protocol AgentNativeToolAuditStore {
  func append(_ record: AgentNativeToolAuditRecord)
  func list(
    limit: Int,
    toolId: String,
    status: AgentNativeToolResultStatus?
  ) -> [AgentNativeToolAuditRecord]
  func clear()
}

final class InMemoryAgentNativeToolAuditStore: AgentNativeToolAuditStore {
  static let maxRecords = 10_000
  static let maxListLimit = 500

  private let lock = NSLock()
  private var records: [AgentNativeToolAuditRecord] = []

  func append(_ record: AgentNativeToolAuditRecord) {
    lock.lock()
    defer { lock.unlock() }
    records.append(record)
    if records.count > Self.maxRecords {
      records.removeFirst(records.count - Self.maxRecords)
    }
  }

  func list(
    limit: Int = 100,
    toolId: String = "",
    status: AgentNativeToolResultStatus? = nil
  ) -> [AgentNativeToolAuditRecord] {
    lock.lock()
    defer { lock.unlock() }
    return records
      .reversed()
      .filter { toolId.isEmpty || $0.toolId == toolId }
      .filter { status == nil || $0.status == status }
      .prefix(limit.clamped(to: 1...Self.maxListLimit))
      .map { $0 }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    records.removeAll()
  }
}

final class FileAgentNativeToolAuditStore: AgentNativeToolAuditStore {
  private let fileURL: URL
  private let fileManager: FileManager
  private let lock = NSLock()
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(fileURL: URL, fileManager: FileManager = .default) {
    self.fileURL = fileURL
    self.fileManager = fileManager
  }

  func append(_ record: AgentNativeToolAuditRecord) {
    lock.lock()
    defer { lock.unlock() }
    let retained = Array((loadUnlocked() + [record]).suffix(InMemoryAgentNativeToolAuditStore.maxRecords))
    saveUnlocked(retained)
  }

  func list(
    limit: Int = 100,
    toolId: String = "",
    status: AgentNativeToolResultStatus? = nil
  ) -> [AgentNativeToolAuditRecord] {
    lock.lock()
    defer { lock.unlock() }
    return loadUnlocked()
      .reversed()
      .filter { toolId.isEmpty || $0.toolId == toolId }
      .filter { status == nil || $0.status == status }
      .prefix(limit.clamped(to: 1...InMemoryAgentNativeToolAuditStore.maxListLimit))
      .map { $0 }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    try? fileManager.removeItem(at: fileURL)
  }

  private func loadUnlocked() -> [AgentNativeToolAuditRecord] {
    guard fileManager.fileExists(atPath: fileURL.path),
          let data = try? Data(contentsOf: fileURL) else {
      return []
    }
    return (try? decoder.decode([AgentNativeToolAuditRecord].self, from: data)) ?? []
  }

  private func saveUnlocked(_ records: [AgentNativeToolAuditRecord]) {
    do {
      let directory = fileURL.deletingLastPathComponent()
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
      let data = try encoder.encode(records)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      // Audit failures must not break the native tool execution path.
    }
  }
}
