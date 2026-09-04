import CryptoKit
import Foundation

enum VoiceAgentRunState: String, Codable, CaseIterable, Identifiable {
  case created = "CREATED"
  case accepted = "ACCEPTED"
  case queued = "QUEUED"
  case starting = "STARTING"
  case running = "RUNNING"
  case waitingInput = "WAITING_INPUT"
  case waitingApproval = "WAITING_APPROVAL"
  case cancelling = "CANCELLING"
  case completed = "COMPLETED"
  case failed = "FAILED"
  case cancelled = "CANCELLED"
  case timedOut = "TIMED_OUT"

  var id: String { rawValue }

  var isTerminal: Bool {
    [.completed, .failed, .cancelled, .timedOut].contains(self)
  }
}

struct VoiceAgentRunRequest: Equatable {
  var sessionId: String
  var conversationId: String
  var turnId: String
  var taskId: String
  var sourceMessageId: String
  var contactId: String
  var agentId: String
  var agentName: String
  var goal: String
  var idempotencyKey: String
  var traceId: String
  var createdAtMillis: Int64
}

struct VoiceAgentRunSnapshot: Codable, Equatable, Identifiable {
  var runId: String
  var sessionId: String
  var conversationId: String
  var turnId: String
  var taskId: String
  var sourceMessageId: String
  var contactId: String
  var agentId: String
  var agentName: String
  var goal: String
  var idempotencyKey: String
  var traceId: String
  var state: VoiceAgentRunState
  var stage: String
  var progressMessage: String
  var progressPercent: Double?
  var partialResult: String
  var resultSummary: String
  var approvalId: String
  var lastStatusSequence: Int64
  var lastPartialSequence: Int64
  var seenEventIds: [String]
  var createdAtMillis: Int64
  var acceptedAtMillis: Int64
  var updatedAtMillis: Int64
  var completedAtMillis: Int64

  var id: String { runId }
  var hasRemoteAcceptance: Bool { acceptedAtMillis > 0 }
  var cancellable: Bool { !state.isTerminal && state != .cancelling }

  enum CodingKeys: String, CodingKey {
    case runId = "run_id"
    case sessionId = "session_id"
    case conversationId = "conversation_id"
    case turnId = "turn_id"
    case taskId = "task_id"
    case sourceMessageId = "source_message_id"
    case contactId = "contact_id"
    case agentId = "agent_id"
    case agentName = "agent_name"
    case goal
    case idempotencyKey = "idempotency_key"
    case traceId = "trace_id"
    case state
    case stage
    case progressMessage = "progress_message"
    case progressPercent = "progress_percent"
    case partialResult = "partial_result"
    case resultSummary = "result_summary"
    case approvalId = "approval_id"
    case lastStatusSequence = "last_status_sequence"
    case lastPartialSequence = "last_partial_sequence"
    case seenEventIds = "seen_event_ids"
    case createdAtMillis = "created_at_millis"
    case acceptedAtMillis = "accepted_at_millis"
    case updatedAtMillis = "updated_at_millis"
    case completedAtMillis = "completed_at_millis"
  }

  init(
    runId: String,
    sessionId: String,
    conversationId: String,
    turnId: String,
    taskId: String,
    sourceMessageId: String,
    contactId: String,
    agentId: String,
    agentName: String,
    goal: String,
    idempotencyKey: String,
    traceId: String,
    state: VoiceAgentRunState = .created,
    stage: String = "",
    progressMessage: String = "",
    progressPercent: Double? = nil,
    partialResult: String = "",
    resultSummary: String = "",
    approvalId: String = "",
    lastStatusSequence: Int64 = 0,
    lastPartialSequence: Int64 = 0,
    seenEventIds: [String] = [],
    createdAtMillis: Int64,
    acceptedAtMillis: Int64 = 0,
    updatedAtMillis: Int64,
    completedAtMillis: Int64 = 0
  ) {
    self.runId = runId
    self.sessionId = sessionId
    self.conversationId = conversationId
    self.turnId = turnId
    self.taskId = taskId
    self.sourceMessageId = sourceMessageId
    self.contactId = contactId
    self.agentId = agentId
    self.agentName = String(agentName.prefix(256))
    self.goal = String(goal.prefix(4_000))
    self.idempotencyKey = idempotencyKey
    self.traceId = traceId
    self.state = state
    self.stage = String(stage.prefix(256))
    self.progressMessage = String(progressMessage.prefix(2_000))
    self.progressPercent = progressPercent?.clamped(to: 0...100)
    self.partialResult = String(partialResult.prefix(16_000))
    self.resultSummary = String(resultSummary.prefix(8_000))
    self.approvalId = String(approvalId.prefix(512))
    self.lastStatusSequence = max(lastStatusSequence, 0)
    self.lastPartialSequence = max(lastPartialSequence, 0)
    self.seenEventIds = Array(seenEventIds.suffix(256))
    self.createdAtMillis = max(createdAtMillis, 0)
    self.acceptedAtMillis = max(acceptedAtMillis, 0)
    self.updatedAtMillis = max(updatedAtMillis, self.createdAtMillis)
    self.completedAtMillis = max(completedAtMillis, 0)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      runId: try container.decodeIfPresent(String.self, forKey: .runId) ?? "",
      sessionId: try container.decodeIfPresent(String.self, forKey: .sessionId) ?? "",
      conversationId: try container.decodeIfPresent(String.self, forKey: .conversationId) ?? "",
      turnId: try container.decodeIfPresent(String.self, forKey: .turnId) ?? "",
      taskId: try container.decodeIfPresent(String.self, forKey: .taskId) ?? "",
      sourceMessageId: try container.decodeIfPresent(String.self, forKey: .sourceMessageId) ?? "",
      contactId: try container.decodeIfPresent(String.self, forKey: .contactId) ?? "",
      agentId: try container.decodeIfPresent(String.self, forKey: .agentId) ?? "",
      agentName: try container.decodeIfPresent(String.self, forKey: .agentName) ?? "",
      goal: try container.decodeIfPresent(String.self, forKey: .goal) ?? "",
      idempotencyKey: try container.decodeIfPresent(String.self, forKey: .idempotencyKey) ?? "",
      traceId: try container.decodeIfPresent(String.self, forKey: .traceId) ?? "",
      state: try container.decodeIfPresent(VoiceAgentRunState.self, forKey: .state) ?? .created,
      stage: try container.decodeIfPresent(String.self, forKey: .stage) ?? "",
      progressMessage: try container.decodeIfPresent(String.self, forKey: .progressMessage) ?? "",
      progressPercent: try container.decodeIfPresent(Double.self, forKey: .progressPercent),
      partialResult: try container.decodeIfPresent(String.self, forKey: .partialResult) ?? "",
      resultSummary: try container.decodeIfPresent(String.self, forKey: .resultSummary) ?? "",
      approvalId: try container.decodeIfPresent(String.self, forKey: .approvalId) ?? "",
      lastStatusSequence: try container.decodeIfPresent(Int64.self, forKey: .lastStatusSequence) ?? 0,
      lastPartialSequence: try container.decodeIfPresent(Int64.self, forKey: .lastPartialSequence) ?? 0,
      seenEventIds: try container.decodeIfPresent([String].self, forKey: .seenEventIds) ?? [],
      createdAtMillis: try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? 0,
      acceptedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .acceptedAtMillis) ?? 0,
      updatedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .updatedAtMillis) ?? 0,
      completedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .completedAtMillis) ?? 0
    )
  }
}

struct VoiceAgentRunUpdate: Equatable {
  var snapshot: VoiceAgentRunSnapshot
  var eventId: String
  var eventKind: String
  var message: String
  var firstAcceptance: Bool
  var firstProgress: Bool
  var firstPartialResult: Bool
}

protocol VoiceAgentRunRepository: AnyObject {
  func list() -> [VoiceAgentRunSnapshot]
  func save(_ snapshot: VoiceAgentRunSnapshot)
  func clear()
}

final class UserDefaultsVoiceAgentRunRepository: VoiceAgentRunRepository {
  private let defaults: UserDefaults
  private let key: String
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    defaults: UserDefaults = .standard,
    key: String = "galaxyssi.voice.agent.runs.v1"
  ) {
    self.defaults = defaults
    self.key = key
  }

  func list() -> [VoiceAgentRunSnapshot] {
    guard let data = defaults.data(forKey: key) else { return [] }
    return (try? decoder.decode([VoiceAgentRunSnapshot].self, from: data)) ?? []
  }

  func save(_ snapshot: VoiceAgentRunSnapshot) {
    var snapshots = list().filter { $0.runId != snapshot.runId }
    snapshots.append(snapshot)
    snapshots.sort { lhs, rhs in
      if lhs.updatedAtMillis != rhs.updatedAtMillis {
        return lhs.updatedAtMillis > rhs.updatedAtMillis
      }
      return lhs.runId < rhs.runId
    }
    guard let data = try? encoder.encode(Array(snapshots.prefix(256))) else { return }
    defaults.set(data, forKey: key)
  }

  func clear() {
    defaults.removeObject(forKey: key)
  }
}

final class VoiceAgentRunBridge {
  typealias Listener = (VoiceAgentRunUpdate) -> Void

  private let repository: VoiceAgentRunRepository
  private let controlStore: AgentRunControlStore
  private let clock: () -> Int64
  private let lock = NSRecursiveLock()
  private var listeners: [String: Listener] = [:]

  init(
    repository: VoiceAgentRunRepository = UserDefaultsVoiceAgentRunRepository(),
    controlStore: AgentRunControlStore = UserDefaultsAgentRunEventStore(),
    clock: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
  ) {
    self.repository = repository
    self.controlStore = controlStore
    self.clock = clock
  }

  @discardableResult
  func addListener(_ listener: @escaping Listener) -> String {
    let id = UUID().uuidString
    locked { listeners[id] = listener }
    return id
  }

  func removeListener(_ id: String) {
    locked { listeners.removeValue(forKey: id) }
  }

  @discardableResult
  func createRun(_ request: VoiceAgentRunRequest) -> VoiceAgentRunSnapshot {
    let result: (snapshot: VoiceAgentRunSnapshot, update: VoiceAgentRunUpdate?) = locked {
      if let existing = repository.list().first(where: {
        $0.idempotencyKey == request.idempotencyKey
      }) {
        return (existing, nil)
      }
      let now = request.createdAtMillis > 0 ? request.createdAtMillis : clock()
      let snapshot = VoiceAgentRunSnapshot(
        runId: stableRunId(request.idempotencyKey),
        sessionId: clean(request.sessionId),
        conversationId: clean(request.conversationId),
        turnId: clean(request.turnId),
        taskId: clean(request.taskId),
        sourceMessageId: clean(request.sourceMessageId),
        contactId: clean(request.contactId),
        agentId: clean(request.agentId),
        agentName: request.agentName,
        goal: request.goal,
        idempotencyKey: clean(request.idempotencyKey),
        traceId: clean(request.traceId),
        createdAtMillis: now,
        updatedAtMillis: now
      )
      repository.save(snapshot)
      appendControlEvent(
        snapshot: snapshot,
        eventId: "voice-run-created:\(snapshot.runId)",
        type: .runCreated,
        payload: ["voice_event": .string("created")]
      )
      return (
        snapshot,
        VoiceAgentRunUpdate(
          snapshot: snapshot,
          eventId: "voice-run-created:\(snapshot.runId)",
          eventKind: "created",
          message: "",
          firstAcceptance: false,
          firstProgress: false,
          firstPartialResult: false
        )
      )
    }
    if let update = result.update { notify(update) }
    return result.snapshot
  }

  @discardableResult
  func bindTransportIdentity(
    sessionId: String,
    taskId: String,
    sourceMessageId: String
  ) -> VoiceAgentRunSnapshot? {
    let result: (snapshot: VoiceAgentRunSnapshot?, update: VoiceAgentRunUpdate?) = locked {
      guard let current = repository.list().first(where: { $0.sessionId == clean(sessionId) }),
            !current.state.isTerminal else {
        return (nil, nil)
      }
      let normalizedTaskId = clean(taskId)
      let normalizedSourceMessageId = clean(sourceMessageId)
      guard !normalizedTaskId.isEmpty || !normalizedSourceMessageId.isEmpty else {
        return (current, nil)
      }
      var next = current
      if !normalizedTaskId.isEmpty {
        next.taskId = normalizedTaskId
      }
      if !normalizedSourceMessageId.isEmpty {
        next.sourceMessageId = normalizedSourceMessageId
      }
      guard next != current else { return (current, nil) }
      next.updatedAtMillis = max(clock(), current.updatedAtMillis)
      repository.save(next)
      return (
        next,
        VoiceAgentRunUpdate(
          snapshot: next,
          eventId: "transport-bound:\(next.runId):\(next.updatedAtMillis)",
          eventKind: "transport_bound",
          message: "",
          firstAcceptance: false,
          firstProgress: false,
          firstPartialResult: false
        )
      )
    }
    if let update = result.update { notify(update) }
    return result.snapshot
  }

  @discardableResult
  func consumeRemoteEnvelope(_ envelope: [String: Any]) -> VoiceAgentRunUpdate? {
    let update: VoiceAgentRunUpdate? = locked {
      let normalizedEnvelope = flatten(envelope)
      let taskId = string(normalizedEnvelope, "task_id")
      let turnId = string(normalizedEnvelope, "turn_id")
      let sourceMessageId = string(normalizedEnvelope, "source_message_id")
        .ifBlank(string(normalizedEnvelope, "message_id"))
      let runId = string(normalizedEnvelope, "run_id")
      guard let current = repository.list().first(where: { snapshot in
        (!runId.isEmpty && snapshot.runId == runId) ||
          (!taskId.isEmpty && snapshot.taskId == taskId) ||
          (!turnId.isEmpty && snapshot.turnId == turnId) ||
          (!sourceMessageId.isEmpty && snapshot.sourceMessageId == sourceMessageId)
      }) else {
        return nil
      }
      guard !current.state.isTerminal else { return nil }
      let statusSequence = int64(normalizedEnvelope, "status_seq")
      if statusSequence > 0 && statusSequence < current.lastStatusSequence {
        return nil
      }
      let status = string(normalizedEnvelope, "task_status").lowercased()
      let eventKind = normalizedEventKind(
        string(normalizedEnvelope, "event_type"),
        fallback: status
      )
      let progressPayload = object(normalizedEnvelope["progress_event"])
      let partialPayload = object(normalizedEnvelope["partial_result"])
      let approvalPayload = object(normalizedEnvelope["approval_request"])
      let partialSequence = int64(partialPayload, "sequence")
        .ifZero(int64(normalizedEnvelope, "partial_sequence"))
      let eventId = string(normalizedEnvelope, "event_id").ifBlank(
        "status:\(current.taskId):\(max(statusSequence, partialSequence)):\(eventKind)"
      )
      if current.seenEventIds.contains(eventId) {
        return nil
      }
      let progressMessage = string(progressPayload, "message")
        .ifBlank(string(normalizedEnvelope, "progress_message"))
        .ifBlank(string(normalizedEnvelope, "message"))
      let partialText = string(partialPayload, "text")
        .ifBlank(string(partialPayload, "content"))
        .ifBlank(string(normalizedEnvelope, "partial_text"))
      let approvalId = string(approvalPayload, "approval_id")
        .ifBlank(string(approvalPayload, "request_id"))
        .ifBlank(string(normalizedEnvelope, "approval_id"))
      let nextState = state(status: status, eventKind: eventKind)
      let now = max(clock(), current.updatedAtMillis)
      let acceptedAt = current.acceptedAtMillis > 0 || !isAcceptance(status: status, eventKind: eventKind)
        ? current.acceptedAtMillis
        : now
      let nextPartial = mergePartial(current.partialResult, partialText)
      let nextProgressMessage = progressMessage.ifBlank(current.progressMessage)
      let nextStateValue = nextState ?? current.state
      let completedAt = nextStateValue.isTerminal ? (current.completedAtMillis > 0 ? current.completedAtMillis : now) : 0
      let next = VoiceAgentRunSnapshot(
        runId: current.runId,
        sessionId: current.sessionId,
        conversationId: current.conversationId,
        turnId: current.turnId,
        taskId: current.taskId,
        sourceMessageId: current.sourceMessageId,
        contactId: current.contactId,
        agentId: current.agentId,
        agentName: current.agentName,
        goal: current.goal,
        idempotencyKey: current.idempotencyKey,
        traceId: current.traceId,
        state: nextStateValue,
        stage: string(normalizedEnvelope, "stage")
          .ifBlank(string(normalizedEnvelope, "current_step"))
          .ifBlank(current.stage),
        progressMessage: nextProgressMessage,
        progressPercent: double(normalizedEnvelope, "progress_percent")
          ?? double(progressPayload, "percent")
          ?? current.progressPercent,
        partialResult: nextPartial,
        resultSummary: string(normalizedEnvelope, "result_summary")
          .ifBlank(string(normalizedEnvelope, "result"))
          .ifBlank(string(normalizedEnvelope, "content"))
          .ifBlank(current.resultSummary),
        approvalId: approvalId.ifBlank(current.approvalId),
        lastStatusSequence: max(current.lastStatusSequence, statusSequence),
        lastPartialSequence: max(current.lastPartialSequence, partialSequence),
        seenEventIds: Array((current.seenEventIds + [eventId]).suffix(256)),
        createdAtMillis: current.createdAtMillis,
        acceptedAtMillis: acceptedAt,
        updatedAtMillis: now,
        completedAtMillis: completedAt
      )
      guard next != current else { return nil }
      repository.save(next)
      appendControlEvent(
        snapshot: next,
        eventId: eventId,
        type: controlEventType(state: nextStateValue, eventKind: eventKind),
        payload: controlPayload(
          eventKind: eventKind,
          message: progressMessage.ifBlank(partialText),
          percent: next.progressPercent
        )
      )
      return VoiceAgentRunUpdate(
        snapshot: next,
        eventId: eventId,
        eventKind: eventKind,
        message: progressMessage.ifBlank(partialText),
        firstAcceptance: !current.hasRemoteAcceptance && next.hasRemoteAcceptance,
        firstProgress: current.progressMessage.isEmpty && !next.progressMessage.isEmpty,
        firstPartialResult: current.partialResult.isEmpty && !next.partialResult.isEmpty
      )
    }
    if let update { notify(update) }
    return update
  }

  @discardableResult
  func markCancellationRequested(sessionId: String) -> VoiceAgentRunSnapshot? {
    let result: (snapshot: VoiceAgentRunSnapshot?, update: VoiceAgentRunUpdate?) = locked {
      guard let current = repository.list().first(where: { $0.sessionId == clean(sessionId) }),
            current.cancellable else {
        return (nil, nil)
      }
      let now = max(clock(), current.updatedAtMillis)
      let next = VoiceAgentRunSnapshot(
        runId: current.runId,
        sessionId: current.sessionId,
        conversationId: current.conversationId,
        turnId: current.turnId,
        taskId: current.taskId,
        sourceMessageId: current.sourceMessageId,
        contactId: current.contactId,
        agentId: current.agentId,
        agentName: current.agentName,
        goal: current.goal,
        idempotencyKey: current.idempotencyKey,
        traceId: current.traceId,
        state: .cancelling,
        stage: "cancelling",
        progressMessage: current.progressMessage,
        progressPercent: current.progressPercent,
        partialResult: current.partialResult,
        resultSummary: current.resultSummary,
        approvalId: current.approvalId,
        lastStatusSequence: current.lastStatusSequence,
        lastPartialSequence: current.lastPartialSequence,
        seenEventIds: current.seenEventIds,
        createdAtMillis: current.createdAtMillis,
        acceptedAtMillis: current.acceptedAtMillis,
        updatedAtMillis: now,
        completedAtMillis: current.completedAtMillis
      )
      repository.save(next)
      appendControlEvent(
        snapshot: next,
        eventId: "local-cancelling:\(next.runId):\(now)",
        type: .paused,
        payload: [
          "voice_event": .string("cancelling"),
          "reason": .string("user_requested_cancellation")
        ]
      )
      return (
        next,
        VoiceAgentRunUpdate(
          snapshot: next,
          eventId: "local-cancelling:\(next.runId):\(now)",
          eventKind: "cancelling",
          message: "",
          firstAcceptance: false,
          firstProgress: false,
          firstPartialResult: false
        )
      )
    }
    if let update = result.update { notify(update) }
    return result.snapshot
  }

  @discardableResult
  func markFinalResult(sessionId: String, content: String) -> VoiceAgentRunSnapshot? {
    let result: (snapshot: VoiceAgentRunSnapshot?, update: VoiceAgentRunUpdate?) = locked {
      guard let current = repository.list().first(where: { $0.sessionId == clean(sessionId) }),
            !current.state.isTerminal else {
        return (nil, nil)
      }
      let now = max(clock(), current.updatedAtMillis)
      let next = VoiceAgentRunSnapshot(
        runId: current.runId,
        sessionId: current.sessionId,
        conversationId: current.conversationId,
        turnId: current.turnId,
        taskId: current.taskId,
        sourceMessageId: current.sourceMessageId,
        contactId: current.contactId,
        agentId: current.agentId,
        agentName: current.agentName,
        goal: current.goal,
        idempotencyKey: current.idempotencyKey,
        traceId: current.traceId,
        state: .completed,
        stage: "completed",
        progressMessage: current.progressMessage,
        progressPercent: 100,
        partialResult: current.partialResult,
        resultSummary: String(content.prefix(8_000)),
        approvalId: current.approvalId,
        lastStatusSequence: current.lastStatusSequence,
        lastPartialSequence: current.lastPartialSequence,
        seenEventIds: current.seenEventIds,
        createdAtMillis: current.createdAtMillis,
        acceptedAtMillis: current.acceptedAtMillis,
        updatedAtMillis: now,
        completedAtMillis: now
      )
      repository.save(next)
      appendControlEvent(
        snapshot: next,
        eventId: "legacy-final:\(next.runId):\(now)",
        type: .runCompleted,
        payload: [
          "voice_event": .string("completed"),
          "result": .string(String(content.prefix(8_000)))
        ]
      )
      return (
        next,
        VoiceAgentRunUpdate(
          snapshot: next,
          eventId: "legacy-final:\(next.runId):\(now)",
          eventKind: "completed",
          message: String(content.prefix(8_000)),
          firstAcceptance: false,
          firstProgress: false,
          firstPartialResult: false
        )
      )
    }
    if let update = result.update { notify(update) }
    return result.snapshot
  }

  @discardableResult
  func markTimedOut(runId: String, reason: String = "The remote Agent run did not finish before cancellation expired.") -> VoiceAgentRunSnapshot? {
    let result: (snapshot: VoiceAgentRunSnapshot?, update: VoiceAgentRunUpdate?) = locked {
      guard let current = repository.list().first(where: { $0.runId == clean(runId) }),
            !current.state.isTerminal else {
        return (nil, nil)
      }
      let now = max(clock(), current.updatedAtMillis)
      let next = VoiceAgentRunSnapshot(
        runId: current.runId,
        sessionId: current.sessionId,
        conversationId: current.conversationId,
        turnId: current.turnId,
        taskId: current.taskId,
        sourceMessageId: current.sourceMessageId,
        contactId: current.contactId,
        agentId: current.agentId,
        agentName: current.agentName,
        goal: current.goal,
        idempotencyKey: current.idempotencyKey,
        traceId: current.traceId,
        state: .timedOut,
        stage: "timed_out",
        progressMessage: current.progressMessage,
        progressPercent: current.progressPercent,
        partialResult: current.partialResult,
        resultSummary: String(reason.prefix(8_000)),
        approvalId: current.approvalId,
        lastStatusSequence: current.lastStatusSequence,
        lastPartialSequence: current.lastPartialSequence,
        seenEventIds: current.seenEventIds,
        createdAtMillis: current.createdAtMillis,
        acceptedAtMillis: current.acceptedAtMillis,
        updatedAtMillis: now,
        completedAtMillis: now
      )
      repository.save(next)
      appendControlEvent(
        snapshot: next,
        eventId: "local-timeout:\(next.runId):\(now)",
        type: .runFailed,
        payload: [
          "voice_event": .string("timed_out"),
          "reason": .string(String(reason.prefix(2_000)))
        ]
      )
      return (
        next,
        VoiceAgentRunUpdate(
          snapshot: next,
          eventId: "local-timeout:\(next.runId):\(now)",
          eventKind: "timed_out",
          message: String(reason.prefix(2_000)),
          firstAcceptance: false,
          firstProgress: false,
          firstPartialResult: false
        )
      )
    }
    if let update = result.update { notify(update) }
    return result.snapshot
  }

  @discardableResult
  func reconcileStaleCancellations(
    nowMillis: Int64? = nil,
    timeoutMillis: Int64 = 5 * 60 * 1_000
  ) -> [VoiceAgentRunSnapshot] {
    let now = max(nowMillis ?? clock(), 0)
    let staleIds = locked {
      repository.list()
        .filter {
          $0.state == .cancelling &&
            now >= $0.updatedAtMillis &&
            now - $0.updatedAtMillis >= max(timeoutMillis, 1)
        }
        .map(\.runId)
    }
    return staleIds.compactMap {
      markTimedOut(runId: $0)
    }
  }

  func find(runId: String) -> VoiceAgentRunSnapshot? {
    locked { repository.list().first { $0.runId == clean(runId) } }
  }

  func find(sessionId: String) -> VoiceAgentRunSnapshot? {
    locked { repository.list().first { $0.sessionId == clean(sessionId) } }
  }

  func findByTaskId(_ taskId: String) -> VoiceAgentRunSnapshot? {
    locked { repository.list().first { $0.taskId == clean(taskId) } }
  }

  func snapshots(conversationId: String = "") -> [VoiceAgentRunSnapshot] {
    locked {
      repository.list()
        .filter { conversationId.isEmpty || $0.conversationId == clean(conversationId) }
        .sorted { $0.createdAtMillis < $1.createdAtMillis }
    }
  }

  func clear() {
    locked { repository.clear() }
  }

  private func notify(_ update: VoiceAgentRunUpdate) {
    let callbacks = locked { Array(listeners.values) }
    callbacks.forEach { callback in
      DispatchQueue.main.async {
        callback(update)
      }
    }
  }

  private func appendControlEvent(
    snapshot: VoiceAgentRunSnapshot,
    eventId: String,
    type: AgentRunControlEventType,
    payload: AgentRunControlPayload
  ) {
    _ = controlStore.appendNext(AgentRunControlEvent(
      eventId: eventId,
      conversationId: snapshot.conversationId,
      messageId: snapshot.sourceMessageId.ifBlank(snapshot.turnId),
      taskId: snapshot.taskId.ifBlank(snapshot.runId),
      runId: snapshot.runId,
      agentId: snapshot.agentId,
      deviceId: "ios",
      type: type,
      sequence: 0,
      timestampMillis: snapshot.updatedAtMillis,
      payload: payload
    ))
  }

  private func controlEventType(
    state: VoiceAgentRunState,
    eventKind: String
  ) -> AgentRunControlEventType {
    let normalized = eventKind
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "-", with: "_")
    if normalized.contains("progress") || normalized.contains("partial") {
      return .toolProgress
    }
    switch state {
    case .created:
      return .runCreated
    case .accepted:
      return .agentConnected
    case .queued:
      return .runQueued
    case .starting:
      return .runStarted
    case .running:
      return .stepStarted
    case .waitingInput:
      return .waitingForUser
    case .waitingApproval:
      return .toolPermissionRequired
    case .cancelling:
      return .paused
    case .completed:
      return .runCompleted
    case .failed, .timedOut:
      return .runFailed
    case .cancelled:
      return .runCancelled
    }
  }

  private func controlPayload(
    eventKind: String,
    message: String,
    percent: Double?
  ) -> AgentRunControlPayload {
    var payload: AgentRunControlPayload = [
      "voice_event": .string(eventKind)
    ]
    if !message.isEmpty { payload["message"] = .string(String(message.prefix(2_000))) }
    if let percent { payload["progress_percent"] = .int(Int64(percent.rounded())) }
    return payload
  }

  private func state(status: String, eventKind: String) -> VoiceAgentRunState? {
    let value = eventKind.ifBlank(status).replacingOccurrences(of: "-", with: "_")
    switch value {
    case "accepted", "agent_accepted", "run_accepted": return .accepted
    case "queued", "run_queued": return .queued
    case "starting", "started", "run_started": return .starting
    case "running", "progress", "agent_progress", "run_progress": return .running
    case "waiting_input", "waiting_for_user": return .waitingInput
    case "waiting_approval", "approval_required", "permission_required", "tool_permission_required":
      return .waitingApproval
    case "cancelling", "cancel_requested": return .cancelling
    case "completed", "succeeded", "success", "run_completed", "task_completed", "final":
      return .completed
    case "cancelled", "canceled", "run_cancelled", "task_cancelled": return .cancelled
    case "timed_out", "timeout", "task_timeout": return .timedOut
    case "failed", "error", "run_failed", "task_failed": return .failed
    default: return nil
    }
  }

  private func isAcceptance(status: String, eventKind: String) -> Bool {
    [status, eventKind].contains { value in
      ["accepted", "agent_accepted", "run_accepted"].contains(value.lowercased())
    }
  }

  private func mergePartial(_ previous: String, _ incoming: String) -> String {
    let value = String(incoming.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16_000))
    guard !value.isEmpty else { return previous }
    if previous.isEmpty || value.hasPrefix(previous) { return value }
    if previous.hasPrefix(value) { return previous }
    return String((previous + value).prefix(16_000))
  }

  private func stableRunId(_ key: String) -> String {
    let digest = SHA256.hash(data: Data(key.utf8))
    return "voice-" + digest.map { String(format: "%02x", $0) }.joined().prefix(32)
  }

  private func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  private func string(_ object: [String: Any], _ key: String) -> String {
    if let value = object[key] as? String { return clean(value) }
    if let value = object[key] as? NSNumber { return value.stringValue }
    return ""
  }

  private func object(_ value: Any?) -> [String: Any] {
    if let dictionary = value as? [String: Any] {
      return dictionary
    }
    return [:]
  }

  private func flatten(_ envelope: [String: Any]) -> [String: Any] {
    guard let payload = envelope["payload"] as? [String: Any] else {
      return envelope
    }
    var merged = payload
    envelope.forEach { key, value in
      merged[key] = value
    }
    return merged
  }

  private func normalizedEventKind(_ rawValue: String, fallback: String) -> String {
    let normalized = clean(rawValue)
      .lowercased()
      .replacingOccurrences(of: "-", with: "_")
      .replacingOccurrences(of: "/", with: ".")
    let suffix = normalized.split(separator: ".").last.map(String.init) ?? ""
    if ["agent_task_event", "task_event"].contains(suffix) {
      return fallback
    }
    return suffix.ifBlank(fallback)
  }

  private func int64(_ object: [String: Any], _ key: String) -> Int64 {
    if let value = object[key] as? Int64 { return max(value, 0) }
    if let value = object[key] as? Int { return max(Int64(value), 0) }
    if let value = object[key] as? NSNumber { return max(value.int64Value, 0) }
    return max(Int64(string(object, key)) ?? 0, 0)
  }

  private func double(_ object: [String: Any], _ key: String) -> Double? {
    if let value = object[key] as? Double { return value.clamped(to: 0...100) }
    if let value = object[key] as? NSNumber { return value.doubleValue.clamped(to: 0...100) }
    return Double(string(object, key))?.clamped(to: 0...100)
  }
}

private extension Int64 {
  func ifZero(_ fallback: Int64) -> Int64 {
    self == 0 ? fallback : self
  }
}

enum VoiceAgentRunBridgeRegistry {
  static let shared = VoiceAgentRunBridge()
}

private extension Double {
  func clamped(to range: ClosedRange<Double>) -> Double {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
