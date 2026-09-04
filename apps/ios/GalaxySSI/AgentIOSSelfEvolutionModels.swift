import Foundation

enum AgentIOSSelfEvolutionTaskStatus: String, Codable, CaseIterable, Identifiable {
  case proposed
  case preparing
  case running
  case validating
  case waitingApproval = "waiting_approval"
  case publishing
  case published
  case completed
  case failed
  case blocked
  case cancelled
  case rolledBack = "rolled_back"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentIOSSelfEvolutionTaskStatus {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "-", with: "_")
    return allCases.first { $0.rawValue == normalized } ?? .proposed
  }
}

enum AgentIOSSelfEvolutionRisk: String, Codable, CaseIterable, Identifiable {
  case low
  case medium
  case high
  case critical

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentIOSSelfEvolutionRisk {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    return allCases.first { $0.rawValue == normalized } ?? .medium
  }
}

enum AgentIOSSelfEvolutionGateStatus: String, Codable, CaseIterable, Identifiable {
  case pending
  case running
  case passed
  case failed
  case skipped
  case cancelled

  var id: String { rawValue }
}

struct AgentIOSSelfEvolutionGate: Codable, Equatable, Identifiable {
  var id: String
  var status: AgentIOSSelfEvolutionGateStatus
  var durationMillis: Int64
  var exitCode: Int
  var summary: String

  enum CodingKeys: String, CodingKey {
    case id
    case status
    case durationMillis = "duration_millis"
    case exitCode = "exit_code"
    case summary
  }

  func publicValue() -> AgentMcpJSONObject {
    [
      "id": .string(id),
      "status": .string(status.rawValue),
      "duration_millis": .int(durationMillis),
      "exit_code": .int(Int64(exitCode)),
      "summary": .string(summary)
    ]
  }
}

struct AgentIOSSelfEvolutionAttempt: Codable, Equatable, Identifiable {
  var number: Int
  var status: AgentIOSSelfEvolutionTaskStatus
  var workspaceId: String
  var branch: String
  var changedFiles: [String]
  var gates: [AgentIOSSelfEvolutionGate]
  var failureCode: String
  var failureSummary: String
  var startedAtMillis: Int64
  var completedAtMillis: Int64

  var id: Int { number }

  enum CodingKeys: String, CodingKey {
    case number
    case status
    case workspaceId = "workspace_id"
    case branch
    case changedFiles = "changed_files"
    case gates
    case failureCode = "failure_code"
    case failureSummary = "failure_summary"
    case startedAtMillis = "started_at_millis"
    case completedAtMillis = "completed_at_millis"
  }

  func publicValue() -> AgentMcpJSONObject {
    [
      "number": .int(Int64(number)),
      "status": .string(status.rawValue),
      "changed_files": .array(changedFiles.map(AgentMcpJSONValue.string)),
      "gates": .array(gates.map { .object($0.publicValue()) }),
      "failure_code": .string(failureCode),
      "failure_summary": .string(failureSummary),
      "started_at_millis": .int(startedAtMillis),
      "completed_at_millis": .int(completedAtMillis)
    ]
  }
}

struct AgentIOSSelfEvolutionTask: Codable, Equatable, Identifiable {
  var taskId: String
  var problem: String
  var reproductionSteps: [String]
  var scope: [String]
  var acceptance: [String]
  var risk: AgentIOSSelfEvolutionRisk
  var maxAttempts: Int
  var status: AgentIOSSelfEvolutionTaskStatus
  var protocolId: String
  var executionTarget: String
  var baseCommit: String
  var candidateCommit: String
  var candidateBranch: String
  var approvalHash: String
  var attempts: [AgentIOSSelfEvolutionAttempt]
  var lastErrorCode: String
  var lastError: String
  var createdAtMillis: Int64
  var updatedAtMillis: Int64

  var id: String { taskId }

  init(
    taskId: String,
    problem: String,
    reproductionSteps: [String],
    scope: [String],
    acceptance: [String],
    risk: AgentIOSSelfEvolutionRisk,
    maxAttempts: Int,
    status: AgentIOSSelfEvolutionTaskStatus = .proposed,
    protocolId: String = AgentIOSSelfEvolutionNativeToolCatalog.protocolId,
    executionTarget: String = "ios",
    baseCommit: String = "",
    candidateCommit: String = "",
    candidateBranch: String = "",
    approvalHash: String = "",
    attempts: [AgentIOSSelfEvolutionAttempt] = [],
    lastErrorCode: String = "",
    lastError: String = "",
    createdAtMillis: Int64,
    updatedAtMillis: Int64
  ) {
    self.taskId = taskId
    self.problem = problem
    self.reproductionSteps = reproductionSteps
    self.scope = scope
    self.acceptance = acceptance
    self.risk = risk
    self.maxAttempts = max(1, min(maxAttempts, 5))
    self.status = status
    self.protocolId = protocolId
    self.executionTarget = executionTarget
    self.baseCommit = baseCommit
    self.candidateCommit = candidateCommit
    self.candidateBranch = candidateBranch
    self.approvalHash = approvalHash
    self.attempts = attempts
    self.lastErrorCode = lastErrorCode
    self.lastError = lastError
    self.createdAtMillis = max(0, createdAtMillis)
    self.updatedAtMillis = max(0, updatedAtMillis)
  }

  enum CodingKeys: String, CodingKey {
    case taskId = "task_id"
    case problem
    case reproductionSteps = "reproduction_steps"
    case scope
    case acceptance
    case risk = "risk_level"
    case maxAttempts = "max_attempts"
    case status
    case protocolId = "protocol"
    case executionTarget = "execution_target"
    case baseCommit = "base_commit"
    case candidateCommit = "candidate_commit"
    case candidateBranch = "candidate_branch"
    case approvalHash = "approval_hash"
    case attempts
    case lastErrorCode = "last_error_code"
    case lastError = "last_error"
    case createdAtMillis = "created_at_millis"
    case updatedAtMillis = "updated_at_millis"
  }

  func publicValue() -> AgentMcpJSONObject {
    [
      "protocol": .string(protocolId),
      "task_id": .string(taskId),
      "problem": .string(problem),
      "reproduction_steps": .array(reproductionSteps.map(AgentMcpJSONValue.string)),
      "scope": .array(scope.map(AgentMcpJSONValue.string)),
      "acceptance": .array(acceptance.map(AgentMcpJSONValue.string)),
      "risk_level": .string(risk.rawValue),
      "max_attempts": .int(Int64(maxAttempts)),
      "status": .string(status.rawValue),
      "execution_target": .string(executionTarget),
      "base_commit": .string(baseCommit),
      "candidate_commit": .string(candidateCommit),
      "candidate_branch": .string(candidateBranch),
      "approval_hash": .string(approvalHash),
      "attempts": .array(attempts.map { .object($0.publicValue()) }),
      "last_error_code": .string(lastErrorCode),
      "last_error": .string(lastError),
      "created_at_millis": .int(createdAtMillis),
      "updated_at_millis": .int(updatedAtMillis)
    ]
  }

  func candidateWorkspaceId() -> String {
    attempts.last?.workspaceId ?? ""
  }

  func candidateSourceRoot() -> String {
    candidateWorkspaceId().isEmpty ? "" : "source"
  }
}

struct AgentIOSSelfEvolutionHealth: Codable, Equatable {
  var totalTasks: Int
  var queuedTasks: Int
  var activeTasks: Int
  var waitingReview: Int
  var successfulTasks: Int
  var attentionTasks: Int
  var staleTasks: Int
  var totalAttempts: Int
  var failedAttempts: Int
  var retries: Int
  var totalGates: Int
  var passedGates: Int
  var failedGates: Int
  var gatePassPercent: Int
  var successPercent: Int
  var averageAttemptDurationMillis: Int64
  var oldestReviewAgeMillis: Int64
  var lastActivityAtMillis: Int64
  var statusCounts: [String: Int]
  var failureCounts: [String: Int]
  var staleTaskIds: [String]
  var generatedAtMillis: Int64
  var staleAfterMillis: Int64

  func publicValue() -> AgentMcpJSONObject {
    [
      "total_tasks": .int(Int64(totalTasks)),
      "queued_tasks": .int(Int64(queuedTasks)),
      "active_tasks": .int(Int64(activeTasks)),
      "waiting_review": .int(Int64(waitingReview)),
      "successful_tasks": .int(Int64(successfulTasks)),
      "attention_tasks": .int(Int64(attentionTasks)),
      "stale_tasks": .int(Int64(staleTasks)),
      "total_attempts": .int(Int64(totalAttempts)),
      "failed_attempts": .int(Int64(failedAttempts)),
      "retries": .int(Int64(retries)),
      "total_gates": .int(Int64(totalGates)),
      "passed_gates": .int(Int64(passedGates)),
      "failed_gates": .int(Int64(failedGates)),
      "gate_pass_percent": .int(Int64(gatePassPercent)),
      "success_percent": .int(Int64(successPercent)),
      "average_attempt_duration_millis": .int(averageAttemptDurationMillis),
      "oldest_review_age_millis": .int(oldestReviewAgeMillis),
      "last_activity_at_millis": .int(lastActivityAtMillis),
      "status_counts": .object(countsValue(statusCounts)),
      "failure_counts": .object(countsValue(failureCounts)),
      "stale_task_ids": .array(staleTaskIds.map(AgentMcpJSONValue.string)),
      "generated_at_millis": .int(generatedAtMillis),
      "stale_after_millis": .int(staleAfterMillis)
    ]
  }

  private func countsValue(_ counts: [String: Int]) -> AgentMcpJSONObject {
    Dictionary(uniqueKeysWithValues: counts.sorted { $0.key < $1.key }.map {
      ($0.key, AgentMcpJSONValue.int(Int64($0.value)))
    })
  }
}

enum AgentIOSSelfEvolutionHealthAnalyzer {
  static func summarize(
    tasks: [AgentIOSSelfEvolutionTask],
    nowMillis: Int64,
    staleAfterMillis: Int64 = 30 * 60_000
  ) -> AgentIOSSelfEvolutionHealth {
    let now = max(0, nowMillis)
    let staleAfter = max(60_000, staleAfterMillis)
    let attempts = tasks.flatMap(\.attempts)
    let gates = attempts.flatMap(\.gates)
    let statusCounts = Dictionary(grouping: tasks, by: { $0.status.rawValue })
      .mapValues { $0.count }
    let failureCounts = failureCounts(tasks: tasks, attempts: attempts)
    let staleIds = tasks
      .filter { activeStatuses.contains($0.status) }
      .filter { $0.updatedAtMillis > 0 && now - $0.updatedAtMillis >= staleAfter }
      .map(\.taskId)
      .sorted()
    let overdueReview = Set(tasks
      .filter { $0.status == .waitingApproval }
      .filter { $0.updatedAtMillis > 0 && now - $0.updatedAtMillis >= staleAfter }
      .map(\.taskId))
    var attentionIds = Set(tasks.filter { attentionStatuses.contains($0.status) }.map(\.taskId))
    attentionIds.formUnion(staleIds)
    attentionIds.formUnion(overdueReview)
    let durations = attempts.compactMap { attempt -> Int64? in
      guard attempt.startedAtMillis > 0, attempt.completedAtMillis >= attempt.startedAtMillis else {
        return nil
      }
      return attempt.completedAtMillis - attempt.startedAtMillis
    }
    let passedGates = gates.filter { $0.status == .passed }.count
    let failedGates = gates.filter { [.failed, .cancelled].contains($0.status) }.count
    let decidedGates = passedGates + failedGates
    let successful = tasks.filter { successfulStatuses.contains($0.status) }.count
    let unsuccessful = tasks.filter { attentionStatuses.contains($0.status) }.count
    let decidedTasks = successful + unsuccessful
    let reviewAges = tasks.compactMap { task -> Int64? in
      guard task.status == .waitingApproval, task.updatedAtMillis > 0 else { return nil }
      return now - task.updatedAtMillis
    }
    return AgentIOSSelfEvolutionHealth(
      totalTasks: tasks.count,
      queuedTasks: tasks.filter { $0.status == .proposed }.count,
      activeTasks: tasks.filter { activeStatuses.contains($0.status) }.count,
      waitingReview: tasks.filter { $0.status == .waitingApproval }.count,
      successfulTasks: successful,
      attentionTasks: attentionIds.count,
      staleTasks: staleIds.count,
      totalAttempts: attempts.count,
      failedAttempts: attempts.filter { $0.status == .failed }.count,
      retries: tasks.map { max(0, $0.attempts.count - 1) }.reduce(0, +),
      totalGates: gates.count,
      passedGates: passedGates,
      failedGates: failedGates,
      gatePassPercent: decidedGates == 0 ? 0 : (passedGates * 100 + decidedGates / 2) / decidedGates,
      successPercent: decidedTasks == 0 ? 0 : (successful * 100 + decidedTasks / 2) / decidedTasks,
      averageAttemptDurationMillis: durations.isEmpty ? 0 : durations.reduce(0, +) / Int64(durations.count),
      oldestReviewAgeMillis: reviewAges.max() ?? 0,
      lastActivityAtMillis: tasks.map(\.updatedAtMillis).max() ?? 0,
      statusCounts: statusCounts,
      failureCounts: failureCounts,
      staleTaskIds: staleIds,
      generatedAtMillis: now,
      staleAfterMillis: staleAfter
    )
  }

  private static func failureCounts(
    tasks: [AgentIOSSelfEvolutionTask],
    attempts: [AgentIOSSelfEvolutionAttempt]
  ) -> [String: Int] {
    var counts: [String: Int] = [:]
    for code in attempts.map(\.failureCode).filter({ !$0.isEmpty }) {
      counts[code, default: 0] += 1
    }
    for task in tasks where !task.lastErrorCode.isEmpty && task.lastErrorCode != (task.attempts.last?.failureCode ?? "") {
      counts[task.lastErrorCode, default: 0] += 1
    }
    return counts
  }

  private static let activeStatuses: Set<AgentIOSSelfEvolutionTaskStatus> = [
    .preparing,
    .running,
    .validating,
    .publishing
  ]
  private static let successfulStatuses: Set<AgentIOSSelfEvolutionTaskStatus> = [.published, .completed]
  private static let attentionStatuses: Set<AgentIOSSelfEvolutionTaskStatus> = [.failed, .blocked]
}

enum AgentIOSSelfEvolutionPolicy {
  static func taskId() -> String {
    "evolve-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20))"
  }

  static func normalizedScope(_ values: [String]) throws -> [String] {
    let normalized = values
      .map { $0.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: .whitespacesAndNewlines) }
      .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
      .filter { !$0.isEmpty }
      .uniqued()
    guard (1...64).contains(normalized.count) else {
      throw AgentIOSSelfEvolutionValidationError.invalid("Evolution tasks require 1 to 64 scoped paths")
    }
    for value in normalized {
      let parts = value.split(separator: "/").map(String.init)
      guard value.count <= 512, parts.allSatisfy(isSafePathComponent) else {
        throw AgentIOSSelfEvolutionValidationError.invalid("Evolution scope is unsafe: \(value)")
      }
      guard !parts.contains(where: { protectedComponents.contains($0.lowercased()) }) else {
        throw AgentIOSSelfEvolutionValidationError.invalid("Evolution scope is protected: \(value)")
      }
    }
    return normalized
  }

  static func boundedStrings(
    _ values: [AgentMcpJSONValue],
    maxItems: Int,
    maxLength: Int
  ) -> [String] {
    values
      .compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .map { String($0.prefix(maxLength)) }
      .uniqued()
      .prefix(maxItems)
      .map { $0 }
  }

  static func isValidTaskId(_ value: String) -> Bool {
    value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$"#, options: .regularExpression) != nil
  }

  private static func isSafePathComponent(_ value: String) -> Bool {
    guard !["", ".", ".."].contains(value) else { return false }
    return value.range(of: #"^[A-Za-z0-9._+@() -]+$"#, options: .regularExpression) != nil
  }

  private static let protectedComponents: Set<String> = [".git", "node_modules", "dist", "build", "runtime-data"]
}

struct AgentIOSSelfEvolutionValidationError: LocalizedError, Equatable {
  var message: String
  var errorDescription: String? { message }

  static func invalid(_ message: String) -> AgentIOSSelfEvolutionValidationError {
    AgentIOSSelfEvolutionValidationError(message: message)
  }
}

private extension Array where Element: Hashable {
  func uniqued() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}
