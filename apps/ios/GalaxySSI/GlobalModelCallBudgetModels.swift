import CryptoKit
import Foundation

enum GlobalModelCallKind: String, Codable, CaseIterable, Identifiable {
  case cognition = "COGNITION"
  case researchEvidence = "RESEARCH_EVIDENCE"
  case researchSynthesis = "RESEARCH_SYNTHESIS"
  case autonomousAction = "AUTONOMOUS_ACTION"
  case planReview = "PLAN_REVIEW"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> GlobalModelCallKind {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .cognition
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

enum GlobalModelCallBudgetDenial: String, Codable, CaseIterable, Identifiable {
  case dailyLimit = "DAILY_LIMIT"
  case tokenLimit = "TOKEN_LIMIT"
  case reportedCostLimit = "REPORTED_COST_LIMIT"
  case concurrencyLimit = "CONCURRENCY_LIMIT"
  case duplicateDispatch = "DUPLICATE_DISPATCH"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> GlobalModelCallBudgetDenial {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .dailyLimit
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

struct GlobalModelCallDispatch: Codable, Equatable {
  var leaseId: String
  var kind: GlobalModelCallKind
  var startedAtMillis: Int64
  var resourceId: String
  var inputTokens: Int64
  var outputTokens: Int64
  var reportedCostMicros: Int64
  var usageEstimated: Bool
  var completedAtMillis: Int64

  var totalTokens: Int64 {
    GlobalModelUsageEstimator.saturatingAdd(inputTokens, outputTokens)
  }

  init(
    leaseId: String,
    kind: GlobalModelCallKind,
    startedAtMillis: Int64,
    resourceId: String = "",
    inputTokens: Int64 = 0,
    outputTokens: Int64 = 0,
    reportedCostMicros: Int64 = 0,
    usageEstimated: Bool = true,
    completedAtMillis: Int64 = 0
  ) {
    self.leaseId = leaseId
    self.kind = kind
    self.startedAtMillis = startedAtMillis
    self.resourceId = resourceId
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
    self.reportedCostMicros = reportedCostMicros
    self.usageEstimated = usageEstimated
    self.completedAtMillis = completedAtMillis
  }

  enum CodingKeys: String, CodingKey {
    case leaseId = "lease_id"
    case kind
    case startedAtMillis = "started_at_millis"
    case resourceId = "resource_id"
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
    case reportedCostMicros = "reported_cost_micros"
    case usageEstimated = "usage_estimated"
    case completedAtMillis = "completed_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      leaseId: try container.decodeIfPresent(String.self, forKey: .leaseId) ?? "",
      kind: try container.decodeIfPresent(GlobalModelCallKind.self, forKey: .kind) ?? .cognition,
      startedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .startedAtMillis) ?? 0,
      resourceId: try container.decodeIfPresent(String.self, forKey: .resourceId) ?? "",
      inputTokens: try container.decodeIfPresent(Int64.self, forKey: .inputTokens) ?? 0,
      outputTokens: try container.decodeIfPresent(Int64.self, forKey: .outputTokens) ?? 0,
      reportedCostMicros: try container.decodeIfPresent(Int64.self, forKey: .reportedCostMicros) ?? 0,
      usageEstimated: try container.decodeIfPresent(Bool.self, forKey: .usageEstimated) ?? true,
      completedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .completedAtMillis) ?? 0
    )
  }
}

struct GlobalModelCallLease: Codable, Equatable {
  var id: String
  var kind: GlobalModelCallKind
  var ownerKey: String
  var startedAtMillis: Int64
  var expiresAtMillis: Int64

  init(
    id: String,
    kind: GlobalModelCallKind,
    ownerKey: String,
    startedAtMillis: Int64,
    expiresAtMillis: Int64
  ) {
    self.id = id
    self.kind = kind
    self.ownerKey = ownerKey
    self.startedAtMillis = startedAtMillis
    self.expiresAtMillis = expiresAtMillis
  }

  enum CodingKeys: String, CodingKey {
    case id
    case kind
    case ownerKey = "owner_key"
    case startedAtMillis = "started_at_millis"
    case expiresAtMillis = "expires_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
      kind: try container.decodeIfPresent(GlobalModelCallKind.self, forKey: .kind) ?? .cognition,
      ownerKey: try container.decodeIfPresent(String.self, forKey: .ownerKey) ?? "",
      startedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .startedAtMillis) ?? 0,
      expiresAtMillis: try container.decodeIfPresent(Int64.self, forKey: .expiresAtMillis) ?? 0
    )
  }
}

struct GlobalModelCallBudgetState: Codable, Equatable {
  var dispatches: [GlobalModelCallDispatch]
  var activeLeases: [GlobalModelCallLease]

  init(
    dispatches: [GlobalModelCallDispatch] = [],
    activeLeases: [GlobalModelCallLease] = []
  ) {
    self.dispatches = dispatches
    self.activeLeases = activeLeases
  }

  enum CodingKeys: String, CodingKey {
    case dispatches
    case activeLeases = "active_leases"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      dispatches: try container.decodeIfPresent([GlobalModelCallDispatch].self, forKey: .dispatches) ?? [],
      activeLeases: try container.decodeIfPresent([GlobalModelCallLease].self, forKey: .activeLeases) ?? []
    )
  }
}

struct GlobalModelCallBudgetDecision: Codable, Equatable {
  var granted: Bool
  var state: GlobalModelCallBudgetState
  var leaseId: String
  var denial: GlobalModelCallBudgetDenial?
  var nextEligibleAtMillis: Int64

  init(
    granted: Bool,
    state: GlobalModelCallBudgetState,
    leaseId: String = "",
    denial: GlobalModelCallBudgetDenial? = nil,
    nextEligibleAtMillis: Int64 = 0
  ) {
    self.granted = granted
    self.state = state
    self.leaseId = leaseId
    self.denial = denial
    self.nextEligibleAtMillis = nextEligibleAtMillis
  }

  enum CodingKeys: String, CodingKey {
    case granted
    case state
    case leaseId = "lease_id"
    case denial
    case nextEligibleAtMillis = "next_eligible_at_millis"
  }
}

struct GlobalModelCallBudgetSnapshot: Codable, Equatable {
  var dispatchesInWindow: Int
  var activeCalls: Int
  var dailyLimit: Int
  var concurrencyLimit: Int
  var dispatchesByKind: [String: Int]
  var inputTokensInWindow: Int64
  var outputTokensInWindow: Int64
  var totalTokensInWindow: Int64
  var dailyTokenLimit: Int64
  var reportedCostMicrosInWindow: Int64
  var dailyReportedCostLimitMicros: Int64
  var estimatedUsageDispatches: Int
  var unpricedDispatches: Int

  enum CodingKeys: String, CodingKey {
    case dispatchesInWindow = "dispatches_in_window"
    case activeCalls = "active_calls"
    case dailyLimit = "daily_limit"
    case concurrencyLimit = "concurrency_limit"
    case dispatchesByKind = "dispatches_by_kind"
    case inputTokensInWindow = "input_tokens_in_window"
    case outputTokensInWindow = "output_tokens_in_window"
    case totalTokensInWindow = "total_tokens_in_window"
    case dailyTokenLimit = "daily_token_limit"
    case reportedCostMicrosInWindow = "reported_cost_micros_in_window"
    case dailyReportedCostLimitMicros = "daily_reported_cost_limit_micros"
    case estimatedUsageDispatches = "estimated_usage_dispatches"
    case unpricedDispatches = "unpriced_dispatches"
  }
}

struct GlobalModelResourceUsageSnapshot: Codable, Equatable {
  var resourceId: String
  var dispatches: Int
  var averageInputTokens: Int64
  var averageOutputTokens: Int64
  var averageTotalTokens: Int64
  var averageReportedCostMicros: Int64
  var pricedDispatches: Int
  var estimatedUsageDispatches: Int

  init(
    resourceId: String,
    dispatches: Int = 0,
    averageInputTokens: Int64 = 0,
    averageOutputTokens: Int64 = 0,
    averageTotalTokens: Int64 = 0,
    averageReportedCostMicros: Int64 = 0,
    pricedDispatches: Int = 0,
    estimatedUsageDispatches: Int = 0
  ) {
    self.resourceId = resourceId
    self.dispatches = dispatches
    self.averageInputTokens = averageInputTokens
    self.averageOutputTokens = averageOutputTokens
    self.averageTotalTokens = averageTotalTokens
    self.averageReportedCostMicros = averageReportedCostMicros
    self.pricedDispatches = pricedDispatches
    self.estimatedUsageDispatches = estimatedUsageDispatches
  }

  enum CodingKeys: String, CodingKey {
    case resourceId = "resource_id"
    case dispatches
    case averageInputTokens = "average_input_tokens"
    case averageOutputTokens = "average_output_tokens"
    case averageTotalTokens = "average_total_tokens"
    case averageReportedCostMicros = "average_reported_cost_micros"
    case pricedDispatches = "priced_dispatches"
    case estimatedUsageDispatches = "estimated_usage_dispatches"
  }
}

enum GlobalModelUsageEstimator {
  static func estimateTokens(_ texts: String...) -> Int64 {
    var asciiCharacters: Int64 = 0
    var nonAsciiCharacters: Int64 = 0
    for text in texts {
      for scalar in text.unicodeScalars {
        if scalar.value <= 0x7f {
          asciiCharacters += 1
        } else {
          nonAsciiCharacters += 1
        }
      }
    }
    let asciiTokens = (asciiCharacters + 3) / 4
    return max(saturatingAdd(asciiTokens, nonAsciiCharacters), 1)
  }

  static func saturatingAdd(_ left: Int64, _ right: Int64) -> Int64 {
    let safeLeft = max(left, 0)
    let safeRight = max(right, 0)
    if Int64.max - safeLeft < safeRight {
      return Int64.max
    }
    return safeLeft + safeRight
  }
}

enum GlobalModelCallBudgetPolicy {
  static let windowMillis: Int64 = 24 * 60 * 60 * 1_000
  static let minDailyLimit = 1
  static let maxDailyLimit = 200
  static let minConcurrencyLimit = 1
  static let maxConcurrencyLimit = 6
  static let minDailyTokenLimit: Int64 = 10_000
  static let maxDailyTokenLimit: Int64 = 10_000_000
  static let minDailyReportedCostLimitMicros: Int64 = 0
  static let maxDailyReportedCostLimitMicros: Int64 = 100_000_000
  static let minLeaseMillis: Int64 = 30_000
  static let maxLeaseMillis: Int64 = 15 * 60 * 1_000
  static let retryFloorMillis: Int64 = 1_000
  static let maxDispatchHistory = 1_000
  static let maxActiveLeases = 64

  static func acquire(
    state: GlobalModelCallBudgetState,
    leaseId: String,
    kind: GlobalModelCallKind,
    ownerKey: String,
    leaseMillis: Int64,
    dailyLimit: Int,
    concurrencyLimit: Int,
    nowMillis: Int64,
    resourceId: String = "",
    estimatedInputTokens: Int64 = 0,
    dailyTokenLimit: Int64 = GlobalModelCallBudgetPolicy.maxDailyTokenLimit,
    dailyReportedCostLimitMicros: Int64 = 0
  ) -> GlobalModelCallBudgetDecision {
    let normalized = normalize(state: state, nowMillis: nowMillis)
    if let existing = normalized.activeLeases.first(where: { $0.id == leaseId }) {
      return GlobalModelCallBudgetDecision(
        granted: true,
        state: normalized,
        leaseId: existing.id
      )
    }
    if let existing = normalized.dispatches.first(where: { $0.leaseId == leaseId }) {
      return denied(
        state: normalized,
        denial: .duplicateDispatch,
        nextEligibleAtMillis: max(nowMillis + retryFloorMillis, existing.startedAtMillis + windowMillis)
      )
    }

    let appliedDailyLimit = clamp(dailyLimit, minDailyLimit, maxDailyLimit)
    if normalized.dispatches.count >= appliedDailyLimit {
      let oldest = normalized.dispatches.map(\.startedAtMillis).min() ?? nowMillis
      return denied(
        state: normalized,
        denial: .dailyLimit,
        nextEligibleAtMillis: max(nowMillis + retryFloorMillis, oldest + windowMillis)
      )
    }

    let appliedTokenLimit = clamp(dailyTokenLimit, minDailyTokenLimit, maxDailyTokenLimit)
    let reservedInputTokens = clamp(estimatedInputTokens, 0, maxDailyTokenLimit)
    let usedTokens = totalTokens(normalized.dispatches)
    if usedTokens > 0 &&
      GlobalModelUsageEstimator.saturatingAdd(usedTokens, reservedInputTokens) > appliedTokenLimit {
      return denied(
        state: normalized,
        denial: .tokenLimit,
        nextEligibleAtMillis: nextTokenEligibility(
          dispatches: normalized.dispatches,
          reservedInputTokens: reservedInputTokens,
          limit: appliedTokenLimit,
          nowMillis: nowMillis
        )
      )
    }

    let appliedCostLimit = clamp(
      dailyReportedCostLimitMicros,
      minDailyReportedCostLimitMicros,
      maxDailyReportedCostLimitMicros
    )
    if appliedCostLimit > 0 && reportedCostMicros(normalized.dispatches) >= appliedCostLimit {
      return denied(
        state: normalized,
        denial: .reportedCostLimit,
        nextEligibleAtMillis: nextCostEligibility(
          dispatches: normalized.dispatches,
          limit: appliedCostLimit,
          nowMillis: nowMillis
        )
      )
    }

    let appliedConcurrencyLimit = clamp(concurrencyLimit, minConcurrencyLimit, maxConcurrencyLimit)
    if normalized.activeLeases.count >= appliedConcurrencyLimit {
      let earliestExpiry = normalized.activeLeases.map(\.expiresAtMillis).min() ?? nowMillis + retryFloorMillis
      return denied(
        state: normalized,
        denial: .concurrencyLimit,
        nextEligibleAtMillis: max(nowMillis + retryFloorMillis, earliestExpiry)
      )
    }

    let expiry = nowMillis + clamp(leaseMillis, minLeaseMillis, maxLeaseMillis)
    let lease = GlobalModelCallLease(
      id: leaseId,
      kind: kind,
      ownerKey: String(ownerKey.prefix(500)),
      startedAtMillis: nowMillis,
      expiresAtMillis: expiry
    )
    let dispatch = GlobalModelCallDispatch(
      leaseId: leaseId,
      kind: kind,
      startedAtMillis: nowMillis,
      resourceId: String(resourceId.prefix(500)),
      inputTokens: reservedInputTokens,
      usageEstimated: true
    )
    let updated = GlobalModelCallBudgetState(
      dispatches: Array((normalized.dispatches + [dispatch]).suffix(maxDispatchHistory)),
      activeLeases: Array((normalized.activeLeases + [lease]).suffix(maxActiveLeases))
    )
    return GlobalModelCallBudgetDecision(granted: true, state: updated, leaseId: leaseId)
  }

  static func availability(
    state: GlobalModelCallBudgetState,
    dailyLimit: Int,
    concurrencyLimit: Int,
    nowMillis: Int64,
    estimatedInputTokens: Int64 = 0,
    dailyTokenLimit: Int64 = GlobalModelCallBudgetPolicy.maxDailyTokenLimit,
    dailyReportedCostLimitMicros: Int64 = 0
  ) -> GlobalModelCallBudgetDecision {
    let normalized = normalize(state: state, nowMillis: nowMillis)
    let appliedDailyLimit = clamp(dailyLimit, minDailyLimit, maxDailyLimit)
    if normalized.dispatches.count >= appliedDailyLimit {
      let oldest = normalized.dispatches.map(\.startedAtMillis).min() ?? nowMillis
      return denied(
        state: normalized,
        denial: .dailyLimit,
        nextEligibleAtMillis: max(nowMillis + retryFloorMillis, oldest + windowMillis)
      )
    }
    let appliedTokenLimit = clamp(dailyTokenLimit, minDailyTokenLimit, maxDailyTokenLimit)
    let reservedInputTokens = clamp(estimatedInputTokens, 0, maxDailyTokenLimit)
    let usedTokens = totalTokens(normalized.dispatches)
    if usedTokens >= appliedTokenLimit ||
      usedTokens > 0 &&
      GlobalModelUsageEstimator.saturatingAdd(usedTokens, reservedInputTokens) > appliedTokenLimit {
      return denied(
        state: normalized,
        denial: .tokenLimit,
        nextEligibleAtMillis: nextTokenEligibility(
          dispatches: normalized.dispatches,
          reservedInputTokens: reservedInputTokens,
          limit: appliedTokenLimit,
          nowMillis: nowMillis
        )
      )
    }
    let appliedCostLimit = clamp(
      dailyReportedCostLimitMicros,
      minDailyReportedCostLimitMicros,
      maxDailyReportedCostLimitMicros
    )
    if appliedCostLimit > 0 && reportedCostMicros(normalized.dispatches) >= appliedCostLimit {
      return denied(
        state: normalized,
        denial: .reportedCostLimit,
        nextEligibleAtMillis: nextCostEligibility(
          dispatches: normalized.dispatches,
          limit: appliedCostLimit,
          nowMillis: nowMillis
        )
      )
    }
    let appliedConcurrencyLimit = clamp(concurrencyLimit, minConcurrencyLimit, maxConcurrencyLimit)
    if normalized.activeLeases.count >= appliedConcurrencyLimit {
      let earliestExpiry = normalized.activeLeases.map(\.expiresAtMillis).min() ?? nowMillis + retryFloorMillis
      return denied(
        state: normalized,
        denial: .concurrencyLimit,
        nextEligibleAtMillis: max(nowMillis + retryFloorMillis, earliestExpiry)
      )
    }
    return GlobalModelCallBudgetDecision(granted: true, state: normalized)
  }

  static func complete(
    state: GlobalModelCallBudgetState,
    leaseId: String,
    inputTokens: Int64,
    outputTokens: Int64,
    reportedCostMicros: Int64,
    responseText: String,
    nowMillis: Int64
  ) -> GlobalModelCallBudgetState {
    let normalized = normalize(state: state, nowMillis: nowMillis)
    guard let dispatch = normalized.dispatches.first(where: { $0.leaseId == leaseId }) else {
      return GlobalModelCallBudgetState(
        dispatches: normalized.dispatches,
        activeLeases: normalized.activeLeases.filter { $0.id != leaseId }
      )
    }
    let hasActualInput = inputTokens > 0
    let hasActualOutput = outputTokens > 0
    let resolvedInput = hasActualInput ? inputTokens : dispatch.inputTokens
    let resolvedOutput = hasActualOutput ? outputTokens :
      (responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : GlobalModelUsageEstimator.estimateTokens(responseText))
    let updatedDispatch = GlobalModelCallDispatch(
      leaseId: dispatch.leaseId,
      kind: dispatch.kind,
      startedAtMillis: dispatch.startedAtMillis,
      resourceId: dispatch.resourceId,
      inputTokens: max(resolvedInput, 0),
      outputTokens: max(resolvedOutput, 0),
      reportedCostMicros: max(reportedCostMicros, 0),
      usageEstimated: !hasActualInput || !hasActualOutput,
      completedAtMillis: clamp(nowMillis, dispatch.startedAtMillis, nowMillis)
    )
    return GlobalModelCallBudgetState(
      dispatches: normalized.dispatches.map { $0.leaseId == leaseId ? updatedDispatch : $0 },
      activeLeases: normalized.activeLeases.filter { $0.id != leaseId }
    )
  }

  static func release(
    state: GlobalModelCallBudgetState,
    leaseId: String,
    nowMillis: Int64
  ) -> GlobalModelCallBudgetState {
    let normalized = normalize(state: state, nowMillis: nowMillis)
    return GlobalModelCallBudgetState(
      dispatches: normalized.dispatches.map { dispatch in
        guard dispatch.leaseId == leaseId && dispatch.completedAtMillis <= 0 else {
          return dispatch
        }
        var updated = dispatch
        updated.completedAtMillis = max(nowMillis, dispatch.startedAtMillis)
        return updated
      },
      activeLeases: normalized.activeLeases.filter { $0.id != leaseId }
    )
  }

  static func cancel(
    state: GlobalModelCallBudgetState,
    leaseId: String,
    nowMillis: Int64
  ) -> GlobalModelCallBudgetState {
    let normalized = normalize(state: state, nowMillis: nowMillis)
    return GlobalModelCallBudgetState(
      dispatches: normalized.dispatches.filter { $0.leaseId != leaseId },
      activeLeases: normalized.activeLeases.filter { $0.id != leaseId }
    )
  }

  static func normalize(
    state: GlobalModelCallBudgetState,
    nowMillis: Int64
  ) -> GlobalModelCallBudgetState {
    let windowStart = nowMillis - windowMillis
    var seenDispatches: Set<String> = []
    let dispatches = state.dispatches.compactMap { dispatch -> GlobalModelCallDispatch? in
      guard !dispatch.leaseId.isEmpty,
            dispatch.startedAtMillis > 0,
            dispatch.startedAtMillis > windowStart,
            !seenDispatches.contains(dispatch.leaseId) else {
        return nil
      }
      seenDispatches.insert(dispatch.leaseId)
      return GlobalModelCallDispatch(
        leaseId: dispatch.leaseId,
        kind: dispatch.kind,
        startedAtMillis: min(dispatch.startedAtMillis, nowMillis),
        resourceId: String(dispatch.resourceId.prefix(500)),
        inputTokens: max(dispatch.inputTokens, 0),
        outputTokens: max(dispatch.outputTokens, 0),
        reportedCostMicros: max(dispatch.reportedCostMicros, 0),
        usageEstimated: dispatch.usageEstimated,
        completedAtMillis: clamp(dispatch.completedAtMillis, 0, nowMillis)
      )
    }
    .sorted { $0.startedAtMillis < $1.startedAtMillis }

    var seenLeases: Set<String> = []
    let activeLeases = state.activeLeases.compactMap { lease -> GlobalModelCallLease? in
      guard !lease.id.isEmpty,
            lease.startedAtMillis > 0,
            lease.expiresAtMillis > nowMillis,
            !seenLeases.contains(lease.id) else {
        return nil
      }
      seenLeases.insert(lease.id)
      return GlobalModelCallLease(
        id: lease.id,
        kind: lease.kind,
        ownerKey: String(lease.ownerKey.prefix(500)),
        startedAtMillis: min(lease.startedAtMillis, nowMillis),
        expiresAtMillis: lease.expiresAtMillis
      )
    }
    .sorted { $0.startedAtMillis < $1.startedAtMillis }

    return GlobalModelCallBudgetState(
      dispatches: Array(dispatches.suffix(maxDispatchHistory)),
      activeLeases: Array(activeLeases.suffix(maxActiveLeases))
    )
  }

  static func snapshot(
    state: GlobalModelCallBudgetState,
    dailyLimit: Int,
    concurrencyLimit: Int,
    nowMillis: Int64,
    dailyTokenLimit: Int64 = GlobalModelCallBudgetPolicy.maxDailyTokenLimit,
    dailyReportedCostLimitMicros: Int64 = 0
  ) -> GlobalModelCallBudgetSnapshot {
    let normalized = normalize(state: state, nowMillis: nowMillis)
    let byKind = Dictionary(
      uniqueKeysWithValues: GlobalModelCallKind.allCases.map { kind in
        (kind.rawValue, normalized.dispatches.filter { $0.kind == kind }.count)
      }
    )
    return GlobalModelCallBudgetSnapshot(
      dispatchesInWindow: normalized.dispatches.count,
      activeCalls: normalized.activeLeases.count,
      dailyLimit: clamp(dailyLimit, minDailyLimit, maxDailyLimit),
      concurrencyLimit: clamp(concurrencyLimit, minConcurrencyLimit, maxConcurrencyLimit),
      dispatchesByKind: byKind,
      inputTokensInWindow: totalInputTokens(normalized.dispatches),
      outputTokensInWindow: totalOutputTokens(normalized.dispatches),
      totalTokensInWindow: totalTokens(normalized.dispatches),
      dailyTokenLimit: clamp(dailyTokenLimit, minDailyTokenLimit, maxDailyTokenLimit),
      reportedCostMicrosInWindow: reportedCostMicros(normalized.dispatches),
      dailyReportedCostLimitMicros: clamp(
        dailyReportedCostLimitMicros,
        minDailyReportedCostLimitMicros,
        maxDailyReportedCostLimitMicros
      ),
      estimatedUsageDispatches: normalized.dispatches.filter(\.usageEstimated).count,
      unpricedDispatches: normalized.dispatches.filter { $0.reportedCostMicros <= 0 }.count
    )
  }

  static func resourceUsage(
    dispatches: [GlobalModelCallDispatch],
    resourceId: String
  ) -> GlobalModelResourceUsageSnapshot {
    let matching = dispatches.filter { $0.resourceId == resourceId && !resourceId.isEmpty }
    guard !matching.isEmpty else {
      return GlobalModelResourceUsageSnapshot(resourceId: resourceId)
    }
    let priced = matching.filter { $0.reportedCostMicros > 0 }
    return GlobalModelResourceUsageSnapshot(
      resourceId: resourceId,
      dispatches: matching.count,
      averageInputTokens: totalInputTokens(matching) / Int64(matching.count),
      averageOutputTokens: totalOutputTokens(matching) / Int64(matching.count),
      averageTotalTokens: totalTokens(matching) / Int64(matching.count),
      averageReportedCostMicros: priced.isEmpty ? 0 : reportedCostMicros(priced) / Int64(priced.count),
      pricedDispatches: priced.count,
      estimatedUsageDispatches: matching.filter(\.usageEstimated).count
    )
  }

  static func totalInputTokens(_ dispatches: [GlobalModelCallDispatch]) -> Int64 {
    dispatches.reduce(0) { GlobalModelUsageEstimator.saturatingAdd($0, $1.inputTokens) }
  }

  static func totalOutputTokens(_ dispatches: [GlobalModelCallDispatch]) -> Int64 {
    dispatches.reduce(0) { GlobalModelUsageEstimator.saturatingAdd($0, $1.outputTokens) }
  }

  static func totalTokens(_ dispatches: [GlobalModelCallDispatch]) -> Int64 {
    dispatches.reduce(0) { GlobalModelUsageEstimator.saturatingAdd($0, $1.totalTokens) }
  }

  static func reportedCostMicros(_ dispatches: [GlobalModelCallDispatch]) -> Int64 {
    dispatches.reduce(0) { GlobalModelUsageEstimator.saturatingAdd($0, $1.reportedCostMicros) }
  }

  static func leaseId(
    kind: GlobalModelCallKind,
    ownerKey: String
  ) -> String {
    "model-call:\(stableKey(kind.rawValue, ownerKey))"
  }

  private static func nextTokenEligibility(
    dispatches: [GlobalModelCallDispatch],
    reservedInputTokens: Int64,
    limit: Int64,
    nowMillis: Int64
  ) -> Int64 {
    var remaining = totalTokens(dispatches)
    for dispatch in dispatches.sorted(by: { $0.startedAtMillis < $1.startedAtMillis }) {
      remaining = max(remaining - dispatch.totalTokens, 0)
      if remaining == 0 ||
        GlobalModelUsageEstimator.saturatingAdd(remaining, reservedInputTokens) <= limit {
        return max(nowMillis + retryFloorMillis, dispatch.startedAtMillis + windowMillis)
      }
    }
    return nowMillis + windowMillis
  }

  private static func nextCostEligibility(
    dispatches: [GlobalModelCallDispatch],
    limit: Int64,
    nowMillis: Int64
  ) -> Int64 {
    var remaining = reportedCostMicros(dispatches)
    for dispatch in dispatches.sorted(by: { $0.startedAtMillis < $1.startedAtMillis }) {
      remaining = max(remaining - dispatch.reportedCostMicros, 0)
      if remaining < limit {
        return max(nowMillis + retryFloorMillis, dispatch.startedAtMillis + windowMillis)
      }
    }
    return nowMillis + windowMillis
  }

  private static func denied(
    state: GlobalModelCallBudgetState,
    denial: GlobalModelCallBudgetDenial,
    nextEligibleAtMillis: Int64
  ) -> GlobalModelCallBudgetDecision {
    GlobalModelCallBudgetDecision(
      granted: false,
      state: state,
      denial: denial,
      nextEligibleAtMillis: nextEligibleAtMillis
    )
  }

  private static func stableKey(_ values: String...) -> String {
    let normalized = values
      .map { normalizeText($0) }
      .joined(separator: "|")
      .prefix(2_000)
    let digest = SHA256.hash(data: Data(String(normalized).utf8))
    return digest.map { String(format: "%02x", $0) }.joined().prefix(32).description
  }

  private static func normalizeText(_ value: String) -> String {
    value.lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
  }
}
