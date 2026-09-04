import CryptoKit
import Foundation

struct AgentTaskPlanContext: Codable, Equatable {
  var planId: String
  var plannerProfile: String
  var selectedAgentOrModel: String
  var routeKind: AgentRouteKind
  var routeTargetTitle: String
  var routeStatus: String
  var routeRationale: String
  var expectedResult: String
  var rollbackStrategy: String
  var revision: Int
  var replanCount: Int
  var actionCount: Int
  var actionHistoryCount: Int
  var activeCheckpointCount: Int
  var toolGraphDepth: Int
  var requiredPermissionCount: Int
  var requiredPermissions: [AgentPermissionRequirement]
  var timeoutSeconds: Int
  var confirmationRequired: Bool

  enum CodingKeys: String, CodingKey {
    case planId = "plan_id"
    case plannerProfile = "planner_profile"
    case selectedAgentOrModel = "selected_agent_or_model"
    case routeKind = "route_kind"
    case routeTargetTitle = "route_target_title"
    case routeStatus = "route_status"
    case routeRationale = "route_rationale"
    case expectedResult = "expected_result"
    case rollbackStrategy = "rollback_strategy"
    case revision
    case replanCount = "replan_count"
    case actionCount = "action_count"
    case actionHistoryCount = "action_history_count"
    case activeCheckpointCount = "active_checkpoint_count"
    case toolGraphDepth = "tool_graph_depth"
    case requiredPermissionCount = "required_permission_count"
    case requiredPermissions = "required_permissions"
    case timeoutSeconds = "timeout_seconds"
    case confirmationRequired = "confirmation_required"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    planId = try container.decode(String.self, forKey: .planId)
    plannerProfile = try container.decode(String.self, forKey: .plannerProfile)
    selectedAgentOrModel = try container.decode(String.self, forKey: .selectedAgentOrModel)
    routeKind = try container.decode(AgentRouteKind.self, forKey: .routeKind)
    routeTargetTitle = try container.decode(String.self, forKey: .routeTargetTitle)
    routeStatus = try container.decode(String.self, forKey: .routeStatus)
    routeRationale = try container.decode(String.self, forKey: .routeRationale)
    expectedResult = try container.decode(String.self, forKey: .expectedResult)
    rollbackStrategy = try container.decode(String.self, forKey: .rollbackStrategy)
    revision = try container.decode(Int.self, forKey: .revision)
    replanCount = try container.decode(Int.self, forKey: .replanCount)
    actionCount = try container.decode(Int.self, forKey: .actionCount)
    actionHistoryCount = try container.decode(Int.self, forKey: .actionHistoryCount)
    activeCheckpointCount = try container.decode(Int.self, forKey: .activeCheckpointCount)
    toolGraphDepth = try container.decode(Int.self, forKey: .toolGraphDepth)
    requiredPermissionCount = try container.decode(Int.self, forKey: .requiredPermissionCount)
    requiredPermissions = try container.decodeIfPresent([AgentPermissionRequirement].self, forKey: .requiredPermissions) ?? []
    timeoutSeconds = try container.decode(Int.self, forKey: .timeoutSeconds)
    confirmationRequired = try container.decode(Bool.self, forKey: .confirmationRequired)
  }

  init(plan: AgentPlan) {
    planId = plan.planId
    plannerProfile = plan.plannerProfile
    selectedAgentOrModel = plan.selectedAgentOrModel
    routeKind = plan.route.kind
    routeTargetTitle = plan.route.targetTitle.ifBlank(plan.selectedAgentOrModel)
    routeStatus = plan.route.status
    routeRationale = plan.routeRationale
    expectedResult = plan.expectedResult
    rollbackStrategy = plan.rollbackStrategy
    revision = plan.revision
    replanCount = plan.replanCount
    actionCount = plan.actions.count
    actionHistoryCount = plan.actionHistory.count
    activeCheckpointCount = plan.checkpoints.filter { $0.status == .active }.count
    toolGraphDepth = AgentToolCoordination.toolGraphDepth(plan)
    requiredPermissionCount = plan.requiredPermissions.count
    requiredPermissions = plan.requiredPermissions
    timeoutSeconds = plan.timeoutSeconds
    confirmationRequired = plan.confirmationRequired
  }
}

struct AgentTaskRecord: Codable, Equatable, Identifiable {
  var taskId: String
  var sessionId: String
  var goal: String
  var phase: AgentPhase
  var routeKind: AgentRouteKind
  var targetTitle: String
  var risk: AgentRisk
  var blocked: Bool
  var executionLocationKind: AgentExecutionLocationKind
  var executionRuntimeKind: AgentExecutionRuntimeKind
  var executionLocationId: String
  var executionLocationName: String
  var executionRuntimeId: String
  var executionLocationTrusted: Bool
  var pendingAction: AgentAction?
  var pendingActions: [AgentAction]
  var lastCompletedNativeAction: AgentAction?
  var nativeRollbackAction: AgentAction?
  var planContext: AgentTaskPlanContext?
  var activePlan: AgentPlan?
  var lastNativeActionResult: AgentActionResult?
  var nativeActionResults: [String]
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
    executionLocationKind: AgentExecutionLocationKind = .unknown,
    executionRuntimeKind: AgentExecutionRuntimeKind = .unknown,
    executionLocationId: String = "",
    executionLocationName: String = "",
    executionRuntimeId: String = "",
    executionLocationTrusted: Bool = true,
    pendingAction: AgentAction? = nil,
    pendingActions: [AgentAction] = [],
    lastCompletedNativeAction: AgentAction? = nil,
    nativeRollbackAction: AgentAction? = nil,
    planContext: AgentTaskPlanContext? = nil,
    activePlan: AgentPlan? = nil,
    lastNativeActionResult: AgentActionResult? = nil,
    nativeActionResults: [String] = [],
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
    self.executionLocationKind = executionLocationKind
    self.executionRuntimeKind = executionRuntimeKind
    self.executionLocationId = executionLocationId
    self.executionLocationName = executionLocationName
    self.executionRuntimeId = executionRuntimeId
    self.executionLocationTrusted = executionLocationTrusted
    self.pendingAction = pendingAction
    self.pendingActions = pendingActions
    self.lastCompletedNativeAction = lastCompletedNativeAction
    self.nativeRollbackAction = nativeRollbackAction
    self.planContext = planContext
    self.activePlan = activePlan
    self.lastNativeActionResult = lastNativeActionResult
    self.nativeActionResults = nativeActionResults
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
    case executionLocationKind = "execution_location_kind"
    case executionRuntimeKind = "execution_runtime_kind"
    case executionLocationId = "execution_location_id"
    case executionLocationName = "execution_location_name"
    case executionRuntimeId = "execution_runtime_id"
    case executionLocationTrusted = "execution_location_trusted"
    case pendingAction = "pending_action"
    case pendingActions = "pending_actions"
    case lastCompletedNativeAction = "last_completed_native_action"
    case nativeRollbackAction = "native_rollback_action"
    case planContext = "plan_context"
    case activePlan = "active_plan"
    case lastNativeActionResult = "last_native_action_result"
    case nativeActionResults = "native_action_results"
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
      executionLocationKind: try container.decodeIfPresent(AgentExecutionLocationKind.self, forKey: .executionLocationKind) ?? .unknown,
      executionRuntimeKind: try container.decodeIfPresent(AgentExecutionRuntimeKind.self, forKey: .executionRuntimeKind) ?? .unknown,
      executionLocationId: try container.decodeIfPresent(String.self, forKey: .executionLocationId) ?? "",
      executionLocationName: try container.decodeIfPresent(String.self, forKey: .executionLocationName) ?? "",
      executionRuntimeId: try container.decodeIfPresent(String.self, forKey: .executionRuntimeId) ?? "",
      executionLocationTrusted: try container.decodeIfPresent(Bool.self, forKey: .executionLocationTrusted) ?? true,
      pendingAction: try container.decodeIfPresent(AgentAction.self, forKey: .pendingAction),
      pendingActions: try container.decodeIfPresent([AgentAction].self, forKey: .pendingActions) ?? [],
      lastCompletedNativeAction: try container.decodeIfPresent(AgentAction.self, forKey: .lastCompletedNativeAction),
      nativeRollbackAction: try container.decodeIfPresent(AgentAction.self, forKey: .nativeRollbackAction),
      planContext: try container.decodeIfPresent(AgentTaskPlanContext.self, forKey: .planContext),
      activePlan: try container.decodeIfPresent(AgentPlan.self, forKey: .activePlan),
      lastNativeActionResult: try container.decodeIfPresent(AgentActionResult.self, forKey: .lastNativeActionResult),
      nativeActionResults: try container.decodeIfPresent([String].self, forKey: .nativeActionResults) ?? [],
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
  var executionLocationKind: AgentExecutionLocationKind
  var executionRuntimeKind: AgentExecutionRuntimeKind
  var executionDeviceId: String
  var executionDeviceName: String

  init(
    routeId: String = "",
    kind: AgentRouteKind = .unknown,
    targetId: String = "",
    targetTitle: String = "",
    status: String = "",
    deliveryMode: String = "",
    capabilities: [String] = [],
    executionLocationKind: AgentExecutionLocationKind = .unknown,
    executionRuntimeKind: AgentExecutionRuntimeKind = .unknown,
    executionDeviceId: String = "",
    executionDeviceName: String = ""
  ) {
    self.routeId = routeId
    self.kind = kind
    self.targetId = targetId
    self.targetTitle = targetTitle
    self.status = status
    self.deliveryMode = deliveryMode
    self.capabilities = capabilities
    self.executionLocationKind = executionLocationKind
    self.executionRuntimeKind = executionRuntimeKind
    self.executionDeviceId = executionDeviceId
    self.executionDeviceName = executionDeviceName
  }

  enum CodingKeys: String, CodingKey {
    case routeId = "route_id"
    case kind
    case targetId = "target_id"
    case targetTitle = "target_title"
    case status
    case deliveryMode = "delivery_mode"
    case capabilities
    case executionLocationKind = "execution_location_kind"
    case executionRuntimeKind = "execution_runtime_kind"
    case executionDeviceId = "execution_device_id"
    case executionDeviceName = "execution_device_name"
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
      capabilities: try container.decodeIfPresent([String].self, forKey: .capabilities) ?? [],
      executionLocationKind: try container.decodeIfPresent(AgentExecutionLocationKind.self, forKey: .executionLocationKind) ?? .unknown,
      executionRuntimeKind: try container.decodeIfPresent(AgentExecutionRuntimeKind.self, forKey: .executionRuntimeKind) ?? .unknown,
      executionDeviceId: try container.decodeIfPresent(String.self, forKey: .executionDeviceId) ?? "",
      executionDeviceName: try container.decodeIfPresent(String.self, forKey: .executionDeviceName) ?? ""
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
  var responseLanguage: String
  var executionMode: AgentTaskExecutionMode
  var requestedMembers: [AgentRequestedMember]

  init(
    goal: String,
    screen: AgentScreenContext,
    targets: [AgentCallableTarget] = [],
    nativeTools: [AgentNativeToolDescriptor] = [],
    contextDigest: String = "",
    responseLanguage: String = LanguagePolicySettings.auto,
    executionMode: AgentTaskExecutionMode = .autoComplete,
    requestedMembers: [AgentRequestedMember] = []
  ) {
    self.goal = goal
    self.screen = screen
    self.targets = targets
    self.nativeTools = nativeTools
    self.contextDigest = contextDigest
    self.responseLanguage = LanguagePolicySettings.normalizeVoice(responseLanguage)
    self.executionMode = executionMode
    self.requestedMembers = Array(requestedMembers.prefix(12))
  }

  enum CodingKeys: String, CodingKey {
    case goal
    case screen
    case targets
    case nativeTools = "native_tools"
    case contextDigest = "context_digest"
    case responseLanguage = "response_language"
    case executionMode = "execution_mode"
    case requestedMembers = "requested_members"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      goal: try container.decode(String.self, forKey: .goal),
      screen: try container.decode(AgentScreenContext.self, forKey: .screen),
      targets: try container.decodeIfPresent([AgentCallableTarget].self, forKey: .targets) ?? [],
      nativeTools: try container.decodeIfPresent([AgentNativeToolDescriptor].self, forKey: .nativeTools) ?? [],
      contextDigest: try container.decodeIfPresent(String.self, forKey: .contextDigest) ?? "",
      responseLanguage: try container.decodeIfPresent(String.self, forKey: .responseLanguage) ?? LanguagePolicySettings.auto,
      executionMode: try container.decodeIfPresent(AgentTaskExecutionMode.self, forKey: .executionMode) ?? .autoComplete,
      requestedMembers: try container.decodeIfPresent([AgentRequestedMember].self, forKey: .requestedMembers) ?? []
    )
  }
}

enum AgentPlanFactory {
  static let unavailableReasoningConnectorId = "reasoning-provider-unavailable"

  static func singleAction(request: AgentPlanRequest, action: AgentAction) -> AgentPlan {
    actions(request: request, [action])
  }

  static func actions(request: AgentPlanRequest, _ actions: [AgentAction]) -> AgentPlan {
    let aliasedActions = AgentConnectorAliasResolver.resolve(
      actions: actions,
      targets: request.targets
    )
    let plannedActions = AgentHomeAssistantNativeToolPlanBridge.rewrite(
      actions: collapseDuplicateConnectorCalls(aliasedActions),
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
      executionMode: request.executionMode,
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
    if let target = AgentConnectorRouteSelector.select(
      targets: request.targets,
      decision: nil,
      goal: request.goal
    )?.target {
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
          "_galaxyssi_desktop_executor_full":
            String(target.desktopAccessProfile == GalaxySSILinkProtocol.accessDesktopExecutor)
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
    return retained.map { remappingToolGraphIds($0, idMap: idMap) }
  }

  private static func selectedAgentOrModel(_ actions: [AgentAction]) -> String {
    let connectorTargets = actions
      .filter { $0.kind == .callConnector || $0.kind == .controlDevice }
      .map { selectedAgentOrModel($0) }
    let distinctConnectorTargets = stableDistinctStrings(connectorTargets)
    if distinctConnectorTargets.count == 1 {
      return distinctConnectorTargets[0]
    }
    let targets = stableDistinctStrings(actions.map { selectedAgentOrModel($0) })
    return targets.count == 1 ? targets[0] : "Multiple Executors"
  }

  private static func remappingToolGraphIds(_ action: AgentAction, idMap: [String: String]) -> AgentAction {
    var copy = action
    copy.parameters["depends_on"] = stableDistinctStrings(listParameter("depends_on", action: action).map { idMap[$0] ?? $0 })
      .joined(separator: ",")
    copy.parameters["use_outputs_from"] = stableDistinctStrings(listParameter("use_outputs_from", action: action).map { idMap[$0] ?? $0 })
      .joined(separator: ",")
    return copy
  }

  private static func listParameter(_ key: String, action: AgentAction) -> [String] {
    (action.parameters[key] ?? "")
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func stableDistinctStrings(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
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
        title: "Verified GalaxySSI contact",
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
      return "The selected GalaxySSI notification action receives the confirmed reply."
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
      return "Notification reply route selected because a GalaxySSI notification action is targeted."
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
    String(Self.agentNameBasedUUID(value).prefix(8))
  }

  private static func agentNameBasedUUID(_ name: String) -> String {
    var bytes = Array(Insecure.MD5.hash(data: Data(name.utf8)))
    bytes[6] = (bytes[6] & 0x0f) | 0x30
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    let uuid = UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5],
      bytes[6], bytes[7],
      bytes[8], bytes[9],
      bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    ))
    return uuid.uuidString.lowercased()
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
