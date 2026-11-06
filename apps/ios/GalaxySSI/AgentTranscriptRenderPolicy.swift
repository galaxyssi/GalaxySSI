import CryptoKit
import Foundation

struct AgentCommittedTurnProgress: Equatable {
  struct Turn: Equatable {
    let revision: Int64
    let status: AgentWorkspaceStatus
    let startedAt: Int64
    let updatedAt: Int64

    var isRunning: Bool {
      [.created, .queued, .running, .waitingResponse].contains(status)
    }

    func elapsed(at now: Int64, fallbackStart: Int64) -> Int64 {
      let start = startedAt > 0 ? startedAt : fallbackStart
      return max(0, (isRunning ? now : updatedAt) - start)
    }
  }

  private(set) var conversationID = ""
  private(set) var turns: [String: Turn] = [:]

  mutating func merge(conversationID: String, workspaces: [AgentWorkspace]) {
    if self.conversationID != conversationID {
      self.conversationID = conversationID
      turns.removeAll()
    }
    guard !conversationID.isBlank else { return }
    for workspace in workspaces where workspace.conversationId == conversationID &&
      !workspace.workspaceId.isBlank && workspace.workspaceId == workspace.taskId &&
      workspace.parentRunId.isBlank && workspace.deliveryMode == AgentDeliveryMode.respond.rawValue {
      let id = workspace.taskId
      let previous = turns[id]
      if let previous, previous.revision >= workspace.revision { continue }
      let statusAt: Int64
      if let previous, previous.status == workspace.status {
        statusAt = previous.updatedAt
      } else {
        statusAt = Self.statusTimestamp(workspace)
      }
      turns[id] = Turn(revision: workspace.revision, status: workspace.status,
                       startedAt: workspace.createdAtMillis, updatedAt: statusAt)
    }
  }

  func turn(_ id: String, conversationID: String) -> Turn? {
    guard self.conversationID == conversationID else { return nil }
    return turns[id]
  }

  private static func statusTimestamp(_ workspace: AgentWorkspace) -> Int64 {
    let kind: String
    switch workspace.status {
    case .completed: kind = AgentTaskEventKinds.completed
    case .failed: kind = AgentTaskEventKinds.failed
    case .cancelled: kind = AgentTaskEventKinds.cancelled
    case .paused: kind = AgentTaskEventKinds.paused
    case .blocked: kind = AgentTaskEventKinds.blocked
    case .waitingConfirmation: kind = AgentTaskEventKinds.waitingConfirmation
    default: return workspace.updatedAtMillis
    }
    let afterResume = workspace.eventJournal.reversed().prefix { $0.kind != AgentTaskEventKinds.resumed }
    return afterResume.last(where: { $0.kind == kind && $0.timestampMillis > 0 })?.timestampMillis ??
      workspace.updatedAtMillis
  }
}

struct AgentTranscriptRenderDiff: Codable, Equatable {
  var reset: Bool
  var replacementIndices: [Int]
  var appendFromIndex: Int
}

enum AgentProcessClockPolicy {
  static func visibleRequestStarts(_ messages: [ChatMessage], conversationId: String) -> [String: Int64] {
    guard !conversationId.isBlank else { return [:] }
    return messages.reduce(into: [:]) { result, message in
      guard message.conversationId == conversationId, message.isMine, !message.isSystem else { return }
      let start = GalaxySSIChatHistoryCursor(message).createdAtMillis
      guard start > 0 else { return }
      let key = AgentReplyWaitingIndicatorPolicy.turnKey(for: message)
      result[key] = min(result[key] ?? start, start)
    }
  }

  static func startedAt(request: Int64?, fallback: Int64) -> Int64 {
    [request, fallback].compactMap { $0 }.filter { $0 > 0 }.min() ?? fallback
  }

  static func pausesLocalClock(_ phase: AgentPhase) -> Bool {
    [.blocked, .paused, .waitingConfirmation].contains(phase)
  }

  static func pausesRemoteClock(_ status: String) -> Bool {
    ["blocked", "paused", "waiting_input", "waiting_approval", "waiting_confirmation"]
      .contains(AgentRemoteTaskStatusPolicy.normalize(status))
  }

  static func remotePauseTimestamp(_ task: AgentRemoteTaskStatusSnapshot) -> Int64 {
    let current = AgentRemoteTaskStatusPolicy.normalize(task.status)
    return task.history.reversed().prefix {
      AgentRemoteTaskStatusPolicy.normalize($0.status) == current
    }.last?.updatedAtMillis ?? task.updatedAtMillis
  }
  static func sameTurn(_ process: AgentTranscriptEntry, _ candidate: AgentTranscriptEntry) -> Bool {
    guard process.conversationId == candidate.conversationId else { return false }
    if !process.turnId.isBlank { return process.turnId == candidate.turnId }
    if !process.taskId.isBlank { return process.taskId == candidate.taskId }
    return false
  }

  static func finalReplyTimestamp(
    for process: AgentTranscriptEntry,
    in entries: [AgentTranscriptEntry]
  ) -> Int64? {
    entries
      .filter { $0.role == .assistant && !AgentTranscriptRenderPolicy.isLiveStream($0) && sameTurn(process, $0) }
      .map(\.timestampMillis)
      .max()
  }
}

struct AgentTranscriptExecutionProgress: Equatable {
  struct TurnKey: Hashable {
    let conversationId: String
    let turnId: String

    init(_ message: ChatMessage) {
      conversationId = message.conversationId
      turnId = AgentReplyWaitingIndicatorPolicy.turnKey(for: message)
    }
  }

  let status: AgentInteractiveProgressStatus
  let startedAt: Int64
  let updatedAt: Int64

  static func resolve(
    owned: Self?, cached: Self?, deliveredAt: Int64?, requestStartedAt: Int64? = nil
  ) -> Self? {
    func rebased(_ progress: Self) -> Self {
      Self(status: progress.status, startedAt: AgentProcessClockPolicy.startedAt(request: requestStartedAt,
        fallback: progress.startedAt), updatedAt: progress.updatedAt)
    }
    if let owned { return rebased(owned) }
    guard let cached = cached.map(rebased) else {
      guard let requestStartedAt, requestStartedAt > 0,
            let deliveredAt, deliveredAt >= requestStartedAt else { return nil }
      return Self(status: .completed, startedAt: requestStartedAt, updatedAt: deliveredAt)
    }
    if cached.status.animating, let deliveredAt, deliveredAt >= cached.updatedAt, deliveredAt >= cached.startedAt {
      return Self(status: .completed, startedAt: cached.startedAt, updatedAt: deliveredAt)
    }
    if cached.status == .completed, let deliveredAt, deliveredAt >= cached.startedAt {
      return Self(status: .completed, startedAt: cached.startedAt, updatedAt: min(cached.updatedAt, deliveredAt))
    }
    return cached
  }

  static func finalDeliveryTime(_ message: ChatMessage) -> Int64? {
    guard !message.isMine, !message.isSystem, !message.turnId.isBlank,
          [.delivered, .read].contains(message.deliveryStatus),
          !message.remoteMessageId.hasPrefix("agent-stream-"),
          !message.deliveryTrace.contains(where: { event in
            let stage = event.stage.lowercased()
            return ["interim", "milestone", "partial", "cancelled", "failed", "blocked", "denied"]
              .contains(where: stage.contains)
          }) else { return nil }
    return Int64(message.createdAt.timeIntervalSince1970 * 1_000)
  }

  static func finalDeliveryTimes(_ messages: [ChatMessage]) -> [TurnKey: Int64] {
    messages.reduce(into: [:]) { result, message in
      guard let timestamp = finalDeliveryTime(message) else { return }
      let key = TurnKey(message)
      result[key] = min(result[key] ?? timestamp, timestamp)
    }
  }

  static func committed(_ turn: AgentCommittedTurnProgress.Turn) -> Self {
    let status: AgentInteractiveProgressStatus
    switch turn.status {
    case .created, .queued, .running: status = .running
    case .waitingResponse: status = .waitingResponse
    case .waitingConfirmation: status = .waitingConfirmation
    case .paused: status = .paused
    case .blocked: status = .blocked
    case .completed: status = .completed
    case .failed: status = .failed
    case .cancelled: status = .cancelled
    }
    return Self(status: status, startedAt: turn.startedAt, updatedAt: turn.updatedAt)
  }

  static func remoteStatus(_ value: String) -> AgentInteractiveProgressStatus {
    switch AgentRemoteTaskStatusPolicy.normalize(value) {
    case "created", "queued", "accepted", "starting", "running", "executing", "recovering": return .running
    case "waiting_response", "waiting_reply", "cancelling": return .waitingResponse
    case "waiting_input", "waiting_approval", "waiting_confirmation": return .waitingConfirmation
    case "paused": return .paused
    case "blocked": return .blocked
    case "completed": return .completed
    case "failed", "timed_out", "not_found": return .failed
    case "cancelled": return .cancelled
    default: return .unknown
    }
  }

  static func voiceStatus(_ state: VoiceAgentRunState) -> AgentInteractiveProgressStatus {
    switch state {
    case .created, .accepted, .queued, .starting, .running: return .running
    case .waitingInput, .waitingApproval: return .waitingConfirmation
    case .cancelling: return .waitingResponse
    case .completed: return .completed
    case .failed, .timedOut: return .failed
    case .cancelled: return .cancelled
    }
  }
}

final class AgentProcessClock {
  let startedAtMillis: Int64
  private(set) var completedAtMillis: Int64?

  init(startedAtMillis: Int64, completedAtMillis: Int64? = nil) {
    self.startedAtMillis = startedAtMillis
    self.completedAtMillis = completedAtMillis.map { max($0, startedAtMillis) }
  }

  func observe(completedAtMillis: Int64?) {
    guard self.completedAtMillis == nil, let completedAtMillis else { return }
    self.completedAtMillis = max(completedAtMillis, startedAtMillis)
  }

  func elapsed(at nowMillis: Int64) -> Int64 {
    max(0, (completedAtMillis ?? nowMillis) - startedAtMillis)
  }
}

enum AgentTranscriptRenderPolicy {
  static func identity(_ entry: AgentTranscriptEntry) -> String {
    entry.dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(entry.id)
  }

  static func signature(_ entry: AgentTranscriptEntry) -> Int {
    var fields = [
      entry.role.rawValue,
      String(entry.id.hasPrefix("agent-stream-preview-")),
      entry.turnId,
      entry.taskId,
      entry.textSha256.ifBlank(entry.text),
      String(entry.text.count),
      String(entry.textChunkCount),
      String(entry.textLength),
      entry.richOutputSha256.ifBlank(entry.richOutputJson),
      String(entry.richOutputJson.count),
      String(entry.richOutputChunkCount),
      String(entry.richOutputLength),
      entry.sourceConversationId,
      entry.sourceConversationTitle,
      entry.sourceEntryId
    ]
    if entry.role != .assistant {
      fields.insert(String(entry.timestampMillis), at: 1)
    }
    return stableSignature(fields)
  }

  static func isLiveStream(_ entry: AgentTranscriptEntry) -> Bool {
    entry.role == .assistant && entry.id.hasPrefix("agent-stream-")
  }

  static func processGroupSignatures(_ entries: [AgentTranscriptEntry]) -> [String: Int] {
    let finalReplies = Dictionary(grouping: entries.filter {
      $0.role == .assistant && !isLiveStream($0)
    }) {
      AgentTranscriptPresentationPolicy.processGroupKey($0)
    }
    return Dictionary(uniqueKeysWithValues: Dictionary(grouping: entries.filter { $0.role == .process }) {
      AgentTranscriptPresentationPolicy.processGroupKey($0)
    }.map { key, groupEntries in
      let visibleNarration = AgentTranscriptPresentationPolicy.visibleProcessSegments(
        groupEntries
          .sorted { $0.timestampMillis < $1.timestampMillis }
          .uniquedByProcessNarrationIdentity()
      ).flatMap(\.entries)
      let narrationSignature = visibleNarration.reduce(1) { result, entry in
        31 &* result &+ sourceProcessSignature(entry)
      }
      let signature = (finalReplies[key] ?? []).reduce(narrationSignature) { result, entry in
        31 &* result &+ stableSignature([identity(entry), String(entry.timestampMillis)])
      }
      return (key, signature)
    })
  }

  private static func sourceProcessSignature(_ entry: AgentTranscriptEntry) -> Int {
    stableSignature([
      AgentTranscriptPresentationPolicy.processNarrationIdentity(entry.text),
      entry.richOutputJson,
      entry.textSha256,
      entry.richOutputSha256
    ])
  }

  private static func stableSignature(_ fields: [String]) -> Int {
    let hash = Data(SHA256.hash(data: Data(fields.joined(separator: "\u{001f}").utf8)))
    let value = hash.prefix(8).reduce(UInt64(0)) { partial, byte in
      (partial << 8) | UInt64(byte)
    }
    return Int(truncatingIfNeeded: value)
  }

  static func diff(
    renderedIds: [String],
    renderedSignatures: [String: Int],
    incoming: [AgentTranscriptEntry]
  ) -> AgentTranscriptRenderDiff {
    let incomingIds = incoming.map(identity)
    let hasStablePrefix = renderedIds.count <= incomingIds.count &&
      Array(incomingIds.prefix(renderedIds.count)) == renderedIds
    guard hasStablePrefix else {
      return AgentTranscriptRenderDiff(reset: true, replacementIndices: [], appendFromIndex: 0)
    }
    let signatureReplacements = renderedIds.indices.filter { index in
      let entry = incoming[index]
      return renderedSignatures[identity(entry)] != signature(entry)
    }
    let changedAssistantGroups = Set(incoming.enumerated().compactMap { index, entry -> String? in
      guard entry.role == .assistant,
        index >= renderedIds.count ||
          (!isLiveStream(entry) && signatureReplacements.contains(index)) else {
        return nil
      }
      return AgentTranscriptPresentationPolicy.processGroupKey(entry)
    })
    let processCompletionReplacements = renderedIds.indices.filter { index in
      let entry = incoming[index]
      return entry.role == .process &&
        changedAssistantGroups.contains(AgentTranscriptPresentationPolicy.processGroupKey(entry))
    }
    let replacements = Array(Set(signatureReplacements + processCompletionReplacements)).sorted()
    return AgentTranscriptRenderDiff(
      reset: false,
      replacementIndices: replacements,
      appendFromIndex: renderedIds.count
    )
  }
}

private extension Array where Element == AgentTranscriptEntry {
  func uniquedByProcessNarrationIdentity() -> [AgentTranscriptEntry] {
    var seen = Set<String>()
    return filter {
      seen.insert(AgentTranscriptPresentationPolicy.processNarrationIdentity($0.text)).inserted
    }
  }
}
