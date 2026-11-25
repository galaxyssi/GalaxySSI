import Foundation

struct AgentIOSWebSourceReceipt {
  var sourceID: String
  var status: String
  var durationMillis: Int64
  var resultCount: Int

  var isValid: Bool {
    AgentIOSWebSourceHealth.validID(sourceID) && ["completed", "empty", "failed", "cancelled"].contains(status)
  }

  func publicValue() -> AgentMcpJSONObject {
    ["source_id": .string(sourceID), "status": .string(status),
     "duration_millis": .int(max(0, durationMillis)), "result_count": .int(Int64(max(0, resultCount)))]
  }
}

struct AgentIOSWebSourceHealth: Codable, Equatable {
  static let maximumSources = 512
  var sourceID: String
  var attempts: Int64 = 0
  var successes: Int64 = 0
  var emptyResponses: Int64 = 0
  var failures: Int64 = 0
  var consecutiveFailures: Int64 = 0
  var ewmaLatencyMillis: Double = 0
  var ewmaResultCount: Double = 0
  var lastStatus = ""
  var lastAttemptAtMillis: Int64 = 0
  var lastSuccessAtMillis: Int64 = 0
  var circuitOpenUntilMillis: Int64 = 0

  static func validID(_ value: String) -> Bool {
    (1...64).contains(value.count) && value.first.map { "abcdefghijklmnopqrstuvwxyz0123456789".contains($0) } == true &&
      value.allSatisfy { "abcdefghijklmnopqrstuvwxyz0123456789_-".contains($0) }
  }

  var isValid: Bool {
    Self.validID(sourceID) && [attempts, successes, emptyResponses, failures, consecutiveFailures,
      lastAttemptAtMillis, lastSuccessAtMillis, circuitOpenUntilMillis].allSatisfy { $0 >= 0 } &&
      ["", "completed", "empty", "failed", "cancelled"].contains(lastStatus) &&
      ewmaLatencyMillis.isFinite && (0...60_000).contains(ewmaLatencyMillis) &&
      ewmaResultCount.isFinite && (0...24).contains(ewmaResultCount)
  }

  func circuitState(now: Int64) -> String {
    if circuitOpenUntilMillis > now { return "open" }
    return consecutiveFailures >= 3 ? "half_open" : "closed"
  }

  var routingScore: Double {
    let reliable = (Double(successes) + Double(emptyResponses) + 2) / (Double(attempts) + 4)
    let speed = ewmaLatencyMillis <= 0 ? 0.6 : 1 / (1 + ewmaLatencyMillis / 3000)
    return reliable * 1.1 + speed * 0.5 + min(ewmaResultCount / 8, 1) * 0.35 +
      1 / sqrt(Double(attempts) + 1) * 0.25
  }

  func evolved(_ receipt: AgentIOSWebSourceReceipt, now: Int64) -> Self {
    var next = self
    next.lastStatus = receipt.status
    next.lastAttemptAtMillis = max(0, now)
    if receipt.status == "cancelled" { return next }
    let latency = Double(min(max(0, receipt.durationMillis), 60_000))
    let results = Double(min(max(0, receipt.resultCount), 24))
    next.ewmaLatencyMillis = attempts == 0 ? latency : ewmaLatencyMillis * 0.75 + latency * 0.25
    next.ewmaResultCount = attempts == 0 ? results : ewmaResultCount * 0.75 + results * 0.25
    let successful = ["completed", "empty"].contains(receipt.status)
    next.attempts = Self.increment(attempts)
    if receipt.status == "completed" { next.successes = Self.increment(successes) }
    if receipt.status == "empty" { next.emptyResponses = Self.increment(emptyResponses) }
    if !successful { next.failures = Self.increment(failures) }
    next.consecutiveFailures = successful ? 0 : Self.increment(consecutiveFailures)
    next.circuitOpenUntilMillis = 0
    if !successful, next.consecutiveFailures >= 3 {
      let exponent = min(next.consecutiveFailures - 3, 10)
      let cooldown = min(Int64(1_800_000), Int64(60_000) * (Int64(1) << exponent))
      let end = max(0, now).addingReportingOverflow(cooldown)
      next.circuitOpenUntilMillis = end.overflow ? Int64.max : end.partialValue
    }
    if successful { next.lastSuccessAtMillis = max(0, now) }
    return next
  }

  func publicValue(now: Int64) -> AgentMcpJSONObject {
    ["source_id": .string(sourceID), "attempts": .int(attempts), "successes": .int(successes),
     "empty_responses": .int(emptyResponses), "failures": .int(failures),
     "consecutive_failures": .int(consecutiveFailures), "ewma_latency_millis": .double(ewmaLatencyMillis),
     "ewma_result_count": .double(ewmaResultCount), "last_status": .string(lastStatus),
     "last_attempt_at_millis": .int(lastAttemptAtMillis), "last_success_at_millis": .int(lastSuccessAtMillis),
     "circuit_state": .string(circuitState(now: now)), "circuit_open_until_millis": .int(circuitOpenUntilMillis),
     "routing_score": .double(routingScore)]
  }

  private static func increment(_ value: Int64) -> Int64 { value == Int64.max ? value : value + 1 }
  static func elapsed(from: Int64, to: Int64) -> Int64 {
    let elapsed = to.subtractingReportingOverflow(from)
    return elapsed.overflow ? 0 : min(max(0, elapsed.partialValue), 60_000)
  }
}

enum AgentIOSWebSourceHealthRouting {
  struct Selection {
    var selected: [String]
    var skipped: [AgentIOSWebSourceHealth]
  }

  static func select(providers: [String], preferred: Set<String>, health: [String: AgentIOSWebSourceHealth],
                     explicit: Bool, fanout: Int, now: Int64) -> Selection {
    let limit = min(max(fanout, 1), 32)
    if explicit { return Selection(selected: Array(providers.prefix(limit)), skipped: []) }
    let skipped = providers.compactMap { health[$0] }.filter { $0.circuitState(now: now) == "open" }
    let blocked = Set(skipped.map(\.sourceID))
    let selected = providers.enumerated().filter { !blocked.contains($0.element) }.sorted { left, right in
      let leftScore = (preferred.contains(left.element) ? 2.5 : 0) +
        (health[left.element] ?? AgentIOSWebSourceHealth(sourceID: left.element)).routingScore
      let rightScore = (preferred.contains(right.element) ? 2.5 : 0) +
        (health[right.element] ?? AgentIOSWebSourceHealth(sourceID: right.element)).routingScore
      return leftScore == rightScore ? left.offset < right.offset : leftScore > rightScore
    }.prefix(limit).map(\.element)
    return Selection(selected: selected, skipped: skipped)
  }
}
