import Foundation

struct AgentMcpAuditRecord: Codable, Equatable, Identifiable {
  var auditId: String
  var timestampMillis: Int64
  var connectionId: String
  var connectionName: String
  var toolName: String
  var transport: String
  var source: String
  var callerId: String
  var taskId: String
  var conversationId: String
  var risk: String
  var permissions: [String]
  var permissionMode: String
  var permissionDecision: String
  var parameterPreview: AgentMcpJSONObject
  var inputSha256: String
  var status: String
  var durationMillis: Int64
  var outputSha256: String
  var errorCode: String
  var errorMessage: String

  var id: String { auditId }

  init(
    auditId: String = UUID().uuidString,
    timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000),
    connectionId: String,
    connectionName: String,
    toolName: String,
    transport: String,
    source: String,
    callerId: String,
    taskId: String,
    conversationId: String,
    risk: String,
    permissions: [String],
    permissionMode: String,
    permissionDecision: String,
    parameterPreview: AgentMcpJSONObject,
    inputSha256: String,
    status: String,
    durationMillis: Int64,
    outputSha256: String = "",
    errorCode: String = "",
    errorMessage: String = ""
  ) {
    self.auditId = auditId.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? UUID().uuidString
    self.timestampMillis = max(0, timestampMillis)
    self.connectionId = String(connectionId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(192))
    self.connectionName = String(connectionName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(192))
    self.toolName = String(toolName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(192))
    self.transport = String(transport.trimmingCharacters(in: .whitespacesAndNewlines).prefix(96))
    self.source = String(source.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))
    self.callerId = String(callerId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(192))
    self.taskId = String(taskId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(192))
    self.conversationId = String(conversationId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(192))
    self.risk = String(risk.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
    self.permissions = Array(Set(permissions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    self.permissionMode = String(permissionMode.trimmingCharacters(in: .whitespacesAndNewlines).prefix(96))
    self.permissionDecision = String(permissionDecision.trimmingCharacters(in: .whitespacesAndNewlines).prefix(128))
    self.parameterPreview = AgentMcpParameterRedactor.sanitize(parameterPreview)
    self.inputSha256 = String(inputSha256.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
    self.status = String(status.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
    self.durationMillis = max(0, durationMillis)
    self.outputSha256 = String(outputSha256.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
    self.errorCode = String(errorCode.trimmingCharacters(in: .whitespacesAndNewlines).prefix(128))
    self.errorMessage = AgentMcpParameterRedactor.sanitizeText(errorMessage)
  }

  static func toolCall(
    connection: AgentMcpConnection,
    toolName: String,
    assessment: AgentMcpToolAssessment,
    decision: AgentMcpPermissionDecision,
    context: AgentNativeToolInvocationContext,
    status: String,
    durationMillis: Int64,
    outputSha256: String = "",
    errorCode: String = "",
    errorMessage: String = "",
    auditId: String = UUID().uuidString,
    timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> AgentMcpAuditRecord {
    AgentMcpAuditRecord(
      auditId: auditId,
      timestampMillis: timestampMillis,
      connectionId: connection.id,
      connectionName: connection.displayName,
      toolName: toolName,
      transport: connection.transport.rawValue,
      source: "ios-mcp:\(connection.id)",
      callerId: context.callerId,
      taskId: context.attributes["task_id"] ?? "",
      conversationId: context.conversationId,
      risk: assessment.risk.rawValue,
      permissions: assessment.permissions.sorted(),
      permissionMode: connection.permissionMode.rawValue,
      permissionDecision: decision.code,
      parameterPreview: assessment.parameterPreview,
      inputSha256: assessment.inputSha256,
      status: status,
      durationMillis: durationMillis,
      outputSha256: outputSha256,
      errorCode: errorCode,
      errorMessage: errorMessage
    )
  }

  enum CodingKeys: String, CodingKey {
    case auditId = "audit_id"
    case timestampMillis = "timestamp_ms"
    case connectionId = "connection_id"
    case connectionName = "connection_name"
    case toolName = "tool_name"
    case transport
    case source
    case callerId = "caller_id"
    case taskId = "task_id"
    case conversationId = "conversation_id"
    case risk
    case permissions
    case permissionMode = "permission_mode"
    case permissionDecision = "permission_decision"
    case parameterPreview = "parameter_preview"
    case inputSha256 = "input_sha256"
    case status
    case durationMillis = "duration_ms"
    case outputSha256 = "output_sha256"
    case errorCode = "error_code"
    case errorMessage = "error_message"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      auditId: try container.decodeIfPresent(String.self, forKey: .auditId) ?? UUID().uuidString,
      timestampMillis: try container.decodeIfPresent(Int64.self, forKey: .timestampMillis) ?? 0,
      connectionId: try container.decodeIfPresent(String.self, forKey: .connectionId) ?? "",
      connectionName: try container.decodeIfPresent(String.self, forKey: .connectionName) ?? "",
      toolName: try container.decodeIfPresent(String.self, forKey: .toolName) ?? "",
      transport: try container.decodeIfPresent(String.self, forKey: .transport) ?? "",
      source: try container.decodeIfPresent(String.self, forKey: .source) ?? "",
      callerId: try container.decodeIfPresent(String.self, forKey: .callerId) ?? "",
      taskId: try container.decodeIfPresent(String.self, forKey: .taskId) ?? "",
      conversationId: try container.decodeIfPresent(String.self, forKey: .conversationId) ?? "",
      risk: try container.decodeIfPresent(String.self, forKey: .risk) ?? "",
      permissions: try container.decodeIfPresent([String].self, forKey: .permissions) ?? [],
      permissionMode: try container.decodeIfPresent(String.self, forKey: .permissionMode) ?? "",
      permissionDecision: try container.decodeIfPresent(String.self, forKey: .permissionDecision) ?? "",
      parameterPreview: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .parameterPreview) ?? [:],
      inputSha256: try container.decodeIfPresent(String.self, forKey: .inputSha256) ?? "",
      status: try container.decodeIfPresent(String.self, forKey: .status) ?? "",
      durationMillis: try container.decodeIfPresent(Int64.self, forKey: .durationMillis) ?? 0,
      outputSha256: try container.decodeIfPresent(String.self, forKey: .outputSha256) ?? "",
      errorCode: try container.decodeIfPresent(String.self, forKey: .errorCode) ?? "",
      errorMessage: try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? ""
    )
  }
}

protocol AgentMcpAuditStore {
  func append(_ record: AgentMcpAuditRecord)
  func list(connectionId: String, limit: Int) -> [AgentMcpAuditRecord]
  func clear(connectionId: String) -> Int
}

final class InMemoryAgentMcpAuditStore: AgentMcpAuditStore {
  private let lock = NSRecursiveLock()
  private var records: [AgentMcpAuditRecord] = []

  func append(_ record: AgentMcpAuditRecord) {
    synchronized {
      records.append(record)
      if records.count > Self.maxRecords {
        records.removeFirst(records.count - Self.maxRecords)
      }
    }
  }

  func list(connectionId: String = "", limit: Int = 100) -> [AgentMcpAuditRecord] {
    synchronized {
      let cleanConnectionId = connectionId.trimmingCharacters(in: .whitespacesAndNewlines)
      return Array(records
        .filter { cleanConnectionId.isEmpty || $0.connectionId == cleanConnectionId }
        .suffix(min(max(limit, 1), 500))
        .reversed())
    }
  }

  func clear(connectionId: String = "") -> Int {
    synchronized {
      let cleanConnectionId = connectionId.trimmingCharacters(in: .whitespacesAndNewlines)
      let before = records.count
      if cleanConnectionId.isEmpty {
        records.removeAll()
      } else {
        records.removeAll { $0.connectionId == cleanConnectionId }
      }
      return before - records.count
    }
  }

  private func synchronized<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  static let maxRecords = 1_000
}

final class FileAgentMcpAuditStore: AgentMcpAuditStore {
  private let fileURL: URL
  private let fileManager: FileManager
  private let lock = NSRecursiveLock()

  init(directory: URL, fileName: String = "agent-mcp-audit.json", fileManager: FileManager = .default) {
    self.fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
    self.fileManager = fileManager
  }

  init(fileURL: URL, fileManager: FileManager = .default) {
    self.fileURL = fileURL
    self.fileManager = fileManager
  }

  func append(_ record: AgentMcpAuditRecord) {
    synchronized {
      var records = readRecords()
      records.append(record)
      writeRecords(Array(records.suffix(InMemoryAgentMcpAuditStore.maxRecords)))
    }
  }

  func list(connectionId: String = "", limit: Int = 100) -> [AgentMcpAuditRecord] {
    synchronized {
      let cleanConnectionId = connectionId.trimmingCharacters(in: .whitespacesAndNewlines)
      return Array(readRecords()
        .filter { cleanConnectionId.isEmpty || $0.connectionId == cleanConnectionId }
        .suffix(min(max(limit, 1), 500))
        .reversed())
    }
  }

  func clear(connectionId: String = "") -> Int {
    synchronized {
      let cleanConnectionId = connectionId.trimmingCharacters(in: .whitespacesAndNewlines)
      let records = readRecords()
      let kept = cleanConnectionId.isEmpty ? [] : records.filter { $0.connectionId != cleanConnectionId }
      writeRecords(kept)
      return records.count - kept.count
    }
  }

  private func readRecords() -> [AgentMcpAuditRecord] {
    guard fileManager.fileExists(atPath: fileURL.path),
          let document = try? String(contentsOf: fileURL, encoding: .utf8) else {
      return []
    }
    return AgentMcpAuditCodec.decode(document)
  }

  private func writeRecords(_ records: [AgentMcpAuditRecord]) {
    do {
      try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try AgentMcpAuditCodec.encode(records).write(to: fileURL, atomically: true, encoding: .utf8)
    } catch {
      return
    }
  }

  private func synchronized<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}

enum AgentMcpAuditCodec {
  static func emptyDocument() -> String {
    #"{"version":1,"records":[]}"#
  }

  static func encode(_ records: [AgentMcpAuditRecord]) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let document = AgentMcpAuditDocument(version: 1, records: Array(records.suffix(InMemoryAgentMcpAuditStore.maxRecords)))
    guard let data = try? encoder.encode(document) else {
      return emptyDocument()
    }
    return String(decoding: data, as: UTF8.self)
  }

  static func decode(_ document: String) -> [AgentMcpAuditRecord] {
    guard let data = document.data(using: .utf8),
          let decoded = try? JSONDecoder().decode(AgentMcpAuditDocument.self, from: data),
          decoded.version == 1 else {
      return []
    }
    return Array(decoded.records
      .filter {
        !$0.connectionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
          !$0.toolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
      .suffix(InMemoryAgentMcpAuditStore.maxRecords))
  }

  private struct AgentMcpAuditDocument: Codable {
    var version: Int
    var records: [AgentMcpAuditRecord]
  }
}
