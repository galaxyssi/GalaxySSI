import Foundation

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
