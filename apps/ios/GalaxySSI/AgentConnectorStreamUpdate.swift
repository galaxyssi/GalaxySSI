import Foundation
import CryptoKit

enum AgentPublicProgressPolicy {
  static func isInternal(_ value: String) -> Bool {
    value.contains("GALAXYSSI_RECOVERY_ACTION_V1")
  }

  static func text(_ value: String) -> String {
    isInternal(value) ? "" : value
  }

  static func details(_ values: [String]) -> [String] {
    values.filter { !$0.isBlank && !isInternal($0) }
  }
}

struct AgentConnectorPublicProgress: Equatable {
  static let tracePrefix = "connector-progress:"
  var eventId: String
  var generation: Int64
  var sequence: Int64
  var text: String
  var countsForCodexSilence = true

  var traceStage: String {
    let digest = SHA256.hash(data: Data(eventId.utf8)).map { String(format: "%02x", $0) }.joined()
    return "\(Self.tracePrefix)\(generation):\(sequence):\(digest)"
  }

  @MainActor
  static func entries(_ payload: [String: Any], localize: (String, String) -> String) -> [Self] {
    guard payload.string("type") == "agent_task_event",
          let generation = AgentDesktopReplyRecovery.integer(payload["execution_generation"], minimum: 1),
          let sequence = AgentDesktopReplyRecovery.integer(payload["status_sequence"] ?? payload["status_seq"], minimum: 0) else { return [] }
    var events = Array(((payload["events"] as? [[String: Any]]) ?? []).suffix(64))
    if let current = payload.dictionary("progress_event") { events.append(current) }
    return events.compactMap { event in
      let id = event.string("event_id").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !id.isEmpty, id.count <= 200, event["user_visible"] as? Bool != false else { return nil }
      let kind = event.string("kind").lowercased()
      let code = event.string("code").ifBlank(event.dictionary("metadata")?.string("code") ?? "").lowercased()
      let detail = event.string("detail").trimmingCharacters(in: .whitespacesAndNewlines)
      let status = event.string("status").lowercased()
      guard kind != "research_checkpoint", code != "heartbeat",
            !AgentPublicProgressPolicy.isInternal(detail), !AgentPublicProgressPolicy.isInternal(event.string("title")),
            !(code == "dynamic_tool" && detail == "research_checkpoint" && status != "failed") else { return nil }
      if status != "failed", ["web_search", "web_image_search"].contains(code) { return nil }
      if status != "failed", (kind == "plan" || code == "plan"),
         detail.ifBlank(event.string("title")).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "planning" {
        return nil
      }
      let text: String
      if ["narration", "reasoning", "plan"].contains(kind) || ["commentary", "reasoning_summary", "plan"].contains(code) {
        text = String(detail.ifBlank(event.string("title")).prefix(2_000))
      } else {
        let operations: [String: String] = ["command": "Running command", "file_change": "Updating files",
          "web_search": "Searching the web", "web_image_search": "Searching images", "image_view": "Viewing images",
          "mcp_tool": "Calling MCP tool", "dynamic_tool": "Calling tool", "image_generation": "Generating image",
          "agent_collaboration": "Coordinating Agents", "context_compaction": "Compacting context"]
        guard let operation = operations[code] else { return nil }
        let label = localize("galaxyssi.agent.progress.operation.\(code)", operation)
        switch status {
        case "running", "started": text = label
        case "failed": text = String(format: localize("galaxyssi.agent.progress.failed", "Failed: %@"), label)
        default: text = String(format: localize("galaxyssi.agent.progress.completed", "Completed: %@"), label)
        }
      }
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
      let source = (event.dictionary("metadata")?.string("source") ?? "").lowercased()
      let internalSteering = ["replan", "steer", "heartbeat"].contains(kind) ||
        ["replan", "steer", "heartbeat"].contains(code) ||
        ["stall_watchdog", "auto_replan", "self_steering"].contains(source)
      return Self(eventId: id, generation: generation, sequence: sequence, text: text,
        countsForCodexSilence: !internalSteering)
    }
  }

  static func reducing(_ trace: [DeliveryTraceEvent], updates: [Self]) -> [DeliveryTraceEvent] {
    var result = trace
    for update in updates {
      guard !AgentPublicProgressPolicy.isInternal(update.text) else { continue }
      let components = result.filter { $0.stage.hasPrefix(tracePrefix) }.map { $0.stage.split(separator: ":") }
      let floor = components.compactMap { parts -> (Int64, Int64)? in
        guard parts.count == 4, let generation = Int64(parts[1]), let sequence = Int64(parts[2]) else { return nil }
        return (generation, sequence)
      }.max { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
      if let floor, update.generation < floor.0 || (update.generation == floor.0 && update.sequence < floor.1) { continue }
      let suffix = update.traceStage.split(separator: ":").last!
      if let index = result.firstIndex(where: { $0.stage.hasPrefix(tracePrefix) && $0.stage.split(separator: ":").last == suffix }) {
        guard result[index].stage != update.traceStage || result[index].detail != update.text else { continue }
        result[index].stage = update.traceStage
        result[index].detail = update.text
      } else { result.append(DeliveryTraceEvent(stage: update.traceStage, detail: update.text)) }
    }
    let retained = Set(result.filter { $0.stage.hasPrefix(tracePrefix) }.suffix(64).map(\.id))
    return result.filter { !$0.stage.hasPrefix(tracePrefix) || retained.contains($0.id) }
  }
}

enum AgentScreenAnalysisCancellationPolicy {
  static let activePhases: Set<AgentPhase> = [.observing, .planning, .waitingConfirmation,
    .executing, .verifying, .waitingResponse, .paused]

  static func activePhase(for original: ChatMessage, localTasks: [AgentTaskRecord],
                          remoteTasks: [AgentRemoteTaskStatusSnapshot]) -> AgentPhase? {
    guard original.isMine else { return nil }
    let turn = original.turnId.ifBlank(original.id.uuidString)
    if let local = localTasks.first(where: {
      $0.sessionId == original.conversationId &&
        ($0.taskId == turn || $0.taskId == original.id.uuidString) && activePhases.contains($0.phase)
    }) { return local.phase }
    return remoteTasks.filter {
      $0.conversationId == original.conversationId && $0.turnId == turn &&
        !AgentRemoteTaskStatusPolicy.isTerminal($0.status)
    }.max { $0.updatedAtMillis < $1.updatedAtMillis }.map { AgentRemoteTaskStatusPolicy.phase($0.status) }
  }

  static func shouldCancel(_ original: ChatMessage, messages: [ChatMessage],
                           localTasks: [AgentTaskRecord], remoteTasks: [AgentRemoteTaskStatusSnapshot]) -> Bool {
    guard original.isMine else { return false }
    if activePhase(for: original, localTasks: localTasks, remoteTasks: remoteTasks) != nil { return true }
    let turn = original.turnId.ifBlank(original.id.uuidString)
    return !messages.contains {
      !$0.isMine && !$0.isSystem && $0.contactId == original.contactId && $0.conversationId == original.conversationId &&
        $0.turnId.ifBlank($0.id.uuidString) == turn && $0.deliveryStatus == .delivered
    }
  }
}

enum AgentScreenAnalysisReplyPolicy {
  static func isStopped(_ payload: [String: Any], messages: [ChatMessage]) -> Bool {
    guard ["text", "agent_task_event"].contains(payload.string("type")),
          let source = UUID(uuidString: payload.string("source_message_id")),
          !payload.string("conversation_id").isEmpty,
          !payload.string("turn_id").isEmpty else { return false }
    return messages.contains {
      $0.id == source && $0.isMine &&
        $0.conversationId == payload.string("conversation_id") &&
        $0.turnId.ifBlank($0.id.uuidString) == payload.string("turn_id") &&
        $0.deliveryTrace.contains { $0.stage == "screen_analysis_cancelled" }
    }
  }
}

enum AgentConnectorStreamHandoff {
  static func persistThenRetire<Result>(
    persistFinal: () throws -> Result?,
    retireLiveStream: () -> Void
  ) rethrows -> Result? {
    guard let result = try persistFinal() else { return nil }
    retireLiveStream()
    return result
  }
}

struct AgentConnectorStreamUpdate: Equatable {
  let sourceMessageId: String
  let contactId: String
  let conversationId: String
  let turnId: String
  let taskId: String
  let content: String
  let sequence: Int64
  let executionGeneration: Int64

  init?(payload: [String: Any]) {
    guard payload.string("type") == "agent_task_event",
          AgentRemoteTaskStatusPolicy.normalize(
            payload.string("task_status").ifBlank(payload.string("status"))
          ) == "running",
          let partial = payload.dictionary("partial_result") else {
      return nil
    }
    if let visible = partial["user_visible"] as? Bool, !visible {
      return nil
    }
    if let visible = partial["user_visible"] as? NSNumber, !visible.boolValue {
      return nil
    }
    let text = partial.string("text")
      .ifBlank(partial.string("content"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }

    let sourceMessageId = payload.string("source_message_id")
      .ifBlank(String(payload.int("source_message_id")))
    guard !sourceMessageId.isEmpty, sourceMessageId != "0" else { return nil }
    self.sourceMessageId = sourceMessageId
    contactId = payload.string("contact_id").ifBlank("hermes")
    conversationId = payload.string("conversation_id")
    turnId = payload.string("turn_id")
    taskId = payload.string("task_id")
    content = String(text.prefix(Self.maximumContentCharacters))
    sequence = max(0, Int64(partial.int("sequence")))
    let generation = Int64(payload.string("execution_generation")) ?? Int64(payload.int("execution_generation"))
    executionGeneration = AgentRemoteOutcomePolicy.validGeneration(generation) ? generation : 1
  }

  var streamKey: String {
    Self.streamKey(sourceMessageId: sourceMessageId, turnId: turnId)
  }

  static func streamKey(sourceMessageId: String, turnId: String) -> String {
    let cleanSourceMessageId = sourceMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
    if !cleanSourceMessageId.isEmpty, cleanSourceMessageId != "0" {
      return "source:\(cleanSourceMessageId)"
    }
    let cleanTurnId = turnId.trimmingCharacters(in: .whitespacesAndNewlines)
    return cleanTurnId.isEmpty ? "unknown" : "turn:\(cleanTurnId)"
  }

  private static let maximumContentCharacters = 64_000
}
