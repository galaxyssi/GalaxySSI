import CryptoKit
import Foundation

enum AgentObservationDecision: String, Codable, CaseIterable, Identifiable {
  case actionFailed = "ACTION_FAILED"
  case noChangeRequired = "NO_CHANGE_REQUIRED"
  case changedAndStable = "CHANGED_AND_STABLE"
  case changedButUnstable = "CHANGED_BUT_UNSTABLE"
  case timedOut = "TIMED_OUT"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentObservationDecision {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .actionFailed
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

enum AgentRecoveryDecision: String, Codable, CaseIterable, Identifiable {
  case notNeeded = "NOT_NEEDED"
  case retrySucceeded = "RETRY_SUCCEEDED"
  case retryFailed = "RETRY_FAILED"
  case manualRequired = "MANUAL_REQUIRED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentRecoveryDecision {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .manualRequired
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

struct AgentScreenContext: Codable, Equatable {
  var foregroundApp: String
  var activityName: String
  var pageTitle: String
  var visibleTextCount: Int
  var clickableNodeCount: Int
  var inputFieldCount: Int
  var scrollableRegionCount: Int
  var sensitiveFlagCount: Int
  var visibleTexts: [String]
  var selectedText: String
  var isAccessibilityEnabled: Bool
  var snapshotAgeMillis: Int64

  init(
    foregroundApp: String,
    activityName: String = "",
    pageTitle: String = "",
    visibleTextCount: Int = 0,
    clickableNodeCount: Int = 0,
    inputFieldCount: Int = 0,
    scrollableRegionCount: Int = 0,
    sensitiveFlagCount: Int = 0,
    visibleTexts: [String] = [],
    selectedText: String = "",
    isAccessibilityEnabled: Bool = false,
    snapshotAgeMillis: Int64 = 0
  ) {
    self.foregroundApp = foregroundApp
    self.activityName = activityName
    self.pageTitle = pageTitle
    self.visibleTextCount = max(visibleTextCount, 0)
    self.clickableNodeCount = max(clickableNodeCount, 0)
    self.inputFieldCount = max(inputFieldCount, 0)
    self.scrollableRegionCount = max(scrollableRegionCount, 0)
    self.sensitiveFlagCount = max(sensitiveFlagCount, 0)
    self.visibleTexts = visibleTexts
      .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumVisibleTextLength)) }
      .filter { !$0.isEmpty }
      .prefix(Self.maximumVisibleTextItems)
      .map { $0 }
    self.selectedText = String(selectedText.prefix(Self.maximumSelectedTextLength))
    self.isAccessibilityEnabled = isAccessibilityEnabled
    self.snapshotAgeMillis = max(snapshotAgeMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case foregroundApp = "foreground_app"
    case activityName = "activity_name"
    case pageTitle = "page_title"
    case visibleTextCount = "visible_text_count"
    case clickableNodeCount = "clickable_node_count"
    case inputFieldCount = "input_field_count"
    case scrollableRegionCount = "scrollable_region_count"
    case sensitiveFlagCount = "sensitive_flag_count"
    case visibleTexts = "visible_texts"
    case selectedText = "selected_text"
    case isAccessibilityEnabled = "is_accessibility_enabled"
    case snapshotAgeMillis = "snapshot_age_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      foregroundApp: try container.decodeIfPresent(String.self, forKey: .foregroundApp) ?? "",
      activityName: try container.decodeIfPresent(String.self, forKey: .activityName) ?? "",
      pageTitle: try container.decodeIfPresent(String.self, forKey: .pageTitle) ?? "",
      visibleTextCount: try container.decodeIfPresent(Int.self, forKey: .visibleTextCount) ?? 0,
      clickableNodeCount: try container.decodeIfPresent(Int.self, forKey: .clickableNodeCount) ?? 0,
      inputFieldCount: try container.decodeIfPresent(Int.self, forKey: .inputFieldCount) ?? 0,
      scrollableRegionCount: try container.decodeIfPresent(Int.self, forKey: .scrollableRegionCount) ?? 0,
      sensitiveFlagCount: try container.decodeIfPresent(Int.self, forKey: .sensitiveFlagCount) ?? 0,
      visibleTexts: try container.decodeIfPresent([String].self, forKey: .visibleTexts) ?? [],
      selectedText: try container.decodeIfPresent(String.self, forKey: .selectedText) ?? "",
      isAccessibilityEnabled: try container.decodeIfPresent(Bool.self, forKey: .isAccessibilityEnabled) ?? false,
      snapshotAgeMillis: try container.decodeIfPresent(Int64.self, forKey: .snapshotAgeMillis) ?? 0
    )
  }

  private static let maximumVisibleTextItems = 80
  private static let maximumVisibleTextLength = 300
  private static let maximumSelectedTextLength = 1_000
}

struct AgentObservationOutcome: Codable, Equatable {
  var screen: AgentScreenContext
  var decision: AgentObservationDecision
  var sampleCount: Int
  var durationMillis: Int64
  var screenChanged: Bool
  var screenStable: Bool
  var evidence: String

  init(
    screen: AgentScreenContext,
    decision: AgentObservationDecision,
    sampleCount: Int,
    durationMillis: Int64,
    screenChanged: Bool,
    screenStable: Bool,
    evidence: String = ""
  ) {
    self.screen = screen
    self.decision = decision
    self.sampleCount = max(sampleCount, 0)
    self.durationMillis = max(durationMillis, 0)
    self.screenChanged = screenChanged
    self.screenStable = screenStable
    self.evidence = String(evidence.prefix(Self.maximumEvidenceLength))
  }

  enum CodingKeys: String, CodingKey {
    case screen
    case decision
    case sampleCount = "sample_count"
    case durationMillis = "duration_millis"
    case screenChanged = "screen_changed"
    case screenStable = "screen_stable"
    case evidence
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      screen: try container.decodeIfPresent(AgentScreenContext.self, forKey: .screen) ?? AgentScreenContext(foregroundApp: ""),
      decision: try container.decodeIfPresent(AgentObservationDecision.self, forKey: .decision) ?? .actionFailed,
      sampleCount: try container.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 0,
      durationMillis: try container.decodeIfPresent(Int64.self, forKey: .durationMillis) ?? 0,
      screenChanged: try container.decodeIfPresent(Bool.self, forKey: .screenChanged) ?? false,
      screenStable: try container.decodeIfPresent(Bool.self, forKey: .screenStable) ?? false,
      evidence: try container.decodeIfPresent(String.self, forKey: .evidence) ?? ""
    )
  }

  private static let maximumEvidenceLength = 2_000
}

struct AgentObservedContext: Codable, Equatable, Identifiable {
  static let defaultTTLMillis: Int64 = 24 * 60 * 60 * 1_000

  var id: String
  var targetId: String
  var text: String
  var conversationId: String
  var taskId: String
  var createdAtMillis: Int64
  var expiresAtMillis: Int64

  init(
    id: String = UUID().uuidString,
    targetId: String,
    text: String,
    conversationId: String = "",
    taskId: String = "",
    createdAtMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000),
    expiresAtMillis: Int64? = nil
  ) {
    self.id = id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? UUID().uuidString : id
    self.targetId = String(targetId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTargetCharacters))
    self.text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxEntryCharacters))
    self.conversationId = String(conversationId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxIdCharacters))
    self.taskId = String(taskId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxIdCharacters))
    self.createdAtMillis = max(createdAtMillis, 0)
    self.expiresAtMillis = max(expiresAtMillis ?? (self.createdAtMillis + Self.defaultTTLMillis), 0)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case targetId = "target_id"
    case text
    case conversationId = "conversation_id"
    case taskId = "task_id"
    case createdAtMillis = "created_at_millis"
    case expiresAtMillis = "expires_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let createdAtMillis = try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? 0
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
      targetId: try container.decodeIfPresent(String.self, forKey: .targetId) ?? "",
      text: try container.decodeIfPresent(String.self, forKey: .text) ?? "",
      conversationId: try container.decodeIfPresent(String.self, forKey: .conversationId) ?? "",
      taskId: try container.decodeIfPresent(String.self, forKey: .taskId) ?? "",
      createdAtMillis: createdAtMillis,
      expiresAtMillis: try container.decodeIfPresent(Int64.self, forKey: .expiresAtMillis)
    )
  }

  func isExpired(nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)) -> Bool {
    expiresAtMillis > 0 && nowMillis >= expiresAtMillis
  }

  fileprivate var isUsable: Bool {
    !targetId.isEmpty && !text.isEmpty
  }

  fileprivate static let maxTotalEntries = 128
  fileprivate static let maxEntriesPerTarget = 16
  fileprivate static let maxTargetCharacters = 160
  fileprivate static let maxIdCharacters = 160
  fileprivate static let maxEntryCharacters = 8_000
}

enum AgentObservationContextJsonCodec {
  static func encode(_ items: [AgentObservedContext]) -> String {
    guard let data = try? JSONEncoder().encode(items) else {
      return "[]"
    }
    return String(decoding: data, as: UTF8.self)
  }

  static func decode(
    _ raw: String,
    nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> [AgentObservedContext] {
    guard let data = raw.data(using: .utf8),
          let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
      return []
    }
    let decoded = array.compactMap { value -> AgentObservedContext? in
      guard let object = value as? [String: Any],
            JSONSerialization.isValidJSONObject(object),
            let data = try? JSONSerialization.data(withJSONObject: object),
            let item = try? JSONDecoder().decode(AgentObservedContext.self, from: data) else {
        return nil
      }
      return item
    }
    return decoded.filter { $0.isUsable && !$0.isExpired(nowMillis: nowMillis) }
  }
}

final class InMemoryAgentObservationContextStore {
  private let lock = NSRecursiveLock()
  private let clock: () -> Int64
  private let idFactory: () -> String
  private var document: String

  init(
    serialized: String = "[]",
    clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
    idFactory: @escaping () -> String = { UUID().uuidString }
  ) {
    self.document = serialized
    self.clock = clock
    self.idFactory = idFactory
  }

  func observe(
    targetId: String,
    text: String,
    conversationId: String = "",
    taskId: String = ""
  ) -> AgentObservedContext? {
    lock.lock()
    defer { lock.unlock() }
    let now = max(clock(), 0)
    let entry = AgentObservedContext(
      id: idFactory(),
      targetId: targetId,
      text: text,
      conversationId: conversationId,
      taskId: taskId,
      createdAtMillis: now,
      expiresAtMillis: now + AgentObservedContext.defaultTTLMillis
    )
    guard entry.isUsable else {
      return nil
    }
    let current = load(nowMillis: now).filter { existing in
      !(existing.targetId == entry.targetId &&
        existing.text == entry.text &&
        existing.conversationId == entry.conversationId)
    }
    let otherTargets = current.filter { $0.targetId != entry.targetId }
    let targetEntries = Array((current.filter { $0.targetId == entry.targetId } + [entry]).suffix(AgentObservedContext.maxEntriesPerTarget))
    let bounded = Array((otherTargets + targetEntries)
      .sorted { $0.createdAtMillis < $1.createdAtMillis }
      .suffix(AgentObservedContext.maxTotalEntries))
    save(bounded)
    return entry
  }

  func peek(targetId: String, conversationId: String = "") -> [AgentObservedContext] {
    lock.lock()
    defer { lock.unlock() }
    let targetId = targetId.trimmingCharacters(in: .whitespacesAndNewlines)
    let conversationId = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    return Array(load(nowMillis: max(clock(), 0)).filter { entry in
      entry.targetId == targetId &&
        (conversationId.isEmpty || entry.conversationId.isEmpty || entry.conversationId == conversationId)
    }.suffix(AgentObservedContext.maxEntriesPerTarget))
  }

  func acknowledge(entryIds: Set<String>) -> Int {
    lock.lock()
    defer { lock.unlock() }
    guard !entryIds.isEmpty else {
      return 0
    }
    let current = load(nowMillis: max(clock(), 0))
    let remaining = current.filter { !entryIds.contains($0.id) }
    if remaining.count != current.count {
      save(remaining)
    }
    return current.count - remaining.count
  }

  func clearTarget(_ targetId: String) -> Int {
    lock.lock()
    defer { lock.unlock() }
    let targetId = targetId.trimmingCharacters(in: .whitespacesAndNewlines)
    let current = load(nowMillis: max(clock(), 0))
    let remaining = current.filter { $0.targetId != targetId }
    if remaining.count != current.count {
      save(remaining)
    }
    return current.count - remaining.count
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    document = "[]"
  }

  func serializedSnapshot() -> String {
    lock.lock()
    defer { lock.unlock() }
    return document
  }

  private func load(nowMillis: Int64) -> [AgentObservedContext] {
    AgentObservationContextJsonCodec.decode(document, nowMillis: nowMillis)
  }

  private func save(_ items: [AgentObservedContext]) {
    document = AgentObservationContextJsonCodec.encode(items)
  }
}

struct AgentContinuousObservationController {
  let maxSamples: Int
  let stableSampleCount: Int
  let sampleIntervalMillis: Int64

  init(
    maxSamples: Int = 10,
    stableSampleCount: Int = 2,
    sampleIntervalMillis: Int64 = 250
  ) {
    precondition((1...Self.maxAllowedSamples).contains(maxSamples))
    precondition((1...maxSamples).contains(stableSampleCount))
    precondition((0...Self.maxSampleIntervalMillis).contains(sampleIntervalMillis))
    self.maxSamples = maxSamples
    self.stableSampleCount = stableSampleCount
    self.sampleIntervalMillis = sampleIntervalMillis
  }

  func observe(
    beforeAction: AgentScreenContext,
    actionSucceeded: Bool,
    changeExpected: Bool,
    capture: () -> AgentScreenContext,
    sleep: (Int64) -> Void = { millis in
      guard millis > 0 else { return }
      Thread.sleep(forTimeInterval: Double(millis) / 1_000)
    },
    nowMillis: () -> Int64 = {
      Int64(Date().timeIntervalSince1970 * 1_000)
    }
  ) -> AgentObservationOutcome {
    let startedAt = nowMillis()
    var latest = capture()
    if !actionSucceeded {
      return outcome(
        screen: latest,
        decision: .actionFailed,
        sampleCount: 1,
        startedAt: startedAt,
        changed: latest.fingerprint() != beforeAction.fingerprint(),
        stable: false,
        nowMillis: nowMillis
      )
    }
    if !changeExpected {
      return outcome(
        screen: latest,
        decision: .noChangeRequired,
        sampleCount: 1,
        startedAt: startedAt,
        changed: latest.fingerprint() != beforeAction.fingerprint(),
        stable: true,
        nowMillis: nowMillis
      )
    }

    let beforeFingerprint = beforeAction.fingerprint()
    var previousFingerprint: AgentScreenFingerprint?
    var changed = false
    var stableSamples = 0
    var samples = 0
    for index in 0..<maxSamples {
      if index > 0 {
        sleep(sampleIntervalMillis)
        latest = capture()
      }
      samples += 1
      let fingerprint = latest.fingerprint()
      let differsFromBefore = fingerprint != beforeFingerprint
      changed = changed || differsFromBefore
      if !differsFromBefore {
        stableSamples = 0
      } else if previousFingerprint == fingerprint {
        stableSamples += 1
      } else {
        stableSamples = 1
      }
      previousFingerprint = fingerprint
      if changed && stableSamples >= stableSampleCount {
        return outcome(
          screen: latest,
          decision: .changedAndStable,
          sampleCount: samples,
          startedAt: startedAt,
          changed: true,
          stable: true,
          nowMillis: nowMillis
        )
      }
    }
    return outcome(
      screen: latest,
      decision: changed ? .changedButUnstable : .timedOut,
      sampleCount: samples,
      startedAt: startedAt,
      changed: changed,
      stable: false,
      nowMillis: nowMillis
    )
  }

  private func outcome(
    screen: AgentScreenContext,
    decision: AgentObservationDecision,
    sampleCount: Int,
    startedAt: Int64,
    changed: Bool,
    stable: Bool,
    nowMillis: () -> Int64
  ) -> AgentObservationOutcome {
    let duration = max(nowMillis() - startedAt, 0)
    return AgentObservationOutcome(
      screen: screen,
      decision: decision,
      sampleCount: sampleCount,
      durationMillis: duration,
      screenChanged: changed,
      screenStable: stable,
      evidence: "decision=\(decision.rawValue); samples=\(sampleCount); duration_ms=\(duration); changed=\(changed); stable=\(stable)"
    )
  }

  private static let maxAllowedSamples = 30
  private static let maxSampleIntervalMillis: Int64 = 2_000
}

private struct AgentScreenFingerprint: Equatable {
  var foregroundApp: String
  var activityName: String
  var pageTitle: String
  var visibleTextCount: Int
  var clickableNodeCount: Int
  var inputFieldCount: Int
  var scrollableRegionCount: Int
  var sensitiveFlagCount: Int
  var selectedText: String
  var isAccessibilityEnabled: Bool
}

private extension AgentScreenContext {
  func fingerprint() -> AgentScreenFingerprint {
    AgentScreenFingerprint(
      foregroundApp: foregroundApp,
      activityName: activityName,
      pageTitle: pageTitle,
      visibleTextCount: visibleTextCount,
      clickableNodeCount: clickableNodeCount,
      inputFieldCount: inputFieldCount,
      scrollableRegionCount: scrollableRegionCount,
      sensitiveFlagCount: sensitiveFlagCount,
      selectedText: Self.normalizedFingerprintText(selectedText),
      isAccessibilityEnabled: isAccessibilityEnabled
    )
  }

  private static func normalizedFingerprintText(_ value: String) -> String {
    value
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}

struct AgentActionResult: Codable, Equatable {
  var actionId: String
  var success: Bool
  var message: String
  var metadata: [String: String]

  init(
    actionId: String,
    success: Bool,
    message: String,
    metadata: [String: String] = [:]
  ) {
    self.actionId = actionId
    self.success = success
    self.message = String(message.prefix(Self.maximumMessageLength))
    self.metadata = metadata
  }

  enum CodingKeys: String, CodingKey {
    case actionId = "action_id"
    case success
    case message
    case metadata
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      actionId: try container.decodeIfPresent(String.self, forKey: .actionId) ?? "",
      success: try container.decodeIfPresent(Bool.self, forKey: .success) ?? false,
      message: try container.decodeIfPresent(String.self, forKey: .message) ?? "",
      metadata: try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    )
  }

  private static let maximumMessageLength = 2_000
}

struct AgentRecoveryAttempt: Equatable {
  var result: AgentActionResult?
  var observation: AgentObservationOutcome
}

struct AgentRecoveryOutcome: Equatable {
  var result: AgentActionResult?
  var observation: AgentObservationOutcome
  var decision: AgentRecoveryDecision
  var attemptCount: Int
}

enum AgentPhase: String, Codable, CaseIterable, Identifiable {
  case observing = "OBSERVING"
  case planning = "PLANNING"
  case waitingConfirmation = "WAITING_CONFIRMATION"
  case executing = "EXECUTING"
  case verifying = "VERIFYING"
  case waitingResponse = "WAITING_RESPONSE"
  case paused = "PAUSED"
  case cancelled = "CANCELLED"
  case blocked = "BLOCKED"
  case completed = "COMPLETED"
  case failed = "FAILED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentPhase {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .executing
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

enum AgentExecutionLoopPhase: String, Codable, CaseIterable, Identifiable {
  case plan = "PLAN"
  case act = "ACT"
  case observe = "OBSERVE"
  case replan = "REPLAN"
  case verify = "VERIFY"
  case finalize = "FINALIZE"
  case learn = "LEARN"
  case waitingConfirmation = "WAITING_CONFIRMATION"
  case waitingResponse = "WAITING_RESPONSE"
  case paused = "PAUSED"
  case blocked = "BLOCKED"
  case failed = "FAILED"
  case cancelled = "CANCELLED"
  case completed = "COMPLETED"

  var id: String { rawValue }

  var isActive: Bool {
    [.plan, .act, .observe, .replan, .verify, .finalize, .learn].contains(self)
  }

  var isTerminal: Bool {
    [.blocked, .failed, .cancelled, .completed].contains(self)
  }

  static func fromWireValue(_ value: String?) -> AgentExecutionLoopPhase {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .plan
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

struct AgentExecutionLoopUsage: Codable, Equatable {
  var iterations: Int
  var actions: Int
  var replans: Int
  var toolCalls: Int
  var retries: Int
  var activeDurationMillis: Int64
  var activeSinceMillis: Int64

  init(
    iterations: Int = 0,
    actions: Int = 0,
    replans: Int = 0,
    toolCalls: Int = 0,
    retries: Int = 0,
    activeDurationMillis: Int64 = 0,
    activeSinceMillis: Int64 = 0
  ) {
    self.iterations = iterations
    self.actions = actions
    self.replans = replans
    self.toolCalls = toolCalls
    self.retries = retries
    self.activeDurationMillis = activeDurationMillis
    self.activeSinceMillis = activeSinceMillis
  }

  enum CodingKeys: String, CodingKey {
    case iterations
    case actions
    case replans
    case toolCalls = "tool_calls"
    case retries
    case activeDurationMillis = "active_duration_millis"
    case activeSinceMillis = "active_since_millis"
  }

  func elapsedActiveMillis(nowMillis: Int64, phase: AgentExecutionLoopPhase) -> Int64 {
    activeDurationMillis + (phase.isActive && activeSinceMillis > 0 ? max(nowMillis - activeSinceMillis, 0) : 0)
  }
}

struct AgentExecutionLoopSnapshot: Codable, Equatable {
  var taskId: String
  var phase: AgentExecutionLoopPhase
  var usage: AgentExecutionLoopUsage
  var resumePhase: AgentExecutionLoopPhase
  var lastActionId: String
  var lastReason: String
  var budgetFailure: String
  var startedAtMillis: Int64
  var updatedAtMillis: Int64
  var revision: Int64

  init(
    taskId: String,
    phase: AgentExecutionLoopPhase,
    usage: AgentExecutionLoopUsage = AgentExecutionLoopUsage(),
    resumePhase: AgentExecutionLoopPhase = .plan,
    lastActionId: String = "",
    lastReason: String = "",
    budgetFailure: String = "",
    startedAtMillis: Int64 = 0,
    updatedAtMillis: Int64 = 0,
    revision: Int64 = 1
  ) {
    self.taskId = taskId
    self.phase = phase
    self.usage = usage
    self.resumePhase = resumePhase
    self.lastActionId = lastActionId
    self.lastReason = lastReason
    self.budgetFailure = budgetFailure
    self.startedAtMillis = startedAtMillis
    self.updatedAtMillis = updatedAtMillis
    self.revision = revision
  }

  enum CodingKeys: String, CodingKey {
    case taskId = "task_id"
    case phase
    case usage
    case resumePhase = "resume_phase"
    case lastActionId = "last_action_id"
    case lastReason = "last_reason"
    case budgetFailure = "budget_failure"
    case startedAtMillis = "started_at_millis"
    case updatedAtMillis = "updated_at_millis"
    case revision
  }
}

struct AgentExecutionLoopEvent: Codable, Equatable {
  var previousPhase: AgentExecutionLoopPhase?
  var phase: AgentExecutionLoopPhase
  var reason: String
  var snapshot: AgentExecutionLoopSnapshot
  var toolCall: Bool
  var retry: Bool

  init(
    previousPhase: AgentExecutionLoopPhase? = nil,
    phase: AgentExecutionLoopPhase,
    reason: String = "",
    snapshot: AgentExecutionLoopSnapshot,
    toolCall: Bool = false,
    retry: Bool = false
  ) {
    self.previousPhase = previousPhase
    self.phase = phase
    self.reason = reason
    self.snapshot = snapshot
    self.toolCall = toolCall
    self.retry = retry
  }

  enum CodingKeys: String, CodingKey {
    case previousPhase = "previous_phase"
    case phase
    case reason
    case snapshot
    case toolCall = "tool_call"
    case retry
  }
}

enum AgentRunControlEventType: String, Codable, CaseIterable, Identifiable {
  case runCreated = "RUN_CREATED"
  case runQueued = "RUN_QUEUED"
  case runStarted = "RUN_STARTED"
  case planning = "PLANNING"
  case thinking = "THINKING"
  case agentConnected = "AGENT_CONNECTED"
  case stepStarted = "STEP_STARTED"
  case toolPermissionRequired = "TOOL_PERMISSION_REQUIRED"
  case permissionRevoked = "PERMISSION_REVOKED"
  case toolStarted = "TOOL_STARTED"
  case toolProgress = "TOOL_PROGRESS"
  case toolCompleted = "TOOL_COMPLETED"
  case waitingForUser = "WAITING_FOR_USER"
  case waitingForDevice = "WAITING_FOR_DEVICE"
  case paused = "PAUSED"
  case retrying = "RETRYING"
  case handoff = "HANDOFF"
  case stepCompleted = "STEP_COMPLETED"
  case runCompleted = "RUN_COMPLETED"
  case runFailed = "RUN_FAILED"
  case runCancelled = "RUN_CANCELLED"
  case runRecovered = "RUN_RECOVERED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentRunControlEventType {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .runFailed
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

enum AgentRunControlPayloadValue: Codable, Equatable {
  case string(String)
  case int(Int64)
  case bool(Bool)

  var stringValue: String? {
    switch self {
    case .string(let value):
      return value
    case .int(let value):
      return String(value)
    case .bool(let value):
      return value ? "true" : "false"
    }
  }

  var intValue: Int64? {
    switch self {
    case .int(let value):
      return value
    case .string(let value):
      return Int64(value)
    case .bool:
      return nil
    }
  }

  var boolValue: Bool? {
    switch self {
    case .bool(let value):
      return value
    case .string(let value):
      return Bool(value)
    case .int:
      return nil
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int64.self) {
      self = .int(value)
    } else {
      self = .string((try? container.decode(String.self)) ?? "")
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .int(let value):
      try container.encode(value)
    case .bool(let value):
      try container.encode(value)
    }
  }
}

typealias AgentRunControlPayload = [String: AgentRunControlPayloadValue]

struct AgentRunControlEvent: Codable, Equatable {
  var eventId: String
  var conversationId: String
  var messageId: String
  var taskId: String
  var runId: String
  var stepId: String
  var toolCallId: String
  var agentId: String
  var deviceId: String
  var type: AgentRunControlEventType
  var sequence: Int64
  var timestampMillis: Int64
  var payload: AgentRunControlPayload

  init(
    eventId: String = UUID().uuidString,
    conversationId: String,
    messageId: String,
    taskId: String,
    runId: String,
    stepId: String = "",
    toolCallId: String = "",
    agentId: String,
    deviceId: String,
    type: AgentRunControlEventType,
    sequence: Int64,
    timestampMillis: Int64 = 0,
    payload: AgentRunControlPayload = [:]
  ) {
    self.eventId = eventId
    self.conversationId = conversationId
    self.messageId = messageId
    self.taskId = taskId
    self.runId = runId
    self.stepId = stepId
    self.toolCallId = toolCallId
    self.agentId = agentId
    self.deviceId = deviceId
    self.type = type
    self.sequence = sequence
    self.timestampMillis = timestampMillis
    self.payload = payload
  }

  enum CodingKeys: String, CodingKey {
    case eventId = "event_id"
    case conversationId = "conversation_id"
    case messageId = "message_id"
    case taskId = "task_id"
    case runId = "run_id"
    case stepId = "step_id"
    case toolCallId = "tool_call_id"
    case agentId = "agent_id"
    case deviceId = "device_id"
    case type
    case sequence
    case timestampMillis = "timestamp_millis"
    case payload
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    eventId = try container.decodeIfPresent(String.self, forKey: .eventId) ?? UUID().uuidString
    conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId) ?? ""
    messageId = try container.decodeIfPresent(String.self, forKey: .messageId) ?? ""
    taskId = try container.decodeIfPresent(String.self, forKey: .taskId) ?? ""
    runId = try container.decodeIfPresent(String.self, forKey: .runId) ?? ""
    stepId = try container.decodeIfPresent(String.self, forKey: .stepId) ?? ""
    toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId) ?? ""
    agentId = try container.decodeIfPresent(String.self, forKey: .agentId) ?? ""
    deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
    type = try container.decodeIfPresent(AgentRunControlEventType.self, forKey: .type) ?? .runFailed
    sequence = try container.decodeIfPresent(Int64.self, forKey: .sequence) ?? 0
    timestampMillis = try container.decodeIfPresent(Int64.self, forKey: .timestampMillis) ?? 0
    payload = try container.decodeIfPresent(AgentRunControlPayload.self, forKey: .payload) ?? [:]
  }
}

enum AgentRunControlState: String, Codable, CaseIterable, Identifiable {
  case created = "CREATED"
  case queued = "QUEUED"
  case running = "RUNNING"
  case waitingForUser = "WAITING_FOR_USER"
  case waitingForDevice = "WAITING_FOR_DEVICE"
  case paused = "PAUSED"
  case completed = "COMPLETED"
  case failed = "FAILED"
  case cancelled = "CANCELLED"

  var id: String { rawValue }

  var isTerminal: Bool {
    [.completed, .failed, .cancelled].contains(self)
  }

  static func fromWireValue(_ value: String?) -> AgentRunControlState {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .failed
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

struct AgentRunControlSnapshot: Codable, Equatable {
  var runId: String
  var taskId: String
  var state: AgentRunControlState
  var agentId: String
  var deviceId: String
  var lastSequence: Int64
  var lastEvent: AgentRunControlEvent

  enum CodingKeys: String, CodingKey {
    case runId = "run_id"
    case taskId = "task_id"
    case state
    case agentId = "agent_id"
    case deviceId = "device_id"
    case lastSequence = "last_sequence"
    case lastEvent = "last_event"
  }
}

enum AgentConnectionKind: String, Codable, CaseIterable, Identifiable {
  case inProcess = "IN_PROCESS"
  case binder = "BINDER"
  case signalasiLink = "SIGNALASI_LINK"
  case cliJson = "CLI_JSON"
  case stdio = "STDIO"
  case http = "HTTP"
  case websocket = "WEBSOCKET"
  case mcp = "MCP"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentConnectionKind {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .http
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

enum AgentResourceLocation: String, Codable, CaseIterable, Identifiable {
  case phone = "PHONE"
  case trustedDesktop = "TRUSTED_DESKTOP"
  case privateNetwork = "PRIVATE_NETWORK"
  case cloud = "CLOUD"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentResourceLocation {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .cloud
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

enum AgentRecordedRunStatus: String, Codable, CaseIterable, Identifiable {
  case running = "RUNNING"
  case completed = "COMPLETED"
  case failed = "FAILED"
  case cancelled = "CANCELLED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentRecordedRunStatus {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .failed
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

struct AgentRecordedRun: Codable, Equatable, Identifiable {
  var runId: String
  var conversationId: String
  var taskThreadId: String
  var originalRequest: String
  var normalizedIntent: String
  var extractedInputs: AgentMcpJSONObject
  var agentPlan: [AgentMcpJSONValue]
  var toolCalls: [AgentToolCallRecord]
  var sources: [AgentMcpJSONValue]
  var transformations: [AgentMcpJSONValue]
  var finalOutput: AgentMcpJSONObject
  var renderSpec: AgentMcpJSONObject
  var artifacts: [AgentArtifactReference]
  var userFeedback: [String]
  var activeSkillId: String
  var executionResourceId: String
  var parentRunId: String
  var revisionNumber: Int
  var status: AgentRecordedRunStatus
  var createdAtMillis: Int64
  var completedAtMillis: Int64

  var id: String { runId }

  init(
    runId: String,
    conversationId: String,
    taskThreadId: String,
    originalRequest: String,
    normalizedIntent: String = "",
    extractedInputs: AgentMcpJSONObject = [:],
    agentPlan: [AgentMcpJSONValue] = [],
    toolCalls: [AgentToolCallRecord] = [],
    sources: [AgentMcpJSONValue] = [],
    transformations: [AgentMcpJSONValue] = [],
    finalOutput: AgentMcpJSONObject = [:],
    renderSpec: AgentMcpJSONObject = [:],
    artifacts: [AgentArtifactReference] = [],
    userFeedback: [String] = [],
    activeSkillId: String = "",
    executionResourceId: String = "",
    parentRunId: String = "",
    revisionNumber: Int = 1,
    status: AgentRecordedRunStatus = .running,
    createdAtMillis: Int64 = 0,
    completedAtMillis: Int64 = 0
  ) {
    self.runId = runId
    self.conversationId = conversationId
    self.taskThreadId = taskThreadId
    self.originalRequest = originalRequest
    self.normalizedIntent = normalizedIntent
    self.extractedInputs = extractedInputs
    self.agentPlan = agentPlan
    self.toolCalls = Array(toolCalls.prefix(AgentSkillLimits.maxToolCalls))
    self.sources = sources
    self.transformations = transformations
    self.finalOutput = finalOutput
    self.renderSpec = renderSpec
    self.artifacts = Array(artifacts.prefix(AgentSkillLimits.maxArtifacts))
    self.userFeedback = userFeedback.prefix(32).map { String($0.prefix(AgentSkillLimits.maxFeedbackCharacters)) }
    self.activeSkillId = String(activeSkillId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    self.executionResourceId = String(executionResourceId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    self.parentRunId = String(parentRunId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    self.revisionNumber = max(revisionNumber, 1)
    self.status = status
    self.createdAtMillis = createdAtMillis
    self.completedAtMillis = completedAtMillis
  }

  enum CodingKeys: String, CodingKey {
    case runId = "run_id"
    case conversationId = "conversation_id"
    case taskThreadId = "task_thread_id"
    case originalRequest = "original_request"
    case normalizedIntent = "normalized_intent"
    case extractedInputs = "extracted_inputs"
    case agentPlan = "agent_plan"
    case toolCalls = "tool_calls"
    case sources
    case transformations
    case finalOutput = "final_output"
    case renderSpec = "render_spec"
    case artifacts
    case userFeedback = "user_feedback"
    case activeSkillId = "active_skill_id"
    case executionResourceId = "execution_resource_id"
    case parentRunId = "parent_run_id"
    case revisionNumber = "revision_number"
    case status
    case createdAtMillis = "created_at_millis"
    case completedAtMillis = "completed_at_millis"
    case createdAtAndroid = "created_at"
    case completedAtAndroid = "completed_at"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let createdAt = try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ??
      (try container.decodeIfPresent(Int64.self, forKey: .createdAtAndroid)) ?? 0
    let completedAt = try container.decodeIfPresent(Int64.self, forKey: .completedAtMillis) ??
      (try container.decodeIfPresent(Int64.self, forKey: .completedAtAndroid)) ?? 0
    self.init(
      runId: try container.decodeIfPresent(String.self, forKey: .runId) ?? "",
      conversationId: try container.decodeIfPresent(String.self, forKey: .conversationId) ?? "",
      taskThreadId: try container.decodeIfPresent(String.self, forKey: .taskThreadId) ?? "",
      originalRequest: try container.decodeIfPresent(String.self, forKey: .originalRequest) ?? "",
      normalizedIntent: try container.decodeIfPresent(String.self, forKey: .normalizedIntent) ?? "",
      extractedInputs: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .extractedInputs) ?? [:],
      agentPlan: try container.decodeIfPresent([AgentMcpJSONValue].self, forKey: .agentPlan) ?? [],
      toolCalls: try container.decodeIfPresent([AgentToolCallRecord].self, forKey: .toolCalls) ?? [],
      sources: try container.decodeIfPresent([AgentMcpJSONValue].self, forKey: .sources) ?? [],
      transformations: try container.decodeIfPresent([AgentMcpJSONValue].self, forKey: .transformations) ?? [],
      finalOutput: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .finalOutput) ?? [:],
      renderSpec: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .renderSpec) ?? [:],
      artifacts: try container.decodeIfPresent([AgentArtifactReference].self, forKey: .artifacts) ?? [],
      userFeedback: try container.decodeIfPresent([String].self, forKey: .userFeedback) ?? [],
      activeSkillId: try container.decodeIfPresent(String.self, forKey: .activeSkillId) ?? "",
      executionResourceId: try container.decodeIfPresent(String.self, forKey: .executionResourceId) ?? "",
      parentRunId: try container.decodeIfPresent(String.self, forKey: .parentRunId) ?? "",
      revisionNumber: try container.decodeIfPresent(Int.self, forKey: .revisionNumber) ?? 1,
      status: try container.decodeIfPresent(AgentRecordedRunStatus.self, forKey: .status) ?? .running,
      createdAtMillis: createdAt,
      completedAtMillis: completedAt
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(runId, forKey: .runId)
    try container.encode(conversationId, forKey: .conversationId)
    try container.encode(taskThreadId, forKey: .taskThreadId)
    try container.encode(originalRequest, forKey: .originalRequest)
    try container.encode(normalizedIntent, forKey: .normalizedIntent)
    try container.encode(extractedInputs, forKey: .extractedInputs)
    try container.encode(agentPlan, forKey: .agentPlan)
    try container.encode(toolCalls, forKey: .toolCalls)
    try container.encode(sources, forKey: .sources)
    try container.encode(transformations, forKey: .transformations)
    try container.encode(finalOutput, forKey: .finalOutput)
    try container.encode(renderSpec, forKey: .renderSpec)
    try container.encode(artifacts, forKey: .artifacts)
    try container.encode(userFeedback, forKey: .userFeedback)
    try container.encode(activeSkillId, forKey: .activeSkillId)
    try container.encode(executionResourceId, forKey: .executionResourceId)
    try container.encode(parentRunId, forKey: .parentRunId)
    try container.encode(revisionNumber, forKey: .revisionNumber)
    try container.encode(status, forKey: .status)
    try container.encode(createdAtMillis, forKey: .createdAtMillis)
    try container.encode(completedAtMillis, forKey: .completedAtMillis)
  }
}

struct AgentRunRecoveryRegistration: Codable, Equatable {
  var agentId: String
  var location: AgentResourceLocation
  var connectionKind: AgentConnectionKind

  init(
    agentId: String,
    location: AgentResourceLocation,
    connectionKind: AgentConnectionKind
  ) {
    self.agentId = agentId
    self.location = location
    self.connectionKind = connectionKind
  }

  enum CodingKeys: String, CodingKey {
    case agentId = "agent_id"
    case location
    case connectionKind = "connection_kind"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      agentId: try container.decodeIfPresent(String.self, forKey: .agentId) ?? "",
      location: try container.decodeIfPresent(AgentResourceLocation.self, forKey: .location) ?? .cloud,
      connectionKind: try container.decodeIfPresent(AgentConnectionKind.self, forKey: .connectionKind) ?? .http
    )
  }
}

enum AgentRunRecoveryDisposition: String, Codable, CaseIterable, Identifiable {
  case restoreLocalWait = "RESTORE_LOCAL_WAIT"
  case reconnectDurableRemote = "RECONNECT_DURABLE_REMOTE"
  case failNonReplayable = "FAIL_NON_REPLAYABLE"
  case ignoreTerminal = "IGNORE_TERMINAL"

  var id: String { rawValue }
}

struct AgentRunRecoveryDecision: Codable, Equatable {
  var disposition: AgentRunRecoveryDisposition
  var reason: String
}

enum AgentRunEventStore {
  static func reduce(
    current: AgentRunControlState,
    event: AgentRunControlEventType
  ) -> AgentRunControlState {
    let next: AgentRunControlState
    switch event {
    case .runCreated:
      next = .created
    case .runQueued:
      next = .queued
    case .runStarted,
         .planning,
         .thinking,
         .agentConnected,
         .stepStarted,
         .toolStarted,
         .toolProgress,
         .toolCompleted,
         .retrying,
         .handoff,
         .stepCompleted,
         .runRecovered:
      next = .running
    case .toolPermissionRequired,
         .waitingForUser:
      next = .waitingForUser
    case .permissionRevoked,
         .paused:
      next = .paused
    case .waitingForDevice:
      next = .waitingForDevice
    case .runCompleted:
      next = .completed
    case .runFailed:
      next = .failed
    case .runCancelled:
      next = .cancelled
    }
    if current.isTerminal && event != .runRecovered {
      return current
    }
    return next
  }

  static func recoverableRuns(_ snapshots: [AgentRunControlSnapshot]) -> [AgentRunControlSnapshot] {
    snapshots.filter { !$0.state.isTerminal }
  }
}

enum AgentRunRecoveryPolicy {
  static func decide(
    snapshot: AgentRunControlSnapshot,
    recordedRun: AgentRecordedRun?,
    registration: AgentRunRecoveryRegistration?
  ) -> AgentRunRecoveryDecision {
    if let recordedRun, recordedRun.status != .running {
      return AgentRunRecoveryDecision(
        disposition: .ignoreTerminal,
        reason: "recorded_run_is_terminal"
      )
    }
    if snapshot.state == .waitingForUser || snapshot.state == .paused {
      return AgentRunRecoveryDecision(
        disposition: .restoreLocalWait,
        reason: "user_resumable_checkpoint"
      )
    }
    if let registration,
      registration.location == .trustedDesktop,
      durableRemoteConnectionKinds.contains(registration.connectionKind) {
      return AgentRunRecoveryDecision(
        disposition: .reconnectDurableRemote,
        reason: "durable_remote_run_can_reconnect"
      )
    }
    return AgentRunRecoveryDecision(
      disposition: .failNonReplayable,
      reason: "interrupted_run_cannot_be_replayed_safely"
    )
  }

  private static let durableRemoteConnectionKinds: Set<AgentConnectionKind> = [
    .signalasiLink,
    .websocket,
    .cliJson,
    .stdio
  ]
}

enum AgentPrivateDataExportPolicy: String, Codable, CaseIterable, Identifiable {
  case alwaysEncrypted = "ALWAYS_ENCRYPTED"
  case optionalContacts = "OPTIONAL_CONTACTS"
  case optionalSessionHistory = "OPTIONAL_SESSION_HISTORY"
  case neverExport = "NEVER_EXPORT"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentPrivateDataExportPolicy {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .neverExport
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

enum AgentPrivateDataSensitivity: String, Codable, CaseIterable, Identifiable {
  case personal = "PERSONAL"
  case secret = "SECRET"
  case ephemeral = "EPHEMERAL"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentPrivateDataSensitivity {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .personal
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

enum AgentPrivateDataErasePolicy: String, Codable, CaseIterable, Identifiable {
  case delete = "DELETE"
  case deleteAndRotateIdentity = "DELETE_AND_ROTATE_IDENTITY"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentPrivateDataErasePolicy {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .delete
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

struct AgentPrivateDataDescriptor: Codable, Equatable, Identifiable {
  var id: String
  var category: String
  var storageIds: Set<String>
  var backupPath: String
  var exportPolicy: AgentPrivateDataExportPolicy
  var sensitivity: AgentPrivateDataSensitivity
  var erasePolicy: AgentPrivateDataErasePolicy

  init(
    id: String,
    category: String,
    storageIds: Set<String>,
    backupPath: String = "",
    exportPolicy: AgentPrivateDataExportPolicy,
    sensitivity: AgentPrivateDataSensitivity,
    erasePolicy: AgentPrivateDataErasePolicy = .delete
  ) {
    self.id = id
    self.category = category
    self.storageIds = storageIds
    self.backupPath = backupPath
    self.exportPolicy = exportPolicy
    self.sensitivity = sensitivity
    self.erasePolicy = erasePolicy
  }

  enum CodingKeys: String, CodingKey {
    case id
    case category
    case storageIds = "storage_ids"
    case backupPath = "backup_path"
    case exportPolicy = "export_policy"
    case sensitivity
    case erasePolicy = "erase_policy"
  }
}

struct AgentPrivateDataInventoryAudit: Codable, Equatable {
  var duplicateIds: Set<String>
  var descriptorsWithoutStorage: Set<String>
  var exportedDescriptorsWithoutPath: Set<String>
  var nonExportedDescriptorsWithPath: Set<String>
  var identityRotationCount: Int

  var complete: Bool {
    duplicateIds.isEmpty &&
      descriptorsWithoutStorage.isEmpty &&
      exportedDescriptorsWithoutPath.isEmpty &&
      nonExportedDescriptorsWithPath.isEmpty &&
      identityRotationCount == 1
  }

  enum CodingKeys: String, CodingKey {
    case duplicateIds = "duplicate_ids"
    case descriptorsWithoutStorage = "descriptors_without_storage"
    case exportedDescriptorsWithoutPath = "exported_descriptors_without_path"
    case nonExportedDescriptorsWithPath = "non_exported_descriptors_with_path"
    case identityRotationCount = "identity_rotation_count"
  }
}

struct AgentPrivateDataBackupManifest: Codable, Equatable {
  var policyVersion: Int
  var encryptedContainerRequired: Bool
  var privateModeExported: Bool
  var pausedTrackingExported: Bool
  var identityRotatedOnReset: Bool
  var includedStoreIds: [String]
  var secretStoreIds: [String]
  var excludedStoreIds: [String]
  var eraseStoreIds: [String]

  enum CodingKeys: String, CodingKey {
    case policyVersion = "policy_version"
    case encryptedContainerRequired = "encrypted_container_required"
    case privateModeExported = "private_mode_exported"
    case pausedTrackingExported = "paused_tracking_exported"
    case identityRotatedOnReset = "identity_rotated_on_reset"
    case includedStoreIds = "included_store_ids"
    case secretStoreIds = "secret_store_ids"
    case excludedStoreIds = "excluded_store_ids"
    case eraseStoreIds = "erase_store_ids"
  }
}

enum AgentPrivateDataInventory {
  static let policyVersion = 1

  static let descriptors: [AgentPrivateDataDescriptor] = [
    item(
      "identity",
      "Identity keys and installation identity",
      "keychain:identity.p256.private",
      "user_defaults:signalasi_signal_store",
      "user_defaults:signalasi_signal_trust",
      backupPath: "root.identity",
      exportPolicy: .alwaysEncrypted,
      sensitivity: .secret,
      erasePolicy: .deleteAndRotateIdentity
    ),
    item("profile", "Local profile", "user_defaults:signalasi_app_store", backupPath: "root.profile"),
    item(
      "contacts",
      "Contacts, paired endpoints, and cloud model credentials",
      "user_defaults:signalasi_app_store",
      "keychain:cloud_api_keys",
      backupPath: "root.contacts",
      exportPolicy: .optionalContacts,
      sensitivity: .secret
    ),
    item(
      "friend_requests",
      "Pending trust requests",
      "user_defaults:signalasi_app_store",
      backupPath: "root.friend_requests",
      exportPolicy: .optionalContacts
    ),
    item(
      "chat_history",
      "Contact message history",
      "user_defaults:signalasi_app_store",
      backupPath: "root.messages",
      exportPolicy: .optionalSessionHistory
    ),
    item("memory", "Long-term memory", "user_defaults:signalasi_agent_memory_v2", backupPath: "agent.memory"),
    item(
      "memory_deletion_index",
      "Causal memory deletion tombstones",
      "user_defaults:signalasi_agent_memory_deletions_v1",
      backupPath: "agent.memory_deletion_index",
      sensitivity: .secret
    ),
    item("knowledge", "Personal knowledge index", "user_defaults:signalasi_agent_knowledge", backupPath: "agent.knowledge"),
    item(
      "tasks",
      "Task history",
      "user_defaults:signalasi_agent_tasks",
      backupPath: "agent.tasks",
      exportPolicy: .optionalSessionHistory
    ),
    item(
      "transcript",
      "Agent transcript",
      "user_defaults:signalasi_agent_transcript",
      "user_defaults:signalasi_agent_transcript_entries",
      backupPath: "agent.transcript",
      exportPolicy: .optionalSessionHistory
    ),
    item(
      "agent_conversations",
      "Agent conversation metadata",
      "user_defaults:signalasi_agent_transcript",
      backupPath: "agent.agent_conversations",
      exportPolicy: .optionalSessionHistory
    ),
    item(
      "active_agent_conversation",
      "Active conversation pointer",
      "user_defaults:signalasi_agent_transcript",
      backupPath: "agent.active_agent_conversation",
      exportPolicy: .optionalSessionHistory,
      sensitivity: .ephemeral
    ),
    item("workflows", "Saved workflows", "user_defaults:signalasi_agent_workflows", backupPath: "agent.workflows"),
    item("workflow_schedules", "Workflow schedules", "user_defaults:signalasi_agent_workflow_schedules", backupPath: "agent.workflow_schedules"),
    item("workflow_triggers", "Workflow triggers", "user_defaults:signalasi_agent_workflow_triggers", backupPath: "agent.workflow_triggers"),
    item(
      "workflow_history",
      "Workflow execution history",
      "user_defaults:signalasi_agent_workflow_execution_history",
      backupPath: "agent.workflow_execution_history"
    ),
    item("safety", "Safety and execution policy", "user_defaults:signalasi_agent_safety", backupPath: "agent.safety"),
    item(
      "custom_devices",
      "Custom device connectors and credentials",
      "user_defaults:signalasi_custom_device_connectors",
      "keychain:custom_device_connectors",
      backupPath: "agent.custom_device_connectors",
      sensitivity: .secret
    ),
    item("personal_asi", "Personal ASI world, graph, event, and autonomy state", "user_defaults:signalasi_global_super_agent", backupPath: "agent.global_super_agent"),
    item("self_model", "Learned Agent self model", "user_defaults:signalasi_agent_self_model", backupPath: "agent.agent_self_model"),
    item("model_planner", "Model planner settings", "user_defaults:signalasi_agent_model_planner", backupPath: "agent.model_planner"),
    item("voice_assistant", "Wake, ASR, and TTS settings", "user_defaults:signalasi_voice_assistant", backupPath: "agent.voice_assistant"),
    item(
      "home_assistant",
      "Home Assistant endpoint and access token",
      "user_defaults:signalasi_home_assistant",
      "keychain:home_assistant",
      backupPath: "agent.home_assistant",
      sensitivity: .secret
    ),
    localOnly("permission_grants", "Host permission grants", "user_defaults:signalasi_permission_grants_v1", .secret),
    localOnly("policy_firewall_replay", "External request replay claims", "user_defaults:signalasi_policy_firewall_replay_v1", .secret),
    localOnly("policy_firewall_audit", "External request policy decisions", "user_defaults:signalasi_policy_firewall_audit_v1", .ephemeral),
    localOnly("cross_team_delegations", "Isolated cross-team delegation envelopes and receipts", "user_defaults:signalasi_cross_team_delegations_v1", .ephemeral),
    localOnly("agent_reputation_ledger", "Signed Agent execution receipts and independent attestations", "user_defaults:signalasi_agent_reputation_ledger_v1", .personal),
    localOnly("run_start_receipts", "Cross-end idempotency receipts", "user_defaults:signalasi_run_start_receipts_v1", .ephemeral),
    localOnly("provider_health", "Per-runtime health and circuit state", "user_defaults:signalasi_agent_provider_health", .ephemeral),
    localOnly("run_workspaces", "Active Run workspaces and checkpoints", "user_defaults:signalasi_agent_workspaces", .ephemeral),
    localOnly("run_events", "Run event ledger", "user_defaults:signalasi_agent_runs", .ephemeral),
    localOnly("data_disclosure_ledger", "Model and Agent data-flow metadata and destination blocks", "files:AgentDataDisclosure/agent-data-disclosure-ledger.json", .secret),
    localOnly("connector_responses", "Pending connector responses", "user_defaults:signalasi_agent_connector_responses", .ephemeral),
    localOnly("mcp_credentials", "MCP connections and credentials", "user_defaults:signalasi_mcp_connections", .secret),
    localOnly("mcp_tool_audit", "Redacted MCP permission decisions and tool receipts", "user_defaults:signalasi_mcp_tool_audit", .ephemeral),
    localOnly("mcp_packages", "Installed MCP packages", "user_defaults:signalasi_mcp_packages", .secret),
    localOnly("installed_skills", "Installed executable Skill packages", "user_defaults:signalasi_agent_skills", .secret),
    localOnly("link_delivery", "Signal Link outbox and inbox receipts", "user_defaults:signalasi_link_delivery_v1", .ephemeral),
    localOnly("runtime_files", "On-device Linux workspaces, exports, downloads, and caches", "files:agent-runtime", .ephemeral)
  ]

  static func backupManifest(
    includeContacts: Bool,
    includeSessionHistory: Bool
  ) -> AgentPrivateDataBackupManifest {
    let included = descriptors.filter {
      shouldExport(
        descriptor: $0,
        includeContacts: includeContacts,
        includeSessionHistory: includeSessionHistory
      )
    }
    let includedIds = Set(included.map(\.id))
    let excluded = descriptors.filter { !includedIds.contains($0.id) }
    return AgentPrivateDataBackupManifest(
      policyVersion: policyVersion,
      encryptedContainerRequired: true,
      privateModeExported: false,
      pausedTrackingExported: false,
      identityRotatedOnReset: true,
      includedStoreIds: included.map(\.id),
      secretStoreIds: included.filter { $0.sensitivity == .secret }.map(\.id),
      excludedStoreIds: excluded.map(\.id),
      eraseStoreIds: descriptors.map(\.id)
    )
  }

  static func shouldExport(
    descriptor: AgentPrivateDataDescriptor,
    includeContacts: Bool,
    includeSessionHistory: Bool
  ) -> Bool {
    switch descriptor.exportPolicy {
    case .alwaysEncrypted:
      return true
    case .optionalContacts:
      return includeContacts
    case .optionalSessionHistory:
      return includeSessionHistory
    case .neverExport:
      return false
    }
  }

  static func audit() -> AgentPrivateDataInventoryAudit {
    var idCounts: [String: Int] = [:]
    descriptors.forEach { idCounts[$0.id, default: 0] += 1 }
    return AgentPrivateDataInventoryAudit(
      duplicateIds: Set(idCounts.filter { $0.value > 1 }.map(\.key)),
      descriptorsWithoutStorage: Set(descriptors.filter { $0.storageIds.isEmpty }.map(\.id)),
      exportedDescriptorsWithoutPath: Set(descriptors.filter {
        $0.exportPolicy != .neverExport && $0.backupPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }.map(\.id)),
      nonExportedDescriptorsWithPath: Set(descriptors.filter {
        $0.exportPolicy == .neverExport && !$0.backupPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }.map(\.id)),
      identityRotationCount: descriptors.filter { $0.erasePolicy == .deleteAndRotateIdentity }.count
    )
  }

  private static func item(
    _ id: String,
    _ category: String,
    _ storageIds: String...,
    backupPath: String,
    exportPolicy: AgentPrivateDataExportPolicy = .alwaysEncrypted,
    sensitivity: AgentPrivateDataSensitivity = .personal,
    erasePolicy: AgentPrivateDataErasePolicy = .delete
  ) -> AgentPrivateDataDescriptor {
    AgentPrivateDataDescriptor(
      id: id,
      category: category,
      storageIds: Set(storageIds),
      backupPath: backupPath,
      exportPolicy: exportPolicy,
      sensitivity: sensitivity,
      erasePolicy: erasePolicy
    )
  }

  private static func localOnly(
    _ id: String,
    _ category: String,
    _ storageId: String,
    _ sensitivity: AgentPrivateDataSensitivity
  ) -> AgentPrivateDataDescriptor {
    AgentPrivateDataDescriptor(
      id: id,
      category: category,
      storageIds: [storageId],
      exportPolicy: .neverExport,
      sensitivity: sensitivity
    )
  }
}
