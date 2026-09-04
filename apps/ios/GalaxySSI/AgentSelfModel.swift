import CryptoKit
import Foundation
import SwiftUI

struct AgentSelfCapabilityBelief: Codable, Equatable, Identifiable {
  var key: String
  var taskFamily: String
  var resourceKey: String
  var requiredCapabilities: Set<AgentCapability>
  var successfulRuns: Int
  var failedRuns: Int
  var cancelledRuns: Int
  var correctionCount: Int
  var consecutiveFailures: Int
  var averageLatencyMillis: Int64
  var lastOutcome: AgentPhase
  var lastFailureCategory: String
  var firstObservedAtMillis: Int64
  var lastObservedAtMillis: Int64

  var id: String { key }
  var terminalRuns: Int { successfulRuns + failedRuns + cancelledRuns }
  var evaluatedRuns: Int { successfulRuns + failedRuns }
  var successRate: Double {
    evaluatedRuns == 0 ? 0.5 : Double(successfulRuns) / Double(evaluatedRuns)
  }
  var confidence: Double { min(1, Double(evaluatedRuns) / 8.0) }

  init(
    key: String,
    taskFamily: String,
    resourceKey: String,
    requiredCapabilities: Set<AgentCapability> = [],
    successfulRuns: Int = 0,
    failedRuns: Int = 0,
    cancelledRuns: Int = 0,
    correctionCount: Int = 0,
    consecutiveFailures: Int = 0,
    averageLatencyMillis: Int64 = 0,
    lastOutcome: AgentPhase = .executing,
    lastFailureCategory: String = "",
    firstObservedAtMillis: Int64 = 0,
    lastObservedAtMillis: Int64 = 0
  ) {
    self.key = String(key.prefix(120))
    self.taskFamily = String(taskFamily.prefix(240))
    self.resourceKey = String(resourceKey.prefix(80))
    self.requiredCapabilities = requiredCapabilities
    self.successfulRuns = max(0, successfulRuns)
    self.failedRuns = max(0, failedRuns)
    self.cancelledRuns = max(0, cancelledRuns)
    self.correctionCount = max(0, correctionCount)
    self.consecutiveFailures = max(0, consecutiveFailures)
    self.averageLatencyMillis = max(0, averageLatencyMillis)
    self.lastOutcome = lastOutcome
    self.lastFailureCategory = String(lastFailureCategory.prefix(80))
    self.firstObservedAtMillis = max(0, firstObservedAtMillis)
    self.lastObservedAtMillis = max(0, lastObservedAtMillis)
  }
}

struct AgentSelfModel: Codable, Equatable {
  static let identityId = "galaxyssi-mobile"

  var identityId: String = AgentSelfModel.identityId
  var totalRuns: Int = 0
  var successfulRuns: Int = 0
  var failedRuns: Int = 0
  var cancelledRuns: Int = 0
  var beliefs: [AgentSelfCapabilityBelief] = []
  var processedRunIds: [String] = []
  var processedFeedbackKeys: [String] = []
  var updatedAtMillis: Int64 = 0

  var strengths: [AgentSelfCapabilityBelief] {
    beliefs.filter { $0.evaluatedRuns >= 3 && $0.successRate >= 0.75 }
      .sorted { lhs, rhs in
        if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
        if lhs.successRate != rhs.successRate { return lhs.successRate > rhs.successRate }
        return lhs.lastObservedAtMillis > rhs.lastObservedAtMillis
      }
      .prefix(5).map { $0 }
  }

  var limitations: [AgentSelfCapabilityBelief] {
    beliefs.filter { $0.failedRuns >= 2 && ($0.successRate < 0.5 || $0.consecutiveFailures >= 2) }
      .sorted { lhs, rhs in
        if lhs.consecutiveFailures != rhs.consecutiveFailures {
          return lhs.consecutiveFailures > rhs.consecutiveFailures
        }
        if lhs.successRate != rhs.successRate { return lhs.successRate < rhs.successRate }
        return lhs.lastObservedAtMillis > rhs.lastObservedAtMillis
      }
      .prefix(5).map { $0 }
  }
}

struct AgentSelfCalibration: Equatable {
  var scoreAdjustment: Int = 0
  var confidence: Double = 0
  var evidenceRuns: Int = 0
  var reason: String = ""
}

struct AgentSelfModelMutation: Equatable {
  var before: AgentSelfModel
  var after: AgentSelfModel
  var belief: AgentSelfCapabilityBelief?
  var changed: Bool { before != after }
}

enum AgentSelfModelReducer {
  static func observe(_ current: AgentSelfModel, task: AgentTaskRecord) -> AgentSelfModelMutation {
    guard task.phase.isSelfModelTerminal, !task.taskId.isBlank,
          !current.processedRunIds.contains(task.taskId) else {
      return AgentSelfModelMutation(before: current, after: current, belief: nil)
    }
    let requirements = AgentTaskRequirementAnalyzer.analyze(task.goal)
    let family = safeTaskFamily(task.goal, requirements: requirements)
    let resource = resourceKey(task.executionRuntimeId.ifBlank(task.executionLocationId).ifBlank(task.routeKind.rawValue))
    let key = stableKey(family, resource, requirements.capabilities.sorted { $0.rawValue < $1.rawValue }.map(\.rawValue).joined(separator: ","))
    let now = task.updatedAtMillis > 0 ? task.updatedAtMillis : AgentMemoryClock.nowMillis()
    let latency = task.createdAtMillis > 0 ? max(0, now - task.createdAtMillis) : 0
    let existing = current.beliefs.first { $0.key == key }
    let previousSamples = existing?.terminalRuns ?? 0
    let averageLatency: Int64
    if latency <= 0 {
      averageLatency = existing?.averageLatencyMillis ?? 0
    } else if previousSamples == 0 {
      averageLatency = latency
    } else {
      averageLatency = ((existing?.averageLatencyMillis ?? 0) * Int64(previousSamples) + latency) /
        Int64(previousSamples + 1)
    }
    let completed = task.phase == .completed
    let cancelled = task.phase == .cancelled
    let belief = (existing ?? AgentSelfCapabilityBelief(
      key: key,
      taskFamily: family,
      resourceKey: resource,
      requiredCapabilities: requirements.capabilities,
      firstObservedAtMillis: task.createdAtMillis > 0 ? task.createdAtMillis : now
    )).copy(
      successfulRuns: (existing?.successfulRuns ?? 0) + (completed ? 1 : 0),
      failedRuns: (existing?.failedRuns ?? 0) + (!completed && !cancelled ? 1 : 0),
      cancelledRuns: (existing?.cancelledRuns ?? 0) + (cancelled ? 1 : 0),
      consecutiveFailures: completed ? 0 : (cancelled ? existing?.consecutiveFailures ?? 0 : (existing?.consecutiveFailures ?? 0) + 1),
      averageLatencyMillis: averageLatency,
      lastOutcome: task.phase,
      lastFailureCategory: completed || cancelled ? "" : failureCategory(task),
      lastObservedAtMillis: now
    )
    var beliefs = (current.beliefs.filter { $0.key != key } + [belief])
      .sorted { $0.lastObservedAtMillis > $1.lastObservedAtMillis }
    beliefs = Array(beliefs.prefix(512))
    let after = AgentSelfModel(
      identityId: current.identityId,
      totalRuns: current.totalRuns + 1,
      successfulRuns: current.successfulRuns + (completed ? 1 : 0),
      failedRuns: current.failedRuns + (!completed && !cancelled ? 1 : 0),
      cancelledRuns: current.cancelledRuns + (cancelled ? 1 : 0),
      beliefs: beliefs,
      processedRunIds: Array((current.processedRunIds + [task.taskId]).suffix(4_000)),
      processedFeedbackKeys: current.processedFeedbackKeys,
      updatedAtMillis: now
    )
    return AgentSelfModelMutation(before: current, after: after, belief: belief)
  }

  static func calibration(
    model: AgentSelfModel,
    goal: String,
    resourceId: String,
    requirements: AgentTaskRequirements
  ) -> AgentSelfCalibration {
    let resource = resourceKey(resourceId)
    let family = safeTaskFamily(goal, requirements: requirements)
    let matches = model.beliefs.filter { belief in
      belief.resourceKey == resource && belief.evaluatedRuns > 0 &&
        (AgentLearningAnalyzer.sameTaskFamily(belief.taskFamily, family) ||
          capabilityOverlap(belief.requiredCapabilities, requirements.capabilities) >= 0.74)
    }
    guard !matches.isEmpty else { return AgentSelfCalibration() }
    let evidence = matches.reduce(0) { $0 + $1.evaluatedRuns }
    guard evidence >= 2 else { return AgentSelfCalibration(evidenceRuns: evidence) }
    let successes = matches.reduce(0) { $0 + $1.successfulRuns }
    let failures = matches.reduce(0) { $0 + $1.failedRuns }
    let corrections = matches.reduce(0) { $0 + $1.correctionCount }
    let consecutiveFailures = matches.map(\.consecutiveFailures).max() ?? 0
    let confidence = min(1, Double(evidence) / 10)
    let reliability = Double(successes) / Double(max(1, successes + failures))
    var adjustment = Int(((reliability - 0.5) * 220 * confidence).rounded())
    adjustment -= min(48, corrections * 12)
    if consecutiveFailures >= 2 { adjustment -= min(145, 70 + (consecutiveFailures - 2) * 25) }
    return AgentSelfCalibration(
      scoreAdjustment: min(120, max(-180, adjustment)),
      confidence: confidence,
      evidenceRuns: evidence,
      reason: "self_model:\(successes)s/\(failures)f/\(corrections)c"
    )
  }

  static func calibrationAdjustment(
    goal: String,
    resourceId: String,
    requirements: AgentTaskRequirements
  ) -> Int {
    calibration(
      model: UserDefaultsAgentSelfModelStore.shared.snapshot(),
      goal: goal,
      resourceId: resourceId,
      requirements: requirements
    ).scoreAdjustment
  }

  static func resourceKey(_ value: String) -> String {
    let id = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if id.isEmpty || id == "phone" || id == "ios" || id == AgentSelfModel.identityId { return AgentSelfModel.identityId }
    if id == "claude" || id == "claude-code" || id.contains(":claude-code") { return "claude-code" }
    if id == "codex" || id.contains(":codex") { return "codex" }
    if id == "hermes" || id.contains(":hermes") { return "hermes" }
    if id == "openclaw" || id.contains(":openclaw") { return "openclaw" }
    if id == "local-llm" || id.contains(":local-llm") { return "local-llm" }
    if id == "cloud-models" || id.hasPrefix("cloud-model:") { return "cloud-models" }
    if id.hasPrefix("skill:") { return "skill:\(stableKey(id).prefix(20))" }
    return "resource:\(stableKey(id).prefix(24))"
  }

  private static func safeTaskFamily(_ request: String, requirements: AgentTaskRequirements) -> String {
    if AgentLearningAnalyzer.containsSensitiveData(request) ||
      requirements.dataSensitivity == .confidential || requirements.dataSensitivity == .restricted {
      return capabilityFamily(requirements.capabilities)
    }
    return AgentLearningAnalyzer.taskFamily(request).ifBlank(capabilityFamily(requirements.capabilities))
  }

  private static func capabilityFamily(_ capabilities: Set<AgentCapability>) -> String {
    "capabilities:" + capabilities.sorted { $0.rawValue < $1.rawValue }.map { $0.rawValue.lowercased() }.joined(separator: ",")
  }

  private static func failureCategory(_ task: AgentTaskRecord) -> String {
    let signal = (task.executionLog + [task.result, task.verification]).joined(separator: " ").lowercased()
    if signal.contains("timeout") || signal.contains("timed out") { return "timeout" }
    if signal.contains("permission") || signal.contains("denied") { return "permission" }
    if signal.contains("network") || signal.contains("offline") || signal.contains("unreachable") { return "connectivity" }
    if signal.contains("cancel") { return "cancelled" }
    return task.nativeActionResults.isEmpty ? "run_failure" : "tool_failure"
  }

  private static func capabilityOverlap(_ left: Set<AgentCapability>, _ right: Set<AgentCapability>) -> Double {
    if left.isEmpty && right.isEmpty { return 1 }
    if left.isEmpty || right.isEmpty { return 0 }
    return Double(left.intersection(right).count) / Double(left.union(right).count)
  }

  private static func stableKey(_ values: String...) -> String {
    SHA256.hash(data: Data(values.joined(separator: "\u{0}").utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

private extension AgentPhase {
  var isSelfModelTerminal: Bool { self == .completed || self == .failed || self == .cancelled || self == .blocked }
}

private extension AgentSelfCapabilityBelief {
  func copy(
    successfulRuns: Int,
    failedRuns: Int,
    cancelledRuns: Int,
    consecutiveFailures: Int,
    averageLatencyMillis: Int64,
    lastOutcome: AgentPhase,
    lastFailureCategory: String,
    lastObservedAtMillis: Int64
  ) -> AgentSelfCapabilityBelief {
    AgentSelfCapabilityBelief(
      key: key,
      taskFamily: taskFamily,
      resourceKey: resourceKey,
      requiredCapabilities: requiredCapabilities,
      successfulRuns: successfulRuns,
      failedRuns: failedRuns,
      cancelledRuns: cancelledRuns,
      correctionCount: correctionCount,
      consecutiveFailures: consecutiveFailures,
      averageLatencyMillis: averageLatencyMillis,
      lastOutcome: lastOutcome,
      lastFailureCategory: lastFailureCategory,
      firstObservedAtMillis: firstObservedAtMillis,
      lastObservedAtMillis: lastObservedAtMillis
    )
  }
}

final class UserDefaultsAgentSelfModelStore {
  static let shared = UserDefaultsAgentSelfModelStore()
  static let key = "galaxyssi_agent_self_model"

  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let lock = NSLock()

  init(defaults: UserDefaults = .standard, secrets: GalaxySSISecretStore = KeychainSecretStore.shared) {
    self.defaults = defaults
    self.secrets = secrets
  }

  func snapshot() -> AgentSelfModel {
    lock.lock(); defer { lock.unlock() }
    return loadLocked()
  }

  @discardableResult
  func observe(task: AgentTaskRecord) -> AgentSelfModelMutation {
    lock.lock(); defer { lock.unlock() }
    let mutation = AgentSelfModelReducer.observe(loadLocked(), task: task)
    if mutation.changed, let data = try? JSONEncoder().encode(mutation.after) {
      _ = GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: Self.key, secrets: secrets)
    }
    return mutation
  }

  func calibration(goal: String, resourceId: String, requirements: AgentTaskRequirements) -> AgentSelfCalibration {
    AgentSelfModelReducer.calibration(model: snapshot(), goal: goal, resourceId: resourceId, requirements: requirements)
  }

  func clear() {
    lock.lock(); defer { lock.unlock() }
    GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: Self.key, secrets: secrets)
  }

  private func loadLocked() -> AgentSelfModel {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: Self.key, secrets: secrets),
          let model = try? JSONDecoder().decode(AgentSelfModel.self, from: data) else {
      return AgentSelfModel()
    }
    return model
  }
}

struct GalaxySSIAgentSelfModelView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @State private var model = UserDefaultsAgentSelfModelStore.shared.snapshot()

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("self_model_title", "Agent self model"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: t("self_model_hero_title", "Learning from real task outcomes"),
            subtitle: t(
              "self_model_hero_subtitle",
              "The model stays on this iPhone and keeps only bounded, content-minimized evidence"
            ),
            systemImage: "brain.head.profile",
            tint: .galaxySSIInsightText,
            badge: model.totalRuns == 0 ? t("self_model_no_data", "No data") : t("self_model_local", "On device")
          )
          summarySection
          beliefSection(
            title: t("self_model_strengths", "Strengths"),
            empty: t("self_model_strengths_empty", "Complete more tasks to identify reliable capabilities"),
            beliefs: model.strengths,
            tint: .galaxySSIInsightText
          )
          beliefSection(
            title: t("self_model_limitations", "Limitations"),
            empty: t("self_model_limitations_empty", "No repeated limitation has been detected"),
            beliefs: model.limitations,
            tint: .orange
          )
          footer
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear { model = UserDefaultsAgentSelfModelStore.shared.snapshot() }
  }

  private var summarySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("self_model_summary", "Summary"))
      GalaxySSISecurityStatusRow(
        title: t("self_model_total_runs", "Observed tasks"),
        subtitle: t("self_model_total_runs_subtitle", "Terminal task outcomes used as local evidence"),
        systemImage: "checklist",
        tint: .blue,
        badge: "\(model.totalRuns)"
      )
      GalaxySSISecurityStatusRow(
        title: t("self_model_success_rate", "Evaluated success rate"),
        subtitle: String(format: t("self_model_success_breakdown", "%d successful, %d failed"), model.successfulRuns, model.failedRuns),
        systemImage: "chart.line.uptrend.xyaxis",
        tint: model.successfulRuns >= model.failedRuns ? .galaxySSIInsightText : .orange,
        badge: percent(successRate)
      )
      GalaxySSISecurityStatusRow(
        title: t("self_model_beliefs", "Capability beliefs"),
        subtitle: t("self_model_beliefs_subtitle", "Task family and execution resource combinations"),
        systemImage: "square.stack.3d.up",
        tint: .purple,
        badge: "\(model.beliefs.count)"
      )
    }
  }

  private func beliefSection(
    title: String,
    empty: String,
    beliefs: [AgentSelfCapabilityBelief],
    tint: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: title)
      if beliefs.isEmpty {
        GalaxySSISecurityStatusRow(
          title: empty,
          subtitle: "",
          systemImage: "minus.circle",
          tint: .gray,
          badge: ""
        )
      } else {
        ForEach(beliefs) { belief in
          GalaxySSISecurityStatusRow(
            title: displayFamily(belief.taskFamily),
            subtitle: "\(resourceLabel(belief.resourceKey)) / \(belief.evaluatedRuns) \(t("self_model_evaluated", "evaluated"))",
            systemImage: belief.successRate >= 0.75 ? "checkmark.circle" : "exclamationmark.triangle",
            tint: tint,
            badge: percent(belief.successRate)
          )
        }
      }
    }
  }

  private var footer: some View {
    Text(t(
      "self_model_footer",
      "Task text is normalized before learning. Secrets, credentials, and private content are excluded from the model."
    ))
      .font(.system(size: 12))
      .foregroundColor(.galaxySSITextSecondary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 4)
  }

  private var successRate: Double {
    let evaluated = model.successfulRuns + model.failedRuns
    return evaluated == 0 ? 0.5 : Double(model.successfulRuns) / Double(evaluated)
  }

  private func displayFamily(_ value: String) -> String {
    value.replacingOccurrences(of: "capabilities:", with: t("self_model_capabilities", "Capabilities: "))
      .ifBlank(t("self_model_unknown_family", "General task"))
  }

  private func resourceLabel(_ value: String) -> String {
    value.replacingOccurrences(of: "resource:", with: "")
      .replacingOccurrences(of: "skill:", with: "Skill ")
      .ifBlank(t("self_model_phone", "iPhone"))
  }

  private func percent(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .percent
    formatter.locale = GalaxySSILocalization.interfaceLocale(language: interfaceLanguage)
    return formatter.string(from: NSNumber(value: value)) ?? "0%"
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
