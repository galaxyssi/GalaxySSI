import CoreFoundation
import Foundation

enum GlobalRichObservationExtractor {
  static func transcriptEventType(
    _ entry: AgentTranscriptEntry,
    updated: Bool
  ) -> GlobalConversationEventType {
    if entry.role == .process,
      AgentTranscriptPresentationPolicy.processContentKind(entry) == .toolActivity {
      return toolLifecycleType(content: entry.text, metadata: [:]) ?? .toolStarted
    }
    return updated ? .messageUpdated : .messageCreated
  }

  static func extract(
    conversation: AgentConversation,
    entry: AgentTranscriptEntry,
    rootEventId: String
  ) -> [GlobalConversationEvent] {
    if entry.richOutputJson.isBlank || conversation.privateMode || conversation.trackingPaused {
      return []
    }
    let sensitivity: GlobalConversationSensitivity = conversation.privateMode ? .sessionPrivate : .personal
    let actor: GlobalConversationActor
    if entry.dedupeKey.hasPrefix("global-agent:") {
      actor = .globalAgent
    } else {
      switch entry.role {
      case .user:
        actor = .user
      case .assistant:
        actor = .assistant
      case .process:
        actor = .tool
      }
    }

    var seen = Set<String>()
    return AgentRichContentCodec.decode(entry.richOutputJson).compactMap { block in
      guard let eventType = classify(role: entry.role, block: block) else {
        return nil
      }
      let fingerprint = GlobalAgentText.stableKey(
        block.id,
        block.type.rawValue,
        block.title,
        block.uri,
        block.mimeType,
        String(block.text.prefix(512)),
        String(block.fallbackText.prefix(256))
      )
      guard seen.insert("\(eventType.rawValue):\(fingerprint)").inserted else {
        return nil
      }

      let resource = resourceName(block)
      let status = toolStatus(eventType)
      var metadata = [
        "origin": "rich_transcript",
        "block_id": String(block.id.prefix(120)),
        "block_type": block.type.rawValue.lowercased(),
        "resource_name": String(resource.prefix(240)),
        "mime_type": String(block.mimeType.prefix(160)),
        "resource_scheme": resourceScheme(block.uri),
        "inline_data": (!block.dataB64.isBlank).description,
        "turn_id": entry.turnId,
        "task_id": entry.taskId
      ]
      if !status.isEmpty {
        metadata["tool_status"] = status
      }
      if toolEvents.contains(eventType) {
        metadata["tool_key"] = toolKey(entry: entry, block: block)
      }
      for (key, value) in safeMetadata(block.metadata) {
        metadata["rich_\(String(key.prefix(64)))"] = String(value.prefix(256))
      }
      let topicHints: Set<String> = conversation.title.caseInsensitiveCompare("New session") == .orderedSame
        ? []
        : [conversation.title]

      return GlobalConversationEvent(
        id: "rich:\(entry.id):\(eventType.rawValue.lowercased()):\(String(fingerprint.prefix(24)))",
        type: eventType,
        conversationId: entry.conversationId,
        messageId: entry.id,
        actor: toolEvents.contains(eventType) ? .tool : actor,
        timestampMillis: entry.timestampMillis,
        content: String(observationSummary(type: eventType, block: block, resourceName: resource).prefix(maxObservationContent)),
        contentRef: "encrypted://agent-transcript/\(entry.conversationId)/\(entry.id)#rich=\(String(fingerprint.prefix(24)))",
        conversationTitle: conversation.title,
        topicHints: topicHints,
        sensitivity: sensitivity,
        metadata: metadata,
        causalEventIds: Set([rootEventId])
      )
    }
  }

  static func toolLifecycleType(
    content: String,
    metadata: [String: String]
  ) -> GlobalConversationEventType? {
    let state = ([content] + ["status", "state", "phase"].compactMap { metadata[$0] })
      .joined(separator: " ")
      .lowercased()
    if state.isBlank {
      return nil
    }
    if cancellationSignals.contains(where: state.contains) {
      return .toolCancelled
    }
    if failureSignals.contains(where: state.contains) {
      return .toolFailed
    }
    if completionSignals.contains(where: state.contains) {
      return .toolCompleted
    }
    return .toolStarted
  }

  private static func classify(
    role: AgentTranscriptRole,
    block: AgentRichBlock
  ) -> GlobalConversationEventType? {
    if toolBlocks.contains(block.type) {
      return toolLifecycleType(
        content: [block.title, block.text, block.fallbackText].joined(separator: " "),
        metadata: block.metadata
      )
    }
    if role == .user && attachmentBlocks.contains(block.type) {
      return .attachmentAdded
    }
    if role != .user && isArtifact(block) {
      return .artifactCreated
    }
    return nil
  }

  private static func isArtifact(_ block: AgentRichBlock) -> Bool {
    artifactBlocks.contains(block.type) ||
      (
        conditionalArtifactBlocks.contains(block.type) &&
          (
            !block.uri.isBlank ||
              !block.dataB64.isBlank ||
              !block.title.isBlank ||
              block.metadata["artifact"] == "true" ||
              block.metadata["runtime_artifact"] == "true"
          )
      )
  }

  private static func observationSummary(
    type: GlobalConversationEventType,
    block: AgentRichBlock,
    resourceName: String
  ) -> String {
    let details: String
    switch block.type {
    case .table:
      let columns = block.columns.filter { !$0.isBlank }.prefix(8).joined(separator: ", ")
      details = "\(block.rows.count) rows\(columns.isBlank ? "" : "; columns: \(columns)")"
    case .code, .diff, .json:
      details = block.language
    default:
      details = [block.mimeType, block.metadata["size"], block.metadata["size_bytes"]]
        .compactMap { $0 }
        .filter { !$0.isBlank }
        .reduce(into: [String]()) { result, value in
          if !result.contains(value) {
            result.append(value)
          }
        }
        .joined(separator: ", ")
    }
    let suffix = details.isBlank ? "" : " (\(details))"
    switch type {
    case .attachmentAdded:
      return "Attached \(blockLabel(block)): \(resourceName)\(suffix)"
    case .artifactCreated:
      return "Created \(blockLabel(block)): \(resourceName)\(suffix)"
    case .toolStarted:
      return toolSummary(status: "started", block: block, fallback: resourceName)
    case .toolCompleted:
      return toolSummary(status: "completed", block: block, fallback: resourceName)
    case .toolCancelled:
      return toolSummary(status: "cancelled", block: block, fallback: resourceName)
    case .toolFailed:
      return toolSummary(status: "failed", block: block, fallback: resourceName)
    default:
      return resourceName
    }
  }

  private static func toolSummary(
    status: String,
    block: AgentRichBlock,
    fallback: String
  ) -> String {
    let detail = [block.title, block.text, block.fallbackText]
      .first { !$0.isBlank }?
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return "Tool \(status): \(String(detail.ifBlank(fallback).prefix(800)))"
  }

  private static func resourceName(_ block: AgentRichBlock) -> String {
    let uriName = block.uri
      .components(separatedBy: "#")[0]
      .components(separatedBy: "?")[0]
      .split(separator: "/")
      .last
      .map(String.init) ?? ""
    let candidate = [
      block.title,
      block.metadata["display_name"] ?? "",
      block.metadata["name"] ?? "",
      block.fallbackText,
      uriName
    ]
      .first { !$0.isBlank }?
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return String(candidate.ifBlank(blockLabel(block)).prefix(240))
  }

  private static func blockLabel(_ block: AgentRichBlock) -> String {
    switch block.type {
    case .image, .gallery:
      return "image"
    case .video:
      return "video"
    case .audio:
      return "audio"
    case .table:
      return "table"
    case .chart:
      return "chart"
    case .mermaid:
      return "diagram"
    case .code:
      return "code"
    case .diff:
      return "diff"
    case .json:
      return "JSON"
    case .html, .webpage:
      return "web artifact"
    case .tool, .status, .progress:
      return "operation"
    default:
      return "file"
    }
  }

  private static func resourceScheme(_ uri: String) -> String {
    let scheme = uri.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    return String(scheme.lowercased().prefix(24))
  }

  private static func toolKey(entry: AgentTranscriptEntry, block: AgentRichBlock) -> String {
    [
      block.metadata["tool_run_id"],
      block.metadata["tool_call_id"],
      block.metadata["tool_id"],
      block.metadata["tool_name"],
      block.id,
      entry.taskId,
      entry.turnId
    ]
      .compactMap { $0 }
      .first { !$0.isBlank }
      .map { String($0.prefix(160)) } ?? ""
  }

  private static func toolStatus(_ eventType: GlobalConversationEventType) -> String {
    switch eventType {
    case .toolCompleted:
      return "completed"
    case .toolCancelled:
      return "cancelled"
    case .toolFailed:
      return "failed"
    case .toolStarted:
      return "started"
    default:
      return ""
    }
  }

  private static func safeMetadata(_ metadata: [String: String]) -> [(String, String)] {
    metadata
      .filter { safeMetadataKeys.contains($0.key.lowercased()) }
      .sorted { $0.key < $1.key }
      .prefix(maxCopiedMetadata)
      .map { ($0.key, $0.value) }
  }

  private static let attachmentBlocks: Set<AgentRichBlockType> = [
    .file,
    .image,
    .gallery,
    .video,
    .audio
  ]
  private static let artifactBlocks = attachmentBlocks.union([
    .table,
    .chart,
    .mermaid,
    .diff,
    .html,
    .webpage
  ])
  private static let conditionalArtifactBlocks: Set<AgentRichBlockType> = [.code, .json]
  private static let toolBlocks: Set<AgentRichBlockType> = [.tool, .status, .progress]
  private static let toolEvents: Set<GlobalConversationEventType> = [
    .toolStarted,
    .toolCompleted,
    .toolCancelled,
    .toolFailed
  ]
  private static let failureSignals = [
    "failed", "failure", "error", "timed out", "timeout", "blocked",
    "\u{5931}\u{8d25}", "\u{9519}\u{8bef}", "\u{8d85}\u{65f6}", "\u{963b}\u{585e}"
  ]
  private static let cancellationSignals = [
    "cancelled", "canceled", "aborted", "stopped by user",
    "\u{53d6}\u{6d88}", "\u{7528}\u{6237}\u{505c}\u{6b62}"
  ]
  private static let completionSignals = [
    "completed", "complete", "succeeded", "success", "finished", "done", "ready",
    "\u{5df2}\u{5b8c}\u{6210}", "\u{5b8c}\u{6210}", "\u{6210}\u{529f}", "\u{5df2}\u{5c31}\u{7eea}"
  ]
  private static let safeMetadataKeys: Set<String> = [
    "artifact", "artifact_kind", "detail", "display_name", "duration", "duration_ms", "file_count",
    "format", "language", "name", "phase", "runtime_artifact", "sha256", "size", "size_bytes",
    "state", "status", "tool_call_id", "tool_id", "tool_name", "tool_run_id", "verified"
  ]
  private static let maxCopiedMetadata = 12
  private static let maxObservationContent = 1_200
}

enum GlobalRecordedRunObservationExtractor {
  static func started(
    _ run: AgentRecordedRun,
    conversationTitle: String = ""
  ) -> GlobalConversationEvent {
    GlobalConversationEvent(
      id: startedEventId(run.runId),
      type: .taskUpdated,
      conversationId: run.conversationId,
      messageId: run.runId,
      actor: .tool,
      timestampMillis: run.createdAtMillis,
      content: "Agent run started: \(compact(run.originalRequest, limit: 800))",
      contentRef: "encrypted://agent-runs/\(run.runId)",
      conversationTitle: String(conversationTitle.prefix(160)),
      metadata: runMetadata(run, status: "running")
    )
  }

  static func completed(
    _ run: AgentRecordedRun,
    conversationTitle: String = ""
  ) -> [GlobalConversationEvent] {
    let terminalStatus = run.status.rawValue.lowercased()
    let completedEventId = "recorded-run:\(run.runId):\(terminalStatus)"
    let terminal = GlobalConversationEvent(
      id: completedEventId,
      type: terminalType(run.status),
      conversationId: run.conversationId,
      messageId: run.runId,
      actor: .tool,
      timestampMillis: run.completedAtMillis > 0 ? run.completedAtMillis : GlobalRealtimeClock.nowMillis(),
      content: "Agent run \(terminalStatus): \(compact(run.originalRequest, limit: 800))",
      contentRef: "encrypted://agent-runs/\(run.runId)",
      conversationTitle: String(conversationTitle.prefix(160)),
      metadata: runMetadata(run, status: terminalStatus),
      causalEventIds: [startedEventId(run.runId)]
    )
    let roots: Set<String> = [startedEventId(run.runId), completedEventId]
    let toolEvents = run.toolCalls.map { call in
      toolEvent(run: run, call: call, terminalTimestampMillis: terminal.timestampMillis, conversationTitle: conversationTitle, roots: roots)
    }
    let artifactEvents = run.artifacts.map { artifact in
      artifactEvent(run: run, artifact: artifact, terminalTimestampMillis: terminal.timestampMillis, conversationTitle: conversationTitle, roots: roots)
    }
    return [terminal] + toolEvents + artifactEvents
  }

  static func feedback(
    run: AgentRecordedRun,
    feedback: String,
    timestampMillis: Int64 = GlobalRealtimeClock.nowMillis(),
    conversationTitle: String = ""
  ) -> GlobalConversationEvent {
    let clean = compact(feedback, limit: 1_200)
    let fingerprint = GlobalAgentText.stableKey(run.runId, clean, String(timestampMillis))
    return GlobalConversationEvent(
      id: "recorded-run-feedback:\(run.runId):\(String(fingerprint.prefix(24)))",
      type: .userFeedback,
      conversationId: run.conversationId,
      messageId: run.runId,
      actor: .user,
      timestampMillis: timestampMillis,
      content: clean,
      contentRef: "encrypted://agent-runs/\(run.runId)/feedback",
      conversationTitle: String(conversationTitle.prefix(160)),
      metadata: [
        "origin": "agent_run",
        "run_id": run.runId,
        "task_id": run.runId,
        "task_thread_id": run.taskThreadId,
        "feedback_kind": "run_feedback"
      ],
      causalEventIds: [startedEventId(run.runId)]
    )
  }

  private static func terminalType(_ status: AgentRecordedRunStatus) -> GlobalConversationEventType {
    switch status {
    case .completed:
      return .taskUpdated
    case .cancelled:
      return .toolCancelled
    case .failed:
      return .toolFailed
    case .running:
      return .toolStarted
    }
  }

  private static func toolEvent(
    run: AgentRecordedRun,
    call: AgentToolCallRecord,
    terminalTimestampMillis: Int64,
    conversationTitle: String,
    roots: Set<String>
  ) -> GlobalConversationEvent {
    let detail: String
    if !call.errorMessage.isBlank {
      detail = compact(call.errorMessage, limit: 800)
    } else if !call.result.isEmpty {
      detail = summarizeJson(call.result)
    } else {
      detail = call.status.rawValue.lowercased()
    }
    return GlobalConversationEvent(
      id: "recorded-tool:\(run.runId):\(call.id):\(call.status.rawValue.lowercased())",
      type: eventType(call.status),
      conversationId: run.conversationId,
      messageId: run.runId,
      actor: .tool,
      timestampMillis: call.completedAtMillis > 0 ? call.completedAtMillis : (call.startedAtMillis > 0 ? call.startedAtMillis : terminalTimestampMillis),
      content: "\(call.toolName) \(call.status.rawValue.lowercased())\(detail.isBlank ? "" : ": \(detail)")",
      contentRef: "encrypted://agent-runs/\(run.runId)/tools/\(call.id)",
      conversationTitle: String(conversationTitle.prefix(160)),
      metadata: [
        "origin": "agent_run",
        "run_id": run.runId,
        "task_id": run.runId,
        "task_thread_id": run.taskThreadId,
        "tool_call_id": call.id,
        "tool_key": call.id,
        "tool_name": String(call.toolName.prefix(160)),
        "tool_status": call.status.rawValue.lowercased(),
        "verified": (call.status == .succeeded).description
      ],
      causalEventIds: roots
    )
  }

  private static func artifactEvent(
    run: AgentRecordedRun,
    artifact: AgentArtifactReference,
    terminalTimestampMillis: Int64,
    conversationTitle: String,
    roots: Set<String>
  ) -> GlobalConversationEvent {
    let name = artifact.name.ifBlank(artifact.id)
    var metadata = [
      "origin": "agent_run",
      "run_id": run.runId,
      "task_id": run.runId,
      "task_thread_id": run.taskThreadId,
      "artifact_id": artifact.id,
      "resource_name": String(artifact.name.prefix(240)),
      "mime_type": String(artifact.mimeType.prefix(160)),
      "resource_scheme": resourceScheme(artifact.uri)
    ]
    for (key, value) in parseArtifactMetadata(artifact.metadataJson) {
      metadata[key] = value
    }
    return GlobalConversationEvent(
      id: "recorded-artifact:\(run.runId):\(artifact.id)",
      type: .artifactCreated,
      conversationId: run.conversationId,
      messageId: run.runId,
      actor: .tool,
      timestampMillis: artifact.createdAtMillis > 0 ? artifact.createdAtMillis : terminalTimestampMillis,
      content: "Created artifact: \(String(name.prefix(240)))\(artifact.mimeType.isBlank ? "" : " (\(artifact.mimeType))")",
      contentRef: "encrypted://agent-runs/\(run.runId)/artifacts/\(artifact.id)",
      conversationTitle: String(conversationTitle.prefix(160)),
      metadata: metadata,
      causalEventIds: roots
    )
  }

  private static func eventType(_ status: AgentToolCallStatus) -> GlobalConversationEventType {
    switch status {
    case .pending, .running:
      return .toolStarted
    case .succeeded:
      return .toolCompleted
    case .failed:
      return .toolFailed
    case .cancelled:
      return .toolCancelled
    }
  }

  private static func runMetadata(
    _ run: AgentRecordedRun,
    status: String
  ) -> [String: String] {
    [
      "origin": "agent_run",
      "run_id": run.runId,
      "task_id": run.runId,
      "task_thread_id": run.taskThreadId,
      "task_status": status,
      "active_skill_id": String(run.activeSkillId.prefix(160)),
      "execution_resource_id": resourceKey(run.executionResourceId),
      "revision": String(run.revisionNumber)
    ]
  }

  private static func startedEventId(_ runId: String) -> String {
    "recorded-run:\(runId):started"
  }

  private static func summarizeJson(_ object: AgentMcpJSONObject) -> String {
    object.keys
      .sorted()
      .filter { !sensitiveKey($0) }
      .compactMap { key in
        scalarSummary(object[key]).map { "\(key)=\($0)" }
      }
      .prefix(8)
      .joined(separator: ", ")
      .ifBlank("result available")
      .prefixString(800)
  }

  private static func scalarSummary(_ value: AgentMcpJSONValue?) -> String? {
    guard let value else { return nil }
    switch value {
    case .string(let text):
      let clean = compact(text, limit: 160)
      return clean.isEmpty ? nil : clean
    case .int(let value):
      return String(value)
    case .double(let value):
      return String(value)
    case .bool(let value):
      return value.description
    case .array(let values):
      return "\(values.count) items"
    case .object(let object):
      return "\(object.count) fields"
    case .null:
      return nil
    }
  }

  private static func parseArtifactMetadata(_ raw: String) -> [String: String] {
    guard !raw.isBlank,
      let data = raw.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return [:]
    }
    var result: [String: String] = [:]
    for key in object.keys.sorted() where safeArtifactMetadataKeys.contains(key.lowercased()) {
      guard result.count < maxArtifactMetadata,
        let value = scalarSummary(object[key]) else {
        continue
      }
      result["artifact_\(String(key.prefix(64)))"] = String(value.prefix(256))
    }
    return result
  }

  private static func scalarSummary(_ value: Any?) -> String? {
    switch value {
    case nil:
      return nil
    case is NSNull:
      return nil
    case let value as String:
      let clean = compact(value, limit: 160)
      return clean.isEmpty ? nil : clean
    case let value as NSNumber:
      if CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() {
        return value.boolValue.description
      }
      return value.stringValue
    case let value as [Any]:
      return "\(value.count) items"
    case let value as [String: Any]:
      return "\(value.count) fields"
    default:
      return nil
    }
  }

  private static func sensitiveKey(_ key: String) -> Bool {
    let lower = key.lowercased()
    return sensitiveKeyTerms.contains { lower.contains($0) }
  }

  private static func resourceScheme(_ uri: String) -> String {
    let scheme = uri.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    return String(scheme.lowercased().prefix(24))
  }

  private static func resourceKey(_ value: String) -> String {
    let id = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if id.isEmpty || id == identityId || id == "phone" || id == "ios" || id == "android" {
      return identityId
    }
    if id == "claude" || id == "claude-code" || id.contains(":claude-code") {
      return "claude-code"
    }
    if id == "codex" || id.contains(":codex") {
      return "codex"
    }
    if id == "hermes" || id.contains(":hermes") {
      return "hermes"
    }
    if id == "openclaw" || id.contains(":openclaw") {
      return "openclaw"
    }
    if id == "local-llm" || id.contains(":local-llm") {
      return "local-llm"
    }
    if id == "cloud-models" || id.hasPrefix("cloud-model:") {
      return "cloud-models"
    }
    if id.hasPrefix("skill:") {
      return "skill:\(String(GlobalAgentText.stableKey(id).prefix(20)))"
    }
    return "resource:\(String(GlobalAgentText.stableKey(id).prefix(24)))"
  }

  private static func compact(_ value: String, limit: Int) -> String {
    value
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefixString(limit)
  }

  private static let identityId = "identity"
  private static let sensitiveKeyTerms = [
    "authorization", "password", "secret", "token", "cookie", "api_key", "apikey", "uri", "path"
  ]
  private static let safeArtifactMetadataKeys: Set<String> = [
    "artifact_kind", "duration", "duration_ms", "file_count", "format", "hash", "height",
    "language", "sha256", "size", "size_bytes", "width"
  ]
  private static let maxArtifactMetadata = 12
}

private extension StringProtocol {
  func prefixString(_ limit: Int) -> String {
    String(prefix(Swift.max(limit, 0)))
  }
}
