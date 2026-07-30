import CryptoKit
import Foundation

struct AgentTaskRecord: Codable, Equatable, Identifiable {
  var taskId: String
  var sessionId: String
  var goal: String
  var phase: AgentPhase
  var routeKind: AgentRouteKind
  var targetTitle: String
  var risk: AgentRisk
  var blocked: Bool
  var result: String
  var verification: String
  var outputFiles: [String]
  var executionLog: [String]
  var createdAtMillis: Int64
  var updatedAtMillis: Int64

  var id: String { taskId }

  init(
    taskId: String,
    sessionId: String,
    goal: String,
    phase: AgentPhase,
    routeKind: AgentRouteKind,
    targetTitle: String,
    risk: AgentRisk,
    blocked: Bool,
    result: String = "",
    verification: String = "",
    outputFiles: [String] = [],
    executionLog: [String] = [],
    createdAtMillis: Int64 = 0,
    updatedAtMillis: Int64 = 0
  ) {
    self.taskId = taskId
    self.sessionId = sessionId
    self.goal = goal
    self.phase = phase
    self.routeKind = routeKind
    self.targetTitle = targetTitle
    self.risk = risk
    self.blocked = blocked
    self.result = result
    self.verification = verification
    self.outputFiles = outputFiles
    self.executionLog = executionLog
    self.createdAtMillis = createdAtMillis
    self.updatedAtMillis = updatedAtMillis
  }

  enum CodingKeys: String, CodingKey {
    case taskId = "task_id"
    case sessionId = "session_id"
    case goal
    case phase
    case routeKind = "route_kind"
    case targetTitle = "target_title"
    case risk
    case blocked
    case result
    case verification
    case outputFiles = "output_files"
    case executionLog = "execution_log"
    case createdAtMillis = "created_at_millis"
    case updatedAtMillis = "updated_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      taskId: try container.decodeIfPresent(String.self, forKey: .taskId) ?? "",
      sessionId: try container.decodeIfPresent(String.self, forKey: .sessionId) ?? "",
      goal: try container.decodeIfPresent(String.self, forKey: .goal) ?? "",
      phase: try container.decodeIfPresent(AgentPhase.self, forKey: .phase) ?? .executing,
      routeKind: try container.decodeIfPresent(AgentRouteKind.self, forKey: .routeKind) ?? .unknown,
      targetTitle: try container.decodeIfPresent(String.self, forKey: .targetTitle) ?? "",
      risk: try container.decodeIfPresent(AgentRisk.self, forKey: .risk) ?? .medium,
      blocked: try container.decodeIfPresent(Bool.self, forKey: .blocked) ?? false,
      result: try container.decodeIfPresent(String.self, forKey: .result) ?? "",
      verification: try container.decodeIfPresent(String.self, forKey: .verification) ?? "",
      outputFiles: try container.decodeIfPresent([String].self, forKey: .outputFiles) ?? [],
      executionLog: try container.decodeIfPresent([String].self, forKey: .executionLog) ?? [],
      createdAtMillis: try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? 0,
      updatedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .updatedAtMillis) ?? 0
    )
  }
}

enum AgentStepKind: String, Codable, CaseIterable, Identifiable {
  case observeScreen = "OBSERVE_SCREEN"
  case analyzeGoal = "ANALYZE_GOAL"
  case buildPlan = "BUILD_PLAN"
  case confirmAndAct = "CONFIRM_AND_ACT"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentStepKind {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .buildPlan
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

enum AgentStepStatus: String, Codable, CaseIterable, Identifiable {
  case current = "CURRENT"
  case done = "DONE"
  case waiting = "WAITING"
  case safe = "SAFE"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentStepStatus {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .waiting
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

struct AgentStep: Codable, Equatable {
  var order: Int
  var kind: AgentStepKind
  var status: AgentStepStatus
}

struct AgentPermissionRequirement: Codable, Equatable {
  var id: String
  var title: String
  var required: Bool
  var granted: Bool

  init(
    id: String,
    title: String,
    required: Bool = true,
    granted: Bool = false
  ) {
    self.id = id
    self.title = title
    self.required = required
    self.granted = granted
  }
}

struct AgentPlanValidation: Codable, Equatable {
  var valid: Bool
  var issues: [String]

  init(valid: Bool = true, issues: [String] = []) {
    self.valid = valid
    self.issues = issues
  }
}

struct AgentSafetyReview: Codable, Equatable {
  var risk: AgentRisk
  var requiresConfirmation: Bool
  var blocked: Bool
  var mode: AgentPermissionMode
  var deniedPermissions: [String]
  var warnings: [String]
  var reason: String

  init(
    risk: AgentRisk = .low,
    requiresConfirmation: Bool = true,
    blocked: Bool = false,
    mode: AgentPermissionMode = .askBeforeAction,
    deniedPermissions: [String] = [],
    warnings: [String] = [],
    reason: String = ""
  ) {
    self.risk = risk
    self.requiresConfirmation = requiresConfirmation
    self.blocked = blocked
    self.mode = mode
    self.deniedPermissions = deniedPermissions
    self.warnings = warnings
    self.reason = reason
  }

  enum CodingKeys: String, CodingKey {
    case risk
    case requiresConfirmation = "requires_confirmation"
    case blocked
    case mode
    case deniedPermissions = "denied_permissions"
    case warnings
    case reason
  }
}

struct AgentRoute: Codable, Equatable {
  var routeId: String
  var kind: AgentRouteKind
  var targetId: String
  var targetTitle: String
  var status: String
  var deliveryMode: String
  var capabilities: [String]

  init(
    routeId: String = "",
    kind: AgentRouteKind = .unknown,
    targetId: String = "",
    targetTitle: String = "",
    status: String = "",
    deliveryMode: String = "",
    capabilities: [String] = []
  ) {
    self.routeId = routeId
    self.kind = kind
    self.targetId = targetId
    self.targetTitle = targetTitle
    self.status = status
    self.deliveryMode = deliveryMode
    self.capabilities = capabilities
  }

  enum CodingKeys: String, CodingKey {
    case routeId = "route_id"
    case kind
    case targetId = "target_id"
    case targetTitle = "target_title"
    case status
    case deliveryMode = "delivery_mode"
    case capabilities
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      routeId: try container.decodeIfPresent(String.self, forKey: .routeId) ?? "",
      kind: try container.decodeIfPresent(AgentRouteKind.self, forKey: .kind) ?? .unknown,
      targetId: try container.decodeIfPresent(String.self, forKey: .targetId) ?? "",
      targetTitle: try container.decodeIfPresent(String.self, forKey: .targetTitle) ?? "",
      status: try container.decodeIfPresent(String.self, forKey: .status) ?? "",
      deliveryMode: try container.decodeIfPresent(String.self, forKey: .deliveryMode) ?? "",
      capabilities: try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
    )
  }
}

struct AgentVerificationResult: Codable, Equatable {
  var actionId: String
  var success: Bool
  var evidence: String
  var timestampMillis: Int64

  init(
    actionId: String,
    success: Bool = false,
    evidence: String = "",
    timestampMillis: Int64 = 0
  ) {
    self.actionId = actionId
    self.success = success
    self.evidence = evidence
    self.timestampMillis = timestampMillis
  }

  enum CodingKeys: String, CodingKey {
    case actionId = "action_id"
    case success
    case evidence
    case timestampMillis = "timestamp_millis"
  }
}

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
    let payload = [
      screen.foregroundApp,
      screen.activityName,
      screen.pageTitle,
      screen.visibleTexts.prefix(40).joined(separator: "\u{001f}"),
      String(screen.clickableNodeCount),
      String(screen.inputFieldCount)
    ].joined(separator: "\u{001e}")
    return String(javaStringHash(payload))
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

enum AgentAuditEvent: String, Codable, CaseIterable, Identifiable {
  case screenObserved = "SCREEN_OBSERVED"
  case screenVerified = "SCREEN_VERIFIED"
  case checkpointSaved = "CHECKPOINT_SAVED"
  case checkpointRestored = "CHECKPOINT_RESTORED"
  case checkpointRestoreFailed = "CHECKPOINT_RESTORE_FAILED"
  case planReplanned = "PLAN_REPLANNED"
  case planReplanLimitReached = "PLAN_REPLAN_LIMIT_REACHED"
  case planEdited = "PLAN_EDITED"
  case planEditRejected = "PLAN_EDIT_REJECTED"
  case reasoningSummary = "REASONING_SUMMARY"
  case toolStarted = "TOOL_STARTED"
  case toolCompleted = "TOOL_COMPLETED"
  case toolOutputHandoff = "TOOL_OUTPUT_HANDOFF"
  case toolGraphBlocked = "TOOL_GRAPH_BLOCKED"
  case autonomyGuardBlocked = "AUTONOMY_GUARD_BLOCKED"
  case actionRecoveryStarted = "ACTION_RECOVERY_STARTED"
  case actionRecoveryCompleted = "ACTION_RECOVERY_COMPLETED"
  case actionRecoveryManualRequired = "ACTION_RECOVERY_MANUAL_REQUIRED"
  case goalReceived = "GOAL_RECEIVED"
  case invocationAudit = "INVOCATION_AUDIT"
  case connectorResponseReceived = "CONNECTOR_RESPONSE_RECEIVED"
  case responseSelfCheckPassed = "RESPONSE_SELF_CHECK_PASSED"
  case responseSelfCheckFailed = "RESPONSE_SELF_CHECK_FAILED"
  case memorySkipped = "MEMORY_SKIPPED"
  case memoryForgotten = "MEMORY_FORGOTTEN"
  case memoryUpdated = "MEMORY_UPDATED"
  case memoryConflictDetected = "MEMORY_CONFLICT_DETECTED"
  case memoryConflictResolved = "MEMORY_CONFLICT_RESOLVED"
  case knowledgeImported = "KNOWLEDGE_IMPORTED"
  case knowledgeAccessed = "KNOWLEDGE_ACCESSED"
  case knowledgeAccessUpdated = "KNOWLEDGE_ACCESS_UPDATED"
  case workflowUpdated = "WORKFLOW_UPDATED"
  case workflowRun = "WORKFLOW_RUN"
  case actionExecuted = "ACTION_EXECUTED"
  case actionBlocked = "ACTION_BLOCKED"
  case taskCancelled = "TASK_CANCELLED"
  case taskPaused = "TASK_PAUSED"
  case taskResumed = "TASK_RESUMED"
  case taskInterrupted = "TASK_INTERRUPTED"
  case settingsUpdated = "SETTINGS_UPDATED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentAuditEvent {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .invocationAudit
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

struct AgentAuditEntry: Codable, Equatable {
  var event: AgentAuditEvent
  var detail: String
  var timestampMillis: Int64

  init(
    event: AgentAuditEvent,
    detail: String = "",
    timestampMillis: Int64 = 0
  ) {
    self.event = event
    self.detail = detail
    self.timestampMillis = timestampMillis
  }

  enum CodingKeys: String, CodingKey {
    case event
    case detail
    case timestampMillis = "timestamp_millis"
  }
}

struct AgentPlan: Codable, Equatable, Identifiable {
  var goal: String
  var screen: AgentScreenContext
  var steps: [AgentStep]
  var actions: [AgentAction]
  var executionMode: AgentTaskExecutionMode
  var planId: String
  var selectedAgentOrModel: String
  var requiredPermissions: [AgentPermissionRequirement]
  var confirmationRequired: Bool
  var rollbackStrategy: String
  var expectedResult: String
  var timeoutSeconds: Int
  var plannerProfile: String
  var contextDigest: String
  var routeRationale: String
  var route: AgentRoute
  var validation: AgentPlanValidation
  var verificationResults: [AgentVerificationResult]
  var safetyReview: AgentSafetyReview
  var revision: Int
  var replanCount: Int
  var actionHistory: [AgentAction]
  var checkpoints: [AgentExecutionCheckpoint]

  var id: String { planId }

  init(
    goal: String,
    screen: AgentScreenContext,
    steps: [AgentStep],
    actions: [AgentAction],
    executionMode: AgentTaskExecutionMode = .autoComplete,
    planId: String = UUID().uuidString,
    selectedAgentOrModel: String? = nil,
    requiredPermissions: [AgentPermissionRequirement] = [],
    confirmationRequired: Bool = true,
    rollbackStrategy: String = "Stop execution and ask the user before retrying.",
    expectedResult: String? = nil,
    timeoutSeconds: Int = 60,
    plannerProfile: String = "rule-based-local",
    contextDigest: String = "",
    routeRationale: String = "",
    route: AgentRoute = AgentRoute(),
    validation: AgentPlanValidation = AgentPlanValidation(),
    verificationResults: [AgentVerificationResult] = [],
    safetyReview: AgentSafetyReview = AgentSafetyReview(),
    revision: Int = 1,
    replanCount: Int = 0,
    actionHistory: [AgentAction] = [],
    checkpoints: [AgentExecutionCheckpoint] = []
  ) {
    self.goal = goal
    self.screen = screen
    self.steps = steps
    self.actions = actions
    self.executionMode = executionMode
    self.planId = planId
    self.selectedAgentOrModel = selectedAgentOrModel ?? actions.first?.target ?? ""
    self.requiredPermissions = requiredPermissions
    self.confirmationRequired = confirmationRequired
    self.rollbackStrategy = rollbackStrategy
    self.expectedResult = expectedResult ?? actions.first?.description ?? ""
    self.timeoutSeconds = timeoutSeconds
    self.plannerProfile = plannerProfile
    self.contextDigest = contextDigest
    self.routeRationale = routeRationale
    self.route = route
    self.validation = validation
    self.verificationResults = verificationResults
    self.safetyReview = safetyReview
    self.revision = revision
    self.replanCount = replanCount
    self.actionHistory = actionHistory
    self.checkpoints = checkpoints
  }

  enum CodingKeys: String, CodingKey {
    case goal
    case screen
    case steps
    case actions
    case executionMode = "execution_mode"
    case planId = "plan_id"
    case selectedAgentOrModel = "selected_agent_or_model"
    case requiredPermissions = "required_permissions"
    case confirmationRequired = "confirmation_required"
    case rollbackStrategy = "rollback_strategy"
    case expectedResult = "expected_result"
    case timeoutSeconds = "timeout_seconds"
    case plannerProfile = "planner_profile"
    case contextDigest = "context_digest"
    case routeRationale = "route_rationale"
    case route
    case validation
    case verificationResults = "verification_results"
    case safetyReview = "safety_review"
    case revision
    case replanCount = "replan_count"
    case actionHistory = "action_history"
    case checkpoints
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      goal: try container.decodeIfPresent(String.self, forKey: .goal) ?? "",
      screen: try container.decodeIfPresent(AgentScreenContext.self, forKey: .screen) ?? AgentScreenContext(foregroundApp: ""),
      steps: try container.decodeIfPresent([AgentStep].self, forKey: .steps) ?? [],
      actions: try container.decodeIfPresent([AgentAction].self, forKey: .actions) ?? [],
      executionMode: try container.decodeIfPresent(AgentTaskExecutionMode.self, forKey: .executionMode) ?? .autoComplete,
      planId: try container.decodeIfPresent(String.self, forKey: .planId) ?? UUID().uuidString,
      selectedAgentOrModel: try container.decodeIfPresent(String.self, forKey: .selectedAgentOrModel),
      requiredPermissions: try container.decodeIfPresent([AgentPermissionRequirement].self, forKey: .requiredPermissions) ?? [],
      confirmationRequired: try container.decodeIfPresent(Bool.self, forKey: .confirmationRequired) ?? true,
      rollbackStrategy: try container.decodeIfPresent(String.self, forKey: .rollbackStrategy) ?? "Stop execution and ask the user before retrying.",
      expectedResult: try container.decodeIfPresent(String.self, forKey: .expectedResult),
      timeoutSeconds: try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 60,
      plannerProfile: try container.decodeIfPresent(String.self, forKey: .plannerProfile) ?? "rule-based-local",
      contextDigest: try container.decodeIfPresent(String.self, forKey: .contextDigest) ?? "",
      routeRationale: try container.decodeIfPresent(String.self, forKey: .routeRationale) ?? "",
      route: try container.decodeIfPresent(AgentRoute.self, forKey: .route) ?? AgentRoute(),
      validation: try container.decodeIfPresent(AgentPlanValidation.self, forKey: .validation) ?? AgentPlanValidation(),
      verificationResults: try container.decodeIfPresent([AgentVerificationResult].self, forKey: .verificationResults) ?? [],
      safetyReview: try container.decodeIfPresent(AgentSafetyReview.self, forKey: .safetyReview) ?? AgentSafetyReview(),
      revision: try container.decodeIfPresent(Int.self, forKey: .revision) ?? 1,
      replanCount: try container.decodeIfPresent(Int.self, forKey: .replanCount) ?? 0,
      actionHistory: try container.decodeIfPresent([AgentAction].self, forKey: .actionHistory) ?? [],
      checkpoints: try container.decodeIfPresent([AgentExecutionCheckpoint].self, forKey: .checkpoints) ?? []
    )
  }
}

struct AgentSessionSnapshot: Codable, Equatable {
  var sessionId: String
  var phase: AgentPhase
  var currentGoal: String
  var currentScreen: AgentScreenContext
  var currentPlan: AgentPlan?
  var auditTrail: [AgentAuditEntry]
  var lastActionResult: AgentActionResult?
  var activeWorkflowExecutionId: String
  var taskExecutionMode: AgentTaskExecutionMode
  var executionLoopSnapshot: AgentExecutionLoopSnapshot?
  var updatedAtMillis: Int64

  init(
    sessionId: String,
    phase: AgentPhase,
    currentGoal: String,
    currentScreen: AgentScreenContext,
    currentPlan: AgentPlan?,
    auditTrail: [AgentAuditEntry],
    lastActionResult: AgentActionResult?,
    activeWorkflowExecutionId: String = "",
    taskExecutionMode: AgentTaskExecutionMode = .autoComplete,
    executionLoopSnapshot: AgentExecutionLoopSnapshot? = nil,
    updatedAtMillis: Int64
  ) {
    self.sessionId = sessionId
    self.phase = phase
    self.currentGoal = currentGoal
    self.currentScreen = currentScreen
    self.currentPlan = currentPlan
    self.auditTrail = auditTrail
    self.lastActionResult = lastActionResult
    self.activeWorkflowExecutionId = activeWorkflowExecutionId
    self.taskExecutionMode = taskExecutionMode
    self.executionLoopSnapshot = executionLoopSnapshot
    self.updatedAtMillis = updatedAtMillis
  }

  enum CodingKeys: String, CodingKey {
    case sessionId = "session_id"
    case phase
    case currentGoal = "current_goal"
    case currentScreen = "current_screen"
    case currentPlan = "current_plan"
    case auditTrail = "audit_trail"
    case lastActionResult = "last_action_result"
    case activeWorkflowExecutionId = "active_workflow_execution_id"
    case taskExecutionMode = "task_execution_mode"
    case executionLoopSnapshot = "execution_loop_snapshot"
    case updatedAtMillis = "updated_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      sessionId: try container.decodeIfPresent(String.self, forKey: .sessionId) ?? "",
      phase: try container.decodeIfPresent(AgentPhase.self, forKey: .phase) ?? .observing,
      currentGoal: try container.decodeIfPresent(String.self, forKey: .currentGoal) ?? "",
      currentScreen: try container.decodeIfPresent(AgentScreenContext.self, forKey: .currentScreen) ?? AgentScreenContext(foregroundApp: ""),
      currentPlan: try container.decodeIfPresent(AgentPlan.self, forKey: .currentPlan),
      auditTrail: try container.decodeIfPresent([AgentAuditEntry].self, forKey: .auditTrail) ?? [],
      lastActionResult: try container.decodeIfPresent(AgentActionResult.self, forKey: .lastActionResult),
      activeWorkflowExecutionId: try container.decodeIfPresent(String.self, forKey: .activeWorkflowExecutionId) ?? "",
      taskExecutionMode: try container.decodeIfPresent(AgentTaskExecutionMode.self, forKey: .taskExecutionMode) ?? .autoComplete,
      executionLoopSnapshot: try container.decodeIfPresent(AgentExecutionLoopSnapshot.self, forKey: .executionLoopSnapshot),
      updatedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .updatedAtMillis) ?? 0
    )
  }
}

struct AgentPlanLifecycleNormalization: Equatable {
  var plan: AgentPlan
  var removedActions: [AgentAction]

  var changed: Bool {
    !removedActions.isEmpty
  }

  func recoverResult(previous: AgentActionResult?) -> AgentActionResult? {
    guard changed else {
      return previous
    }
    let removedIds = Set(removedActions.map(\.id))
    if let previous,
      !removedIds.contains(previous.actionId),
      !previous.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return previous
    }
    guard let action = plan.actions.reversed().first(where: {
      !$0.result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Self.resultStatuses.contains($0.status)
    }) else {
      return previous
    }
    return AgentActionResult(
      actionId: action.id,
      success: action.status == .completed,
      message: action.result
    )
  }

  private static let resultStatuses: Set<AgentActionStatus> = [
    .completed,
    .failed,
    .blocked
  ]
}

struct AgentSessionLifecycleNormalization: Equatable {
  var session: AgentSessionSnapshot
  var removedActions: [AgentAction]

  var changed: Bool {
    !removedActions.isEmpty
  }
}

enum AgentPlanValidator {
  static func validate(_ plan: AgentPlan) -> AgentPlanValidation {
    var issues: [String] = []
    if isBlank(plan.goal) {
      issues.append("goal_blank")
    }
    if plan.actions.isEmpty {
      issues.append("actions_empty")
    }
    let actionIds = plan.actions.map(\.id)
    if Set(actionIds).count != actionIds.count {
      issues.append("action_ids_duplicate")
    }
    for action in plan.actions {
      if isBlank(action.description) {
        issues.append("action_description_blank:\(action.id)")
      }
    }
    if plan.safetyReview.risk.weight >= AgentRisk.high.weight && !plan.confirmationRequired {
      issues.append("high_risk_without_confirmation")
    }
    if plan.actions.contains(where: { $0.kind == .callConnector || $0.kind == .controlDevice }) &&
      plan.route.kind == .unknown {
      issues.append("route_unknown")
    }
    return AgentPlanValidation(valid: issues.isEmpty, issues: issues)
  }

  private static func isBlank(_ value: String) -> Bool {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

struct AgentPlanRequest: Codable, Equatable {
  var goal: String
  var screen: AgentScreenContext
  var targets: [AgentCallableTarget]
  var nativeTools: [AgentNativeToolDescriptor]
  var contextDigest: String

  init(
    goal: String,
    screen: AgentScreenContext,
    targets: [AgentCallableTarget] = [],
    nativeTools: [AgentNativeToolDescriptor] = [],
    contextDigest: String = ""
  ) {
    self.goal = goal
    self.screen = screen
    self.targets = targets
    self.nativeTools = nativeTools
    self.contextDigest = contextDigest
  }

  enum CodingKeys: String, CodingKey {
    case goal
    case screen
    case targets
    case nativeTools = "native_tools"
    case contextDigest = "context_digest"
  }
}

enum AgentPlanFactory {
  static let unavailableReasoningConnectorId = "reasoning-provider-unavailable"

  static func singleAction(request: AgentPlanRequest, action: AgentAction) -> AgentPlan {
    actions(request: request, [action])
  }

  static func actions(request: AgentPlanRequest, _ actions: [AgentAction]) -> AgentPlan {
    let plannedActions = AgentHomeAssistantNativeToolPlanBridge.rewrite(
      actions: collapseDuplicateConnectorCalls(actions),
      request: request
    )
    let resolvedActions = plannedActions.isEmpty ? [emptyPlanFallbackAction(request)] : plannedActions
    let routeAction = resolvedActions.first {
      $0.kind == .callConnector || $0.kind == .controlDevice
    } ?? resolvedActions[0]
    var plan = AgentPlan(
      goal: request.goal,
      screen: request.screen,
      steps: [
        AgentStep(order: 1, kind: .observeScreen, status: .done),
        AgentStep(order: 2, kind: .analyzeGoal, status: .done),
        AgentStep(order: 3, kind: .buildPlan, status: .done),
        AgentStep(order: 4, kind: .confirmAndAct, status: .current)
      ],
      actions: resolvedActions,
      selectedAgentOrModel: selectedAgentOrModel(resolvedActions),
      requiredPermissions: distinctPermissions(resolvedActions.flatMap { permissions(for: $0, request: request) }),
      confirmationRequired: true,
      rollbackStrategy: rollbackStrategy(for: resolvedActions),
      expectedResult: expectedResult(for: resolvedActions),
      timeoutSeconds: min(resolvedActions.map { timeoutSeconds(for: $0) }.reduce(0, +), 240),
      plannerProfile: "rule-based-local",
      contextDigest: resolvedContextDigest(request),
      routeRationale: routeRationale(for: routeAction, request: request),
      route: AgentRouteResolver.resolve(action: routeAction, targets: request.targets)
    )
    plan.validation = AgentPlanValidator.validate(plan)
    return plan
  }

  private static func emptyPlanFallbackAction(_ request: AgentPlanRequest) -> AgentAction {
    if let target = AgentConnectorRouteSelector.select(targets: request.targets, decision: nil)?.target {
      return AgentAction(
        id: "fallback-connector-\(stableSuffix(request.goal))",
        kind: .callConnector,
        target: target.title,
        risk: .low,
        status: .pendingConfirmation,
        description: "Ask \(target.title)",
        parameters: [
          "connector_id": target.id,
          "prompt": request.goal,
          "planner_fallback": "empty_action_plan",
          "_signalasi_desktop_executor_full":
            String(target.desktopAccessProfile == SignalASILinkProtocol.accessDesktopExecutor)
        ],
        requiresConfirmation: false
      )
    }
    return AgentAction(
      id: "connector-unavailable-\(stableSuffix(request.goal))",
      kind: .callConnector,
      target: "Agent or model",
      risk: .low,
      status: .pendingConfirmation,
      description: "Report that no reasoning provider is configured",
      parameters: [
        "connector_id": unavailableReasoningConnectorId,
        "prompt": request.goal,
        "planner_fallback": "empty_action_plan"
      ],
      requiresConfirmation: false
    )
  }

  private static func collapseDuplicateConnectorCalls(_ actions: [AgentAction]) -> [AgentAction] {
    var canonicalIds: [String: String] = [:]
    let retained = actions.filter { action in
      guard action.kind == .callConnector, action.id != "knowledge-answer" else {
        canonicalIds[action.id] = action.id
        return true
      }
      let connector = firstNonBlank(action.parameters["connector_id"] ?? "", action.target)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      let key = "\(action.kind.rawValue):\(connector)"
      if let canonicalId = canonicalIds[key] {
        canonicalIds[action.id] = canonicalId
        return false
      }
      canonicalIds[key] = action.id
      canonicalIds[action.id] = action.id
      return true
    }
    var idMap: [String: String] = [:]
    for action in actions {
      idMap[action.id] = firstNonBlank(canonicalIds[action.id] ?? "", action.id)
    }
    return retained.map { $0.remappingToolGraphIds(idMap: idMap) }
  }

  private static func selectedAgentOrModel(_ actions: [AgentAction]) -> String {
    let connectorTargets = actions
      .filter { $0.kind == .callConnector || $0.kind == .controlDevice }
      .map { selectedAgentOrModel($0) }
      .stableDistinct()
    if connectorTargets.count == 1 {
      return connectorTargets[0]
    }
    let targets = actions.map { selectedAgentOrModel($0) }.stableDistinct()
    return targets.count == 1 ? targets[0] : "Multiple Executors"
  }

  private static func selectedAgentOrModel(_ action: AgentAction) -> String {
    switch action.kind {
    case .callConnector, .controlDevice:
      return action.target
    case .importWebKnowledge:
      return "Agent Knowledge"
    default:
      return "Mobile Executor"
    }
  }

  private static func permissions(
    for action: AgentAction,
    request: AgentPlanRequest
  ) -> [AgentPermissionRequirement] {
    var permissions: [AgentPermissionRequirement] = []
    switch action.kind {
    case .readScreen, .saveScreenKnowledge, .copyScreenText, .tap, .longPress, .typeText,
         .deleteText, .pasteText, .swipe, .back, .home, .recents, .lockScreen:
      permissions.append(AgentPermissionRequirement(
        id: "accessibility_service",
        title: "Screen Agent permission",
        granted: request.screen.isAccessibilityEnabled
      ))
    case .openApp, .openURL, .setAlarm:
      permissions.append(intentPermission(for: action))
    case .createNotification:
      permissions.append(AgentPermissionRequirement(id: "post_notification", title: "Post local notification", granted: true))
    case .replyNotification:
      permissions.append(AgentPermissionRequirement(
        id: "notification_direct_reply",
        title: "Notification direct reply",
        granted: false
      ))
    case .callNativeTool:
      if let descriptor = request.nativeTools.first(where: { $0.id == action.parameters["tool_id"] }) {
        permissions += descriptor.requiredPermissions.map { requirement in
          AgentPermissionRequirement(
            id: requirement.id,
            title: requirement.title,
            granted: descriptor.availability.status == .available
          )
        }
      }
    case .callConnector, .controlDevice:
      let connectorId = action.parameters["connector_id"] ?? ""
      let target = request.targets.first { target in
        target.id == connectorId || target.title == action.target
      }
      permissions.append(AgentPermissionRequirement(
        id: "paired_contact",
        title: "Verified SignalASI contact",
        granted: AgentConnectorRouteSelector.isDeliverable(target)
      ))
    case .draftPlan, .importWebKnowledge:
      break
    }
    if action.kind == .pasteText {
      permissions.append(AgentPermissionRequirement(id: "clipboard_read", title: "Clipboard read", granted: true))
    }
    if action.kind == .copyScreenText {
      permissions.append(AgentPermissionRequirement(id: "clipboard_write", title: "Clipboard write", granted: true))
    }
    return permissions
  }

  private static func intentPermission(for action: AgentAction) -> AgentPermissionRequirement {
    let id: String
    if action.id.contains("notification-listener") {
      id = "notification_listener_settings"
    } else if action.id.contains("accessibility") {
      id = "accessibility_settings"
    } else if action.id.contains("current-app-settings") {
      id = "current_app_details_settings"
    } else if action.id == "open-installed-app" {
      id = "launch_installed_app"
    } else if action.id.contains("camera") {
      id = "camera_app_handoff"
    } else if action.id.contains("phone") {
      id = "phone_dialer_handoff"
    } else if action.id.contains("messages") {
      id = "messages_app_handoff"
    } else if action.kind == .setAlarm {
      id = "alarm_handoff"
    } else if action.kind == .openURL {
      id = "external_url_handoff"
    } else {
      id = "ios_system_handoff"
    }
    return AgentPermissionRequirement(id: id, title: id.replacingOccurrences(of: "_", with: " "), granted: true)
  }

  private static func rollbackStrategy(for action: AgentAction) -> String {
    switch action.kind {
    case .typeText, .deleteText, .pasteText:
      return "Stop before sending or submitting anything."
    case .tap, .longPress, .swipe:
      return "Observe the result and go back if the page changed unexpectedly."
    case .lockScreen:
      return "Wake and unlock the phone manually to continue."
    case .replyNotification:
      return "The sent reply cannot be recalled; report delivery failure immediately."
    case .callNativeTool:
      return "Use the native tool receipt and its verification evidence before retrying."
    case .callConnector, .controlDevice:
      return "Keep the task in chat history and report delivery failure."
    case .importWebKnowledge:
      return "Remove the imported source if extraction or indexing is incorrect."
    default:
      return "Stop execution and ask the user before retrying."
    }
  }

  private static func rollbackStrategy(for actions: [AgentAction]) -> String {
    actions.count == 1 ? rollbackStrategy(for: actions[0]) : "Stop the queue and ask the user before retrying the next action."
  }

  private static func expectedResult(for action: AgentAction) -> String {
    switch action.kind {
    case .openApp:
      return "The requested iOS app or handoff surface opens."
    case .openURL:
      return "The requested URL opens in a browser or matching app."
    case .setAlarm:
      return "Alarm setup is opened or handed off."
    case .lockScreen:
      return "The phone screen is locked through the approved system path."
    case .copyScreenText:
      return "Visible screen text is copied to the clipboard."
    case .saveScreenKnowledge:
      return "Current screen is saved into Agent knowledge."
    case .deleteText:
      return "Text is cleared from the active input field."
    case .pasteText:
      return "Clipboard text is pasted into the active input field."
    case .createNotification:
      return "A local iOS notification is created."
    case .replyNotification:
      return "The selected SignalASI notification action receives the confirmed reply."
    case .callNativeTool:
      return "The selected phone-native tool returns a locally verified receipt."
    case .callConnector:
      return "The task is sent to the paired agent contact."
    case .controlDevice:
      return "The trusted device connector receives the task."
    case .importWebKnowledge:
      return "The web page is extracted and indexed in Agent knowledge."
    default:
      return action.description
    }
  }

  private static func expectedResult(for actions: [AgentAction]) -> String {
    actions.count == 1 ? expectedResult(for: actions[0]) : "Run \(actions.count) queued actions in order."
  }

  private static func timeoutSeconds(for action: AgentAction) -> Int {
    switch action.kind {
    case .callConnector, .controlDevice:
      return 120
    case .importWebKnowledge:
      return 45
    case .openURL, .openApp, .setAlarm, .replyNotification, .callNativeTool:
      return 30
    case .createNotification:
      return 10
    default:
      return 20
    }
  }

  private static func routeRationale(
    for action: AgentAction,
    request: AgentPlanRequest
  ) -> String {
    switch action.kind {
    case .callConnector:
      let connectorId = action.parameters["connector_id"] ?? ""
      let target = request.targets.first { $0.id == connectorId || $0.title == action.target }
      switch target?.kind {
      case .some(.model):
        return "Model route selected for reasoning or generation outside the phone UI."
      case .some(.agent):
        return "Desktop Agent route selected for specialist work beyond local iOS actions."
      case .some(.device):
        return "Device connector route selected for trusted external device control."
      case .some(.knowledge):
        return "Knowledge route selected for memory or document retrieval."
      case nil:
        return "Connector route selected from the requested target, but the contact is not available yet."
      }
    case .controlDevice:
      return "Device route selected because the goal targets Home Assistant or smart devices."
    case .callNativeTool:
      return "Phone-native tool route selected from the locally validated capability catalog."
    case .importWebKnowledge:
      return "Knowledge route selected to extract and index a user-approved web page."
    case .readScreen, .saveScreenKnowledge, .copyScreenText:
      return "Local perception route selected because the task depends on the current phone screen."
    case .tap, .typeText, .deleteText, .pasteText, .swipe, .longPress, .back, .home, .recents:
      return "Mobile executor route selected because the task changes the current iOS UI."
    case .openApp, .openURL, .setAlarm:
      return "iOS handoff route selected because the task maps to an app or system surface."
    case .createNotification:
      return "Local notification route selected because the task should alert the user on this phone."
    case .replyNotification:
      return "Notification reply route selected because a SignalASI notification action is targeted."
    case .lockScreen:
      return "Mobile executor route selected for an owner-confirmed screen lock."
    case .draftPlan:
      return "Local planning route selected because the task needs clarification or a safe plan first."
    }
  }

  private static func distinctPermissions(_ permissions: [AgentPermissionRequirement]) -> [AgentPermissionRequirement] {
    var seen: Set<String> = []
    return permissions.filter { permission in
      seen.insert("\(permission.id):\(permission.title)").inserted
    }
  }

  private static func resolvedContextDigest(_ request: AgentPlanRequest) -> String {
    let clean = request.contextDigest.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? stableSuffix("\(request.goal)\u{001f}\(request.targets.map(\.id).joined(separator: ","))") : clean
  }

  private static func stableSuffix(_ value: String) -> String {
    String(agentNameBasedUUID(value).prefix(8))
  }

  private static func firstNonBlank(_ values: String...) -> String {
    values
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? ""
  }
}

enum AgentRouteResolver {
  static func resolve(action: AgentAction, targets: [AgentCallableTarget]) -> AgentRoute {
    let connectorId = action.parameters["connector_id"] ?? ""
    let target = targets.first { candidate in
      candidate.id == connectorId || candidate.title == action.target
    }
    let kind: AgentRouteKind
    switch action.kind {
    case .callConnector:
      if connectorId == AgentPlanFactory.unavailableReasoningConnectorId {
        kind = .localSystem
      } else {
        switch target?.kind {
        case .some(.model):
          kind = target?.id == "local-llm" ? .localModel : .cloudModel
        case .some(.agent):
          kind = .desktopAgent
        case .some(.device):
          kind = .deviceConnector
        case .some(.knowledge):
          kind = .knowledge
        case nil:
          kind = .unknown
        }
      }
    case .controlDevice:
      kind = .deviceConnector
    case .callNativeTool, .readScreen, .saveScreenKnowledge, .draftPlan, .tap, .typeText,
         .deleteText, .pasteText, .swipe, .longPress, .back, .home, .recents, .lockScreen,
         .openApp, .openURL, .setAlarm, .createNotification, .replyNotification, .copyScreenText:
      kind = .localSystem
    case .importWebKnowledge:
      kind = .knowledge
    }
    return AgentRoute(
      routeId: connectorId.isEmpty ? action.id : connectorId,
      kind: kind,
      targetId: target?.id ?? (connectorId.isEmpty ? action.target : connectorId),
      targetTitle: target?.title ?? action.target,
      status: target?.status.rawValue ?? AgentConnectorStatus.available.rawValue,
      deliveryMode: deliveryMode(for: kind),
      capabilities: target?.capabilities.map(\.rawValue).sorted() ?? []
    )
  }

  private static func deliveryMode(for kind: AgentRouteKind) -> String {
    switch kind {
    case .localSystem:
      return "local_system"
    case .cloudModel:
      return "mobile_cloud_api"
    case .localModel:
      return "local_model"
    case .desktopAgent:
      return "pc_connector"
    case .deviceConnector:
      return "device_connector"
    case .knowledge:
      return "knowledge"
    case .unknown:
      return "unknown"
    }
  }
}

enum AgentPlanLifecyclePolicy {
  static func normalize(_ plan: AgentPlan) -> AgentPlanLifecycleNormalization {
    let legacyRuntimeDrafts = !plan.actions.isEmpty &&
      plan.actions.allSatisfy {
        $0.kind == .draftPlan &&
          $0.target.caseInsensitiveCompare(localAgentRuntimeTarget) == .orderedSame
      } ? plan.actions : []

    if !legacyRuntimeDrafts.isEmpty {
      let recovered = recoverCompletedHistory(plan: plan, drafts: legacyRuntimeDrafts)
      if recovered.changed {
        return recovered
      }
      return retireLegacyRuntimeFallback(plan: plan, drafts: legacyRuntimeDrafts)
    }

    let trailingDrafts = trailingRetirableDrafts(plan.actions)
    if trailingDrafts.isEmpty {
      return AgentPlanLifecycleNormalization(plan: plan, removedActions: [])
    }
    if trailingDrafts.count == plan.actions.count {
      return recoverCompletedHistory(plan: plan, drafts: trailingDrafts)
    }
    let retainedActions = Array(plan.actions.dropLast(trailingDrafts.count))
    if !retainedActions.contains(where: { $0.kind != .draftPlan }) {
      return AgentPlanLifecycleNormalization(plan: plan, removedActions: [])
    }
    let removedIds = Set(trailingDrafts.map(\.id))
    var normalized = plan
    normalized.actions = retainedActions
    normalized.verificationResults = plan.verificationResults.filter { !removedIds.contains($0.actionId) }
    normalized.checkpoints = plan.checkpoints.filter { !removedIds.contains($0.actionId) }
    normalized.validation = AgentPlanValidator.validate(normalized)
    return AgentPlanLifecycleNormalization(plan: normalized, removedActions: trailingDrafts)
  }

  static func normalize(_ session: AgentSessionSnapshot) -> AgentSessionLifecycleNormalization {
    guard let plan = session.currentPlan else {
      return AgentSessionLifecycleNormalization(session: session, removedActions: [])
    }
    let planNormalization = normalize(plan)
    guard planNormalization.changed else {
      return AgentSessionLifecycleNormalization(session: session, removedActions: [])
    }
    var normalizedSession = session
    normalizedSession.phase = resolvedPhase(plan: planNormalization.plan, fallback: session.phase)
    normalizedSession.currentPlan = planNormalization.plan
    normalizedSession.lastActionResult = planNormalization.recoverResult(previous: session.lastActionResult)
    return AgentSessionLifecycleNormalization(
      session: normalizedSession,
      removedActions: planNormalization.removedActions
    )
  }

  static func recoverCompletedConnector(
    session: AgentSessionSnapshot,
    persistedTask: AgentTaskRecord?,
    missingResult: String
  ) -> AgentSessionSnapshot {
    guard let plan = session.currentPlan else {
      return session
    }
    let receivedConnectorResponse = session.auditTrail.contains {
      $0.event == .connectorResponseReceived
    }
    let staleRuntimeDrafts = !plan.actions.isEmpty &&
      plan.actions.allSatisfy {
        $0.kind == .draftPlan &&
          $0.target.caseInsensitiveCompare(localAgentRuntimeTarget) == .orderedSame
      }
    guard receivedConnectorResponse, staleRuntimeDrafts else {
      return session
    }

    let durableResult = durableConnectorResult(from: persistedTask)
    let previousResult = session.lastActionResult.flatMap { result -> String? in
      guard !isBlank(result.message),
        plan.actions.allSatisfy({ $0.id != result.actionId }) else {
        return nil
      }
      return result.message
    } ?? ""
    let resultText = firstNonBlank(durableResult, previousResult, missingResult.trimmingCharacters(in: .whitespacesAndNewlines))
    guard !isBlank(resultText) else {
      return session
    }

    let recoveredAction: AgentAction
    if var historicalConnector = plan.actionHistory.reversed().first(where: { $0.kind == .callConnector }) {
      historicalConnector.status = .completed
      historicalConnector.result = resultText
      historicalConnector.evidence = restoredConnectorEvidence
      recoveredAction = historicalConnector
    } else {
      recoveredAction = AgentAction(
        id: "restored-connector-result",
        kind: .callConnector,
        target: firstNonBlank(persistedTask?.targetTitle ?? "", plan.route.targetTitle, "remote-agent"),
        risk: persistedTask?.risk ?? .low,
        status: .completed,
        description: "Restore completed remote Agent result",
        requiresConfirmation: false,
        result: resultText,
        evidence: restoredConnectorEvidence
      )
    }

    var normalizedPlan = plan
    normalizedPlan.actions = [recoveredAction]
    normalizedPlan.selectedAgentOrModel = recoveredAction.target
    normalizedPlan.expectedResult = resultText
    normalizedPlan.actionHistory = plan.actionHistory.filter { $0.id != recoveredAction.id }
    normalizedPlan.confirmationRequired = false
    normalizedPlan.validation = AgentPlanValidator.validate(normalizedPlan)

    var normalizedSession = session
    normalizedSession.phase = .completed
    normalizedSession.currentPlan = normalizedPlan
    normalizedSession.lastActionResult = AgentActionResult(
      actionId: recoveredAction.id,
      success: true,
      message: resultText
    )
    return normalizedSession
  }

  private static func recoverCompletedHistory(
    plan: AgentPlan,
    drafts: [AgentAction]
  ) -> AgentPlanLifecycleNormalization {
    guard let recoveredIndex = plan.actionHistory.lastIndex(where: {
      $0.kind != .draftPlan &&
        $0.status == .completed &&
        !isBlank($0.result)
    }) else {
      return AgentPlanLifecycleNormalization(plan: plan, removedActions: [])
    }
    let recoveredAction = plan.actionHistory[recoveredIndex]
    var retainedHistory = plan.actionHistory
    retainedHistory.remove(at: recoveredIndex)
    let removedIds = Set(drafts.map(\.id))
    var normalized = plan
    normalized.actions = [recoveredAction]
    normalized.actionHistory = retainedHistory
    normalized.selectedAgentOrModel = recoveredAction.target
    normalized.expectedResult = recoveredAction.result
    normalized.verificationResults = plan.verificationResults.filter { !removedIds.contains($0.actionId) }
    normalized.checkpoints = plan.checkpoints.filter { !removedIds.contains($0.actionId) }
    normalized.validation = AgentPlanValidator.validate(normalized)
    return AgentPlanLifecycleNormalization(plan: normalized, removedActions: drafts)
  }

  private static func retireLegacyRuntimeFallback(
    plan: AgentPlan,
    drafts: [AgentAction]
  ) -> AgentPlanLifecycleNormalization {
    guard var retired = drafts.last else {
      return AgentPlanLifecycleNormalization(plan: plan, removedActions: [])
    }
    retired.target = taskCompleteTarget
    retired.status = .failed
    retired.description = "Task routing failed"
    retired.requiresConfirmation = false
    retired.result = "No Agent or model accepted this task. Send it again to retry with current resources."
    retired.evidence = "retired_legacy_runtime_fallback"
    var normalized = plan
    normalized.actions = [retired]
    normalized.selectedAgentOrModel = ""
    normalized.expectedResult = retired.result
    normalized.confirmationRequired = false
    normalized.route = AgentRoute()
    normalized.routeRationale = "Legacy internal planner fallback retired."
    let removedIds = Set(drafts.map(\.id))
    normalized.verificationResults = plan.verificationResults.filter { !removedIds.contains($0.actionId) }
    normalized.checkpoints = plan.checkpoints.filter { !removedIds.contains($0.actionId) }
    normalized.validation = AgentPlanValidator.validate(normalized)
    return AgentPlanLifecycleNormalization(plan: normalized, removedActions: drafts)
  }

  private static func resolvedPhase(plan: AgentPlan, fallback: AgentPhase) -> AgentPhase {
    if plan.actions.contains(where: { $0.status == .waitingResponse }) {
      return .waitingResponse
    }
    if plan.actions.contains(where: { $0.status == .running }) {
      return .paused
    }
    if plan.actions.contains(where: { $0.status == .pendingConfirmation || $0.status == .proposed }) {
      return .waitingConfirmation
    }
    if plan.actions.contains(where: { $0.status == .failed }) {
      return .failed
    }
    if plan.actions.contains(where: { $0.status == .blocked }) {
      return .blocked
    }
    if !plan.actions.isEmpty && plan.actions.allSatisfy({ terminalStatuses.contains($0.status) }) {
      return .completed
    }
    return fallback
  }

  private static func trailingRetirableDrafts(_ actions: [AgentAction]) -> [AgentAction] {
    var drafts: [AgentAction] = []
    for action in actions.reversed() {
      guard action.kind == .draftPlan,
        action.target.caseInsensitiveCompare(taskCompleteTarget) != .orderedSame else {
        break
      }
      drafts.append(action)
    }
    return Array(drafts.reversed())
  }

  private static func durableConnectorResult(from task: AgentTaskRecord?) -> String {
    guard let task,
      !isBlank(task.result),
      task.targetTitle.caseInsensitiveCompare(localAgentRuntimeTarget) != .orderedSame,
      connectorRouteKinds.contains(task.routeKind) else {
      return ""
    }
    return task.result
  }

  private static func firstNonBlank(_ values: String...) -> String {
    values.first { !isBlank($0) } ?? ""
  }

  private static func isBlank(_ value: String) -> Bool {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static let terminalStatuses: Set<AgentActionStatus> = [
    .completed,
    .failed,
    .blocked,
    .rolledBack
  ]
  private static let connectorRouteKinds: Set<AgentRouteKind> = [
    .desktopAgent,
    .cloudModel,
    .localModel
  ]
  private static let taskCompleteTarget = "task-complete"
  private static let localAgentRuntimeTarget = "local-agent-runtime"
  private static let restoredConnectorEvidence = "restored_connector_terminal_result"
}

enum AgentTaskLivenessState: String, Codable, CaseIterable, Identifiable {
  case healthy = "HEALTHY"
  case stalled = "STALLED"
  case timedOut = "TIMED_OUT"

  var id: String { rawValue }
}

struct AgentTaskLivenessDecision: Codable, Equatable {
  var state: AgentTaskLivenessState
  var reason: String
  var idleMillis: Int64
  var lifetimeMillis: Int64

  init(
    state: AgentTaskLivenessState,
    reason: String = "",
    idleMillis: Int64 = 0,
    lifetimeMillis: Int64 = 0
  ) {
    self.state = state
    self.reason = reason
    self.idleMillis = idleMillis
    self.lifetimeMillis = lifetimeMillis
  }

  enum CodingKeys: String, CodingKey {
    case state
    case reason
    case idleMillis = "idle_millis"
    case lifetimeMillis = "lifetime_millis"
  }
}

enum AgentTaskLivenessSignalKind: String, Codable, CaseIterable, Identifiable {
  case stalled = "STALLED"
  case recovered = "RECOVERED"
  case timedOut = "TIMED_OUT"

  var id: String { rawValue }
}

struct AgentTaskLivenessSignal: Codable, Equatable {
  var kind: AgentTaskLivenessSignalKind
  var workspace: AgentWorkspace
  var reason: String
  var observedAtMillis: Int64

  enum CodingKeys: String, CodingKey {
    case kind
    case workspace
    case reason
    case observedAtMillis = "observed_at_millis"
  }
}

enum AgentTaskTerminalReplyPolicy {
  static func hasTerminalReply(entries: [AgentTranscriptEntry], turnId: String) -> Bool {
    let cleanTurnId = turnId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanTurnId.isEmpty else {
      return false
    }
    return entries.contains { entry in
      (entry.turnId == cleanTurnId || entry.taskId == cleanTurnId) &&
        entry.role == .assistant &&
        terminalDedupePrefixes.contains(where: { entry.dedupeKey.hasPrefix($0) })
    }
  }

  private static let terminalDedupePrefixes = [
    "assistant-final:",
    "result:",
    "direct-system:",
    "fast-local:",
    "skill-command:",
    "skill-result:"
  ]
}

struct AgentTaskLivenessPolicy: Codable, Equatable {
  var queuedWarningMillis: Int64
  var queuedTimeoutMillis: Int64
  var runningWarningMillis: Int64
  var runningTimeoutMillis: Int64
  var waitingResponseWarningMillis: Int64
  var waitingResponseTimeoutMillis: Int64
  var absoluteTimeoutMillis: Int64
  var watchdogIntervalMillis: Int64
  var heartbeatWriteThrottleMillis: Int64

  init(
    queuedWarningMillis: Int64 = 15_000,
    queuedTimeoutMillis: Int64 = 90_000,
    runningWarningMillis: Int64 = 45_000,
    runningTimeoutMillis: Int64 = 10 * 60_000,
    waitingResponseWarningMillis: Int64 = 30_000,
    waitingResponseTimeoutMillis: Int64 = 6 * 60_000,
    absoluteTimeoutMillis: Int64 = 0,
    watchdogIntervalMillis: Int64 = 5_000,
    heartbeatWriteThrottleMillis: Int64 = 2_000
  ) {
    precondition(queuedWarningMillis > 0 && queuedTimeoutMillis > queuedWarningMillis)
    precondition(runningWarningMillis > 0 && runningTimeoutMillis > runningWarningMillis)
    precondition(waitingResponseWarningMillis > 0 && waitingResponseTimeoutMillis > waitingResponseWarningMillis)
    precondition(absoluteTimeoutMillis >= 0)
    precondition(watchdogIntervalMillis > 0)
    precondition(heartbeatWriteThrottleMillis >= 0)
    self.queuedWarningMillis = queuedWarningMillis
    self.queuedTimeoutMillis = queuedTimeoutMillis
    self.runningWarningMillis = runningWarningMillis
    self.runningTimeoutMillis = runningTimeoutMillis
    self.waitingResponseWarningMillis = waitingResponseWarningMillis
    self.waitingResponseTimeoutMillis = waitingResponseTimeoutMillis
    self.absoluteTimeoutMillis = absoluteTimeoutMillis
    self.watchdogIntervalMillis = watchdogIntervalMillis
    self.heartbeatWriteThrottleMillis = heartbeatWriteThrottleMillis
  }

  enum CodingKeys: String, CodingKey {
    case queuedWarningMillis = "queued_warning_millis"
    case queuedTimeoutMillis = "queued_timeout_millis"
    case runningWarningMillis = "running_warning_millis"
    case runningTimeoutMillis = "running_timeout_millis"
    case waitingResponseWarningMillis = "waiting_response_warning_millis"
    case waitingResponseTimeoutMillis = "waiting_response_timeout_millis"
    case absoluteTimeoutMillis = "absolute_timeout_millis"
    case watchdogIntervalMillis = "watchdog_interval_millis"
    case heartbeatWriteThrottleMillis = "heartbeat_write_throttle_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      queuedWarningMillis: try container.decodeIfPresent(Int64.self, forKey: .queuedWarningMillis) ?? 15_000,
      queuedTimeoutMillis: try container.decodeIfPresent(Int64.self, forKey: .queuedTimeoutMillis) ?? 90_000,
      runningWarningMillis: try container.decodeIfPresent(Int64.self, forKey: .runningWarningMillis) ?? 45_000,
      runningTimeoutMillis: try container.decodeIfPresent(Int64.self, forKey: .runningTimeoutMillis) ?? 10 * 60_000,
      waitingResponseWarningMillis: try container.decodeIfPresent(Int64.self, forKey: .waitingResponseWarningMillis) ?? 30_000,
      waitingResponseTimeoutMillis: try container.decodeIfPresent(Int64.self, forKey: .waitingResponseTimeoutMillis) ?? 6 * 60_000,
      absoluteTimeoutMillis: try container.decodeIfPresent(Int64.self, forKey: .absoluteTimeoutMillis) ?? 0,
      watchdogIntervalMillis: try container.decodeIfPresent(Int64.self, forKey: .watchdogIntervalMillis) ?? 5_000,
      heartbeatWriteThrottleMillis: try container.decodeIfPresent(Int64.self, forKey: .heartbeatWriteThrottleMillis) ?? 2_000
    )
  }

  func evaluate(
    workspace: AgentWorkspace,
    nowMillis: Int64,
    volatileActivityAtMillis: Int64 = 0
  ) -> AgentTaskLivenessDecision {
    if workspace.status.isTerminal ||
      workspace.cancellationRequested ||
      Self.userControlledStatuses.contains(workspace.status) {
      return AgentTaskLivenessDecision(state: .healthy)
    }
    let now = max(nowMillis, 0)
    let lastActivity = max(
      meaningfulActivityAt(workspace),
      max(volatileActivityAtMillis, 0)
    )
    let startedAt = workspace.createdAtMillis > 0
      ? workspace.createdAtMillis
      : (lastActivity > 0 ? lastActivity : now)
    let idleMillis = max(now - min(lastActivity, now), 0)
    let lifetimeMillis = max(now - min(startedAt, now), 0)
    if absoluteTimeoutMillis > 0 && lifetimeMillis >= absoluteTimeoutMillis {
      return AgentTaskLivenessDecision(
        state: .timedOut,
        reason: "absolute_deadline_exceeded",
        idleMillis: idleMillis,
        lifetimeMillis: lifetimeMillis
      )
    }
    guard let thresholds = thresholds(for: workspace.status) else {
      return AgentTaskLivenessDecision(state: .healthy)
    }
    if idleMillis >= thresholds.timeout {
      return AgentTaskLivenessDecision(
        state: .timedOut,
        reason: "\(workspace.status.rawValue.lowercased())_progress_timeout",
        idleMillis: idleMillis,
        lifetimeMillis: lifetimeMillis
      )
    }
    if idleMillis >= thresholds.warning {
      return AgentTaskLivenessDecision(
        state: .stalled,
        reason: "\(workspace.status.rawValue.lowercased())_progress_stalled",
        idleMillis: idleMillis,
        lifetimeMillis: lifetimeMillis
      )
    }
    return AgentTaskLivenessDecision(
      state: .healthy,
      idleMillis: idleMillis,
      lifetimeMillis: lifetimeMillis
    )
  }

  func hasUnresolvedStall(workspace: AgentWorkspace) -> Bool {
    guard let stalledSequence = workspace.eventJournal
      .reversed()
      .first(where: { $0.kind == AgentTaskEventKinds.stalled })?.sequence else {
      return false
    }
    return !workspace.eventJournal.contains { event in
      event.sequence > stalledSequence && !Self.supervisorObservationEvents.contains(event.kind)
    }
  }

  func meaningfulActivityAt(_ workspace: AgentWorkspace) -> Int64 {
    let eventAt = workspace.eventJournal
      .filter { !Self.supervisorObservationEvents.contains($0.kind) }
      .map(\.timestampMillis)
      .max() ?? 0
    return max(
      workspace.createdAtMillis,
      eventAt,
      workspace.eventJournal.isEmpty ? workspace.updatedAtMillis : 0
    )
  }

  private func thresholds(for status: AgentWorkspaceStatus) -> (warning: Int64, timeout: Int64)? {
    switch status {
    case .created, .queued:
      return (queuedWarningMillis, queuedTimeoutMillis)
    case .running:
      return (runningWarningMillis, runningTimeoutMillis)
    case .waitingResponse:
      return (waitingResponseWarningMillis, waitingResponseTimeoutMillis)
    case .waitingConfirmation, .paused, .blocked, .completed, .failed, .cancelled:
      return nil
    }
  }

  private static let userControlledStatuses: Set<AgentWorkspaceStatus> = [
    .waitingConfirmation,
    .paused,
    .blocked
  ]
  private static let supervisorObservationEvents: Set<String> = [
    AgentTaskEventKinds.stalled,
    AgentTaskEventKinds.timedOut
  ]
}
