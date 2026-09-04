import Foundation

enum GlobalActionEvidenceKind: String, Codable, CaseIterable, Identifiable {
  case delegatedResult = "DELEGATED_RESULT"
  case localReceipt = "LOCAL_RECEIPT"
  case nativeToolReceipt = "NATIVE_TOOL_RECEIPT"
  case researchLedger = "RESEARCH_LEDGER"
  case artifact = "ARTIFACT"
  case userConfirmation = "USER_CONFIRMATION"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> GlobalActionEvidenceKind {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()
      .replacingOccurrences(of: "-", with: "_")
      .replacingOccurrences(of: " ", with: "_") ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .delegatedResult
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

enum GlobalActionVerificationStatus: String, Codable, CaseIterable, Identifiable {
  case pending = "PENDING"
  case supported = "SUPPORTED"
  case verified = "VERIFIED"
  case insufficient = "INSUFFICIENT"
  case contested = "CONTESTED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> GlobalActionVerificationStatus {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()
      .replacingOccurrences(of: "-", with: "_")
      .replacingOccurrences(of: " ", with: "_") ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .pending
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

struct GlobalActionEvidence: Codable, Equatable, Identifiable {
  var id: String
  var kind: GlobalActionEvidenceKind
  var summary: String
  var sourceRef: String
  var confidence: Double
  var verified: Bool
  var createdAtMillis: Int64

  init(
    id: String = UUID().uuidString,
    kind: GlobalActionEvidenceKind,
    summary: String,
    sourceRef: String = "",
    confidence: Double = 0.5,
    verified: Bool = false,
    createdAtMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) {
    self.id = String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumIdCharacters))
      .ifBlank(UUID().uuidString)
    self.kind = kind
    self.summary = String(summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumSummaryCharacters))
    self.sourceRef = String(sourceRef.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumSourceRefCharacters))
    self.confidence = min(max(confidence, 0), 1)
    self.verified = verified
    self.createdAtMillis = max(createdAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case kind
    case summary
    case sourceRef = "source_ref"
    case sourceRefLegacy = "sourceRef"
    case confidence
    case verified
    case createdAtMillis = "created_at_millis"
    case createdAtMillisLegacy = "createdAtMillis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
      kind: try container.decodeIfPresent(GlobalActionEvidenceKind.self, forKey: .kind) ?? .delegatedResult,
      summary: try container.decodeIfPresent(String.self, forKey: .summary) ?? "",
      sourceRef: try container.decodeIfPresent(String.self, forKey: .sourceRef) ??
        (try container.decodeIfPresent(String.self, forKey: .sourceRefLegacy)) ?? "",
      confidence: try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.5,
      verified: try container.decodeIfPresent(Bool.self, forKey: .verified) ?? false,
      createdAtMillis: try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ??
        (try container.decodeIfPresent(Int64.self, forKey: .createdAtMillisLegacy)) ?? 0
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(kind, forKey: .kind)
    try container.encode(summary, forKey: .summary)
    try container.encode(sourceRef, forKey: .sourceRef)
    try container.encode(confidence, forKey: .confidence)
    try container.encode(verified, forKey: .verified)
    try container.encode(createdAtMillis, forKey: .createdAtMillis)
  }

  private static let maximumIdCharacters = 160
  private static let maximumSummaryCharacters = 2_000
  private static let maximumSourceRefCharacters = 512
}

struct GlobalActionVerificationContract: Codable, Equatable {
  var criteria: [String]
  var acceptedEvidenceKinds: Set<GlobalActionEvidenceKind>
  var minimumEvidenceCount: Int
  var minimumConfidence: Double
  var requireVerifiedEvidence: Bool

  init(
    criteria: [String] = [],
    acceptedEvidenceKinds: Set<GlobalActionEvidenceKind> = [],
    minimumEvidenceCount: Int = 1,
    minimumConfidence: Double = 0.5,
    requireVerifiedEvidence: Bool = false
  ) {
    self.criteria = Array(criteria.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumCriterionCharacters)) }
      .filter { !$0.isEmpty }
      .prefix(Self.maximumCriteria))
    self.acceptedEvidenceKinds = acceptedEvidenceKinds
    self.minimumEvidenceCount = max(minimumEvidenceCount, 1)
    self.minimumConfidence = min(max(minimumConfidence, 0), 1)
    self.requireVerifiedEvidence = requireVerifiedEvidence
  }

  enum CodingKeys: String, CodingKey {
    case criteria
    case acceptedEvidenceKinds = "accepted_evidence_kinds"
    case acceptedEvidenceKindsLegacy = "acceptedEvidenceKinds"
    case minimumEvidenceCount = "minimum_evidence_count"
    case minimumEvidenceCountLegacy = "minimumEvidenceCount"
    case minimumConfidence = "minimum_confidence"
    case minimumConfidenceLegacy = "minimumConfidence"
    case requireVerifiedEvidence = "require_verified_evidence"
    case requireVerifiedEvidenceLegacy = "requireVerifiedEvidence"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      criteria: try container.decodeIfPresent([String].self, forKey: .criteria) ?? [],
      acceptedEvidenceKinds: try container.decodeIfPresent(Set<GlobalActionEvidenceKind>.self, forKey: .acceptedEvidenceKinds) ??
        (try container.decodeIfPresent(Set<GlobalActionEvidenceKind>.self, forKey: .acceptedEvidenceKindsLegacy)) ?? [],
      minimumEvidenceCount: try container.decodeIfPresent(Int.self, forKey: .minimumEvidenceCount) ??
        (try container.decodeIfPresent(Int.self, forKey: .minimumEvidenceCountLegacy)) ?? 1,
      minimumConfidence: try container.decodeIfPresent(Double.self, forKey: .minimumConfidence) ??
        (try container.decodeIfPresent(Double.self, forKey: .minimumConfidenceLegacy)) ?? 0.5,
      requireVerifiedEvidence: try container.decodeIfPresent(Bool.self, forKey: .requireVerifiedEvidence) ??
        (try container.decodeIfPresent(Bool.self, forKey: .requireVerifiedEvidenceLegacy)) ?? false
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(criteria, forKey: .criteria)
    try container.encode(acceptedEvidenceKinds.sorted { $0.rawValue < $1.rawValue }, forKey: .acceptedEvidenceKinds)
    try container.encode(minimumEvidenceCount, forKey: .minimumEvidenceCount)
    try container.encode(minimumConfidence, forKey: .minimumConfidence)
    try container.encode(requireVerifiedEvidence, forKey: .requireVerifiedEvidence)
  }

  private static let maximumCriteria = 8
  private static let maximumCriterionCharacters = 600
}

enum GlobalActionVerificationPolicy {
  static func defaultContract(action: GlobalAutonomousAction) -> GlobalActionVerificationContract {
    let criterion = String(action.expectedResult.ifBlank(action.goal).prefix(600))
    switch action.kind {
    case .analyze, .draft:
      return GlobalActionVerificationContract(
        criteria: [criterion],
        acceptedEvidenceKinds: [.delegatedResult, .artifact],
        minimumConfidence: 0.50
      )
    case .readOnlyCheck:
      return GlobalActionVerificationContract(
        criteria: [criterion],
        acceptedEvidenceKinds: [.delegatedResult, .localReceipt, .researchLedger],
        minimumConfidence: 0.58
      )
    case .invokeTool:
      return GlobalActionVerificationContract(
        criteria: [criterion],
        acceptedEvidenceKinds: [.nativeToolReceipt],
        minimumConfidence: 0.72
      )
    case .createTopic, .startMonitor:
      return GlobalActionVerificationContract(
        criteria: [criterion],
        acceptedEvidenceKinds: [.localReceipt],
        minimumConfidence: 0.90,
        requireVerifiedEvidence: true
      )
    case .startResearch:
      return GlobalActionVerificationContract(
        criteria: [criterion],
        acceptedEvidenceKinds: [.researchLedger],
        minimumConfidence: 0.56,
        requireVerifiedEvidence: true
      )
    }
  }

  static func evaluate(
    contract: GlobalActionVerificationContract,
    evidence: [GlobalActionEvidence]
  ) -> GlobalActionVerificationStatus {
    if contract.criteria.isEmpty {
      return .insufficient
    }
    let accepted = evidence.filter { item in
      (contract.acceptedEvidenceKinds.isEmpty || contract.acceptedEvidenceKinds.contains(item.kind)) &&
        item.confidence >= contract.minimumConfidence
    }
    if accepted.count < max(contract.minimumEvidenceCount, 1) {
      return .insufficient
    }
    if contract.requireVerifiedEvidence && !accepted.contains(where: \.verified) {
      return .insufficient
    }
    return accepted.contains(where: \.verified) ? .verified : .supported
  }
}
