import CryptoKit
import Foundation

enum AgentConnectorKind: String, Codable, CaseIterable, Identifiable {
  case model = "MODEL"
  case agent = "AGENT"
  case device = "DEVICE"
  case knowledge = "KNOWLEDGE"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentConnectorKind {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .agent
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

enum AgentConnectorStatus: String, Codable, CaseIterable, Identifiable {
  case available = "AVAILABLE"
  case needsSetup = "NEEDS_SETUP"
  case disconnected = "DISCONNECTED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentConnectorStatus {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .disconnected
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

enum AgentCapability: String, Codable, CaseIterable, Identifiable {
  case chat = "CHAT"
  case reasoning = "REASONING"
  case liveData = "LIVE_DATA"
  case toolUse = "TOOL_USE"
  case mcp = "MCP"
  case skill = "SKILL"
  case localInference = "LOCAL_INFERENCE"
  case research = "RESEARCH"
  case code = "CODE"
  case taskExecution = "TASK_EXECUTION"
  case smartHome = "SMART_HOME"
  case deviceControl = "DEVICE_CONTROL"
  case knowledgeSearch = "KNOWLEDGE_SEARCH"
  case screenReading = "SCREEN_READING"
  case clipboard = "CLIPBOARD"
  case systemSettings = "SYSTEM_SETTINGS"
  case appNavigation = "APP_NAVIGATION"
  case alarm = "ALARM"

  var id: String { rawValue }
  var wireValue: String { rawValue.lowercased() }

  static func fromWireValue(_ value: String?) -> AgentCapability? {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self)) ?? .chat
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentReputationOutcome: String, Codable, CaseIterable, Identifiable {
  case succeeded = "SUCCEEDED"
  case partial = "PARTIAL"
  case failed = "FAILED"
  case timedOut = "TIMED_OUT"
  case cancelled = "CANCELLED"
  case rejected = "REJECTED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentReputationOutcome? {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    guard let value = Self.fromWireValue(try container.decode(String.self)) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unknown agent reputation outcome"
      )
    }
    self = value
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentReputationReceiptProvenance: String, Codable, CaseIterable, Identifiable {
  case executorSigned = "EXECUTOR_SIGNED"
  case hostObserved = "HOST_OBSERVED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentReputationReceiptProvenance? {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    guard let value = Self.fromWireValue(try container.decode(String.self)) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unknown agent reputation receipt provenance"
      )
    }
    self = value
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentReputationVerificationVerdict: String, Codable, CaseIterable, Identifiable {
  case passed = "PASSED"
  case failed = "FAILED"
  case inconclusive = "INCONCLUSIVE"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentReputationVerificationVerdict? {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    guard let value = Self.fromWireValue(try container.decode(String.self)) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unknown agent reputation verification verdict"
      )
    }
    self = value
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentSignedExecutionReceipt: Codable, Equatable {
  static let currentVersion = 1

  var receiptId: String
  var runId: String
  var taskIdHash: String
  var agentId: String
  var installationId: String
  var executorFailureDomain: String
  var capabilities: Set<AgentCapability>
  var outcome: AgentReputationOutcome
  var provenance: AgentReputationReceiptProvenance
  var startedAtMillis: Int64
  var completedAtMillis: Int64
  var deadlineAtMillis: Int64
  var estimatedCostUnits: Int
  var actualCostUnits: Int
  var outputHash: String
  var evidenceHash: String
  var signerId: String
  var signatureKeyId: String
  var signature: String

  var canonicalJson: String {
    AgentMcpJSONCodec.stringify(canonicalObject())
  }

  init(
    receiptId: String,
    runId: String,
    taskIdHash: String,
    agentId: String,
    installationId: String,
    executorFailureDomain: String,
    capabilities: Set<AgentCapability>,
    outcome: AgentReputationOutcome,
    provenance: AgentReputationReceiptProvenance,
    startedAtMillis: Int64,
    completedAtMillis: Int64,
    deadlineAtMillis: Int64 = 0,
    estimatedCostUnits: Int = 0,
    actualCostUnits: Int = 0,
    outputHash: String = "",
    evidenceHash: String = "",
    signerId: String,
    signatureKeyId: String,
    signature: String
  ) {
    self.receiptId = receiptId
    self.runId = runId
    self.taskIdHash = taskIdHash
    self.agentId = agentId
    self.installationId = installationId
    self.executorFailureDomain = executorFailureDomain
    self.capabilities = capabilities
    self.outcome = outcome
    self.provenance = provenance
    self.startedAtMillis = startedAtMillis
    self.completedAtMillis = completedAtMillis
    self.deadlineAtMillis = deadlineAtMillis
    self.estimatedCostUnits = estimatedCostUnits
    self.actualCostUnits = actualCostUnits
    self.outputHash = outputHash
    self.evidenceHash = evidenceHash
    self.signerId = signerId
    self.signatureKeyId = signatureKeyId
    self.signature = signature
  }

  enum CodingKeys: String, CodingKey {
    case receiptId = "receipt_id"
    case runId = "run_id"
    case taskIdHash = "task_id_hash"
    case agentId = "agent_id"
    case installationId = "installation_id"
    case executorFailureDomain = "executor_failure_domain"
    case capabilities
    case outcome
    case provenance
    case startedAtMillis = "started_at_millis"
    case completedAtMillis = "completed_at_millis"
    case deadlineAtMillis = "deadline_at_millis"
    case estimatedCostUnits = "estimated_cost_units"
    case actualCostUnits = "actual_cost_units"
    case outputHash = "output_hash"
    case evidenceHash = "evidence_hash"
    case signerId = "signer_id"
    case signatureKeyId = "signature_key_id"
    case signature
  }

  func canonicalPayload() -> Data {
    Data(canonicalJson.utf8)
  }

  func canonicalObject() -> AgentMcpJSONObject {
    [
      "version": .int(Int64(Self.currentVersion)),
      "receipt_id": .string(receiptId),
      "run_id": .string(runId),
      "task_id_hash": .string(taskIdHash.lowercased()),
      "agent_id": .string(agentId),
      "installation_id": .string(installationId),
      "executor_failure_domain": .string(executorFailureDomain),
      "capabilities": .array(capabilities.map(\.rawValue).sorted().map(AgentMcpJSONValue.string)),
      "outcome": .string(outcome.rawValue),
      "provenance": .string(provenance.rawValue),
      "started_at_millis": .int(startedAtMillis),
      "completed_at_millis": .int(completedAtMillis),
      "deadline_at_millis": .int(deadlineAtMillis),
      "estimated_cost_units": .int(Int64(estimatedCostUnits)),
      "actual_cost_units": .int(Int64(actualCostUnits)),
      "output_hash": .string(outputHash.lowercased()),
      "evidence_hash": .string(evidenceHash.lowercased()),
      "signer_id": .string(signerId),
      "signature_key_id": .string(signatureKeyId.lowercased())
    ]
  }
}

struct AgentSignedReputationAttestation: Codable, Equatable {
  static let currentVersion = 1

  var attestationId: String
  var receiptId: String
  var receiptPayloadHash: String
  var verifierAgentId: String
  var verifierInstallationId: String
  var verifierFailureDomain: String
  var verdict: AgentReputationVerificationVerdict
  var evidenceHash: String
  var createdAtMillis: Int64
  var signerId: String
  var signatureKeyId: String
  var signature: String

  var canonicalJson: String {
    AgentMcpJSONCodec.stringify(canonicalObject())
  }

  init(
    attestationId: String,
    receiptId: String,
    receiptPayloadHash: String,
    verifierAgentId: String,
    verifierInstallationId: String,
    verifierFailureDomain: String,
    verdict: AgentReputationVerificationVerdict,
    evidenceHash: String,
    createdAtMillis: Int64,
    signerId: String,
    signatureKeyId: String,
    signature: String
  ) {
    self.attestationId = attestationId
    self.receiptId = receiptId
    self.receiptPayloadHash = receiptPayloadHash
    self.verifierAgentId = verifierAgentId
    self.verifierInstallationId = verifierInstallationId
    self.verifierFailureDomain = verifierFailureDomain
    self.verdict = verdict
    self.evidenceHash = evidenceHash
    self.createdAtMillis = createdAtMillis
    self.signerId = signerId
    self.signatureKeyId = signatureKeyId
    self.signature = signature
  }

  enum CodingKeys: String, CodingKey {
    case attestationId = "attestation_id"
    case receiptId = "receipt_id"
    case receiptPayloadHash = "receipt_payload_hash"
    case verifierAgentId = "verifier_agent_id"
    case verifierInstallationId = "verifier_installation_id"
    case verifierFailureDomain = "verifier_failure_domain"
    case verdict
    case evidenceHash = "evidence_hash"
    case createdAtMillis = "created_at_millis"
    case signerId = "signer_id"
    case signatureKeyId = "signature_key_id"
    case signature
  }

  func canonicalPayload() -> Data {
    Data(canonicalJson.utf8)
  }

  func canonicalObject() -> AgentMcpJSONObject {
    [
      "version": .int(Int64(Self.currentVersion)),
      "attestation_id": .string(attestationId),
      "receipt_id": .string(receiptId),
      "receipt_payload_hash": .string(receiptPayloadHash.lowercased()),
      "verifier_agent_id": .string(verifierAgentId),
      "verifier_installation_id": .string(verifierInstallationId),
      "verifier_failure_domain": .string(verifierFailureDomain),
      "verdict": .string(verdict.rawValue),
      "evidence_hash": .string(evidenceHash.lowercased()),
      "created_at_millis": .int(createdAtMillis),
      "signer_id": .string(signerId),
      "signature_key_id": .string(signatureKeyId.lowercased())
    ]
  }

  func validationFailure(
    for receipt: AgentSignedExecutionReceipt,
    nowMillis: Int64
  ) -> String? {
    guard AgentReputationValidation.validId(attestationId),
      AgentReputationValidation.validId(verifierAgentId),
      AgentReputationValidation.validId(verifierInstallationId),
      AgentReputationValidation.validId(signerId) else {
      return AgentReputationValidation.identityInvalidReason
    }
    guard AgentReputationValidation.isSha256(receiptPayloadHash),
      AgentReputationValidation.isSha256(evidenceHash),
      AgentReputationValidation.isSha256(signatureKeyId) else {
      return AgentReputationValidation.hashInvalidReason
    }
    guard receiptPayloadHash == agentReputationSha256(receipt.canonicalPayload()) else {
      return AgentRemoteReputation.invalidBindingReason
    }
    let verifierDomain = verifierFailureDomain.trimmingCharacters(in: .whitespacesAndNewlines)
    guard verifierAgentId != receipt.agentId,
      verifierInstallationId != receipt.installationId,
      signerId != receipt.signerId,
      !verifierDomain.isEmpty,
      verifierDomain != receipt.executorFailureDomain else {
      return AgentReputationValidation.independenceBoundaryInvalidReason
    }
    guard verifierInstallationId == signerId else {
      return AgentReputationValidation.signerSubjectMismatchReason
    }
    guard createdAtMillis >= receipt.completedAtMillis,
      createdAtMillis <= nowMillis + AgentReputationValidation.maxClockSkewMillis else {
      return AgentReputationValidation.timeBoundaryInvalidReason
    }
    guard !signature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      signature.count <= AgentReputationValidation.maxSignatureCharacters else {
      return AgentReputationValidation.signatureInvalidReason
    }
    return nil
  }
}

struct AgentReputationSnapshot: Codable, Equatable {
  var agentId: String
  var score: Int
  var confidence: Int
  var reliability: Int
  var quality: Int
  var timeliness: Int
  var costEfficiency: Int
  var evaluatedRuns: Int
  var independentlyVerifiedRuns: Int
  var disputedRuns: Int
  var timeoutRuns: Int
  var independentFailureDomains: Int
  var lastEvidenceAtMillis: Int64
  var routingAdjustment: Int

  enum CodingKeys: String, CodingKey {
    case agentId = "agent_id"
    case score
    case confidence
    case reliability
    case quality
    case timeliness
    case costEfficiency = "cost_efficiency"
    case evaluatedRuns = "evaluated_runs"
    case independentlyVerifiedRuns = "independently_verified_runs"
    case disputedRuns = "disputed_runs"
    case timeoutRuns = "timeout_runs"
    case independentFailureDomains = "independent_failure_domains"
    case lastEvidenceAtMillis = "last_evidence_at_millis"
    case routingAdjustment = "routing_adjustment"
  }

  static func neutral(_ agentId: String) -> AgentReputationSnapshot {
    AgentReputationSnapshot(
      agentId: agentId,
      score: 70,
      confidence: 0,
      reliability: 70,
      quality: 70,
      timeliness: 70,
      costEfficiency: 70,
      evaluatedRuns: 0,
      independentlyVerifiedRuns: 0,
      disputedRuns: 0,
      timeoutRuns: 0,
      independentFailureDomains: 0,
      lastEvidenceAtMillis: 0,
      routingAdjustment: 0
    )
  }
}

enum AgentReputationScoring {
  static func snapshot(
    agentId: String,
    capabilities: Set<AgentCapability> = [],
    receipts allReceipts: [AgentSignedExecutionReceipt],
    attestations allAttestations: [AgentSignedReputationAttestation],
    nowMillis: Int64
  ) -> AgentReputationSnapshot {
    let receipts = latestReceipts(
      agentId: agentId,
      capabilities: capabilities,
      receipts: allReceipts
    )
    guard !receipts.isEmpty else {
      return .neutral(agentId)
    }

    var reliabilityTotal = 0.0
    var qualityTotal = 0.0
    var timelinessTotal = 0.0
    var costTotal = 0.0
    var evidenceTotal = 0.0
    var verifiedRuns = 0
    var disputedRuns = 0
    var timeoutRuns = 0
    var lastEvidenceAt: Int64 = 0
    var verifierDomains = Set<String>()

    for receipt in receipts {
      let attestations = allAttestations.filter {
        $0.receiptId == receipt.receiptId &&
          $0.validationFailure(for: receipt, nowMillis: nowMillis) == nil
      }
      let failed = attestations.contains { $0.verdict == .failed }
      let passed = !failed && attestations.contains { $0.verdict == .passed }
      if passed {
        verifiedRuns += 1
        attestations
          .filter { $0.verdict == .passed }
          .forEach { verifierDomains.insert($0.signerId) }
      }
      if failed {
        disputedRuns += 1
      }
      if receipt.outcome == .timedOut {
        timeoutRuns += 1
      }

      let age = max(Int64(0), nowMillis - receipt.completedAtMillis)
      let recency = exp(-log(2.0) * Double(age) / reputationHalfLifeMillis)
      let provenanceWeight = receipt.provenance == .executorSigned ? 0.25 : 0.60
      let verificationWeight: Double
      if failed {
        verificationWeight = 1.25
      } else if passed {
        verificationWeight = 1.0
      } else {
        verificationWeight = provenanceWeight
      }
      let outcomeWeight: Double
      switch receipt.outcome {
      case .cancelled:
        outcomeWeight = 0.20
      case .rejected:
        outcomeWeight = 0.10
      case .succeeded, .partial, .failed, .timedOut:
        outcomeWeight = 1.0
      }
      let weight = recency * verificationWeight * outcomeWeight
      guard weight > 0.0 else {
        continue
      }

      let reliability = failed ? 0.0 : reliabilityValue(for: receipt.outcome)
      let quality: Double
      if failed {
        quality = 0.0
      } else if passed {
        quality = 1.0
      } else {
        quality = qualityValue(for: receipt.outcome)
      }
      let timeliness: Double
      if receipt.deadlineAtMillis <= 0 {
        timeliness = reliability
      } else if receipt.completedAtMillis <= receipt.deadlineAtMillis {
        timeliness = 1.0
      } else {
        timeliness = 0.0
      }
      let costEfficiency: Double
      if receipt.estimatedCostUnits <= 0 {
        costEfficiency = reliability > 0.0 ? 0.75 : 0.0
      } else if receipt.actualCostUnits <= receipt.estimatedCostUnits {
        costEfficiency = 1.0
      } else {
        costEfficiency = Double(receipt.estimatedCostUnits) / Double(max(receipt.actualCostUnits, 1))
      }

      reliabilityTotal += reliability * weight
      qualityTotal += quality * weight
      timelinessTotal += timeliness * weight
      costTotal += costEfficiency * weight
      evidenceTotal += weight
      lastEvidenceAt = max(
        max(lastEvidenceAt, receipt.completedAtMillis),
        attestations.map(\.createdAtMillis).max() ?? 0
      )
    }

    guard evidenceTotal > 0.0 else {
      return .neutral(agentId)
    }
    let reliability = posteriorPercent(success: reliabilityTotal, total: evidenceTotal)
    let quality = posteriorPercent(success: qualityTotal, total: evidenceTotal)
    let timeliness = posteriorPercent(success: timelinessTotal, total: evidenceTotal)
    let costEfficiency = posteriorPercent(success: costTotal, total: evidenceTotal)
    let score = clamp(
      Int((
        Double(reliability) * 0.45 +
          Double(quality) * 0.25 +
          Double(timeliness) * 0.15 +
          Double(costEfficiency) * 0.15
      ).rounded()),
      lower: 0,
      upper: 100
    )
    let confidence = clamp(
      Int(((1.0 - exp(-evidenceTotal / confidenceScale)) * 100.0).rounded()),
      lower: 0,
      upper: 100
    )
    let routingAdjustment: Int
    if confidence < minRoutingConfidence {
      routingAdjustment = 0
    } else {
      routingAdjustment = clamp(
        Int((Double(score - routingNeutralScore) * Double(confidence) / 100.0 * routingWeight).rounded()),
        lower: -maxRoutingAdjustment,
        upper: maxRoutingAdjustment
      )
    }

    return AgentReputationSnapshot(
      agentId: agentId,
      score: score,
      confidence: confidence,
      reliability: reliability,
      quality: quality,
      timeliness: timeliness,
      costEfficiency: costEfficiency,
      evaluatedRuns: receipts.count,
      independentlyVerifiedRuns: verifiedRuns,
      disputedRuns: disputedRuns,
      timeoutRuns: timeoutRuns,
      independentFailureDomains: verifierDomains.count,
      lastEvidenceAtMillis: lastEvidenceAt,
      routingAdjustment: routingAdjustment
    )
  }

  private static func latestReceipts(
    agentId: String,
    capabilities: Set<AgentCapability>,
    receipts: [AgentSignedExecutionReceipt]
  ) -> [AgentSignedExecutionReceipt] {
    var latestByRun: [String: AgentSignedExecutionReceipt] = [:]
    for receipt in receipts where receipt.agentId == agentId {
      if !capabilities.isEmpty && receipt.capabilities.isDisjoint(with: capabilities) {
        continue
      }
      guard let existing = latestByRun[receipt.runId] else {
        latestByRun[receipt.runId] = receipt
        continue
      }
      if receipt.completedAtMillis > existing.completedAtMillis ||
        (receipt.completedAtMillis == existing.completedAtMillis && receipt.receiptId > existing.receiptId) {
        latestByRun[receipt.runId] = receipt
      }
    }
    return Array(latestByRun.values)
  }

  private static func posteriorPercent(success: Double, total: Double) -> Int {
    clamp(
      Int(((priorSuccess + success) / (priorWeight + total) * 100.0).rounded()),
      lower: 0,
      upper: 100
    )
  }

  private static func reliabilityValue(for outcome: AgentReputationOutcome) -> Double {
    switch outcome {
    case .succeeded:
      return 1.0
    case .partial:
      return 0.60
    case .cancelled:
      return 0.50
    case .failed, .timedOut, .rejected:
      return 0.0
    }
  }

  private static func qualityValue(for outcome: AgentReputationOutcome) -> Double {
    switch outcome {
    case .succeeded:
      return 0.75
    case .partial, .cancelled:
      return 0.50
    case .failed, .timedOut, .rejected:
      return 0.0
    }
  }

  private static func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
    min(max(value, lower), upper)
  }

  private static let priorWeight = 2.0
  private static let priorSuccess = 1.4
  private static let confidenceScale = 5.0
  private static let minRoutingConfidence = 15
  private static let routingNeutralScore = 65
  private static let routingWeight = 4.0
  private static let maxRoutingAdjustment = 180
  private static let reputationHalfLifeMillis = Double(30 * 24 * 60 * 60 * 1_000)
}

enum AgentEndpointStatus: String, Codable, CaseIterable, Identifiable {
  case online = "ONLINE"
  case offline = "OFFLINE"
  case idle = "IDLE"
  case busy = "BUSY"
  case degraded = "DEGRADED"
  case updating = "UPDATING"
  case permissionRequired = "PERMISSION_REQUIRED"
  case unreachable = "UNREACHABLE"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentEndpointStatus {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .offline
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

enum AgentResourceType: String, Codable, CaseIterable, Identifiable {
  case onDeviceModel = "ON_DEVICE_MODEL"
  case remoteLocalModel = "REMOTE_LOCAL_MODEL"
  case cloudModel = "CLOUD_MODEL"
  case localAgent = "LOCAL_AGENT"
  case remoteAgent = "REMOTE_AGENT"
  case localTool = "LOCAL_TOOL"
  case localMcp = "LOCAL_MCP"
  case remoteMcp = "REMOTE_MCP"
  case cloudMcp = "CLOUD_MCP"
  case localSkill = "LOCAL_SKILL"
  case remoteSkill = "REMOTE_SKILL"
  case cloudSkill = "CLOUD_SKILL"
  case homeAssistant = "HOME_ASSISTANT"
  case customDevice = "CUSTOM_DEVICE"
  case knowledge = "KNOWLEDGE"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentResourceType {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .cloudModel
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

enum AgentResourceCost: String, Codable, CaseIterable, Comparable, Identifiable {
  case free = "FREE"
  case low = "LOW"
  case medium = "MEDIUM"
  case high = "HIGH"

  var id: String { rawValue }
  var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

  static func < (lhs: AgentResourceCost, rhs: AgentResourceCost) -> Bool {
    lhs.rank < rhs.rank
  }
}

enum AgentResourceLatency: String, Codable, CaseIterable, Comparable, Identifiable {
  case instant = "INSTANT"
  case fast = "FAST"
  case normal = "NORMAL"
  case slow = "SLOW"

  var id: String { rawValue }
  var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

  static func < (lhs: AgentResourceLatency, rhs: AgentResourceLatency) -> Bool {
    lhs.rank < rhs.rank
  }
}

enum AgentResourceQuality: String, Codable, CaseIterable, Comparable, Identifiable {
  case basic = "BASIC"
  case standard = "STANDARD"
  case strong = "STRONG"
  case frontier = "FRONTIER"

  var id: String { rawValue }
  var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

  static func < (lhs: AgentResourceQuality, rhs: AgentResourceQuality) -> Bool {
    lhs.rank < rhs.rank
  }
}

enum AgentResourceTrust: String, Codable, CaseIterable, Identifiable {
  case phoneSystem = "PHONE_SYSTEM"
  case verifiedPaired = "VERIFIED_PAIRED"
  case privateConfigured = "PRIVATE_CONFIGURED"
  case cloudConfigured = "CLOUD_CONFIGURED"
  case unknown = "UNKNOWN"

  var id: String { rawValue }
}

enum AgentResourceEnergy: String, Codable, CaseIterable, Comparable, Identifiable {
  case minimal = "MINIMAL"
  case low = "LOW"
  case moderate = "MODERATE"
  case high = "HIGH"

  var id: String { rawValue }
  var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

  static func < (lhs: AgentResourceEnergy, rhs: AgentResourceEnergy) -> Bool {
    lhs.rank < rhs.rank
  }

  static func fromWireValue(_ value: String?) -> AgentResourceEnergy {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .low
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

struct AgentProtocolRange: Codable, Equatable {
  var preferred: String
  var minimum: String
  var maximum: String
  var features: Set<String>

  init(
    preferred: String = "1.1",
    minimum: String = "1.0",
    maximum: String = "1.1",
    features: Set<String> = []
  ) {
    self.preferred = preferred
    self.minimum = minimum
    self.maximum = maximum
    self.features = features
  }
}

struct AgentRegistration: Codable, Equatable, Identifiable {
  var agentId: String
  var installationId: String
  var deviceId: String
  var providerId: String
  var displayName: String
  var kind: AgentConnectorKind
  var location: AgentResourceLocation
  var status: AgentEndpointStatus
  var capabilities: Set<AgentCapability>
  var toolIds: Set<String>
  var permissionScopes: Set<String>
  var `protocol`: AgentProtocolRange
  var connectionKind: AgentConnectionKind
  var cost: AgentResourceCost
  var latency: AgentResourceLatency
  var trust: AgentResourceTrust
  var activeRuns: Int
  var maxParallelRuns: Int
  var capabilitiesHash: String
  var failureDomain: String
  var runtimeFailureDomain: String
  var adapterType: String
  var independentlyUpgradeable: Bool
  var providerProfile: ProviderProfile?
  var lastHeartbeatMillis: Int64
  var updatedAtMillis: Int64

  var id: String { agentId }
  var hasCapacity: Bool { activeRuns < max(maxParallelRuns, 1) }

  init(
    agentId: String,
    installationId: String,
    deviceId: String,
    providerId: String,
    displayName: String,
    kind: AgentConnectorKind = .agent,
    location: AgentResourceLocation = .trustedDesktop,
    status: AgentEndpointStatus = .online,
    capabilities: Set<AgentCapability> = [.chat],
    toolIds: Set<String> = [],
    permissionScopes: Set<String> = [],
    protocol: AgentProtocolRange = AgentProtocolRange(),
    connectionKind: AgentConnectionKind = .signalasiLink,
    cost: AgentResourceCost = .free,
    latency: AgentResourceLatency = .normal,
    trust: AgentResourceTrust = .verifiedPaired,
    activeRuns: Int = 0,
    maxParallelRuns: Int = 1,
    capabilitiesHash: String = "",
    failureDomain: String = "",
    runtimeFailureDomain: String = "",
    adapterType: String = "",
    independentlyUpgradeable: Bool = true,
    providerProfile: ProviderProfile? = nil,
    lastHeartbeatMillis: Int64 = 0,
    updatedAtMillis: Int64 = 0
  ) {
    self.agentId = agentId
    self.installationId = installationId
    self.deviceId = deviceId
    self.providerId = providerId
    self.displayName = displayName
    self.kind = kind
    self.location = location
    self.status = status
    self.capabilities = capabilities
    self.toolIds = toolIds
    self.permissionScopes = permissionScopes
    self.`protocol` = `protocol`
    self.connectionKind = connectionKind
    self.cost = cost
    self.latency = latency
    self.trust = trust
    self.activeRuns = activeRuns
    self.maxParallelRuns = maxParallelRuns
    self.capabilitiesHash = capabilitiesHash
    self.failureDomain = failureDomain
    self.runtimeFailureDomain = runtimeFailureDomain
    self.adapterType = adapterType
    self.independentlyUpgradeable = independentlyUpgradeable
    self.providerProfile = providerProfile
    self.lastHeartbeatMillis = lastHeartbeatMillis
    self.updatedAtMillis = updatedAtMillis
  }

  enum CodingKeys: String, CodingKey {
    case agentId = "agent_id"
    case installationId = "installation_id"
    case deviceId = "device_id"
    case providerId = "provider_id"
    case displayName = "display_name"
    case kind
    case location
    case status
    case capabilities
    case toolIds = "tool_ids"
    case permissionScopes = "permission_scopes"
    case `protocol`
    case connectionKind = "connection_kind"
    case cost
    case latency
    case trust
    case activeRuns = "active_runs"
    case maxParallelRuns = "max_parallel_runs"
    case capabilitiesHash = "capabilities_hash"
    case failureDomain = "failure_domain"
    case runtimeFailureDomain = "runtime_failure_domain"
    case adapterType = "adapter_type"
    case independentlyUpgradeable = "independently_upgradeable"
    case providerProfile = "provider_profile"
    case lastHeartbeatMillis = "last_heartbeat_millis"
    case updatedAtMillis = "updated_at_millis"
  }
}

enum ProviderProfileKind: String, Codable, CaseIterable, Identifiable {
  case agent = "AGENT"
  case cloudModel = "CLOUD_MODEL"
  case localModel = "LOCAL_MODEL"

  var id: String { rawValue }
}

struct ProviderPricingProfile: Codable, Equatable {
  var tier: AgentResourceCost
  var inputMicrosPerMillionTokens: Int64?
  var outputMicrosPerMillionTokens: Int64?
  var currency: String
  var source: String

  init(
    tier: AgentResourceCost,
    inputMicrosPerMillionTokens: Int64? = nil,
    outputMicrosPerMillionTokens: Int64? = nil,
    currency: String = "USD",
    source: String = "catalog_tier"
  ) {
    self.tier = tier
    self.inputMicrosPerMillionTokens = inputMicrosPerMillionTokens
    self.outputMicrosPerMillionTokens = outputMicrosPerMillionTokens
    self.currency = currency.isEmpty ? "USD" : currency
    self.source = source.isEmpty ? "catalog_tier" : source
  }

  enum CodingKeys: String, CodingKey {
    case tier
    case inputMicrosPerMillionTokens = "input_micros_per_million_tokens"
    case outputMicrosPerMillionTokens = "output_micros_per_million_tokens"
    case currency
    case source
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      tier: ProviderProfileCatalog.cost(
        try container.decodeIfPresent(String.self, forKey: .tier),
        fallback: .free
      ),
      inputMicrosPerMillionTokens: try container.decodeIfPresent(Int64.self, forKey: .inputMicrosPerMillionTokens),
      outputMicrosPerMillionTokens: try container.decodeIfPresent(Int64.self, forKey: .outputMicrosPerMillionTokens),
      currency: try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD",
      source: try container.decodeIfPresent(String.self, forKey: .source) ?? "catalog_tier"
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(tier.rawValue.lowercased(), forKey: .tier)
    try container.encodeIfPresent(inputMicrosPerMillionTokens, forKey: .inputMicrosPerMillionTokens)
    try container.encodeIfPresent(outputMicrosPerMillionTokens, forKey: .outputMicrosPerMillionTokens)
    try container.encode(currency, forKey: .currency)
    try container.encode(source, forKey: .source)
  }
}

struct ProviderPerformanceProfile: Codable, Equatable {
  var attempts: Int
  var successes: Int
  var failures: Int
  var consecutiveFailures: Int
  var failureRate: Double
  var ewmaLatencyMs: Double
  var lastObservedAtMillis: Int64

  init(
    attempts: Int = 0,
    successes: Int = 0,
    failures: Int = 0,
    consecutiveFailures: Int = 0,
    failureRate: Double = 0,
    ewmaLatencyMs: Double = 0,
    lastObservedAtMillis: Int64 = 0
  ) {
    self.attempts = max(0, attempts)
    self.successes = max(0, successes)
    self.failures = max(0, failures)
    self.consecutiveFailures = max(0, consecutiveFailures)
    self.failureRate = min(max(failureRate, 0), 1)
    self.ewmaLatencyMs = max(0, ewmaLatencyMs)
    self.lastObservedAtMillis = max(0, lastObservedAtMillis)
  }

  enum CodingKeys: String, CodingKey {
    case attempts
    case successes
    case failures
    case consecutiveFailures = "consecutive_failures"
    case failureRate = "failure_rate"
    case ewmaLatencyMs = "ewma_latency_ms"
    case lastObservedAtMillis = "last_observed_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      attempts: try container.decodeIfPresent(Int.self, forKey: .attempts) ?? 0,
      successes: try container.decodeIfPresent(Int.self, forKey: .successes) ?? 0,
      failures: try container.decodeIfPresent(Int.self, forKey: .failures) ?? 0,
      consecutiveFailures: try container.decodeIfPresent(Int.self, forKey: .consecutiveFailures) ?? 0,
      failureRate: try container.decodeIfPresent(Double.self, forKey: .failureRate) ?? 0,
      ewmaLatencyMs: try container.decodeIfPresent(Double.self, forKey: .ewmaLatencyMs) ?? 0,
      lastObservedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .lastObservedAtMillis) ?? 0
    )
  }
}

struct ProviderProfile: Codable, Equatable, Identifiable {
  static let schemaVersion = 1

  var profileId: String
  var resourceId: String
  var providerId: String
  var productId: String
  var displayName: String
  var kind: ProviderProfileKind
  var location: AgentResourceLocation
  var status: AgentConnectorStatus
  var protocolFamily: String
  var adapterType: String
  var modelId: String
  var capabilities: Set<AgentCapability>
  var toolIds: Set<String>
  var contextWindowTokens: Int
  var maxOutputTokens: Int
  var maxParallelRuns: Int
  var supportsTools: Bool
  var supportsStreaming: Bool
  var supportsBackground: Bool
  var latency: AgentResourceLatency
  var quality: AgentResourceQuality
  var trust: AgentResourceTrust
  var failureDomain: String
  var endpointConfigured: Bool
  var credentialConfigured: Bool
  var pricing: ProviderPricingProfile
  var performance: ProviderPerformanceProfile
  var schemaVersion: Int
  var metadata: [String: String]

  var id: String { profileId }

  init(
    profileId: String,
    resourceId: String,
    providerId: String,
    productId: String,
    displayName: String,
    kind: ProviderProfileKind,
    location: AgentResourceLocation,
    status: AgentConnectorStatus,
    protocolFamily: String,
    adapterType: String,
    modelId: String = "",
    capabilities: Set<AgentCapability> = [],
    toolIds: Set<String> = [],
    contextWindowTokens: Int = 8_192,
    maxOutputTokens: Int = 4_096,
    maxParallelRuns: Int = 1,
    supportsTools: Bool = false,
    supportsStreaming: Bool = false,
    supportsBackground: Bool = false,
    latency: AgentResourceLatency = .normal,
    quality: AgentResourceQuality = .standard,
    trust: AgentResourceTrust = .unknown,
    failureDomain: String = "",
    endpointConfigured: Bool = false,
    credentialConfigured: Bool = false,
    pricing: ProviderPricingProfile = ProviderPricingProfile(tier: .free),
    performance: ProviderPerformanceProfile = ProviderPerformanceProfile(),
    schemaVersion: Int = ProviderProfile.schemaVersion,
    metadata: [String: String] = [:]
  ) {
    self.profileId = profileId
    self.resourceId = resourceId
    self.providerId = providerId
    self.productId = productId
    self.displayName = displayName
    self.kind = kind
    self.location = location
    self.status = status
    self.protocolFamily = protocolFamily
    self.adapterType = adapterType
    self.modelId = modelId
    self.capabilities = capabilities
    self.toolIds = toolIds
    self.contextWindowTokens = max(0, contextWindowTokens)
    self.maxOutputTokens = max(0, maxOutputTokens)
    self.maxParallelRuns = max(1, maxParallelRuns)
    self.supportsTools = supportsTools
    self.supportsStreaming = supportsStreaming
    self.supportsBackground = supportsBackground
    self.latency = latency
    self.quality = quality
    self.trust = trust
    self.failureDomain = failureDomain
    self.endpointConfigured = endpointConfigured
    self.credentialConfigured = credentialConfigured
    self.pricing = pricing
    self.performance = performance
    self.schemaVersion = schemaVersion
    self.metadata = metadata
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case profileId = "profile_id"
    case resourceId = "resource_id"
    case providerId = "provider_id"
    case productId = "product_id"
    case displayName = "display_name"
    case kind
    case location
    case status
    case protocolFamily = "protocol_family"
    case adapterType = "adapter_type"
    case modelId = "model_id"
    case capabilities
    case toolIds = "tool_ids"
    case contextWindowTokens = "context_window_tokens"
    case maxOutputTokens = "max_output_tokens"
    case maxParallelRuns = "max_parallel_runs"
    case supportsTools = "supports_tools"
    case supportsStreaming = "supports_streaming"
    case supportsBackground = "supports_background"
    case latency = "latency_tier"
    case quality = "quality_tier"
    case trust
    case failureDomain = "failure_domain"
    case endpointConfigured = "endpoint_configured"
    case credentialConfigured = "credential_configured"
    case pricing
    case performance
    case metadata
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let schema = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
    guard schema == Self.schemaVersion else {
      throw DecodingError.dataCorruptedError(
        forKey: .schemaVersion,
        in: container,
        debugDescription: "Unsupported provider profile schema"
      )
    }
    self.init(
      profileId: try container.decodeIfPresent(String.self, forKey: .profileId) ?? "",
      resourceId: try container.decodeIfPresent(String.self, forKey: .resourceId) ?? "",
      providerId: try container.decodeIfPresent(String.self, forKey: .providerId) ?? "",
      productId: try container.decodeIfPresent(String.self, forKey: .productId) ?? "",
      displayName: try container.decodeIfPresent(String.self, forKey: .displayName) ?? "",
      kind: ProviderProfileCatalog.kind(
        try container.decodeIfPresent(String.self, forKey: .kind),
        fallback: .agent
      ),
      location: AgentResourceLocation.fromWireValue(try container.decodeIfPresent(String.self, forKey: .location)),
      status: ProviderProfileCatalog.connectorStatus(try container.decodeIfPresent(String.self, forKey: .status)),
      protocolFamily: try container.decodeIfPresent(String.self, forKey: .protocolFamily) ?? "",
      adapterType: try container.decodeIfPresent(String.self, forKey: .adapterType) ?? "",
      modelId: try container.decodeIfPresent(String.self, forKey: .modelId) ?? "",
      capabilities: ProviderProfileCatalog.capabilities(
        try container.decodeIfPresent([String].self, forKey: .capabilities)
      ),
      toolIds: Set(try container.decodeIfPresent([String].self, forKey: .toolIds) ?? []),
      contextWindowTokens: try container.decodeIfPresent(Int.self, forKey: .contextWindowTokens) ?? 8_192,
      maxOutputTokens: try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens) ?? 4_096,
      maxParallelRuns: try container.decodeIfPresent(Int.self, forKey: .maxParallelRuns) ?? 1,
      supportsTools: try container.decodeIfPresent(Bool.self, forKey: .supportsTools) ?? false,
      supportsStreaming: try container.decodeIfPresent(Bool.self, forKey: .supportsStreaming) ?? false,
      supportsBackground: try container.decodeIfPresent(Bool.self, forKey: .supportsBackground) ?? false,
      latency: ProviderProfileCatalog.latency(
        try container.decodeIfPresent(String.self, forKey: .latency),
        fallback: .normal
      ),
      quality: ProviderProfileCatalog.quality(
        try container.decodeIfPresent(String.self, forKey: .quality),
        fallback: .standard
      ),
      trust: ProviderProfileCatalog.trust(
        try container.decodeIfPresent(String.self, forKey: .trust),
        fallback: .unknown
      ),
      failureDomain: try container.decodeIfPresent(String.self, forKey: .failureDomain) ?? "",
      endpointConfigured: try container.decodeIfPresent(Bool.self, forKey: .endpointConfigured) ?? false,
      credentialConfigured: try container.decodeIfPresent(Bool.self, forKey: .credentialConfigured) ?? false,
      pricing: try container.decodeIfPresent(ProviderPricingProfile.self, forKey: .pricing) ??
        ProviderPricingProfile(tier: .free),
      performance: try container.decodeIfPresent(ProviderPerformanceProfile.self, forKey: .performance) ??
        ProviderPerformanceProfile(),
      schemaVersion: schema,
      metadata: try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(profileId, forKey: .profileId)
    try container.encode(resourceId, forKey: .resourceId)
    try container.encode(providerId, forKey: .providerId)
    try container.encode(productId, forKey: .productId)
    try container.encode(displayName, forKey: .displayName)
    try container.encode(kind.rawValue.lowercased(), forKey: .kind)
    try container.encode(location.rawValue.lowercased(), forKey: .location)
    try container.encode(status.rawValue.lowercased(), forKey: .status)
    try container.encode(protocolFamily, forKey: .protocolFamily)
    try container.encode(adapterType, forKey: .adapterType)
    try container.encode(modelId, forKey: .modelId)
    try container.encode(capabilities.map(\.wireValue).sorted(), forKey: .capabilities)
    try container.encode(toolIds.sorted(), forKey: .toolIds)
    try container.encode(contextWindowTokens, forKey: .contextWindowTokens)
    try container.encode(maxOutputTokens, forKey: .maxOutputTokens)
    try container.encode(maxParallelRuns, forKey: .maxParallelRuns)
    try container.encode(supportsTools, forKey: .supportsTools)
    try container.encode(supportsStreaming, forKey: .supportsStreaming)
    try container.encode(supportsBackground, forKey: .supportsBackground)
    try container.encode(latency.rawValue.lowercased(), forKey: .latency)
    try container.encode(quality.rawValue.lowercased(), forKey: .quality)
    try container.encode(trust.rawValue.lowercased(), forKey: .trust)
    try container.encode(failureDomain, forKey: .failureDomain)
    try container.encode(endpointConfigured, forKey: .endpointConfigured)
    try container.encode(credentialConfigured, forKey: .credentialConfigured)
    try container.encode(pricing, forKey: .pricing)
    try container.encode(performance, forKey: .performance)
    try container.encode(metadata, forKey: .metadata)
  }
}

struct ModelProviderProfileDefinition: Equatable, Identifiable {
  var providerId: String
  var displayName: String
  var protocolFamily: String
  var location: AgentResourceLocation
  var cost: AgentResourceCost
  var latency: AgentResourceLatency
  var quality: AgentResourceQuality
  var contextWindowTokens: Int
  var supportsTools: Bool
  var supportsStreaming: Bool

  var id: String { providerId }
}

enum ProviderProfileCatalog {
  static let modelProviders: [ModelProviderProfileDefinition] = [
    ModelProviderProfileDefinition(
      providerId: "openai",
      displayName: "OpenAI",
      protocolFamily: "openai",
      location: .cloud,
      cost: .medium,
      latency: .normal,
      quality: .frontier,
      contextWindowTokens: 128_000,
      supportsTools: true,
      supportsStreaming: true
    ),
    ModelProviderProfileDefinition(
      providerId: "anthropic",
      displayName: "Claude",
      protocolFamily: "anthropic",
      location: .cloud,
      cost: .medium,
      latency: .normal,
      quality: .frontier,
      contextWindowTokens: 200_000,
      supportsTools: true,
      supportsStreaming: true
    ),
    ModelProviderProfileDefinition(
      providerId: "gemini",
      displayName: "Gemini",
      protocolFamily: "gemini",
      location: .cloud,
      cost: .medium,
      latency: .fast,
      quality: .frontier,
      contextWindowTokens: 1_000_000,
      supportsTools: true,
      supportsStreaming: true
    ),
    ModelProviderProfileDefinition(
      providerId: "deepseek",
      displayName: "DeepSeek",
      protocolFamily: "openai",
      location: .cloud,
      cost: .low,
      latency: .normal,
      quality: .frontier,
      contextWindowTokens: 128_000,
      supportsTools: true,
      supportsStreaming: true
    ),
    ModelProviderProfileDefinition(
      providerId: "qwen",
      displayName: "Qwen",
      protocolFamily: "openai",
      location: .cloud,
      cost: .low,
      latency: .normal,
      quality: .strong,
      contextWindowTokens: 131_072,
      supportsTools: true,
      supportsStreaming: true
    ),
    ModelProviderProfileDefinition(
      providerId: "ollama",
      displayName: "Ollama",
      protocolFamily: "ollama",
      location: .privateNetwork,
      cost: .free,
      latency: .fast,
      quality: .standard,
      contextWindowTokens: 32_768,
      supportsTools: false,
      supportsStreaming: true
    ),
    ModelProviderProfileDefinition(
      providerId: "lm-studio",
      displayName: "LM Studio",
      protocolFamily: "openai",
      location: .privateNetwork,
      cost: .free,
      latency: .fast,
      quality: .standard,
      contextWindowTokens: 32_768,
      supportsTools: false,
      supportsStreaming: true
    ),
    ModelProviderProfileDefinition(
      providerId: "openrouter",
      displayName: "OpenRouter",
      protocolFamily: "openai",
      location: .cloud,
      cost: .medium,
      latency: .normal,
      quality: .frontier,
      contextWindowTokens: 128_000,
      supportsTools: true,
      supportsStreaming: true
    )
  ]

  static func fromCloudContact(
    _ contact: SignalASIContact,
    apiKey: String? = nil,
    status: AgentConnectorStatus = .available,
    performance: ProviderPerformanceProfile = ProviderPerformanceProfile()
  ) -> ProviderProfile {
    let model = contact.selectedCloudModel ?? CloudModelConfig(
      id: contact.id,
      displayName: contact.cloudProvider,
      provider: contact.cloudProvider,
      modelId: "",
      endpoint: "",
      apiStyle: .openAICompatible,
      keychainAccount: "",
      updatedAt: Date(timeIntervalSince1970: 0)
    )
    return fromCloudModel(
      resourceId: contact.id,
      provider: contact.cloudProvider,
      displayName: contact.cloudProvider.isEmpty ? contact.displayTitle : contact.cloudProvider,
      model: model,
      apiKey: apiKey,
      status: status,
      performance: performance
    )
  }

  static func fromCloudModel(
    resourceId: String,
    provider: String,
    displayName: String = "",
    model: CloudModelConfig,
    apiKey: String? = nil,
    status: AgentConnectorStatus = .available,
    performance: ProviderPerformanceProfile = ProviderPerformanceProfile()
  ) -> ProviderProfile {
    let providerId = normalizeProviderId(provider.isEmpty ? model.provider : provider)
    let definition = definition(providerId)
    let endpoint = model.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    let local = isLocalEndpoint(endpoint) || definition.location == .privateNetwork
    var capabilities: Set<AgentCapability> = [.chat, .reasoning]
    if definition.supportsTools {
      capabilities.formUnion([.toolUse, .liveData])
    }
    if local {
      capabilities.insert(.localInference)
    }
    let profileName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? definition.displayName
      : displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let protocolFamily = model.apiStyle.rawValue.isEmpty ? definition.protocolFamily : model.apiStyle.rawValue
    return ProviderProfile(
      profileId: "model:\(providerId)",
      resourceId: resourceId.isEmpty ? "cloud:\(providerId)" : resourceId,
      providerId: providerId,
      productId: providerId,
      displayName: profileName,
      kind: local ? .localModel : .cloudModel,
      location: local ? .privateNetwork : definition.location,
      status: status,
      protocolFamily: protocolFamily,
      adapterType: "\(definition.protocolFamily)-model-api",
      modelId: model.modelId,
      capabilities: capabilities,
      contextWindowTokens: max(4_096, contextWindowTokens(for: model, fallback: definition.contextWindowTokens)),
      maxOutputTokens: max(512, maxOutputTokens(for: model)),
      maxParallelRuns: local ? 2 : 4,
      supportsTools: definition.supportsTools,
      supportsStreaming: definition.supportsStreaming,
      supportsBackground: true,
      latency: definition.latency,
      quality: definition.quality,
      trust: local ? .privateConfigured : .cloudConfigured,
      failureDomain: local ? "private-model:\(providerId)" : "cloud-model:\(providerId)",
      endpointConfigured: !endpoint.isEmpty,
      credentialConfigured: local || CloudModelCredentialPolicy.isStoredCredential(apiKey),
      pricing: ProviderPricingProfile(tier: definition.cost),
      performance: performance,
      metadata: ["native_product_identity": providerId]
    )
  }

  static func fromRegistration(
    _ registration: AgentRegistration,
    existing: ProviderProfile? = nil
  ) -> ProviderProfile {
    let base = existing ?? registration.providerProfile ?? agentProfile(
      resourceId: registration.agentId,
      displayName: registration.displayName,
      providerId: registration.providerId.isEmpty ? registration.agentId : registration.providerId,
      adapterType: registration.adapterType,
      location: registration.location,
      status: registration.status.toConnectorStatus(),
      capabilities: registration.capabilities,
      toolIds: registration.toolIds,
      cost: registration.cost,
      latency: registration.latency,
      trust: registration.trust,
      failureDomain: registration.failureDomain,
      maxParallelRuns: registration.maxParallelRuns
    )
    return ProviderProfile(
      profileId: base.profileId,
      resourceId: registration.agentId,
      providerId: registration.providerId.isEmpty ? base.providerId : registration.providerId,
      productId: base.productId,
      displayName: registration.displayName,
      kind: .agent,
      location: registration.location,
      status: registration.status.toConnectorStatus(),
      protocolFamily: base.protocolFamily,
      adapterType: registration.adapterType.isEmpty ? base.adapterType : registration.adapterType,
      modelId: base.modelId,
      capabilities: registration.capabilities,
      toolIds: registration.toolIds,
      contextWindowTokens: base.contextWindowTokens,
      maxOutputTokens: base.maxOutputTokens,
      maxParallelRuns: max(1, registration.maxParallelRuns),
      supportsTools: base.supportsTools,
      supportsStreaming: base.supportsStreaming,
      supportsBackground: base.supportsBackground,
      latency: registration.latency,
      quality: base.quality,
      trust: registration.trust,
      failureDomain: registration.failureDomain.isEmpty ? base.failureDomain : registration.failureDomain,
      endpointConfigured: true,
      credentialConfigured: true,
      pricing: ProviderPricingProfile(
        tier: registration.cost,
        inputMicrosPerMillionTokens: base.pricing.inputMicrosPerMillionTokens,
        outputMicrosPerMillionTokens: base.pricing.outputMicrosPerMillionTokens,
        currency: base.pricing.currency,
        source: base.pricing.source
      ),
      performance: base.performance,
      metadata: base.metadata
    )
  }

  static func fromTarget(_ target: AgentCallableTarget) -> ProviderProfile {
    if let providerProfile = target.providerProfile {
      return providerProfile
    }
    if target.kind == .model {
      let providerId = providerIdForTarget(target)
      let definition = definition(providerId)
      let local = target.capabilities.contains(.localInference) || definition.location == .privateNetwork
      return ProviderProfile(
        profileId: "model:\(providerId)",
        resourceId: target.id,
        providerId: providerId,
        productId: providerId,
        displayName: target.title,
        kind: local ? .localModel : .cloudModel,
        location: local ? .privateNetwork : definition.location,
        status: target.status,
        protocolFamily: definition.protocolFamily,
        adapterType: target.adapterType.isEmpty ? "model-api" : target.adapterType,
        capabilities: Set(target.capabilities),
        contextWindowTokens: definition.contextWindowTokens,
        maxOutputTokens: 4_096,
        maxParallelRuns: local ? 2 : 4,
        supportsTools: definition.supportsTools,
        supportsStreaming: definition.supportsStreaming,
        supportsBackground: true,
        latency: definition.latency,
        quality: definition.quality,
        trust: local ? .privateConfigured : .cloudConfigured,
        failureDomain: target.failureDomain.isEmpty ? "model:\(providerId)" : target.failureDomain,
        endpointConfigured: false,
        credentialConfigured: local,
        pricing: ProviderPricingProfile(tier: definition.cost),
        metadata: ["native_product_identity": providerId]
      )
    }
    return agentProfile(
      resourceId: target.id,
      displayName: target.title,
      providerId: providerIdForTarget(target),
      adapterType: target.adapterType,
      location: target.kind == .agent || target.failureDomain.hasPrefix("desktop") ? .trustedDesktop : .cloud,
      status: target.status,
      capabilities: Set(target.capabilities),
      failureDomain: target.failureDomain,
      maxParallelRuns: 1
    )
  }

  static func normalizeProviderId(_ value: String) -> String {
    let normalized = value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "_", with: "-")
      .replacingOccurrences(of: " ", with: "-")
    switch normalized {
    case "claude", "anthropic-claude":
      return "anthropic"
    case "google", "google-gemini":
      return "gemini"
    case "lmstudio":
      return "lm-studio"
    case "open-router":
      return "openrouter"
    case "dashscope":
      return "qwen"
    default:
      return normalized.isEmpty ? "custom" : normalized
    }
  }

  static func kind(_ value: String?, fallback: ProviderProfileKind) -> ProviderProfileKind {
    ProviderProfileKind.allCases.first { $0.rawValue == token(value) } ?? fallback
  }

  static func cost(_ value: String?, fallback: AgentResourceCost) -> AgentResourceCost {
    AgentResourceCost.allCases.first { $0.rawValue == token(value) } ?? fallback
  }

  static func latency(_ value: String?, fallback: AgentResourceLatency) -> AgentResourceLatency {
    AgentResourceLatency.allCases.first { $0.rawValue == token(value) } ?? fallback
  }

  static func quality(_ value: String?, fallback: AgentResourceQuality) -> AgentResourceQuality {
    AgentResourceQuality.allCases.first { $0.rawValue == token(value) } ?? fallback
  }

  static func trust(_ value: String?, fallback: AgentResourceTrust) -> AgentResourceTrust {
    AgentResourceTrust.allCases.first { $0.rawValue == token(value) } ?? fallback
  }

  static func capabilities(_ values: [String]?) -> Set<AgentCapability> {
    Set((values ?? []).compactMap(AgentCapability.fromWireValue))
  }

  static func connectorStatus(_ value: String?) -> AgentConnectorStatus {
    switch token(value) {
    case "READY", "CONFIGURED", "ONLINE", "AVAILABLE", "BUSY", "IDLE", "DEGRADED":
      return .available
    case "NEEDS_SETUP", "NOT_CONFIGURED", "PERMISSION_REQUIRED", "UPDATING":
      return .needsSetup
    default:
      return .disconnected
    }
  }

  private static func agentProfile(
    resourceId: String,
    displayName: String,
    providerId: String,
    adapterType: String,
    location: AgentResourceLocation,
    status: AgentConnectorStatus,
    capabilities: Set<AgentCapability>,
    toolIds: Set<String> = [],
    cost: AgentResourceCost = .free,
    latency: AgentResourceLatency = .normal,
    trust: AgentResourceTrust = .verifiedPaired,
    failureDomain: String,
    maxParallelRuns: Int
  ) -> ProviderProfile {
    let productId = normalizeProductId(resourceId)
    return ProviderProfile(
      profileId: "agent:\(resourceId)",
      resourceId: resourceId,
      providerId: providerId.isEmpty ? productId : providerId,
      productId: productId,
      displayName: displayName,
      kind: .agent,
      location: location,
      status: status,
      protocolFamily: "signalasi-agent-adapter",
      adapterType: adapterType.isEmpty ? "\(productId)-native-adapter" : adapterType,
      capabilities: capabilities,
      toolIds: toolIds,
      contextWindowTokens: 64_000,
      maxOutputTokens: 16_000,
      maxParallelRuns: max(1, maxParallelRuns),
      supportsTools: !capabilities.isDisjoint(with: [.toolUse, .code, .taskExecution]),
      supportsStreaming: true,
      supportsBackground: capabilities.contains(.taskExecution),
      latency: latency,
      quality: .strong,
      trust: trust,
      failureDomain: failureDomain.isEmpty ? "agent:\(resourceId)" : failureDomain,
      endpointConfigured: true,
      credentialConfigured: true,
      pricing: ProviderPricingProfile(tier: cost),
      metadata: ["native_product_identity": productId]
    )
  }

  private static func providerIdForTarget(_ target: AgentCallableTarget) -> String {
    let identity = "\(target.id) \(target.title)".lowercased()
    if identity.contains("openrouter") { return "openrouter" }
    if identity.contains("deepseek") { return "deepseek" }
    if identity.contains("qwen") { return "qwen" }
    if identity.contains("gemini") { return "gemini" }
    if identity.contains("claude") || identity.contains("anthropic") { return "anthropic" }
    if identity.contains("ollama") { return "ollama" }
    if identity.contains("lm studio") || identity.contains("lm-studio") { return "lm-studio" }
    if identity.contains("openai") || target.id == "cloud-models" { return "openai" }
    return normalizeProductId(target.id)
  }

  private static func normalizeProductId(_ resourceId: String) -> String {
    let id = resourceId
      .split(separator: ":")
      .last
      .map(String.init)?
      .lowercased() ?? resourceId.lowercased()
    return id == "claude-code" ? "claude" : id
  }

  private static func definition(_ providerId: String) -> ModelProviderProfileDefinition {
    modelProviders.first { $0.providerId == providerId } ?? ModelProviderProfileDefinition(
      providerId: providerId.isEmpty ? "custom" : providerId,
      displayName: providerId.isEmpty ? "Custom" : providerId,
      protocolFamily: "openai",
      location: .cloud,
      cost: .medium,
      latency: .normal,
      quality: .strong,
      contextWindowTokens: 64_000,
      supportsTools: true,
      supportsStreaming: true
    )
  }

  private static func isLocalEndpoint(_ endpoint: String) -> Bool {
    let value = endpoint.lowercased()
    return ["127.0.0.1", "localhost", "192.168.", "10.", "172.16."].contains { value.contains($0) }
  }

  private static func contextWindowTokens(for model: CloudModelConfig, fallback: Int) -> Int {
    let lower = model.modelId.lowercased()
    if lower.contains("gemini") { return max(fallback, 1_000_000) }
    if lower.contains("claude") { return max(fallback, 200_000) }
    if lower.contains("qwen") { return max(fallback, 131_072) }
    return fallback
  }

  private static func maxOutputTokens(for model: CloudModelConfig) -> Int {
    let lower = model.modelId.lowercased()
    if lower.contains("mini") || lower.contains("flash") { return 8_192 }
    return 4_096
  }

  private static func token(_ value: String?) -> String {
    value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
  }
}

private extension AgentEndpointStatus {
  func toConnectorStatus() -> AgentConnectorStatus {
    switch self {
    case .online, .idle, .busy:
      return .available
    case .permissionRequired, .updating:
      return .needsSetup
    case .offline, .degraded, .unreachable:
      return .disconnected
    }
  }
}

struct AgentNetworkSearchQuery: Codable, Equatable {
  static let defaultPageSize = 24
  static let maxPageSize = 100

  var text: String
  var requiredCapabilities: Set<AgentCapability>
  var preferredCapabilities: Set<AgentCapability>
  var kinds: Set<AgentConnectorKind>
  var locations: Set<AgentResourceLocation>
  var statuses: Set<AgentEndpointStatus>
  var providerIds: Set<String>
  var deviceIds: Set<String>
  var excludedAgentIds: Set<String>
  var trustedOnly: Bool
  var routableOnly: Bool
  var includeAtCapacity: Bool
  var maximumCost: AgentResourceCost?
  var maximumLatency: AgentResourceLatency?
  var minimumReputationScore: Int?
  var minimumReputationConfidence: Int
  var pageSize: Int
  var cursor: String

  init(
    text: String = "",
    requiredCapabilities: Set<AgentCapability> = [],
    preferredCapabilities: Set<AgentCapability> = [],
    kinds: Set<AgentConnectorKind> = [],
    locations: Set<AgentResourceLocation> = [],
    statuses: Set<AgentEndpointStatus> = [],
    providerIds: Set<String> = [],
    deviceIds: Set<String> = [],
    excludedAgentIds: Set<String> = [],
    trustedOnly: Bool = false,
    routableOnly: Bool = true,
    includeAtCapacity: Bool = false,
    maximumCost: AgentResourceCost? = nil,
    maximumLatency: AgentResourceLatency? = nil,
    minimumReputationScore: Int? = nil,
    minimumReputationConfidence: Int = 40,
    pageSize: Int = Self.defaultPageSize,
    cursor: String = ""
  ) {
    self.text = text
    self.requiredCapabilities = requiredCapabilities
    self.preferredCapabilities = preferredCapabilities
    self.kinds = kinds
    self.locations = locations
    self.statuses = statuses
    self.providerIds = providerIds
    self.deviceIds = deviceIds
    self.excludedAgentIds = excludedAgentIds
    self.trustedOnly = trustedOnly
    self.routableOnly = routableOnly
    self.includeAtCapacity = includeAtCapacity
    self.maximumCost = maximumCost
    self.maximumLatency = maximumLatency
    self.minimumReputationScore = minimumReputationScore
    self.minimumReputationConfidence = minimumReputationConfidence
    self.pageSize = pageSize
    self.cursor = cursor
  }

  enum CodingKeys: String, CodingKey {
    case text
    case requiredCapabilities = "required_capabilities"
    case preferredCapabilities = "preferred_capabilities"
    case kinds
    case locations
    case statuses
    case providerIds = "provider_ids"
    case deviceIds = "device_ids"
    case excludedAgentIds = "excluded_agent_ids"
    case trustedOnly = "trusted_only"
    case routableOnly = "routable_only"
    case includeAtCapacity = "include_at_capacity"
    case maximumCost = "maximum_cost"
    case maximumLatency = "maximum_latency"
    case minimumReputationScore = "minimum_reputation_score"
    case minimumReputationConfidence = "minimum_reputation_confidence"
    case pageSize = "page_size"
    case cursor
  }
}

struct AgentNetworkSearchHit: Codable, Equatable {
  var registration: AgentRegistration
  var score: Int
  var matchedCapabilities: Set<AgentCapability>
  var reasons: [String]
  var reputation: AgentReputationSnapshot

  enum CodingKeys: String, CodingKey {
    case registration
    case score
    case matchedCapabilities = "matched_capabilities"
    case reasons
    case reputation
  }
}

struct AgentNetworkSearchPage: Codable, Equatable {
  var queryId: String
  var revision: Int64
  var hits: [AgentNetworkSearchHit]
  var totalMatches: Int
  var nextCursor: String
  var cursorReset: Bool
  var generatedAtMillis: Int64

  enum CodingKeys: String, CodingKey {
    case queryId = "query_id"
    case revision
    case hits
    case totalMatches = "total_matches"
    case nextCursor = "next_cursor"
    case cursorReset = "cursor_reset"
    case generatedAtMillis = "generated_at_millis"
  }
}

final class AgentNetworkIndex {
  private var registrationsById: [String: AgentRegistration] = [:]
  private var order: [String] = []
  private var currentRevision: Int64 = 0
  private var reputationsByAgentId: [String: AgentReputationSnapshot] = [:]
  private var reputationRevision: Int64 = 0

  init(
    _ registrations: [AgentRegistration] = [],
    reputations: [String: AgentReputationSnapshot] = [:],
    reputationRevision: Int64 = 0
  ) {
    for registration in registrations where registrationsById[registration.agentId] == nil {
      registrationsById[registration.agentId] = registration
      order.append(registration.agentId)
    }
    if !registrationsById.isEmpty {
      currentRevision = 1
    }
    self.reputationsByAgentId = reputations
    self.reputationRevision = reputationRevision
  }

  func size() -> Int {
    registrationsById.count
  }

  func revision() -> Int64 {
    effectiveRevision()
  }

  func get(_ agentId: String, nowMillis: Int64 = AgentRemoteApprovalClock.nowMillis()) -> AgentRegistration? {
    registrationsById[agentId]?.withEffectiveNetworkStatus(nowMillis: nowMillis)
  }

  func upsert(_ registration: AgentRegistration) {
    let previous = registrationsById[registration.agentId]
    guard previous != registration else {
      return
    }
    if previous == nil {
      order.append(registration.agentId)
    }
    registrationsById[registration.agentId] = registration
    currentRevision += 1
  }

  func replaceReputations(_ reputations: [String: AgentReputationSnapshot], revision: Int64) {
    reputationsByAgentId = reputations
    reputationRevision = revision
  }

  func search(
    _ query: AgentNetworkSearchQuery,
    nowMillis: Int64 = AgentRemoteApprovalClock.nowMillis()
  ) -> AgentNetworkSearchPage {
    var normalizedQuery = query
    normalizedQuery.pageSize = min(max(query.pageSize, 1), AgentNetworkSearchQuery.maxPageSize)
    let searchRevision = effectiveRevision()
    let queryId = fingerprint(normalizedQuery)
    let inferred = inferredCapabilities(from: normalizedQuery.text)
    let preferredCapabilities = normalizedQuery.preferredCapabilities.union(inferred)
    let queryTokens = searchTokens(normalizedQuery.text)

    let ranked = order
      .compactMap { registrationsById[$0] }
      .map { $0.withEffectiveNetworkStatus(nowMillis: nowMillis) }
      .filter { matches($0, query: normalizedQuery, inferred: inferred, preferred: preferredCapabilities, nowMillis: nowMillis) }
      .map {
        toSearchHit(
          registration: $0,
          query: normalizedQuery,
          preferredCapabilities: preferredCapabilities,
          queryTokens: queryTokens,
          nowMillis: nowMillis
        )
      }
      .sorted {
        if $0.score != $1.score {
          return $0.score > $1.score
        }
        let lhsName = $0.registration.displayName.lowercased()
        let rhsName = $1.registration.displayName.lowercased()
        if lhsName != rhsName {
          return lhsName < rhsName
        }
        return $0.registration.agentId < $1.registration.agentId
      }

    let decodedCursor = AgentNetworkCursor.decode(normalizedQuery.cursor)
    let cursorValid = decodedCursor?.revision == searchRevision && decodedCursor?.queryId == queryId
    let cursorIndex = cursorValid
      ? ranked.firstIndex { $0.registration.agentId == decodedCursor?.lastAgentId } ?? -1
      : -1
    let cursorReset = !normalizedQuery.cursor.isEmpty && (!cursorValid || cursorIndex < 0)
    let startIndex = cursorValid && cursorIndex >= 0 ? cursorIndex + 1 : 0
    let endIndex = min(startIndex + normalizedQuery.pageSize, ranked.count)
    let hits = startIndex < ranked.count ? Array(ranked[startIndex..<endIndex]) : []
    let nextCursor = endIndex < ranked.count && !hits.isEmpty
      ? AgentNetworkCursor(revision: searchRevision, queryId: queryId, lastAgentId: hits.last?.registration.agentId ?? "").encode()
      : ""
    return AgentNetworkSearchPage(
      queryId: queryId,
      revision: searchRevision,
      hits: hits,
      totalMatches: ranked.count,
      nextCursor: nextCursor,
      cursorReset: cursorReset,
      generatedAtMillis: nowMillis
    )
  }

  private func matches(
    _ registration: AgentRegistration,
    query: AgentNetworkSearchQuery,
    inferred: Set<AgentCapability>,
    preferred: Set<AgentCapability>,
    nowMillis: Int64
  ) -> Bool {
    if query.excludedAgentIds.contains(registration.agentId) { return false }
    if !registration.capabilities.isSuperset(of: query.requiredCapabilities) { return false }
    if !query.kinds.isEmpty && !query.kinds.contains(registration.kind) { return false }
    if !query.locations.isEmpty && !query.locations.contains(registration.location) { return false }
    if !query.statuses.isEmpty && !query.statuses.contains(registration.status) { return false }
    if !query.providerIds.isEmpty &&
      !query.providerIds.map(normalizeSearchText).contains(normalizeSearchText(registration.providerId)) {
      return false
    }
    if !query.deviceIds.isEmpty &&
      !query.deviceIds.map(normalizeSearchText).contains(normalizeSearchText(registration.deviceId)) {
      return false
    }
    if query.trustedOnly && registration.trust == .unknown { return false }
    if let maximumCost = query.maximumCost, registration.cost > maximumCost { return false }
    if let maximumLatency = query.maximumLatency, registration.latency > maximumLatency { return false }
    if query.routableOnly && !Self.routableStates.contains(registration.status) { return false }
    if query.routableOnly && !query.includeAtCapacity && !registration.hasCapacity { return false }
    if !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let tokenMatches = !registration.indexTokens().isDisjoint(with: searchTokens(query.text))
      let capabilityMatches = inferred.isEmpty || !registration.capabilities.isDisjoint(with: inferred)
      if !tokenMatches && !capabilityMatches {
        return false
      }
    }
    if let minimumReputation = query.minimumReputationScore {
      let reputation = reputation(for: registration, capabilities: query.requiredCapabilities.union(preferred))
      let minimumConfidence = min(max(query.minimumReputationConfidence, 0), 100)
      if reputation.confidence >= minimumConfidence && reputation.score < min(max(minimumReputation, 0), 100) {
        return false
      }
    }
    return true
  }

  private func toSearchHit(
    registration: AgentRegistration,
    query: AgentNetworkSearchQuery,
    preferredCapabilities: Set<AgentCapability>,
    queryTokens: Set<String>,
    nowMillis: Int64
  ) -> AgentNetworkSearchHit {
    var reasons: [String] = []
    var score = 0
    let normalizedText = normalizeSearchText(query.text)
    let searchableFields = [
      registration.agentId,
      registration.displayName,
      registration.providerId,
      registration.deviceId,
      registration.adapterType
    ].map(normalizeSearchText).filter { !$0.isEmpty }
    if !normalizedText.isEmpty {
      if searchableFields.contains(normalizedText) {
        score += 1_200
        reasons.append("identity_exact")
      } else if searchableFields.contains(where: { $0.hasPrefix(normalizedText) }) {
        score += 760
        reasons.append("identity_prefix")
      } else if searchableFields.contains(where: { $0.contains(normalizedText) }) {
        score += 520
        reasons.append("identity_contains")
      }
      let tokenMatches = registration.indexTokens().intersection(queryTokens)
      if !tokenMatches.isEmpty {
        score += tokenMatches.count * 90
        reasons.append("text_tokens:\(tokenMatches.count)")
      }
    }
    let matchedCapabilities = registration.capabilities.intersection(preferredCapabilities)
    let missingPreferred = preferredCapabilities.subtracting(registration.capabilities)
    score += matchedCapabilities.count * 130
    score -= missingPreferred.count * 45
    if !matchedCapabilities.isEmpty {
      reasons.append("capabilities:\(matchedCapabilities.map(\.rawValue).sorted().joined(separator: ","))")
    }
    score += statusScore(registration.status)
    score += registration.hasCapacity ? 90 : -260
    score += trustScore(registration.trust)
    score -= registration.cost.rank * 35
    score -= registration.latency.rank * 30
    let reputation = reputation(for: registration, capabilities: query.requiredCapabilities.union(preferredCapabilities))
    score += reputation.routingAdjustment
    if searchTokens(query.text).contains("fast"), registration.latency <= .fast {
      score += 180
    }
    if searchTokens(query.text).contains("economy"), registration.cost <= .low {
      score += 180
    }
    if registration.lastHeartbeatMillis > 0 {
      let heartbeatAge = max(Int64(0), nowMillis - registration.lastHeartbeatMillis)
      switch heartbeatAge {
      case 0...30_000:
        score += 90
      case 30_001...120_000:
        score += 55
      case 120_001...Self.heartbeatTTLMillis:
        score += 20
      default:
        score -= 120
      }
      reasons.append("heartbeat_age_ms:\(heartbeatAge)")
    }
    reasons.append("status:\(registration.status.rawValue.lowercased())")
    reasons.append("trust:\(registration.trust.rawValue.lowercased())")
    reasons.append("latency:\(registration.latency.rawValue.lowercased())")
    reasons.append("cost:\(registration.cost.rawValue.lowercased())")
    if reputation.confidence > 0 {
      reasons.append("reputation:\(reputation.score)")
      reasons.append("reputation_confidence:\(reputation.confidence)")
    }
    return AgentNetworkSearchHit(
      registration: registration,
      score: score,
      matchedCapabilities: matchedCapabilities,
      reasons: distinctReasons(reasons),
      reputation: reputation
    )
  }

  private func reputation(
    for registration: AgentRegistration,
    capabilities: Set<AgentCapability>
  ) -> AgentReputationSnapshot {
    reputationsByAgentId[registration.agentId] ?? .neutral(registration.agentId)
  }

  private func effectiveRevision() -> Int64 {
    currentRevision * 1_000_003 + reputationRevision
  }

  private func fingerprint(_ query: AgentNetworkSearchQuery) -> String {
    let canonical = [
      normalizeSearchText(query.text),
      query.requiredCapabilities.map(\.rawValue).sorted().joined(separator: ","),
      query.preferredCapabilities.map(\.rawValue).sorted().joined(separator: ","),
      query.kinds.map(\.rawValue).sorted().joined(separator: ","),
      query.locations.map(\.rawValue).sorted().joined(separator: ","),
      query.statuses.map(\.rawValue).sorted().joined(separator: ","),
      query.providerIds.map(normalizeSearchText).sorted().joined(separator: ","),
      query.deviceIds.map(normalizeSearchText).sorted().joined(separator: ","),
      query.excludedAgentIds.sorted().joined(separator: ","),
      String(query.trustedOnly),
      String(query.routableOnly),
      String(query.includeAtCapacity),
      query.maximumCost?.rawValue ?? "",
      query.maximumLatency?.rawValue ?? "",
      query.minimumReputationScore.map { String(min(max($0, 0), 100)) } ?? "",
      String(min(max(query.minimumReputationConfidence, 0), 100)),
      String(min(max(query.pageSize, 1), AgentNetworkSearchQuery.maxPageSize))
    ].joined(separator: "\u{001f}")
    return String(agentReputationSha256(Data(canonical.utf8)).prefix(24))
  }

  private func inferredCapabilities(from text: String) -> Set<AgentCapability> {
    let tokens = searchTokens(text)
    var capabilities = Set<AgentCapability>()
    if !tokens.isDisjoint(with: ["code", "coding", "debug", "python", "repo", "project", "commit"]) {
      capabilities.insert(.code)
    }
    if !tokens.isDisjoint(with: ["research", "search", "web", "latest", "news"]) {
      capabilities.insert(.research)
    }
    if !tokens.isDisjoint(with: ["live", "realtime", "online"]) {
      capabilities.insert(.liveData)
    }
    if !tokens.isDisjoint(with: ["reason", "architecture", "plan"]) {
      capabilities.insert(.reasoning)
    }
    if !tokens.isDisjoint(with: ["verify", "verification", "validate", "audit", "auditor"]) {
      capabilities.insert(.reasoning)
      capabilities.insert(.research)
    }
    return capabilities
  }

  private func statusScore(_ status: AgentEndpointStatus) -> Int {
    switch status {
    case .idle: return 240
    case .online: return 220
    case .busy: return 120
    case .degraded: return -80
    case .updating: return -140
    case .permissionRequired: return -180
    case .offline: return -300
    case .unreachable: return -420
    }
  }

  private func trustScore(_ trust: AgentResourceTrust) -> Int {
    switch trust {
    case .phoneSystem: return 180
    case .verifiedPaired: return 160
    case .privateConfigured: return 110
    case .cloudConfigured: return 55
    case .unknown: return -160
    }
  }

  private func distinctReasons(_ reasons: [String]) -> [String] {
    var seen = Set<String>()
    return reasons.filter { seen.insert($0).inserted }
  }

  private static let routableStates: Set<AgentEndpointStatus> = [.online, .idle, .busy]
  static let heartbeatTTLMillis: Int64 = 10 * 60_000
}

private struct AgentNetworkCursor {
  var revision: Int64
  var queryId: String
  var lastAgentId: String

  func encode() -> String {
    Data("\(revision)\u{001f}\(queryId)\u{001f}\(lastAgentId)".utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  static func decode(_ raw: String) -> AgentNetworkCursor? {
    guard !raw.isEmpty else {
      return nil
    }
    var base64 = raw
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    while base64.count % 4 != 0 {
      base64 += "="
    }
    guard let data = Data(base64Encoded: base64) else {
      return nil
    }
    let parts = String(decoding: data, as: UTF8.self).split(separator: "\u{001f}", omittingEmptySubsequences: false)
    guard parts.count == 3,
      let revision = Int64(parts[0]) else {
      return nil
    }
    return AgentNetworkCursor(revision: revision, queryId: String(parts[1]), lastAgentId: String(parts[2]))
  }
}

private extension AgentRegistration {
  func withEffectiveNetworkStatus(nowMillis: Int64) -> AgentRegistration {
    let stale = location != .phone &&
      lastHeartbeatMillis > 0 &&
      nowMillis - lastHeartbeatMillis > AgentNetworkIndex.heartbeatTTLMillis &&
      status != .offline &&
      status != .unreachable
    guard stale else {
      return self
    }
    var copy = self
    copy.status = .unreachable
    return copy
  }

  func indexTokens() -> Set<String> {
    var tokens = Set<String>()
    [agentId, installationId, deviceId, providerId, displayName, adapterType].forEach {
      tokens.formUnion(searchTokens($0))
    }
    capabilities.forEach { tokens.formUnion(searchTokens($0.rawValue)) }
    toolIds.forEach { tokens.formUnion(searchTokens($0)) }
    return tokens
  }
}

func searchTokens(_ value: String) -> Set<String> {
  Set(normalizeSearchText(value)
    .components(separatedBy: CharacterSet.alphanumerics.inverted)
    .filter { $0.count >= 2 })
}

func normalizeSearchText(_ value: String) -> String {
  value
    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    .lowercased()
    .trimmingCharacters(in: .whitespacesAndNewlines)
}

enum AgentDeliveryMode: String, Codable, CaseIterable, Identifiable {
  case respond = "RESPOND"
  case observe = "OBSERVE"
  case ignore = "IGNORE"

  var id: String { rawValue }
}

enum AgentRoutingMode: String, Codable, CaseIterable, Identifiable {
  case balanced = "BALANCED"
  case fast = "FAST"
  case economy = "ECONOMY"
  case quality = "QUALITY"
  case `private` = "PRIVATE"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentRoutingMode {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .balanced
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

enum AgentDataSensitivity: String, Codable, CaseIterable, Identifiable {
  case `public` = "PUBLIC"
  case personal = "PERSONAL"
  case confidential = "CONFIDENTIAL"
  case restricted = "RESTRICTED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentDataSensitivity {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
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

enum AgentExecutionHorizon: String, Codable, CaseIterable, Identifiable {
  case interactive = "INTERACTIVE"
  case background = "BACKGROUND"
  case longRunning = "LONG_RUNNING"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentExecutionHorizon {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .interactive
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

struct AgentTaskRequirements: Codable, Equatable {
  var capabilities: Set<AgentCapability>
  var mode: AgentRoutingMode
  var liveDataRequired: Bool
  var localOnly: Bool
  var complexReasoning: Bool
  var estimatedInputTokens: Int
  var dataSensitivity: AgentDataSensitivity
  var executionHorizon: AgentExecutionHorizon

  init(
    capabilities: Set<AgentCapability> = [],
    mode: AgentRoutingMode = .balanced,
    liveDataRequired: Bool = false,
    localOnly: Bool = false,
    complexReasoning: Bool = false,
    estimatedInputTokens: Int = 0,
    dataSensitivity: AgentDataSensitivity = .personal,
    executionHorizon: AgentExecutionHorizon = .interactive
  ) {
    self.capabilities = capabilities
    self.mode = mode
    self.liveDataRequired = liveDataRequired
    self.localOnly = localOnly
    self.complexReasoning = complexReasoning
    self.estimatedInputTokens = max(0, estimatedInputTokens)
    self.dataSensitivity = dataSensitivity
    self.executionHorizon = executionHorizon
  }

  enum CodingKeys: String, CodingKey {
    case capabilities
    case mode
    case liveDataRequired = "live_data_required"
    case localOnly = "local_only"
    case complexReasoning = "complex_reasoning"
    case estimatedInputTokens = "estimated_input_tokens"
    case dataSensitivity = "data_sensitivity"
    case executionHorizon = "execution_horizon"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedCapabilities = try container.decodeIfPresent(Set<AgentCapability>.self, forKey: .capabilities) ?? []
    capabilities = decodedCapabilities
    mode = try container.decodeIfPresent(AgentRoutingMode.self, forKey: .mode) ?? .balanced
    liveDataRequired = try container.decodeIfPresent(Bool.self, forKey: .liveDataRequired) ??
      decodedCapabilities.contains(.liveData)
    localOnly = try container.decodeIfPresent(Bool.self, forKey: .localOnly) ?? false
    complexReasoning = try container.decodeIfPresent(Bool.self, forKey: .complexReasoning) ?? false
    estimatedInputTokens = max(0, try container.decodeIfPresent(Int.self, forKey: .estimatedInputTokens) ?? 0)
    dataSensitivity = try container.decodeIfPresent(AgentDataSensitivity.self, forKey: .dataSensitivity) ?? .personal
    executionHorizon = try container.decodeIfPresent(AgentExecutionHorizon.self, forKey: .executionHorizon) ??
      .interactive
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(capabilities, forKey: .capabilities)
    try container.encode(mode, forKey: .mode)
    try container.encode(liveDataRequired, forKey: .liveDataRequired)
    try container.encode(localOnly, forKey: .localOnly)
    try container.encode(complexReasoning, forKey: .complexReasoning)
    try container.encode(estimatedInputTokens, forKey: .estimatedInputTokens)
    try container.encode(dataSensitivity, forKey: .dataSensitivity)
    try container.encode(executionHorizon, forKey: .executionHorizon)
  }
}

struct AgentResourceDescriptor: Codable, Equatable, Identifiable {
  var id: String
  var title: String
  var type: AgentResourceType
  var location: AgentResourceLocation
  var status: AgentConnectorStatus
  var capabilities: Set<AgentCapability>
  var cost: AgentResourceCost
  var latency: AgentResourceLatency
  var quality: AgentResourceQuality
  var supportsTools: Bool
  var targetId: String
  var trust: AgentResourceTrust
  var energy: AgentResourceEnergy
  var contextWindowTokens: Int
  var supportsStreaming: Bool
  var supportsBackground: Bool
  var activeTasks: Int
  var maxParallelTasks: Int
  var failureDomain: String
  var providerProfile: ProviderProfile?

  init(
    id: String,
    title: String,
    type: AgentResourceType,
    location: AgentResourceLocation,
    status: AgentConnectorStatus,
    capabilities: Set<AgentCapability>,
    cost: AgentResourceCost,
    latency: AgentResourceLatency,
    quality: AgentResourceQuality,
    supportsTools: Bool,
    targetId: String = "",
    trust: AgentResourceTrust = .unknown,
    energy: AgentResourceEnergy = .low,
    contextWindowTokens: Int = 8_192,
    supportsStreaming: Bool = false,
    supportsBackground: Bool = false,
    activeTasks: Int = 0,
    maxParallelTasks: Int = 1,
    failureDomain: String = "",
    providerProfile: ProviderProfile? = nil
  ) {
    self.id = id
    self.title = title
    self.type = type
    self.location = location
    self.status = status
    self.capabilities = capabilities
    self.cost = cost
    self.latency = latency
    self.quality = quality
    self.supportsTools = supportsTools
    self.targetId = targetId
    self.trust = trust
    self.energy = energy
    self.contextWindowTokens = max(0, contextWindowTokens)
    self.supportsStreaming = supportsStreaming
    self.supportsBackground = supportsBackground
    self.activeTasks = max(0, activeTasks)
    self.maxParallelTasks = max(1, maxParallelTasks)
    self.failureDomain = failureDomain
    self.providerProfile = providerProfile
  }

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case type
    case location
    case status
    case capabilities
    case cost
    case latency
    case quality
    case supportsTools = "supports_tools"
    case targetId = "target_id"
    case trust
    case energy
    case contextWindowTokens = "context_window_tokens"
    case supportsStreaming = "supports_streaming"
    case supportsBackground = "supports_background"
    case activeTasks = "active_tasks"
    case maxParallelTasks = "max_parallel_tasks"
    case failureDomain = "failure_domain"
    case providerProfile = "provider_profile"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
      title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
      type: try container.decodeIfPresent(AgentResourceType.self, forKey: .type) ?? .cloudModel,
      location: try container.decodeIfPresent(AgentResourceLocation.self, forKey: .location) ?? .cloud,
      status: try container.decodeIfPresent(AgentConnectorStatus.self, forKey: .status) ?? .disconnected,
      capabilities: try container.decodeIfPresent(Set<AgentCapability>.self, forKey: .capabilities) ?? [],
      cost: ProviderProfileCatalog.cost(try container.decodeIfPresent(String.self, forKey: .cost), fallback: .free),
      latency: ProviderProfileCatalog.latency(
        try container.decodeIfPresent(String.self, forKey: .latency),
        fallback: .normal
      ),
      quality: ProviderProfileCatalog.quality(
        try container.decodeIfPresent(String.self, forKey: .quality),
        fallback: .standard
      ),
      supportsTools: try container.decodeIfPresent(Bool.self, forKey: .supportsTools) ?? false,
      targetId: try container.decodeIfPresent(String.self, forKey: .targetId) ?? "",
      trust: ProviderProfileCatalog.trust(try container.decodeIfPresent(String.self, forKey: .trust), fallback: .unknown),
      energy: try container.decodeIfPresent(AgentResourceEnergy.self, forKey: .energy) ?? .low,
      contextWindowTokens: try container.decodeIfPresent(Int.self, forKey: .contextWindowTokens) ?? 8_192,
      supportsStreaming: try container.decodeIfPresent(Bool.self, forKey: .supportsStreaming) ?? false,
      supportsBackground: try container.decodeIfPresent(Bool.self, forKey: .supportsBackground) ?? false,
      activeTasks: try container.decodeIfPresent(Int.self, forKey: .activeTasks) ?? 0,
      maxParallelTasks: try container.decodeIfPresent(Int.self, forKey: .maxParallelTasks) ?? 1,
      failureDomain: try container.decodeIfPresent(String.self, forKey: .failureDomain) ?? "",
      providerProfile: try container.decodeIfPresent(ProviderProfile.self, forKey: .providerProfile)
    )
  }
}

struct AgentRuntimeEnvironment: Codable, Equatable {
  var batteryPercent: Int
  var charging: Bool
  var powerSaveMode: Bool
  var networkAvailable: Bool
  var networkValidated: Bool
  var networkMetered: Bool
  var appMemoryBytes: Int64
  var availableMemoryBytes: Int64

  var energyConstrained: Bool {
    powerSaveMode || (!charging && batteryPercent >= 0 && batteryPercent <= 19)
  }

  init(
    batteryPercent: Int = -1,
    charging: Bool = false,
    powerSaveMode: Bool = false,
    networkAvailable: Bool = false,
    networkValidated: Bool = false,
    networkMetered: Bool = false,
    appMemoryBytes: Int64 = 0,
    availableMemoryBytes: Int64 = 0
  ) {
    self.batteryPercent = batteryPercent
    self.charging = charging
    self.powerSaveMode = powerSaveMode
    self.networkAvailable = networkAvailable
    self.networkValidated = networkValidated
    self.networkMetered = networkMetered
    self.appMemoryBytes = max(0, appMemoryBytes)
    self.availableMemoryBytes = max(0, availableMemoryBytes)
  }

  enum CodingKeys: String, CodingKey {
    case batteryPercent = "battery_percent"
    case charging
    case powerSaveMode = "power_save_mode"
    case networkAvailable = "network_available"
    case networkValidated = "network_validated"
    case networkMetered = "network_metered"
    case appMemoryBytes = "app_memory_bytes"
    case availableMemoryBytes = "available_memory_bytes"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      batteryPercent: try container.decodeIfPresent(Int.self, forKey: .batteryPercent) ?? -1,
      charging: try container.decodeIfPresent(Bool.self, forKey: .charging) ?? false,
      powerSaveMode: try container.decodeIfPresent(Bool.self, forKey: .powerSaveMode) ?? false,
      networkAvailable: try container.decodeIfPresent(Bool.self, forKey: .networkAvailable) ?? false,
      networkValidated: try container.decodeIfPresent(Bool.self, forKey: .networkValidated) ?? false,
      networkMetered: try container.decodeIfPresent(Bool.self, forKey: .networkMetered) ?? false,
      appMemoryBytes: try container.decodeIfPresent(Int64.self, forKey: .appMemoryBytes) ?? 0,
      availableMemoryBytes: try container.decodeIfPresent(Int64.self, forKey: .availableMemoryBytes) ?? 0
    )
  }
}

struct AgentResourceCandidate: Codable, Equatable {
  var resource: AgentResourceDescriptor
  var score: Int
  var reasons: [String]

  init(resource: AgentResourceDescriptor, score: Int, reasons: [String] = []) {
    self.resource = resource
    self.score = score
    self.reasons = reasons
  }
}

struct AgentRoutingDecision: Codable, Equatable {
  var requirements: AgentTaskRequirements
  var primary: AgentResourceCandidate?
  var fallbacks: [AgentResourceCandidate]
  var environment: AgentRuntimeEnvironment
  var catalog: [AgentResourceDescriptor]
  var taskBudget: AgentTaskBudget

  var orderedTargetIds: [String] {
    var ids: [String] = []
    if let primaryId = primary?.resource.targetId, !primaryId.isEmpty {
      ids.append(primaryId)
    }
    ids.append(contentsOf: fallbacks.map(\.resource.targetId).filter { !$0.isEmpty })
    return ids
  }

  init(
    requirements: AgentTaskRequirements,
    primary: AgentResourceCandidate?,
    fallbacks: [AgentResourceCandidate] = [],
    environment: AgentRuntimeEnvironment = AgentRuntimeEnvironment(),
    catalog: [AgentResourceDescriptor] = [],
    taskBudget: AgentTaskBudget = .default
  ) {
    self.requirements = requirements
    self.primary = primary
    self.fallbacks = fallbacks
    self.environment = environment
    self.catalog = catalog
    self.taskBudget = taskBudget
  }

  enum CodingKeys: String, CodingKey {
    case requirements
    case primary
    case fallbacks
    case environment
    case catalog
    case taskBudget = "task_budget"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      requirements: try container.decodeIfPresent(AgentTaskRequirements.self, forKey: .requirements) ??
        AgentTaskRequirements(),
      primary: try container.decodeIfPresent(AgentResourceCandidate.self, forKey: .primary),
      fallbacks: try container.decodeIfPresent([AgentResourceCandidate].self, forKey: .fallbacks) ?? [],
      environment: try container.decodeIfPresent(AgentRuntimeEnvironment.self, forKey: .environment) ??
        AgentRuntimeEnvironment(),
      catalog: try container.decodeIfPresent([AgentResourceDescriptor].self, forKey: .catalog) ?? [],
      taskBudget: try container.decodeIfPresent(AgentTaskBudget.self, forKey: .taskBudget) ?? .default
    )
  }
}

struct AgentConnectorRouteSelection: Codable, Equatable {
  var target: AgentCallableTarget
  var decision: AgentRoutingDecision?
}

enum AgentConnectorRouteSelector {
  static func isDeliverable(_ target: AgentCallableTarget?) -> Bool {
    guard let target else { return false }
    return target.status == .available ||
      (target.status == .disconnected && hasReasoningCapability(target))
  }

  static func select(
    targets: [AgentCallableTarget],
    decision: AgentRoutingDecision?,
    preferredTargetId: String = ""
  ) -> AgentConnectorRouteSelection? {
    let reasoningTargets = targets.filter(hasReasoningCapability)
    var eligible = reasoningTargets.filter { $0.status == .available }
    if eligible.isEmpty {
      eligible = reasoningTargets.filter(isDeliverable)
    }
    guard !eligible.isEmpty else { return nil }

    let eligibleById = eligible.reduce(into: [String: AgentCallableTarget]()) { values, target in
      values[target.id] = target
    }
    let decisionCandidates: [AgentResourceCandidate]
    if let decision {
      decisionCandidates = [decision.primary].compactMap { $0 } + decision.fallbacks
    } else {
      decisionCandidates = []
    }
    var seenTargetIds = Set<String>()
    let routedCandidates = decisionCandidates
      .filter { eligibleById[$0.resource.targetId] != nil }
      .filter { seenTargetIds.insert($0.resource.targetId).inserted }
    let preferredTarget = preferredTargetId.isEmpty ? nil : eligibleById[preferredTargetId]
    let routedTarget = routedCandidates.compactMap { eligibleById[$0.resource.targetId] }.first
    let selectedTarget = preferredTarget ?? routedTarget ?? defaultTarget(eligible)

    guard let decision else {
      return AgentConnectorRouteSelection(target: selectedTarget, decision: nil)
    }
    let selectedCandidate = routedCandidates.first { $0.resource.targetId == selectedTarget.id } ??
      decision.catalog.first { $0.targetId == selectedTarget.id }.map { resource in
        AgentResourceCandidate(
          resource: resource,
          score: 0,
          reasons: [
            selectedTarget.status == .disconnected ?
              "recoverable_connector_status" :
              "eligible_reasoning_fallback"
          ]
        )
      }
    let connectorDecision = selectedCandidate.map { primary in
      AgentRoutingDecision(
        requirements: decision.requirements,
        primary: primary,
        fallbacks: routedCandidates.filter { $0.resource.targetId != selectedTarget.id },
        environment: decision.environment,
        catalog: decision.catalog,
        taskBudget: decision.taskBudget
      )
    }
    return AgentConnectorRouteSelection(target: selectedTarget, decision: connectorDecision)
  }

  private static func hasReasoningCapability(_ target: AgentCallableTarget) -> Bool {
    target.kind != .device &&
      target.capabilities.contains { capability in
        capability == .chat || capability == .reasoning || capability == .research
      }
  }

  private static func defaultTarget(_ targets: [AgentCallableTarget]) -> AgentCallableTarget {
    targets.first { $0.id == "codex" || $0.id.hasSuffix(":codex") } ??
      targets.first { $0.id == "local-llm" } ??
      targets.first { $0.kind == .model } ??
      targets.first { $0.id == "hermes" || $0.id.hasSuffix(":hermes") } ??
      targets.first { $0.capabilities.contains(.research) } ??
      targets[0]
  }
}

enum AgentResourceCatalog {
  static func build(
    targets: [AgentCallableTarget],
    tools: [AgentSystemTool],
    nativeTools: [AgentNativeToolDescriptor] = []
  ) -> [AgentResourceDescriptor] {
    let capabilityMatrix = AgentRuntimeCapabilityMatrix.build(
      nativeTools: nativeTools,
      systemTools: tools,
      targets: targets
    )
    let callable = targets.map(fromTarget)
    let localTools = tools.map { tool in
      let capability = capabilityMatrix.entry(source: .systemTool, id: tool.id)
      return AgentResourceDescriptor(
        id: "tool:\(tool.id)",
        title: tool.title,
        type: systemToolType(tool.id),
        location: .phone,
        status: connectorStatus(capability),
        capabilities: Set(tool.capabilities),
        cost: .free,
        latency: .instant,
        quality: .standard,
        supportsTools: true,
        trust: .phoneSystem,
        energy: .minimal,
        contextWindowTokens: 0,
        supportsStreaming: false,
        supportsBackground: false,
        maxParallelTasks: 4,
        failureDomain: "phone"
      )
    }
    let registeredNativeTools = nativeTools.map { tool in
      fromNativeTool(
        tool,
        capability: capabilityMatrix.entry(source: .nativeTool, id: tool.id)
      )
    }
    return callable + localTools + registeredNativeTools
  }

  private static func fromNativeTool(
    _ tool: AgentNativeToolDescriptor,
    capability: AgentRuntimeCapabilityEntry?
  ) -> AgentResourceDescriptor {
    AgentResourceDescriptor(
      id: "native:\(tool.id)",
      title: tool.title,
      type: nativeToolType(tool.id),
      location: .phone,
      status: connectorStatus(capability),
      capabilities: nativeCapabilities(tool),
      cost: .free,
      latency: .instant,
      quality: .standard,
      supportsTools: true,
      trust: .phoneSystem,
      energy: tool.id.contains("runtime") || tool.id.contains("ffmpeg") ? .high : .minimal,
      contextWindowTokens: 0,
      supportsStreaming: false,
      supportsBackground: tool.location == .application,
      maxParallelTasks: 4,
      failureDomain: "phone"
    )
  }

  private static func fromTarget(_ target: AgentCallableTarget) -> AgentResourceDescriptor {
    let lowerId = target.id.lowercased()
    let providerProfile = [.agent, .model].contains(target.kind) ? ProviderProfileCatalog.fromTarget(target) : nil
    let type = targetType(target, lowerId: lowerId)
    let location = location(for: type)
    let defaults = defaultProfile(for: type)
    let trust = defaultTrust(for: location)
    let contextWindow = defaultContextWindow(for: type)
    let profileFailureDomain = providerProfile?.failureDomain ?? ""
    let failureDomain = !profileFailureDomain.isEmpty
      ? profileFailureDomain
      : target.failureDomain.isEmpty ? defaultFailureDomain(targetId: target.id, location: location) : target.failureDomain

    return AgentResourceDescriptor(
      id: "target:\(target.id)",
      title: target.title,
      type: type,
      location: location,
      status: target.status,
      capabilities: Set(target.capabilities),
      cost: providerProfile?.pricing.tier ?? defaults.cost,
      latency: providerProfile?.latency ?? defaults.latency,
      quality: providerProfile?.quality ?? defaults.quality,
      supportsTools: providerProfile?.supportsTools ??
        (target.capabilities.contains(.toolUse) || target.capabilities.contains(.research)),
      targetId: target.id,
      trust: providerProfile?.trust ?? trust,
      energy: energy(for: type),
      contextWindowTokens: providerProfile?.contextWindowTokens ?? contextWindow,
      supportsStreaming: providerProfile?.supportsStreaming ?? streamingDefault(for: type),
      supportsBackground: providerProfile?.supportsBackground ?? backgroundDefault(for: type),
      maxParallelTasks: providerProfile?.maxParallelRuns ?? maxParallelTasksDefault(for: type),
      failureDomain: failureDomain,
      providerProfile: providerProfile
    )
  }

  private static func systemToolType(_ id: String) -> AgentResourceType {
    if id.hasPrefix("workflow:") || id.hasPrefix("template:") {
      return .localSkill
    }
    if id.localizedCaseInsensitiveContains("mcp") {
      return .localMcp
    }
    return .localTool
  }

  private static func nativeToolType(_ id: String) -> AgentResourceType {
    if id.contains(".mcp.") || id.hasPrefix("mcp.") {
      return .localMcp
    }
    if id.contains(".skill.") || id.hasPrefix("skill.") {
      return .localSkill
    }
    return .localTool
  }

  private static func nativeCapabilities(_ tool: AgentNativeToolDescriptor) -> Set<AgentCapability> {
    let text = ([tool.id] + Array(tool.capabilities)).joined(separator: " ").lowercased()
    var capabilities: Set<AgentCapability> = [.toolUse]
    if containsAny(text, ["web", "http", "browser", "network"]) {
      capabilities.insert(.liveData)
    }
    if containsAny(text, ["web", "research", "search"]) {
      capabilities.insert(.research)
    }
    if containsAny(text, ["workspace", "runtime", "python", "node", "compile", "ffmpeg"]) {
      capabilities.formUnion([.code, .taskExecution])
    }
    if text.contains("mcp") {
      capabilities.insert(.mcp)
    }
    if text.contains("skill") {
      capabilities.insert(.skill)
    }
    if text.contains("screen") || text.contains("ocr") {
      capabilities.insert(.screenReading)
    }
    if text.contains("clipboard") {
      capabilities.insert(.clipboard)
    }
    if text.contains("settings") {
      capabilities.insert(.systemSettings)
    }
    if text.contains("app") || text.contains("package") {
      capabilities.insert(.appNavigation)
    }
    if text.contains("alarm") || text.contains("timer") {
      capabilities.insert(.alarm)
    }
    if containsAny(text, [
      "hardware", "device", "location", "sensor", "bluetooth", "nfc", "wifi",
      "audio", "telephony", "sms", "contact", "calendar", "battery", "power", "storage"
    ]) {
      capabilities.insert(.deviceControl)
    }
    return capabilities
  }

  private static func connectorStatus(_ capability: AgentRuntimeCapabilityEntry?) -> AgentConnectorStatus {
    switch capability?.state {
    case .available:
      return .available
    case .requiresSetup:
      return .needsSetup
    case .unavailable, .blocked, nil:
      return .disconnected
    }
  }

  private static func targetType(_ target: AgentCallableTarget, lowerId: String) -> AgentResourceType {
    if lowerId == "home-assistant" {
      return .homeAssistant
    }
    if lowerId.hasPrefix("custom-device:") {
      return .customDevice
    }
    if lowerId.contains("mcp") {
      return .remoteMcp
    }
    if lowerId.contains("skill") {
      return .remoteSkill
    }
    if target.kind == .knowledge {
      return .knowledge
    }
    if target.kind == .model && (lowerId == "local-llm" || target.capabilities.contains(.localInference)) {
      return .remoteLocalModel
    }
    if target.kind == .model {
      return .cloudModel
    }
    if target.kind == .agent {
      return .remoteAgent
    }
    return .customDevice
  }

  private static func location(for type: AgentResourceType) -> AgentResourceLocation {
    switch type {
    case .onDeviceModel, .localAgent, .localTool, .localMcp, .localSkill, .knowledge:
      return .phone
    case .remoteLocalModel, .remoteAgent, .remoteMcp, .remoteSkill:
      return .trustedDesktop
    case .homeAssistant, .customDevice:
      return .privateNetwork
    case .cloudModel, .cloudMcp, .cloudSkill:
      return .cloud
    }
  }

  private static func defaultProfile(
    for type: AgentResourceType
  ) -> (cost: AgentResourceCost, latency: AgentResourceLatency, quality: AgentResourceQuality) {
    switch type {
    case .cloudModel:
      return (.medium, .normal, .frontier)
    case .remoteAgent, .remoteMcp, .remoteSkill:
      return (.low, .slow, .strong)
    case .remoteLocalModel, .homeAssistant, .customDevice:
      return (.free, .fast, .standard)
    default:
      return (.free, .instant, .standard)
    }
  }

  private static func defaultTrust(for location: AgentResourceLocation) -> AgentResourceTrust {
    switch location {
    case .phone:
      return .phoneSystem
    case .trustedDesktop:
      return .verifiedPaired
    case .privateNetwork:
      return .privateConfigured
    case .cloud:
      return .cloudConfigured
    }
  }

  private static func energy(for type: AgentResourceType) -> AgentResourceEnergy {
    switch type {
    case .onDeviceModel:
      return .high
    case .localAgent, .localMcp, .localSkill:
      return .moderate
    case .localTool, .knowledge:
      return .minimal
    default:
      return .low
    }
  }

  private static func defaultContextWindow(for type: AgentResourceType) -> Int {
    switch type {
    case .cloudModel:
      return 128_000
    case .remoteAgent:
      return 64_000
    case .remoteLocalModel, .onDeviceModel:
      return 16_000
    default:
      return 8_192
    }
  }

  private static func streamingDefault(for type: AgentResourceType) -> Bool {
    type == .cloudModel || type == .remoteAgent || type == .remoteLocalModel
  }

  private static func backgroundDefault(for type: AgentResourceType) -> Bool {
    type == .remoteAgent || type == .remoteLocalModel || type == .remoteMcp || type == .remoteSkill
  }

  private static func maxParallelTasksDefault(for type: AgentResourceType) -> Int {
    switch type {
    case .remoteAgent:
      return 4
    case .cloudModel:
      return 3
    case .remoteLocalModel:
      return 2
    default:
      return 1
    }
  }

  private static func defaultFailureDomain(targetId: String, location: AgentResourceLocation) -> String {
    switch location {
    case .phone:
      return "phone"
    case .cloud:
      return "cloud:\(targetId)"
    case .trustedDesktop:
      return "desktop:\(targetId.split(separator: ":").first.map(String.init) ?? targetId)"
    case .privateNetwork:
      return "private:\(targetId)"
    }
  }

  private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
    terms.contains { text.contains($0) }
  }
}
