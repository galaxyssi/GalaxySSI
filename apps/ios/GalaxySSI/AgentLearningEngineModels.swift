import Foundation

enum AgentLearningProposalKind: String, Codable, CaseIterable, Identifiable {
  case skill = "SKILL"
  case skillUpgrade = "SKILL_UPGRADE"
  case behaviorRule = "BEHAVIOR_RULE"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentLearningProposalKind {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .skill
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try? container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentLearningProposalStatus: String, Codable, CaseIterable, Identifiable {
  case pending = "PENDING"
  case approved = "APPROVED"
  case rejected = "REJECTED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentLearningProposalStatus {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .pending
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try? container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentLearningProposal: Codable, Equatable, Identifiable {
  var id: String
  var kind: AgentLearningProposalKind
  var title: String
  var taskFamily: String
  var summary: String
  var evidenceRunIds: [String]
  var manifestJson: String
  var status: AgentLearningProposalStatus
  var createdAtMillis: Int64
  var reviewedAtMillis: Int64

  init(
    id: String = UUID().uuidString,
    kind: AgentLearningProposalKind,
    title: String,
    taskFamily: String,
    summary: String,
    evidenceRunIds: [String],
    manifestJson: String = "",
    status: AgentLearningProposalStatus = .pending,
    createdAtMillis: Int64 = AgentMemoryClock.nowMillis(),
    reviewedAtMillis: Int64 = 0
  ) {
    self.id = String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters)).ifBlank(UUID().uuidString)
    self.kind = kind
    self.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxTitleCharacters)).ifBlank("Learning proposal")
    self.taskFamily = String(taskFamily.trimmingCharacters(in: .whitespacesAndNewlines).prefix(320))
    self.summary = String(summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxFeedbackCharacters))
    self.evidenceRunIds = Array(evidenceRunIds.map {
      String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    }.filter { !$0.isEmpty }.stableDistinctForLearning().prefix(AgentLearningEngine.maxEvidenceRuns))
    self.manifestJson = String(manifestJson.prefix(AgentSkillLimits.maxManifestBytes))
    self.status = status
    self.createdAtMillis = max(createdAtMillis, 0)
    self.reviewedAtMillis = max(reviewedAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case kind
    case title
    case taskFamily = "task_family"
    case summary
    case evidenceRunIds = "evidence_run_ids"
    case manifestJson = "manifest_json"
    case status
    case createdAtMillis = "created_at_millis"
    case reviewedAtMillis = "reviewed_at_millis"
  }
}

struct AgentLearningOutcome: Equatable {
  var memories: [AgentMemoryWriteResult]
  var proposals: [AgentLearningProposal]

  init(
    memories: [AgentMemoryWriteResult] = [],
    proposals: [AgentLearningProposal] = []
  ) {
    self.memories = memories
    self.proposals = proposals
  }
}

protocol AgentLearningProposalStoring: AnyObject {
  func loadProposals() -> [AgentLearningProposal]
  func saveProposals(_ proposals: [AgentLearningProposal])
  func clear()
}

final class InMemoryAgentLearningProposalStore: AgentLearningProposalStoring {
  private var proposals: [AgentLearningProposal]

  init(_ proposals: [AgentLearningProposal] = []) {
    self.proposals = proposals
  }

  func loadProposals() -> [AgentLearningProposal] {
    proposals
  }

  func saveProposals(_ proposals: [AgentLearningProposal]) {
    self.proposals = proposals
  }

  func clear() {
    proposals.removeAll()
  }
}

enum AgentLearningProposalJSONCodec {
  static func encode(_ proposals: [AgentLearningProposal]) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(proposals) else {
      return "[]"
    }
    return String(decoding: data, as: UTF8.self)
  }

  static func decode(_ raw: String) -> [AgentLearningProposal] {
    guard let data = raw.data(using: .utf8) else {
      return []
    }
    return (try? JSONDecoder().decode([AgentLearningProposal].self, from: data)) ?? []
  }
}

extension AgentLearningAnalyzer {
  static func explicitPreference(_ request: String) -> String? {
    let clean = String(request.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxMemoryCharacters))
    guard clean.count >= minMemoryCharacters, !containsSensitiveData(clean) else {
      return nil
    }
    if let match = firstMatch(clean, pattern: englishPreferencePattern),
       let value = match.groups.first?.trimmingCharacters(in: .whitespacesAndNewlines),
       (minMemoryCharacters...maxMemoryCharacters).contains(value.count) {
      return value
    }
    return cjkPreferencePrefixes.compactMap { prefix -> String? in
      guard clean.hasPrefix(prefix) else { return nil }
      let value = clean.dropFirst(prefix.count)
        .trimmingCharacters(in: preferenceTrimCharacters)
      return (minMemoryCharacters...maxMemoryCharacters).contains(value.count) ? value : nil
    }.first
  }

  static func correctionFeedback(_ request: String) -> String? {
    let clean = String(request.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxMemoryCharacters))
    guard clean.count >= minMemoryCharacters, !containsSensitiveData(clean) else {
      return nil
    }
    if clean.range(of: englishCorrectionPattern, options: .regularExpression) != nil {
      return clean
    }
    if cjkCorrectionPrefixes.contains(where: { clean.hasPrefix($0) }) ||
      (clean.contains(cjkDoNot) && clean.contains(cjkShould)) {
      return clean
    }
    return nil
  }

  static func repeatedFailureFamily(
    run: AgentRecordedRun,
    recentRuns: [AgentRecordedRun],
    minimumFailures: Int = 2
  ) -> String? {
    guard run.status == .failed,
          minimumFailures >= 1,
          !containsSensitiveData(run.originalRequest) else {
      return nil
    }
    let family = taskFamily(run.originalRequest)
    guard !family.isEmpty else {
      return nil
    }
    let failures = recentRuns.filter {
      $0.status == .failed && sameTaskFamily($0.originalRequest, family)
    }.count
    return failures >= minimumFailures ? family : nil
  }

  static func hasUnboundTaskValue(_ value: AgentMcpJSONValue) -> Bool {
    switch value {
    case .string(let text):
      return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text != "{{parameters.request}}"
    case .object(let object):
      return hasUnboundTaskValue(object)
    case .array(let values):
      return values.contains(where: hasUnboundTaskValue)
    case .int, .double, .bool, .null:
      return false
    }
  }

  static func hasUnboundTaskValue(_ object: AgentMcpJSONObject) -> Bool {
    object.values.contains(where: hasUnboundTaskValue)
  }

  static func hasTrustedExecutionEvidence(_ call: AgentToolCallRecord) -> Bool {
    guard call.status == .succeeded else {
      return false
    }
    guard call.toolName == AgentIOSOnDeviceRuntimeNativeToolCatalog.execute else {
      return true
    }
    guard let receipt = call.result["execution_receipt"]?.objectValue else {
      return false
    }
    let createdAt = receipt["created_at_millis"]?.intValue ?? 0
    let completedAt = receipt["completed_at_millis"]?.intValue ?? 0
    return !(receipt["request_id"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      (receipt["status"]?.stringValue ?? "").lowercased() == "completed" &&
      receipt["exit_code"]?.intValue == 0 &&
      isSHA256(receipt["source_sha256"]?.stringValue ?? "") &&
      isSHA256(receipt["stdout_sha256"]?.stringValue ?? "") &&
      isSHA256(receipt["stderr_sha256"]?.stringValue ?? "") &&
      createdAt > 0 &&
      completedAt >= createdAt
  }

  static func runExecutionEvidenceTrusted(_ run: AgentRecordedRun) -> Bool {
    run.toolCalls
      .filter { $0.toolName == AgentIOSOnDeviceRuntimeNativeToolCatalog.execute }
      .allSatisfy { hasTrustedExecutionEvidence($0) }
  }

  private static func firstMatch(_ value: String, pattern: String) -> (groups: [String], range: NSRange)? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }
    let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
    guard let match = regex.firstMatch(in: value, range: nsRange) else {
      return nil
    }
    let groups = (1..<match.numberOfRanges).compactMap { index -> String? in
      guard let range = Range(match.range(at: index), in: value) else {
        return nil
      }
      return String(value[range])
    }
    return (groups, match.range)
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.range(of: #"^[0-9a-f]{64}$"#, options: [.regularExpression, .caseInsensitive]) != nil
  }

  private static let maxMemoryCharacters = 1_000
  private static let minMemoryCharacters = 2
  private static let englishPreferencePattern =
    #"(?i)^(?:please\s+)?(?:remember(?:\s+that)?|i\s+prefer|my\s+preference\s+is|always|use\s+.+?\s+by\s+default)\b[\s,:-]*(.+)$"#
  private static let englishCorrectionPattern =
    #"(?i)^(?:no\b|wrong\b|that(?:'s| is) (?:wrong|not right)|not (?:that|this) way|instead\b|change (?:it|that) to\b|use .+ instead\b|try again\b).+"#
  private static let preferenceTrimCharacters = CharacterSet.whitespacesAndNewlines
    .union(CharacterSet(charactersIn: ":,\u{FF1A}\u{FF0C}-"))
  private static let cjkPreferencePrefixes = [
    "\u{8bf7}\u{8bb0}\u{4f4f}",
    "\u{8bb0}\u{4f4f}",
    "\u{6211}\u{559c}\u{6b22}",
    "\u{6211}\u{504f}\u{597d}",
    "\u{4ee5}\u{540e}",
    "\u{9ed8}\u{8ba4}"
  ]
  private static let cjkCorrectionPrefixes = [
    "\u{4e0d}\u{5bf9}",
    "\u{9519}\u{4e86}",
    "\u{4e0d}\u{662f}\u{8fd9}\u{6837}",
    "\u{6539}\u{6210}",
    "\u{5e94}\u{8be5}",
    "\u{91cd}\u{65b0}"
  ]
  private static let cjkDoNot = "\u{4e0d}\u{8981}"
  private static let cjkShould = "\u{8981}"
}

final class AgentLearningEngine {
  private let memoryStore: AgentMemoryStore
  private let skillRuntime: AgentSkillRuntime
  private let skillCompiler: AgentConversationSkillCompiler
  private let proposalStore: AgentLearningProposalStoring
  private let nowMillis: () -> Int64
  private let idFactory: () -> String

  init(
    memoryStore: AgentMemoryStore,
    skillRuntime: AgentSkillRuntime,
    skillCompiler: AgentConversationSkillCompiler,
    proposalStore: AgentLearningProposalStoring = InMemoryAgentLearningProposalStore(),
    nowMillis: @escaping () -> Int64 = AgentMemoryClock.nowMillis,
    idFactory: @escaping () -> String = { UUID().uuidString }
  ) {
    self.memoryStore = memoryStore
    self.skillRuntime = skillRuntime
    self.skillCompiler = skillCompiler
    self.proposalStore = proposalStore
    self.nowMillis = nowMillis
    self.idFactory = idFactory
  }

  func observeCompletedRun(
    run: AgentRecordedRun,
    recentRuns: [AgentRecordedRun],
    privateMode: Bool,
    memoryCaptureEnabled: Bool
  ) -> AgentLearningOutcome {
    guard !privateMode, [.completed, .failed].contains(run.status) else {
      return AgentLearningOutcome()
    }
    if run.status == .failed {
      return AgentLearningOutcome(
        memories: memoryCaptureEnabled ? learnRepeatedFailure(run: run, recentRuns: recentRuns) : []
      )
    }
    var memories: [AgentMemoryWriteResult] = []
    if memoryCaptureEnabled {
      if let preference = AgentLearningAnalyzer.explicitPreference(run.originalRequest) {
        memories.append(memoryStore.remember(AgentMemoryItem(
          kind: .preference,
          value: preference,
          source: "automatic_learning",
          key: "preference:\(AgentLearningAnalyzer.stableKey(preference))",
          scope: .global,
          confidence: 0.82,
          evidenceCount: 1,
          autoLearned: true,
          lastConfirmedAtMillis: nowMillis()
        )))
      }
      let family = AgentLearningAnalyzer.taskFamily(run.originalRequest)
      let matchingSuccesses = recentRuns.filter { candidate in
        candidate.status == .completed &&
          candidate.toolCalls.contains(where: { AgentLearningAnalyzer.hasTrustedExecutionEvidence($0) }) &&
          AgentLearningAnalyzer.runExecutionEvidenceTrusted(candidate) &&
          AgentLearningAnalyzer.sameTaskFamily(candidate.originalRequest, family)
      }.count
      if !family.isEmpty,
         matchingSuccesses >= Self.minWorkflowMemoryRuns,
         !AgentLearningAnalyzer.containsSensitiveData(run.originalRequest) {
        memories.append(memoryStore.remember(AgentMemoryItem(
          kind: .workflow,
          value: "Successful workflow family: \(family)",
          source: "automatic_learning",
          key: "workflow:\(AgentLearningAnalyzer.stableKey(family))",
          scope: .global,
          confidence: 0.74,
          evidenceCount: matchingSuccesses,
          autoLearned: true,
          expiresAtMillis: nowMillis() + Self.workflowMemoryTTLMillis
        )))
      }
    }
    return AgentLearningOutcome(memories: memories, proposals: proposeSkill(run: run, recentRuns: recentRuns).map { [$0] } ?? [])
  }

  func observeFeedback(run: AgentRecordedRun, recentRuns: [AgentRecordedRun]) -> AgentLearningProposal? {
    guard !run.activeSkillId.isBlank,
          !run.userFeedback.isEmpty,
          !run.userFeedback.contains(where: { AgentLearningAnalyzer.containsSensitiveData($0) }) else {
      return nil
    }
    guard let base = skillRuntime.list()
      .filter({ $0.id == run.activeSkillId })
      .max(by: { compareVersions($0.version, $1.version) < 0 }) else {
      return nil
    }
    if loadProposals().contains(where: {
      $0.kind == .skillUpgrade && $0.evidenceRunIds.contains(run.runId) && $0.status == .pending
    }) {
      return nil
    }
    let improvedRuns = Array(recentRuns.filter {
      $0.activeSkillId == run.activeSkillId &&
        !$0.userFeedback.isEmpty &&
        AgentLearningAnalyzer.runExecutionEvidenceTrusted($0)
    }.suffix(Self.maxEvidenceRuns))
    let evidenceRuns = improvedRuns.isEmpty ? [run] : improvedRuns
    guard let manifest = try? AgentSkillVersionManager(skillRuntime).buildUpgrade(base: base, improvedRuns: evidenceRuns) else {
      return nil
    }
    let proposal = AgentLearningProposal(
      id: idFactory(),
      kind: .skillUpgrade,
      title: manifest.name,
      taskFamily: AgentLearningAnalyzer.taskFamily(run.originalRequest),
      summary: "User correction is ready as a reviewed Skill upgrade",
      evidenceRunIds: evidenceRuns.map(\.runId),
      manifestJson: AgentSkillManifestCodec.encode(manifest),
      createdAtMillis: nowMillis()
    )
    appendProposal(proposal)
    return proposal
  }

  func proposals(status: AgentLearningProposalStatus? = nil) -> [AgentLearningProposal] {
    loadProposals()
      .filter { status == nil || $0.status == status }
      .sorted { $0.createdAtMillis > $1.createdAtMillis }
  }

  func approve(proposalId: String) -> AgentSkillInstallation? {
    var proposals = loadProposals()
    guard let index = proposals.firstIndex(where: { $0.id == proposalId && $0.status == .pending }),
          let manifest = AgentSkillManifestCodec.decode(proposals[index].manifestJson),
          let installed = try? skillRuntime.install(manifest, enabled: true) else {
      return nil
    }
    proposals[index].status = .approved
    proposals[index].reviewedAtMillis = nowMillis()
    saveProposals(proposals)
    return installed
  }

  func reject(proposalId: String) -> Bool {
    review(proposalId, status: .rejected)
  }

  func clear() {
    proposalStore.clear()
  }

  private func proposeSkill(run: AgentRecordedRun, recentRuns: [AgentRecordedRun]) -> AgentLearningProposal? {
    guard run.activeSkillId.isBlank, !AgentLearningAnalyzer.containsSensitiveData(run.originalRequest) else {
      return nil
    }
    let familyRuns = Array(recentRuns
      .filter { candidate in
        candidate.status == .completed &&
          candidate.activeSkillId.isBlank &&
          AgentLearningAnalyzer.runExecutionEvidenceTrusted(candidate) &&
          AgentLearningAnalyzer.sameTaskFamily(candidate.originalRequest, run.originalRequest)
      }
      .stableDistinctByLearning(\.runId)
      .sorted { $0.completedAtMillis < $1.completedAtMillis }
      .suffix(Self.maxEvidenceRuns))
    guard familyRuns.count >= Self.minSuccessfulRuns,
          Set(familyRuns.map(\.originalRequest)).count >= 2 else {
      return nil
    }
    let family = AgentLearningAnalyzer.taskFamily(run.originalRequest)
    guard !loadProposals().contains(where: { $0.taskFamily == family && $0.status != .rejected }) else {
      return nil
    }
    guard var manifest = try? skillCompiler.compile(familyRuns, titleHint: AgentLearningAnalyzer.safeTitle(run.originalRequest)) else {
      return nil
    }
    if manifest.steps.contains(where: { AgentLearningAnalyzer.hasUnboundTaskValue($0.input) }) {
      manifest.nativeTools = [AgentConversationSkillCompiler.agentOrchestrationToolId]
      manifest.permissions = []
      manifest.steps = [
        AgentSkillStep(
          id: "step_1",
          toolId: AgentConversationSkillCompiler.agentOrchestrationToolId,
          input: ["request": .string("{{parameters.request}}")]
        )
      ]
    }
    manifest.source = "automatic_learning_proposal"
    manifest.author = "GalaxySSI Learning"
    manifest.autoInvoke = false
    manifest.instructions = String(manifest.instructions.prefix(Self.maxInstructionsCharacters))
    manifest.renderSpec = [:]
    let proposal = AgentLearningProposal(
      id: idFactory(),
      kind: .skill,
      title: manifest.name,
      taskFamily: family,
      summary: "Repeated successful workflow ready for review",
      evidenceRunIds: familyRuns.map(\.runId),
      manifestJson: AgentSkillManifestCodec.encode(manifest),
      createdAtMillis: nowMillis()
    )
    appendProposal(proposal)
    return proposal
  }

  private func learnRepeatedFailure(run: AgentRecordedRun, recentRuns: [AgentRecordedRun]) -> [AgentMemoryWriteResult] {
    guard let family = AgentLearningAnalyzer.repeatedFailureFamily(
      run: run,
      recentRuns: recentRuns,
      minimumFailures: Self.minRepeatedFailures
    ) else {
      return []
    }
    return [memoryStore.remember(AgentMemoryItem(
      kind: .workflow,
      value: "Do not repeat the unchanged failed workflow for: \(family). Replan or change the execution resource before retrying.",
      source: "automatic_failure_learning",
      key: "failure:\(AgentLearningAnalyzer.stableKey(family))",
      scope: .global,
      confidence: 0.68,
      evidenceCount: 1,
      autoLearned: true,
      expiresAtMillis: nowMillis() + Self.failureMemoryTTLMillis
    ))]
  }

  private func review(_ id: String, status: AgentLearningProposalStatus) -> Bool {
    var proposals = loadProposals()
    guard let index = proposals.firstIndex(where: { $0.id == id && $0.status == .pending }) else {
      return false
    }
    proposals[index].status = status
    proposals[index].reviewedAtMillis = nowMillis()
    saveProposals(proposals)
    return true
  }

  private func appendProposal(_ proposal: AgentLearningProposal) {
    saveProposals(Array((loadProposals() + [proposal]).suffix(Self.maxProposals)))
  }

  private func loadProposals() -> [AgentLearningProposal] {
    proposalStore.loadProposals()
  }

  private func saveProposals(_ proposals: [AgentLearningProposal]) {
    proposalStore.saveProposals(proposals)
  }

  private func compareVersions(_ left: String, _ right: String) -> Int {
    for index in 0..<3 {
      let delta = versionPart(left, index) - versionPart(right, index)
      if delta != 0 {
        return delta
      }
    }
    return 0
  }

  private func versionPart(_ version: String, _ index: Int) -> Int {
    let parts = version.split(separator: ".").map { Int(String($0.filter(\.isNumber))) ?? 0 }
    return parts[safeForLearning: index] ?? 0
  }

  static let minSuccessfulRuns = 3
  static let minWorkflowMemoryRuns = 2
  static let minRepeatedFailures = 2
  static let maxEvidenceRuns = 12
  static let maxProposals = 128
  static let maxInstructionsCharacters = 24_000
  static let workflowMemoryTTLMillis: Int64 = 180 * 24 * 60 * 60 * 1_000
  static let failureMemoryTTLMillis: Int64 = 90 * 24 * 60 * 60 * 1_000
}

private extension Array where Element: Hashable {
  func stableDistinctForLearning() -> [Element] {
    var seen: Set<Element> = []
    var values: [Element] = []
    for item in self where seen.insert(item).inserted {
      values.append(item)
    }
    return values
  }
}

private extension Array {
  func stableDistinctByLearning<Value: Hashable>(_ keyPath: KeyPath<Element, Value>) -> [Element] {
    var seen: Set<Value> = []
    var values: [Element] = []
    for item in self where seen.insert(item[keyPath: keyPath]).inserted {
      values.append(item)
    }
    return values
  }

  subscript(safeForLearning index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
