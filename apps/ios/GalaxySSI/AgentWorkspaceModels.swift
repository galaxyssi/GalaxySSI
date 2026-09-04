import CryptoKit
import Foundation

enum AgentWorkspaceStatus: String, Codable, CaseIterable, Identifiable {
  case created = "CREATED"
  case queued = "QUEUED"
  case running = "RUNNING"
  case waitingConfirmation = "WAITING_CONFIRMATION"
  case waitingResponse = "WAITING_RESPONSE"
  case paused = "PAUSED"
  case blocked = "BLOCKED"
  case completed = "COMPLETED"
  case failed = "FAILED"
  case cancelled = "CANCELLED"

  var id: String { rawValue }

  var isTerminal: Bool {
    [.completed, .failed, .cancelled].contains(self)
  }

  static func fromWireValue(_ value: String?) -> AgentWorkspaceStatus {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .created
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentTaskEventKinds {
  static let queued = "task.queued"
  static let resumed = "task.resumed"
  static let running = "task.running"
  static let completed = "task.completed"
  static let failed = "task.failed"
  static let cancelled = "task.cancelled"
  static let interrupted = "task.interrupted"
  static let checkpoint = "task.checkpoint"
  static let waitingConfirmation = "task.waiting_confirmation"
  static let waitingResponse = "task.waiting_response"
  static let recoveryWaitingResponse = "task.recovery_waiting_response"
  static let paused = "task.paused"
  static let blocked = "task.blocked"
  static let snapshot = "task.execution_snapshot"
  static let permissionRevoked = "task.permission_revoked"
  static let heartbeat = "task.heartbeat"
  static let progress = "task.progress"
  static let stalled = "task.stalled"
  static let timedOut = "task.timed_out"
  static let livenessAssessmentRequested = "task.liveness_assessment_requested"
  static let lateResponse = "task.late_response"
  static let recoveredInterrupted = "task.recovered_interrupted"
}

struct AgentWorkspaceKey: Codable, Equatable {
  var workspaceId: String
  var sessionId: String
  var conversationId: String
  var taskId: String

  enum CodingKeys: String, CodingKey {
    case workspaceId = "workspace_id"
    case sessionId = "session_id"
    case conversationId = "conversation_id"
    case taskId = "task_id"
  }
}

struct AgentWorkspaceEvent: Codable, Equatable {
  var sequence: Int64
  var kind: String
  var message: String
  var payloadJson: String
  var timestampMillis: Int64

  init(
    sequence: Int64 = 0,
    kind: String,
    message: String = "",
    payloadJson: String = "",
    timestampMillis: Int64 = 0
  ) {
    self.sequence = sequence
    self.kind = kind
    self.message = message
    self.payloadJson = payloadJson
    self.timestampMillis = timestampMillis
  }

  enum CodingKeys: String, CodingKey {
    case sequence
    case kind
    case message
    case payloadJson = "payload_json"
    case timestampMillis = "timestamp_millis"
  }

  private enum LegacyCodingKeys: String, CodingKey {
    case timestamp
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sequence = try container.decodeIfPresent(Int64.self, forKey: .sequence) ?? 0
    kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
    message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
    payloadJson = try container.decodeIfPresent(String.self, forKey: .payloadJson) ?? ""
    let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
    timestampMillis = try container.decodeIfPresent(Int64.self, forKey: .timestampMillis) ??
      legacyContainer.decodeIfPresent(Int64.self, forKey: .timestamp) ?? 0
  }
}

struct AgentWorkspace: Codable, Equatable, Identifiable {
  var workspaceId: String
  var sessionId: String
  var conversationId: String
  var taskId: String
  var goal: String
  var parentRunId: String
  var agentId: String
  var deviceId: String
  var remoteRunId: String
  var deliveryMode: String
  var status: AgentWorkspaceStatus
  var currentPlanSnapshot: String
  var resultJson: String
  var errorMessage: String
  var permissionGrantIds: [String]
  var permissionScopes: [String]
  var handoffIds: [String]
  var lastRemoteEventSequence: Int64
  var eventSequence: Int64
  var eventJournal: [AgentWorkspaceEvent]
  var toolCalls: [AgentWorkspaceToolCallRecord]
  var checkpoints: [AgentWorkspaceCheckpoint]
  var artifacts: [AgentWorkspaceArtifactReference]
  var cancellationRequested: Bool
  var createdAtMillis: Int64
  var updatedAtMillis: Int64
  var revision: Int64

  var id: String { workspaceId }

  var key: AgentWorkspaceKey {
    AgentWorkspaceKey(
      workspaceId: workspaceId,
      sessionId: sessionId,
      conversationId: conversationId,
      taskId: taskId
    )
  }

  init(
    workspaceId: String,
    sessionId: String,
    conversationId: String,
    taskId: String,
    goal: String = "",
    parentRunId: String = "",
    agentId: String = "",
    deviceId: String = "",
    remoteRunId: String = "",
    deliveryMode: String = AgentDeliveryMode.respond.rawValue,
    status: AgentWorkspaceStatus = .created,
    currentPlanSnapshot: String = "",
    resultJson: String = "{}",
    errorMessage: String = "",
    permissionGrantIds: [String] = [],
    permissionScopes: [String] = [],
    handoffIds: [String] = [],
    lastRemoteEventSequence: Int64 = 0,
    eventSequence: Int64 = 0,
    eventJournal: [AgentWorkspaceEvent] = [],
    toolCalls: [AgentWorkspaceToolCallRecord] = [],
    checkpoints: [AgentWorkspaceCheckpoint] = [],
    artifacts: [AgentWorkspaceArtifactReference] = [],
    cancellationRequested: Bool = false,
    createdAtMillis: Int64 = 0,
    updatedAtMillis: Int64 = 0,
    revision: Int64 = 0
  ) {
    self.workspaceId = workspaceId
    self.sessionId = sessionId
    self.conversationId = conversationId
    self.taskId = taskId
    self.goal = goal
    self.parentRunId = parentRunId
    self.agentId = agentId
    self.deviceId = deviceId
    self.remoteRunId = remoteRunId
    self.deliveryMode = deliveryMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? AgentDeliveryMode.respond.rawValue
      : deliveryMode.trimmingCharacters(in: .whitespacesAndNewlines)
    self.status = status
    self.currentPlanSnapshot = currentPlanSnapshot
    self.resultJson = resultJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}" : resultJson
    self.errorMessage = errorMessage
    self.permissionGrantIds = Self.cleanList(permissionGrantIds)
    self.permissionScopes = Self.cleanList(permissionScopes)
    self.handoffIds = Self.cleanList(handoffIds)
    self.lastRemoteEventSequence = max(lastRemoteEventSequence, 0)
    self.eventSequence = eventSequence
    self.eventJournal = eventJournal
    self.toolCalls = toolCalls
    self.checkpoints = checkpoints
    self.artifacts = artifacts
    self.cancellationRequested = cancellationRequested
    self.createdAtMillis = createdAtMillis
    self.updatedAtMillis = updatedAtMillis
    self.revision = revision
  }

  enum CodingKeys: String, CodingKey {
    case workspaceId = "workspace_id"
    case sessionId = "session_id"
    case conversationId = "conversation_id"
    case taskId = "task_id"
    case goal
    case parentRunId = "parent_run_id"
    case agentId = "agent_id"
    case deviceId = "device_id"
    case remoteRunId = "remote_run_id"
    case deliveryMode = "delivery_mode"
    case status
    case currentPlanSnapshot = "current_plan_snapshot"
    case resultJson = "result_json"
    case errorMessage = "error_message"
    case permissionGrantIds = "permission_grant_ids"
    case permissionScopes = "permission_scopes"
    case handoffIds = "handoff_ids"
    case lastRemoteEventSequence = "last_remote_event_sequence"
    case eventSequence = "event_sequence"
    case eventJournal = "event_journal"
    case toolCalls = "tool_calls"
    case checkpoints
    case artifacts
    case cancellationRequested = "cancellation_requested"
    case createdAtMillis = "created_at_millis"
    case updatedAtMillis = "updated_at_millis"
    case revision
  }

  private enum LegacyCodingKeys: String, CodingKey {
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId) ?? ""
    sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
    conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId) ?? ""
    taskId = try container.decodeIfPresent(String.self, forKey: .taskId) ?? ""
    goal = try container.decodeIfPresent(String.self, forKey: .goal) ?? ""
    parentRunId = try container.decodeIfPresent(String.self, forKey: .parentRunId) ?? ""
    agentId = try container.decodeIfPresent(String.self, forKey: .agentId) ?? ""
    deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
    remoteRunId = try container.decodeIfPresent(String.self, forKey: .remoteRunId) ?? ""
    let rawDeliveryMode = try container.decodeIfPresent(String.self, forKey: .deliveryMode) ?? ""
    deliveryMode = rawDeliveryMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? AgentDeliveryMode.respond.rawValue
      : rawDeliveryMode.trimmingCharacters(in: .whitespacesAndNewlines)
    status = try container.decodeIfPresent(AgentWorkspaceStatus.self, forKey: .status) ?? .created
    currentPlanSnapshot = try container.decodeIfPresent(String.self, forKey: .currentPlanSnapshot) ?? ""
    let rawResultJson = try container.decodeIfPresent(String.self, forKey: .resultJson) ?? ""
    resultJson = rawResultJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}" : rawResultJson
    errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? ""
    permissionGrantIds = Self.cleanList(try container.decodeIfPresent([String].self, forKey: .permissionGrantIds) ?? [])
    permissionScopes = Self.cleanList(try container.decodeIfPresent([String].self, forKey: .permissionScopes) ?? [])
    handoffIds = Self.cleanList(try container.decodeIfPresent([String].self, forKey: .handoffIds) ?? [])
    lastRemoteEventSequence = max(try container.decodeIfPresent(Int64.self, forKey: .lastRemoteEventSequence) ?? 0, 0)
    eventSequence = try container.decodeIfPresent(Int64.self, forKey: .eventSequence) ?? 0
    eventJournal = try container.decodeIfPresent([AgentWorkspaceEvent].self, forKey: .eventJournal) ?? []
    toolCalls = try container.decodeIfPresent([AgentWorkspaceToolCallRecord].self, forKey: .toolCalls) ?? []
    checkpoints = try container.decodeIfPresent([AgentWorkspaceCheckpoint].self, forKey: .checkpoints) ?? []
    artifacts = try container.decodeIfPresent([AgentWorkspaceArtifactReference].self, forKey: .artifacts) ?? []
    cancellationRequested = try container.decodeIfPresent(Bool.self, forKey: .cancellationRequested) ?? false
    let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
    createdAtMillis = try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ??
      legacyContainer.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
    updatedAtMillis = try container.decodeIfPresent(Int64.self, forKey: .updatedAtMillis) ??
      legacyContainer.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
    revision = try container.decodeIfPresent(Int64.self, forKey: .revision) ?? 0
  }

  private static func cleanList(_ values: [String]) -> [String] {
    values
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}

enum AgentWorkspaceFileErrorCode: String, Codable, CaseIterable, Identifiable {
  case invalidWorkspace = "INVALID_WORKSPACE"
  case invalidPath = "INVALID_PATH"
  case pathEscape = "PATH_ESCAPE"
  case symlinkRejected = "SYMLINK_REJECTED"
  case notFound = "NOT_FOUND"
  case alreadyExists = "ALREADY_EXISTS"
  case notAFile = "NOT_A_FILE"
  case notADirectory = "NOT_A_DIRECTORY"
  case directoryNotEmpty = "DIRECTORY_NOT_EMPTY"
  case unsupportedFileType = "UNSUPPORTED_FILE_TYPE"
  case invalidText = "INVALID_TEXT"
  case limitExceeded = "LIMIT_EXCEEDED"
  case patchMismatch = "PATCH_MISMATCH"
  case invalidArchive = "INVALID_ARCHIVE"
  case accessDenied = "ACCESS_DENIED"
  case ioError = "IO_ERROR"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentWorkspaceFileErrorCode {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .ioError
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentWorkspaceFileError: Codable, Equatable {
  var code: AgentWorkspaceFileErrorCode
  var operation: String
  var path: String
  var message: String

  init(
    code: AgentWorkspaceFileErrorCode,
    operation: String,
    path: String,
    message: String
  ) {
    self.code = code
    self.operation = operation
    self.path = path
    self.message = String(message.prefix(Self.maximumMessageLength))
  }

  private static let maximumMessageLength = 300
}

enum AgentWorkspaceFileResult<Value: Equatable>: Equatable {
  case success(Value)
  case failure(AgentWorkspaceFileError)

  var successful: Bool {
    if case .success = self { return true }
    return false
  }

  var value: Value? {
    if case .success(let value) = self { return value }
    return nil
  }

  var error: AgentWorkspaceFileError? {
    if case .failure(let error) = self { return error }
    return nil
  }
}

struct AgentWorkspaceFilePolicy: Codable, Equatable {
  var maxTextReadBytes: Int64
  var maxBytesReadBytes: Int64
  var maxWriteBytes: Int64
  var maxListEntries: Int
  var maxTreeEntries: Int
  var maxSearchFileBytes: Int64
  var maxSearchTotalBytes: Int64
  var maxSearchResults: Int
  var maxPatchBytes: Int64
  var maxHashBytes: Int64
  var maxZipArchiveBytes: Int64
  var maxZipEntries: Int
  var maxZipEntryBytes: Int64
  var maxZipUncompressedBytes: Int64
  var maxZipCompressionRatio: Double
  var maxZipEntryNameCharacters: Int

  init(
    maxTextReadBytes: Int64 = 1 * 1_024 * 1_024,
    maxBytesReadBytes: Int64 = 8 * 1_024 * 1_024,
    maxWriteBytes: Int64 = 16 * 1_024 * 1_024,
    maxListEntries: Int = 10_000,
    maxTreeEntries: Int = 20_000,
    maxSearchFileBytes: Int64 = 1 * 1_024 * 1_024,
    maxSearchTotalBytes: Int64 = 16 * 1_024 * 1_024,
    maxSearchResults: Int = 500,
    maxPatchBytes: Int64 = 2 * 1_024 * 1_024,
    maxHashBytes: Int64 = 128 * 1_024 * 1_024,
    maxZipArchiveBytes: Int64 = 64 * 1_024 * 1_024,
    maxZipEntries: Int = 2_048,
    maxZipEntryBytes: Int64 = 16 * 1_024 * 1_024,
    maxZipUncompressedBytes: Int64 = 64 * 1_024 * 1_024,
    maxZipCompressionRatio: Double = 100,
    maxZipEntryNameCharacters: Int = 512
  ) {
    self.maxTextReadBytes = Self.positive(maxTextReadBytes)
    self.maxBytesReadBytes = Self.positive(maxBytesReadBytes)
    self.maxWriteBytes = Self.positive(maxWriteBytes)
    self.maxListEntries = Self.positive(maxListEntries)
    self.maxTreeEntries = Self.positive(maxTreeEntries)
    self.maxSearchFileBytes = Self.positive(maxSearchFileBytes)
    self.maxSearchTotalBytes = Self.positive(maxSearchTotalBytes)
    self.maxSearchResults = Self.positive(maxSearchResults)
    self.maxPatchBytes = Self.positive(maxPatchBytes)
    self.maxHashBytes = Self.positive(maxHashBytes)
    self.maxZipArchiveBytes = Self.positive(maxZipArchiveBytes)
    self.maxZipEntries = Self.positive(maxZipEntries)
    self.maxZipEntryBytes = Self.positive(maxZipEntryBytes)
    self.maxZipUncompressedBytes = Self.positive(maxZipUncompressedBytes)
    self.maxZipCompressionRatio = maxZipCompressionRatio.isFinite ? max(maxZipCompressionRatio, 1) : 100
    self.maxZipEntryNameCharacters = Self.positive(maxZipEntryNameCharacters)
  }

  enum CodingKeys: String, CodingKey {
    case maxTextReadBytes = "max_text_read_bytes"
    case maxBytesReadBytes = "max_bytes_read_bytes"
    case maxWriteBytes = "max_write_bytes"
    case maxListEntries = "max_list_entries"
    case maxTreeEntries = "max_tree_entries"
    case maxSearchFileBytes = "max_search_file_bytes"
    case maxSearchTotalBytes = "max_search_total_bytes"
    case maxSearchResults = "max_search_results"
    case maxPatchBytes = "max_patch_bytes"
    case maxHashBytes = "max_hash_bytes"
    case maxZipArchiveBytes = "max_zip_archive_bytes"
    case maxZipEntries = "max_zip_entries"
    case maxZipEntryBytes = "max_zip_entry_bytes"
    case maxZipUncompressedBytes = "max_zip_uncompressed_bytes"
    case maxZipCompressionRatio = "max_zip_compression_ratio"
    case maxZipEntryNameCharacters = "max_zip_entry_name_characters"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      maxTextReadBytes: try container.decodeIfPresent(Int64.self, forKey: .maxTextReadBytes) ?? 1 * 1_024 * 1_024,
      maxBytesReadBytes: try container.decodeIfPresent(Int64.self, forKey: .maxBytesReadBytes) ?? 8 * 1_024 * 1_024,
      maxWriteBytes: try container.decodeIfPresent(Int64.self, forKey: .maxWriteBytes) ?? 16 * 1_024 * 1_024,
      maxListEntries: try container.decodeIfPresent(Int.self, forKey: .maxListEntries) ?? 10_000,
      maxTreeEntries: try container.decodeIfPresent(Int.self, forKey: .maxTreeEntries) ?? 20_000,
      maxSearchFileBytes: try container.decodeIfPresent(Int64.self, forKey: .maxSearchFileBytes) ?? 1 * 1_024 * 1_024,
      maxSearchTotalBytes: try container.decodeIfPresent(Int64.self, forKey: .maxSearchTotalBytes) ?? 16 * 1_024 * 1_024,
      maxSearchResults: try container.decodeIfPresent(Int.self, forKey: .maxSearchResults) ?? 500,
      maxPatchBytes: try container.decodeIfPresent(Int64.self, forKey: .maxPatchBytes) ?? 2 * 1_024 * 1_024,
      maxHashBytes: try container.decodeIfPresent(Int64.self, forKey: .maxHashBytes) ?? 128 * 1_024 * 1_024,
      maxZipArchiveBytes: try container.decodeIfPresent(Int64.self, forKey: .maxZipArchiveBytes) ?? 64 * 1_024 * 1_024,
      maxZipEntries: try container.decodeIfPresent(Int.self, forKey: .maxZipEntries) ?? 2_048,
      maxZipEntryBytes: try container.decodeIfPresent(Int64.self, forKey: .maxZipEntryBytes) ?? 16 * 1_024 * 1_024,
      maxZipUncompressedBytes: try container.decodeIfPresent(Int64.self, forKey: .maxZipUncompressedBytes) ?? 64 * 1_024 * 1_024,
      maxZipCompressionRatio: try container.decodeIfPresent(Double.self, forKey: .maxZipCompressionRatio) ?? 100,
      maxZipEntryNameCharacters: try container.decodeIfPresent(Int.self, forKey: .maxZipEntryNameCharacters) ?? 512
    )
  }

  private static func positive(_ value: Int) -> Int {
    max(value, 1)
  }

  private static func positive(_ value: Int64) -> Int64 {
    max(value, 1)
  }
}

enum AgentWorkspaceEntryType: String, Codable, CaseIterable, Identifiable {
  case file = "FILE"
  case directory = "DIRECTORY"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentWorkspaceEntryType {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .file
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentWorkspaceMutationKind: String, Codable, CaseIterable, Identifiable {
  case initialize = "INITIALIZE"
  case mkdir = "MKDIR"
  case write = "WRITE"
  case create = "CREATE"
  case append = "APPEND"
  case move = "MOVE"
  case copy = "COPY"
  case delete = "DELETE"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentWorkspaceMutationKind {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .write
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentWorkspaceFileMetadata: Codable, Equatable {
  var path: String
  var type: AgentWorkspaceEntryType
  var sizeBytes: Int64
  var lastModifiedMillis: Int64

  init(
    path: String,
    type: AgentWorkspaceEntryType,
    sizeBytes: Int64,
    lastModifiedMillis: Int64 = 0
  ) {
    self.path = AgentWorkspaceFilePathPolicy.displayPath(path)
    self.type = type
    self.sizeBytes = max(sizeBytes, 0)
    self.lastModifiedMillis = max(lastModifiedMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case path
    case type
    case sizeBytes = "size_bytes"
    case lastModifiedMillis = "last_modified_millis"
  }
}

struct AgentWorkspaceMutation: Codable, Equatable {
  var kind: AgentWorkspaceMutationKind
  var path: String
  var sourcePath: String
  var affectedEntries: Int
  var affectedBytes: Int64
  var metadata: AgentWorkspaceFileMetadata?

  init(
    kind: AgentWorkspaceMutationKind,
    path: String,
    sourcePath: String = "",
    affectedEntries: Int = 1,
    affectedBytes: Int64 = 0,
    metadata: AgentWorkspaceFileMetadata? = nil
  ) {
    self.kind = kind
    self.path = AgentWorkspaceFilePathPolicy.displayPath(path)
    self.sourcePath = AgentWorkspaceFilePathPolicy.displayPath(sourcePath)
    self.affectedEntries = max(affectedEntries, 0)
    self.affectedBytes = max(affectedBytes, 0)
    self.metadata = metadata
  }

  enum CodingKeys: String, CodingKey {
    case kind
    case path
    case sourcePath = "source_path"
    case affectedEntries = "affected_entries"
    case affectedBytes = "affected_bytes"
    case metadata
  }
}

struct AgentWorkspaceDirectoryListing: Codable, Equatable {
  var path: String
  var recursive: Bool
  var entries: [AgentWorkspaceFileMetadata]
}

struct AgentWorkspaceTextRead: Codable, Equatable {
  var path: String
  var text: String
  var sizeBytes: Int64
  var sha256: String

  enum CodingKeys: String, CodingKey {
    case path
    case text
    case sizeBytes = "size_bytes"
    case sha256
  }
}

struct AgentWorkspaceSearchMatch: Codable, Equatable {
  var path: String
  var line: Int
  var column: Int
  var excerpt: String
}

struct AgentWorkspaceTextSearchResult: Codable, Equatable {
  var query: String
  var matches: [AgentWorkspaceSearchMatch]
  var scannedFiles: Int
  var skippedFiles: Int
  var scannedBytes: Int64
  var truncated: Bool

  enum CodingKeys: String, CodingKey {
    case query
    case matches
    case scannedFiles = "scanned_files"
    case skippedFiles = "skipped_files"
    case scannedBytes = "scanned_bytes"
    case truncated
  }
}

struct AgentWorkspaceDiffSummary: Codable, Equatable {
  var beforeSha256: String
  var afterSha256: String
  var beforeBytes: Int64
  var afterBytes: Int64
  var beforeLines: Int
  var afterLines: Int
  var addedLines: Int
  var deletedLines: Int
  var changedLinePairs: Int
  var firstChangedLine: Int?

  enum CodingKeys: String, CodingKey {
    case beforeSha256 = "before_sha256"
    case afterSha256 = "after_sha256"
    case beforeBytes = "before_bytes"
    case afterBytes = "after_bytes"
    case beforeLines = "before_lines"
    case afterLines = "after_lines"
    case addedLines = "added_lines"
    case deletedLines = "deleted_lines"
    case changedLinePairs = "changed_line_pairs"
    case firstChangedLine = "first_changed_line"
  }
}

struct AgentWorkspacePatchResult: Codable, Equatable {
  var path: String
  var replacements: Int
  var diff: AgentWorkspaceDiffSummary
  var metadata: AgentWorkspaceFileMetadata
}

struct AgentWorkspaceDigest: Codable, Equatable {
  var path: String
  var algorithm: String
  var hex: String
  var sizeBytes: Int64

  enum CodingKeys: String, CodingKey {
    case path
    case algorithm
    case hex
    case sizeBytes = "size_bytes"
  }
}

struct AgentWorkspaceZipEntryMetadata: Codable, Equatable {
  var path: String
  var directory: Bool
  var compressedBytes: Int64
  var uncompressedBytes: Int64
  var compressionRatio: Double
  var crc32: Int64
  var lastModifiedMillis: Int64

  enum CodingKeys: String, CodingKey {
    case path
    case directory
    case compressedBytes = "compressed_bytes"
    case uncompressedBytes = "uncompressed_bytes"
    case compressionRatio = "compression_ratio"
    case crc32
    case lastModifiedMillis = "last_modified_millis"
  }
}

struct AgentWorkspaceZipListing: Codable, Equatable {
  var archivePath: String
  var archiveBytes: Int64
  var totalCompressedBytes: Int64
  var totalUncompressedBytes: Int64
  var entries: [AgentWorkspaceZipEntryMetadata]

  enum CodingKeys: String, CodingKey {
    case archivePath = "archive_path"
    case archiveBytes = "archive_bytes"
    case totalCompressedBytes = "total_compressed_bytes"
    case totalUncompressedBytes = "total_uncompressed_bytes"
    case entries
  }
}

struct AgentWorkspaceZipExtraction: Codable, Equatable {
  var archivePath: String
  var destinationPath: String
  var extractedEntries: Int
  var extractedBytes: Int64

  enum CodingKeys: String, CodingKey {
    case archivePath = "archive_path"
    case destinationPath = "destination_path"
    case extractedEntries = "extracted_entries"
    case extractedBytes = "extracted_bytes"
  }
}

enum AgentWorkspaceFilePathPolicy {
  static func workspaceDirectoryName(_ workspaceId: String) -> AgentWorkspaceFileResult<String> {
    let pattern = #"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"#
    guard workspaceId.range(of: pattern, options: .regularExpression) != nil else {
      return .failure(
        AgentWorkspaceFileError(
          code: .invalidWorkspace,
          operation: "workspace_directory_name",
          path: workspaceId,
          message: "Workspace ID must be 1-64 ASCII letters, digits, dots, underscores, or hyphens"
        )
      )
    }
    return .success(workspaceId)
  }

  static func normalizeRelativePath(_ input: String, allowRoot: Bool = true) -> AgentWorkspaceFileResult<[String]> {
    guard !input.contains("\u{0000}") else {
      return invalidPath(input, "Path contains a null character")
    }
    let portable = input.replacingOccurrences(of: "\\", with: "/")
    if portable.hasPrefix("/") || portable.hasPrefix("//") || portable.range(of: #"^[A-Za-z]:"#, options: .regularExpression) != nil {
      return pathEscape(input, "Absolute paths are not allowed")
    }
    let segments = portable.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    if segments.contains("..") {
      return pathEscape(input, "Parent traversal is not allowed")
    }
    let normalized = segments.filter { !$0.isEmpty && $0 != "." }
    if !allowRoot && normalized.isEmpty {
      return invalidPath(input, "Operation requires a non-root path")
    }
    return .success(normalized)
  }

  static func normalizeArchiveEntry(
    _ name: String,
    policy: AgentWorkspaceFilePolicy = AgentWorkspaceFilePolicy()
  ) -> AgentWorkspaceFileResult<String> {
    guard name.count <= policy.maxZipEntryNameCharacters else {
      return invalidArchive(name, "ZIP entry name is too long")
    }
    guard !name.contains("\u{0000}") else {
      return invalidArchive(name, "ZIP entry contains a null character")
    }
    var portable = name
    while portable.hasSuffix("/") || portable.hasSuffix("\\") {
      portable.removeLast()
    }
    portable = portable.replacingOccurrences(of: "\\", with: "/")
    if portable.hasPrefix("/") || portable.hasPrefix("//") || portable.range(of: #"^[A-Za-z]:"#, options: .regularExpression) != nil {
      return invalidArchive(name, "ZIP entry uses an absolute path")
    }
    let segments = portable.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    if segments.contains("..") {
      return invalidArchive(name, "ZIP entry contains parent traversal")
    }
    let normalized = segments.filter { !$0.isEmpty && $0 != "." }.joined(separator: "/")
    guard !normalized.isEmpty else {
      return invalidArchive(name, "ZIP entry has an empty path")
    }
    return .success(normalized)
  }

  static func displayPath(_ input: String) -> String {
    guard case .success(let segments) = normalizeRelativePath(input, allowRoot: true) else {
      return input.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return segments.joined(separator: "/")
  }

  private static func invalidPath<T: Equatable>(_ path: String, _ message: String) -> AgentWorkspaceFileResult<T> {
    .failure(AgentWorkspaceFileError(code: .invalidPath, operation: "normalize_path", path: path, message: message))
  }

  private static func pathEscape<T: Equatable>(_ path: String, _ message: String) -> AgentWorkspaceFileResult<T> {
    .failure(AgentWorkspaceFileError(code: .pathEscape, operation: "normalize_path", path: path, message: message))
  }

  private static func invalidArchive<T: Equatable>(_ path: String, _ message: String) -> AgentWorkspaceFileResult<T> {
    .failure(AgentWorkspaceFileError(code: .invalidArchive, operation: "normalize_archive_entry", path: path, message: message))
  }
}

enum AgentWorkspacePatchPolicy {
  static func countOccurrences(text: String, expected: String) -> Int {
    guard !expected.isEmpty else { return 0 }
    var count = 0
    var offset = text.startIndex
    while offset <= text.endIndex {
      guard let range = text.range(of: expected, range: offset..<text.endIndex) else {
        break
      }
      count += 1
      offset = range.upperBound
    }
    return count
  }

  static func replaceOccurrences(text: String, expected: String, replacement: String) -> String {
    guard !expected.isEmpty else { return text }
    var output = ""
    var offset = text.startIndex
    while let range = text.range(of: expected, range: offset..<text.endIndex) {
      output += String(text[offset..<range.lowerBound])
      output += replacement
      offset = range.upperBound
    }
    output += String(text[offset..<text.endIndex])
    return output
  }

  static func summarizeDiff(before: String, after: String) -> AgentWorkspaceDiffSummary {
    let beforeBytes = Data(before.utf8)
    let afterBytes = Data(after.utf8)
    let beforeLines = splitLines(before)
    let afterLines = splitLines(after)
    var prefix = 0
    while prefix < beforeLines.count && prefix < afterLines.count && beforeLines[prefix] == afterLines[prefix] {
      prefix += 1
    }
    var suffix = 0
    while suffix < beforeLines.count - prefix &&
      suffix < afterLines.count - prefix &&
      beforeLines[beforeLines.count - 1 - suffix] == afterLines[afterLines.count - 1 - suffix] {
      suffix += 1
    }
    let removed = beforeLines.count - prefix - suffix
    let added = afterLines.count - prefix - suffix
    return AgentWorkspaceDiffSummary(
      beforeSha256: sha256Hex(beforeBytes),
      afterSha256: sha256Hex(afterBytes),
      beforeBytes: Int64(beforeBytes.count),
      afterBytes: Int64(afterBytes.count),
      beforeLines: beforeLines.count,
      afterLines: afterLines.count,
      addedLines: max(0, added - removed),
      deletedLines: max(0, removed - added),
      changedLinePairs: min(removed, added),
      firstChangedLine: removed == 0 && added == 0 ? nil : prefix + 1
    )
  }

  private static func splitLines(_ text: String) -> [String] {
    text.isEmpty ? [] : text.components(separatedBy: "\n")
  }

  private static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
