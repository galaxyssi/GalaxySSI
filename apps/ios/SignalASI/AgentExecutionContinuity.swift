import Foundation

enum AgentCheckpointStatus: String, Codable, CaseIterable, Identifiable {
  case active = "ACTIVE"
  case restored = "RESTORED"
  case invalidated = "INVALIDATED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentCheckpointStatus {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .active
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

struct AgentExecutionCheckpoint: Codable, Equatable {
  var id: String
  var actionId: String
  var planRevision: Int
  var foregroundApp: String
  var activityName: String
  var pageTitle: String
  var screenDigest: String
  var rollbackAction: AgentAction?
  var status: AgentCheckpointStatus
  var createdAtMillis: Int64
  var summary: String
  var timestampMillis: Int64

  init(
    id: String = UUID().uuidString,
    actionId: String,
    planRevision: Int = 0,
    foregroundApp: String = "",
    activityName: String = "",
    pageTitle: String = "",
    screenDigest: String = "",
    rollbackAction: AgentAction? = nil,
    status: AgentCheckpointStatus = .active,
    createdAtMillis: Int64 = 0,
    summary: String = "",
    timestampMillis: Int64? = nil
  ) {
    self.id = id
    self.actionId = actionId
    self.planRevision = planRevision
    self.foregroundApp = foregroundApp
    self.activityName = activityName
    self.pageTitle = pageTitle
    self.screenDigest = screenDigest
    self.rollbackAction = rollbackAction
    self.status = status
    self.createdAtMillis = max(createdAtMillis, 0)
    self.summary = summary
    self.timestampMillis = max(timestampMillis ?? createdAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case actionId = "action_id"
    case planRevision = "plan_revision"
    case foregroundApp = "foreground_app"
    case activityName = "activity_name"
    case pageTitle = "page_title"
    case screenDigest = "screen_digest"
    case rollbackAction = "rollback_action"
    case status
    case createdAtMillis = "created_at_millis"
    case summary
    case timestampMillis = "timestamp_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let actionId = try container.decodeIfPresent(String.self, forKey: .actionId) ?? ""
    let createdAtMillis = try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ??
      (try container.decodeIfPresent(Int64.self, forKey: .timestampMillis) ?? 0)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ??
        Self.fallbackId(actionId: actionId, createdAtMillis: createdAtMillis),
      actionId: actionId,
      planRevision: try container.decodeIfPresent(Int.self, forKey: .planRevision) ?? 0,
      foregroundApp: try container.decodeIfPresent(String.self, forKey: .foregroundApp) ?? "",
      activityName: try container.decodeIfPresent(String.self, forKey: .activityName) ?? "",
      pageTitle: try container.decodeIfPresent(String.self, forKey: .pageTitle) ?? "",
      screenDigest: try container.decodeIfPresent(String.self, forKey: .screenDigest) ?? "",
      rollbackAction: try container.decodeIfPresent(AgentAction.self, forKey: .rollbackAction),
      status: try container.decodeIfPresent(AgentCheckpointStatus.self, forKey: .status) ?? .active,
      createdAtMillis: createdAtMillis,
      summary: try container.decodeIfPresent(String.self, forKey: .summary) ?? "",
      timestampMillis: try container.decodeIfPresent(Int64.self, forKey: .timestampMillis)
    )
  }

  private static func fallbackId(actionId: String, createdAtMillis: Int64) -> String {
    let suffix = actionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : actionId
    return "checkpoint-\(suffix)-\(max(createdAtMillis, 0))"
  }
}

enum AgentExecutionContinuity {
  static func checkpointBefore(
    action: AgentAction,
    screen: AgentScreenContext,
    planRevision: Int,
    id: String = UUID().uuidString,
    nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> AgentExecutionCheckpoint {
    AgentExecutionCheckpoint(
      id: id,
      actionId: action.id,
      planRevision: planRevision,
      foregroundApp: screen.foregroundApp,
      activityName: screen.activityName,
      pageTitle: screen.pageTitle,
      screenDigest: screenDigest(screen),
      rollbackAction: rollbackAction(for: action),
      status: .active,
      createdAtMillis: nowMillis
    )
  }

  static func screenDigest(_ screen: AgentScreenContext) -> String {
    let notifications = screen.notifications.items.prefix(6).map { item in
      [item.key, item.packageName, item.title, String(item.postedAtMillis), item.sensitiveFlags.joined(separator: ",")]
        .joined(separator: "\u{001f}")
    }.joined(separator: "\u{001d}")
    let clickableElements = screen.clickableElements.prefix(12).map { item in
      [item.viewId, item.label].joined(separator: "\u{001f}")
    }.joined(separator: "\u{001d}")
    let inputFields = screen.inputFields.prefix(8).map { item in
      [item.viewId, item.label].joined(separator: "\u{001f}")
    }.joined(separator: "\u{001d}")
    let payload: [String] = [
      screen.foregroundApp,
      screen.activityName,
      screen.pageTitle,
      screen.visibleTexts.prefix(40).joined(separator: "\u{001f}"),
      String(screen.clickableNodeCount),
      String(screen.inputFieldCount),
      String(screen.notifications.totalCount),
      notifications,
      screen.clipboard.textHash,
      String(screen.clipboard.textLength),
      screen.clipboard.sensitiveFlags.joined(separator: ","),
      screen.sensitiveFlags.joined(separator: ","),
      clickableElements,
      inputFields,
      screen.scrollableRegions.prefix(6).map(\.viewId).joined(separator: "\u{001d}"),
      String(screen.deviceStatus.batteryPercent),
      String(screen.deviceStatus.charging),
      String(screen.deviceStatus.powerSaveMode),
      screen.deviceStatus.network,
      String(screen.deviceStatus.freeStorageMb),
      screen.deviceStatus.thermalState
    ]
    return String(javaStringHash(payload.joined(separator: "\u{001e}")))
  }

  private static func rollbackAction(for action: AgentAction) -> AgentAction? {
    switch action.kind {
    case .openApp, .openURL, .recents:
      return AgentAction(
        id: "rollback-\(action.id)",
        kind: .back,
        target: action.target,
        risk: .low,
        status: .pendingConfirmation,
        description: "Return to the screen before \(action.description)",
        requiresConfirmation: true
      )
    case .swipe:
      return reverseSwipe(action)
    default:
      return nil
    }
  }

  private static func reverseSwipe(_ action: AgentAction) -> AgentAction? {
    guard let fromX = action.parameters["from_x"],
          let fromY = action.parameters["from_y"],
          let toX = action.parameters["to_x"],
          let toY = action.parameters["to_y"] else {
      return nil
    }
    return AgentAction(
      id: "rollback-\(action.id)",
      kind: .swipe,
      target: action.target,
      risk: .low,
      status: .pendingConfirmation,
      description: "Reverse the previous swipe",
      parameters: [
        "from_x": toX,
        "from_y": toY,
        "to_x": fromX,
        "to_y": fromY
      ],
      requiresConfirmation: true
    )
  }

  private static func javaStringHash(_ value: String) -> Int32 {
    var hash: Int32 = 0
    for codeUnit in value.utf16 {
      hash = hash &* 31 &+ Int32(codeUnit)
    }
    return hash
  }
}

extension AgentPlan {
  func addCheckpoint(_ checkpoint: AgentExecutionCheckpoint) -> AgentPlan {
    var copy = self
    copy.checkpoints = Array((copy.checkpoints + [checkpoint]).suffix(20))
    return copy
  }

  func markCheckpoint(_ checkpointId: String, status: AgentCheckpointStatus) -> AgentPlan {
    var copy = self
    copy.checkpoints = copy.checkpoints.map { checkpoint in
      guard checkpoint.id == checkpointId else {
        return checkpoint
      }
      var marked = checkpoint
      marked.status = status
      return marked
    }
    return copy
  }

  func recoverInterruptedExecution() -> AgentPlan {
    var copy = self
    copy.actions = copy.actions.map { action in
      guard action.status == .running else {
        return action
      }
      var interrupted = action
      interrupted.status = .pendingConfirmation
      interrupted.result = "Execution was interrupted before verification"
      interrupted.evidence = "interrupted"
      return interrupted
    }
    return copy
  }

  func historyForReplan() -> [AgentAction] {
    let terminalStatuses: [AgentActionStatus] = [.completed, .failed, .blocked, .rolledBack]
    return Array((actionHistory + actions.filter { terminalStatuses.contains($0.status) }).suffix(40))
  }
}
