import Foundation

struct AgentWorkspaceRevisionConflictError: LocalizedError, Equatable {
  var workspaceId: String
  var expectedRevision: Int64
  var actualRevision: Int64

  var errorDescription: String? {
    "Agent workspace revision conflict for \(workspaceId): expected \(expectedRevision), actual \(actualRevision)"
  }
}

protocol AgentWorkspaceStore {
  func list() -> [AgentWorkspace]
  func find(_ workspaceId: String) -> AgentWorkspace?
  func upsert(_ workspace: AgentWorkspace, expectedRevision: Int64) throws -> AgentWorkspace
  func appendEvent(
    workspaceId: String,
    event: AgentWorkspaceEvent,
    expectedRevision: Int64?
  ) throws -> AgentWorkspace?
  func checkpoint(
    workspaceId: String,
    checkpoint: AgentWorkspaceCheckpoint,
    expectedRevision: Int64?
  ) throws -> AgentWorkspace?
  func requestCancel(
    _ workspaceId: String,
    expectedRevision: Int64?,
    timestampMillis: Int64
  ) throws -> AgentWorkspace?
  func delete(_ workspaceId: String, expectedRevision: Int64?) throws -> Bool
  func clear()
  func recoverable() -> [AgentWorkspace]
}

extension AgentWorkspaceStore {
  func find(_ key: AgentWorkspaceKey) -> AgentWorkspace? {
    guard let workspace = find(key.workspaceId) else {
      return nil
    }
    return workspace.key == key ? workspace : nil
  }

  func upsert(_ workspace: AgentWorkspace) throws -> AgentWorkspace {
    try upsert(workspace, expectedRevision: workspace.revision)
  }

  func appendEvent(
    workspaceId: String,
    kind: String,
    message: String = "",
    payloadJson: String = "",
    expectedRevision: Int64? = nil,
    timestampMillis: Int64 = 0
  ) throws -> AgentWorkspace? {
    try appendEvent(
      workspaceId: workspaceId,
      event: AgentWorkspaceEvent(
        kind: kind,
        message: message,
        payloadJson: payloadJson,
        timestampMillis: timestampMillis
      ),
      expectedRevision: expectedRevision
    )
  }

  func checkpoint(
    workspaceId: String,
    checkpointId: String,
    planSnapshot: String = "",
    stateJson: String = "",
    expectedRevision: Int64? = nil,
    createdAtMillis: Int64 = 0
  ) throws -> AgentWorkspace? {
    try checkpoint(
      workspaceId: workspaceId,
      checkpoint: AgentWorkspaceCheckpoint(
        id: checkpointId,
        planSnapshot: planSnapshot,
        stateJson: stateJson,
        createdAtMillis: createdAtMillis
      ),
      expectedRevision: expectedRevision
    )
  }
}

final class InMemoryAgentWorkspaceStore: AgentWorkspaceStore {
  private var document: String
  private let clock: () -> Int64
  private let lock = NSRecursiveLock()

  init(
    initialWorkspaces: [AgentWorkspace] = [],
    clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    let fitted = (try? AgentWorkspaceStoreBounds.fitSerializedLimit(initialWorkspaces)) ?? []
    self.document = AgentWorkspaceJsonCodec.encodeList(fitted)
    self.clock = clock
  }

  convenience init(
    serialized: String,
    clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.init(initialWorkspaces: AgentWorkspaceJsonCodec.decodeList(serialized), clock: clock)
  }

  func list() -> [AgentWorkspace] {
    synchronized {
      Self.newestFirst(AgentWorkspaceJsonCodec.decodeList(document))
    }
  }

  func find(_ workspaceId: String) -> AgentWorkspace? {
    let cleanId = workspaceId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanId.isEmpty else { return nil }
    return synchronized {
      AgentWorkspaceJsonCodec.decodeList(document).first { $0.workspaceId == cleanId }
    }
  }

  func upsert(_ workspace: AgentWorkspace, expectedRevision: Int64) throws -> AgentWorkspace {
    try synchronized {
      guard let normalized = AgentWorkspaceBoundsPolicy.normalizeOrNil(workspace) else {
        throw AgentRuntimeCapabilityError.invalid("Agent workspace fields are invalid or exceed storage limits")
      }
      let items = AgentWorkspaceJsonCodec.decodeList(document)
      let existing = items.first { $0.workspaceId == normalized.workspaceId }
      let actualRevision = existing?.revision ?? 0
      try checkRevision(workspaceId: normalized.workspaceId, expected: expectedRevision, actual: actualRevision)
      guard actualRevision < Int64.max else {
        throw AgentRuntimeCapabilityError.invalid("Agent workspace revision exhausted")
      }
      if let existing {
        guard existing.key == normalized.key else {
          throw AgentRuntimeCapabilityError.invalid("Agent workspace identity fields cannot change")
        }
        guard normalized.eventSequence >= existing.eventSequence else {
          throw AgentRuntimeCapabilityError.invalid("Agent workspace event sequence cannot move backwards")
        }
      }

      let mutationTime = now()
      let createdAt = existing?.createdAtMillis ?? positive(normalized.createdAtMillis, fallback: mutationTime)
      var updated = normalized
      updated.createdAtMillis = createdAt
      updated.updatedAtMillis = max(createdAt, normalized.updatedAtMillis, existing?.updatedAtMillis ?? 0, mutationTime)
      updated.revision = actualRevision + 1
      try persist(items.filter { $0.workspaceId != updated.workspaceId } + [updated])
      return updated
    }
  }

  func appendEvent(
    workspaceId: String,
    event: AgentWorkspaceEvent,
    expectedRevision: Int64?
  ) throws -> AgentWorkspace? {
    try synchronized {
      let items = AgentWorkspaceJsonCodec.decodeList(document)
      guard let current = items.first(where: { $0.workspaceId == workspaceId.trimmingCharacters(in: .whitespacesAndNewlines) }) else {
        return nil
      }
      try checkRevisionIfPresent(current, expectedRevision)
      guard current.eventSequence < Int64.max, current.revision < Int64.max else {
        throw AgentRuntimeCapabilityError.invalid("Agent workspace counters are exhausted")
      }

      let mutationTime = now()
      let timestamp = positive(event.timestampMillis, fallback: mutationTime)
      guard let appended = AgentWorkspaceBoundsPolicy.normalizeEventOrNil(
        AgentWorkspaceEvent(
          sequence: current.eventSequence + 1,
          kind: event.kind,
          message: event.message,
          payloadJson: event.payloadJson,
          timestampMillis: timestamp
        )
      ) else {
        throw AgentRuntimeCapabilityError.invalid("Agent workspace event is invalid or exceeds storage limits")
      }
      var updated = current
      updated.eventSequence = appended.sequence
      updated.eventJournal = Array((current.eventJournal + [appended]).suffix(AgentWorkspaceBoundsPolicy.maxEvents))
      updated.updatedAtMillis = max(current.updatedAtMillis, timestamp, mutationTime)
      updated.revision = current.revision + 1
      try persist(items.filter { $0.workspaceId != current.workspaceId } + [updated])
      return updated
    }
  }

  func checkpoint(
    workspaceId: String,
    checkpoint: AgentWorkspaceCheckpoint,
    expectedRevision: Int64?
  ) throws -> AgentWorkspace? {
    try synchronized {
      let items = AgentWorkspaceJsonCodec.decodeList(document)
      guard let current = items.first(where: { $0.workspaceId == workspaceId.trimmingCharacters(in: .whitespacesAndNewlines) }) else {
        return nil
      }
      try checkRevisionIfPresent(current, expectedRevision)
      guard current.revision < Int64.max else {
        throw AgentRuntimeCapabilityError.invalid("Agent workspace revision exhausted")
      }

      let mutationTime = now()
      let timestamp = positive(checkpoint.createdAtMillis, fallback: mutationTime)
      let snapshot = checkpoint.planSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? current.currentPlanSnapshot
        : checkpoint.planSnapshot
      guard let normalized = AgentWorkspaceBoundsPolicy.normalizeCheckpointOrNil(
        AgentWorkspaceCheckpoint(
          id: checkpoint.id,
          eventSequence: current.eventSequence,
          planSnapshot: snapshot,
          stateJson: checkpoint.stateJson,
          createdAtMillis: timestamp
        )
      ) else {
        throw AgentRuntimeCapabilityError.invalid("Agent workspace checkpoint is invalid or exceeds storage limits")
      }
      var checkpoints = current.checkpoints.filter { $0.id != normalized.id } + [normalized]
      checkpoints.sort {
        if $0.eventSequence != $1.eventSequence { return $0.eventSequence < $1.eventSequence }
        if $0.createdAtMillis != $1.createdAtMillis { return $0.createdAtMillis < $1.createdAtMillis }
        return $0.id < $1.id
      }

      var updated = current
      updated.currentPlanSnapshot = normalized.planSnapshot
      updated.checkpoints = Array(checkpoints.suffix(AgentWorkspaceBoundsPolicy.maxCheckpoints))
      updated.updatedAtMillis = max(current.updatedAtMillis, timestamp, mutationTime)
      updated.revision = current.revision + 1
      try persist(items.filter { $0.workspaceId != current.workspaceId } + [updated])
      return updated
    }
  }

  func requestCancel(
    _ workspaceId: String,
    expectedRevision: Int64? = nil,
    timestampMillis: Int64 = 0
  ) throws -> AgentWorkspace? {
    try synchronized {
      let items = AgentWorkspaceJsonCodec.decodeList(document)
      guard let current = items.first(where: { $0.workspaceId == workspaceId.trimmingCharacters(in: .whitespacesAndNewlines) }) else {
        return nil
      }
      try checkRevisionIfPresent(current, expectedRevision)
      if current.cancellationRequested {
        return current
      }
      guard current.revision < Int64.max else {
        throw AgentRuntimeCapabilityError.invalid("Agent workspace revision exhausted")
      }

      let mutationTime = now()
      let timestamp = positive(timestampMillis, fallback: mutationTime)
      var updated = current
      updated.cancellationRequested = true
      updated.updatedAtMillis = max(current.updatedAtMillis, timestamp, mutationTime)
      updated.revision = current.revision + 1
      try persist(items.filter { $0.workspaceId != current.workspaceId } + [updated])
      return updated
    }
  }

  func delete(_ workspaceId: String, expectedRevision: Int64? = nil) throws -> Bool {
    try synchronized {
      let cleanId = workspaceId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !cleanId.isEmpty else { return false }
      let items = AgentWorkspaceJsonCodec.decodeList(document)
      guard let current = items.first(where: { $0.workspaceId == cleanId }) else {
        return false
      }
      try checkRevisionIfPresent(current, expectedRevision)
      try persist(items.filter { $0.workspaceId != cleanId })
      return true
    }
  }

  func clear() {
    synchronized {
      document = AgentWorkspaceJsonCodec.emptyDocument()
    }
  }

  func recoverable() -> [AgentWorkspace] {
    synchronized {
      Self.newestFirst(
        AgentWorkspaceJsonCodec.decodeList(document)
          .filter { !$0.status.isTerminal && !$0.cancellationRequested }
      )
    }
  }

  func serializedSnapshot() -> String {
    synchronized { document }
  }

  private func persist(_ workspaces: [AgentWorkspace]) throws {
    document = AgentWorkspaceJsonCodec.encodeList(try AgentWorkspaceStoreBounds.fitSerializedLimit(workspaces))
  }

  private func checkRevisionIfPresent(_ workspace: AgentWorkspace, _ expectedRevision: Int64?) throws {
    if let expectedRevision {
      try checkRevision(workspaceId: workspace.workspaceId, expected: expectedRevision, actual: workspace.revision)
    }
  }

  private func checkRevision(workspaceId: String, expected: Int64, actual: Int64) throws {
    if expected != actual {
      throw AgentWorkspaceRevisionConflictError(
        workspaceId: workspaceId,
        expectedRevision: expected,
        actualRevision: actual
      )
    }
  }

  private func now() -> Int64 {
    max(clock(), 0)
  }

  private func positive(_ value: Int64, fallback: Int64) -> Int64 {
    value > 0 ? value : fallback
  }

  private func synchronized<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  private static func newestFirst(_ workspaces: [AgentWorkspace]) -> [AgentWorkspace] {
    workspaces.sorted {
      if $0.updatedAtMillis != $1.updatedAtMillis { return $0.updatedAtMillis > $1.updatedAtMillis }
      if $0.createdAtMillis != $1.createdAtMillis { return $0.createdAtMillis > $1.createdAtMillis }
      return $0.workspaceId < $1.workspaceId
    }
  }
}

enum AgentWorkspaceJsonCodec {
  static let version: Int64 = 2
  static let maxSerializedCharacters = 4 * 1_024 * 1_024

  static func emptyDocument() -> String {
    #"{"version":2,"workspaces":[]}"#
  }

  static func encode(_ workspace: AgentWorkspace) throws -> String {
    guard let normalized = AgentWorkspaceBoundsPolicy.normalizeOrNil(workspace) else {
      throw AgentRuntimeCapabilityError.invalid("Agent workspace fields are invalid or exceed storage limits")
    }
    let writer = AgentWorkspaceJSONObjectWriter()
    writer.number("version", version)
    workspaceFields(normalized, into: writer)
    return writer.finish()
  }

  static func decode(_ raw: String) -> AgentWorkspace? {
    guard let root = rootObject(raw), version(in: root) <= version else {
      return nil
    }
    return decodeWorkspace(root)
  }

  static func encodeList(_ workspaces: [AgentWorkspace]) -> String {
    let bounded = AgentWorkspaceBoundsPolicy.boundWorkspaces(workspaces)
    let writer = AgentWorkspaceJSONObjectWriter()
    writer.number("version", version)
    writer.array("workspaces") { array in
      for workspace in bounded {
        array.object { object in
          workspaceFields(workspace, into: object)
        }
      }
    }
    return writer.finish()
  }

  static func decodeList(_ raw: String) -> [AgentWorkspace] {
    guard let root = rootObject(raw), version(in: root) <= version else {
      return []
    }
    let values = root["workspaces"] as? [Any] ?? []
    return AgentWorkspaceBoundsPolicy.boundWorkspaces(values.compactMap { value in
      guard let object = value as? [String: Any] else { return nil }
      return decodeWorkspace(object)
    })
  }

  fileprivate static func encodedListLength(_ workspaces: [AgentWorkspace]) -> Int {
    encodeList(workspaces).count
  }

  private static func workspaceFields(_ workspace: AgentWorkspace, into writer: AgentWorkspaceJSONObjectWriter) {
    writer.string("workspace_id", workspace.workspaceId)
    writer.string("session_id", workspace.sessionId)
    writer.string("conversation_id", workspace.conversationId)
    writer.string("task_id", workspace.taskId)
    writer.string("goal", workspace.goal)
    writer.string("parent_run_id", workspace.parentRunId)
    writer.string("agent_id", workspace.agentId)
    writer.string("device_id", workspace.deviceId)
    writer.string("remote_run_id", workspace.remoteRunId)
    writer.string("delivery_mode", workspace.deliveryMode)
    writer.string("status", workspace.status.rawValue)
    writer.string("current_plan_snapshot", workspace.currentPlanSnapshot)
    writer.string("result_json", workspace.resultJson)
    writer.string("error_message", workspace.errorMessage)
    writer.array("permission_grant_ids") { array in
      workspace.permissionGrantIds.forEach(array.stringValue)
    }
    writer.array("permission_scopes") { array in
      workspace.permissionScopes.forEach(array.stringValue)
    }
    writer.array("handoff_ids") { array in
      workspace.handoffIds.forEach(array.stringValue)
    }
    writer.number("last_remote_event_sequence", workspace.lastRemoteEventSequence)
    writer.number("event_sequence", workspace.eventSequence)
    writer.array("event_journal") { array in
      for event in workspace.eventJournal {
        array.object { object in
          object.number("sequence", event.sequence)
          object.string("kind", event.kind)
          object.string("message", event.message)
          object.string("payload_json", event.payloadJson)
          object.number("timestamp", event.timestampMillis)
        }
      }
    }
    writer.array("tool_calls") { array in
      for toolCall in workspace.toolCalls {
        array.object { object in
          object.string("id", toolCall.id)
          object.string("tool_name", toolCall.toolName)
          object.string("status", toolCall.status.rawValue)
          object.string("arguments_json", toolCall.argumentsJson)
          object.string("result_json", toolCall.resultJson)
          object.string("error_message", toolCall.errorMessage)
          object.number("started_at", toolCall.startedAtMillis)
          object.number("completed_at", toolCall.completedAtMillis)
        }
      }
    }
    writer.array("checkpoints") { array in
      for checkpoint in workspace.checkpoints {
        array.object { object in
          object.string("id", checkpoint.id)
          object.number("event_sequence", checkpoint.eventSequence)
          object.string("plan_snapshot", checkpoint.planSnapshot)
          object.string("state_json", checkpoint.stateJson)
          object.number("created_at", checkpoint.createdAtMillis)
        }
      }
    }
    writer.array("artifacts") { array in
      for artifact in workspace.artifacts {
        array.object { object in
          object.string("id", artifact.id)
          object.string("uri", artifact.uri)
          object.string("name", artifact.name)
          object.string("mime_type", artifact.mimeType)
          object.string("metadata_json", artifact.metadataJson)
          object.number("created_at", artifact.createdAtMillis)
        }
      }
    }
    writer.boolean("cancellation_requested", workspace.cancellationRequested)
    writer.number("created_at", workspace.createdAtMillis)
    writer.number("updated_at", workspace.updatedAtMillis)
    writer.number("revision", workspace.revision)
  }

  private static func decodeWorkspace(_ object: [String: Any]) -> AgentWorkspace? {
    guard isValidStatus(object["status"]) else {
      return nil
    }
    var sanitized = object
    if let toolCalls = object["tool_calls"] as? [Any] {
      sanitized["tool_calls"] = toolCalls.compactMap { value -> [String: Any]? in
        guard let call = value as? [String: Any], isValidToolStatus(call["status"]) else {
          return nil
        }
        return call
      }
    }
    guard JSONSerialization.isValidJSONObject(sanitized),
      let data = try? JSONSerialization.data(withJSONObject: sanitized),
      let decoded = try? JSONDecoder().decode(AgentWorkspace.self, from: data) else {
      return nil
    }
    return AgentWorkspaceBoundsPolicy.normalizeOrNil(decoded)
  }

  private static func rootObject(_ raw: String) -> [String: Any]? {
    guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      raw.count <= maxSerializedCharacters,
      let data = raw.data(using: .utf8),
      let parsed = try? JSONSerialization.jsonObject(with: data),
      let object = parsed as? [String: Any] else {
      return nil
    }
    return object
  }

  private static func version(in object: [String: Any]) -> Int64 {
    if let number = object["version"] as? NSNumber {
      return number.int64Value
    }
    if let string = object["version"] as? String, let value = Int64(string) {
      return value
    }
    return version
  }

  private static func isValidStatus(_ value: Any?) -> Bool {
    guard let raw = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else {
      return false
    }
    return AgentWorkspaceStatus.allCases.contains { $0.rawValue == raw }
  }

  private static func isValidToolStatus(_ value: Any?) -> Bool {
    guard let raw = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else {
      return false
    }
    return AgentToolCallStatus.allCases.contains { $0.rawValue == raw }
  }
}

private enum AgentWorkspaceStoreBounds {
  static func fitSerializedLimit(_ workspaces: [AgentWorkspace]) throws -> [AgentWorkspace] {
    var bounded = AgentWorkspaceBoundsPolicy.boundWorkspaces(workspaces)
    while bounded.count > 1 && AgentWorkspaceJsonCodec.encodedListLength(bounded) > AgentWorkspaceJsonCodec.maxSerializedCharacters {
      if let terminalIndex = bounded.firstIndex(where: { $0.status.isTerminal }) {
        bounded.remove(at: terminalIndex)
      } else {
        bounded.removeFirst()
      }
    }
    if bounded.count == 1 && AgentWorkspaceJsonCodec.encodedListLength(bounded) > AgentWorkspaceJsonCodec.maxSerializedCharacters {
      bounded[0] = shrinkSingle(bounded[0])
    }
    guard AgentWorkspaceJsonCodec.encodedListLength(bounded) <= AgentWorkspaceJsonCodec.maxSerializedCharacters else {
      throw AgentRuntimeCapabilityError.invalid("Agent workspace storage limit exceeded")
    }
    return bounded
  }

  private static func shrinkSingle(_ source: AgentWorkspace) -> AgentWorkspace {
    var workspace = source
    while AgentWorkspaceJsonCodec.encodedListLength([workspace]) > AgentWorkspaceJsonCodec.maxSerializedCharacters {
      if !workspace.eventJournal.isEmpty {
        workspace.eventJournal.removeFirst()
      } else if !workspace.toolCalls.isEmpty {
        workspace.toolCalls.removeFirst()
      } else if !workspace.checkpoints.isEmpty {
        workspace.checkpoints.removeFirst()
      } else if !workspace.artifacts.isEmpty {
        workspace.artifacts.removeFirst()
      } else if workspace.currentPlanSnapshot.count > 1_024 {
        workspace.currentPlanSnapshot = String(workspace.currentPlanSnapshot.prefix(workspace.currentPlanSnapshot.count / 2))
      } else if workspace.resultJson.count > 1_024 {
        workspace.resultJson = String(workspace.resultJson.prefix(workspace.resultJson.count / 2))
      } else if workspace.goal.count > 1_024 {
        workspace.goal = String(workspace.goal.prefix(workspace.goal.count / 2))
      } else {
        return workspace
      }
    }
    return workspace
  }
}

private final class AgentWorkspaceJSONObjectWriter {
  private var output = "{"
  private var first = true

  func string(_ name: String, _ value: String) {
    field(name)
    output += value.agentWorkspaceJSONString
  }

  func number(_ name: String, _ value: Int64) {
    field(name)
    output += "\(value)"
  }

  func boolean(_ name: String, _ value: Bool) {
    field(name)
    output += value ? "true" : "false"
  }

  func array(_ name: String, _ body: (AgentWorkspaceJSONArrayWriter) -> Void) {
    field(name)
    let writer = AgentWorkspaceJSONArrayWriter()
    body(writer)
    output += writer.finish()
  }

  func finish() -> String {
    output + "}"
  }

  private func field(_ name: String) {
    if !first {
      output += ","
    }
    first = false
    output += name.agentWorkspaceJSONString
    output += ":"
  }
}

private final class AgentWorkspaceJSONArrayWriter {
  private var output = "["
  private var first = true

  func stringValue(_ value: String) {
    next()
    output += value.agentWorkspaceJSONString
  }

  func object(_ body: (AgentWorkspaceJSONObjectWriter) -> Void) {
    next()
    let writer = AgentWorkspaceJSONObjectWriter()
    body(writer)
    output += writer.finish()
  }

  func finish() -> String {
    output + "]"
  }

  private func next() {
    if !first {
      output += ","
    }
    first = false
  }
}

private extension String {
  var agentWorkspaceJSONString: String {
    var result = "\""
    for scalar in unicodeScalars {
      switch scalar.value {
      case 34:
        result += "\\\""
      case 92:
        result += "\\\\"
      case 8:
        result += "\\b"
      case 12:
        result += "\\f"
      case 10:
        result += "\\n"
      case 13:
        result += "\\r"
      case 9:
        result += "\\t"
      default:
        if scalar.value < 0x20 {
          result += String(format: "\\u%04x", scalar.value)
        } else {
          result.unicodeScalars.append(scalar)
        }
      }
    }
    result += "\""
    return result
  }
}
