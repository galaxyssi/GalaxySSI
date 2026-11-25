import Foundation

struct AgentIOSWebExecutionBudget {
  private let duration: Int64
  private let started: Int64
  private let now: () -> Int64

  init(durationMillis: Int64, now: @escaping () -> Int64 = {
    Int64(ProcessInfo.processInfo.systemUptime * 1_000)
  }) {
    duration = min(max(durationMillis, 1), 300_000)
    self.now = now
    started = now()
  }

  var remainingMillis: Int64 {
    let elapsed = now().subtractingReportingOverflow(started)
    guard !elapsed.overflow, elapsed.partialValue >= 0 else { return 0 }
    return max(0, duration - min(duration, elapsed.partialValue))
  }

  var expired: Bool { remainingMillis == 0 }

  func invocation(parent: AgentNativeToolInvocation, input: AgentMcpJSONObject,
                  timeoutMillis: Int64, nowMillis: @escaping () -> Int64,
                  isCancelled: @escaping () -> Bool = { false }) throws -> AgentNativeToolInvocation {
    if parent.isCancellationRequested || isCancelled() { throw AgentNativeToolInvocationError.cancelled }
    let remaining = min(remainingMillis, parent.remainingTimeMillis, timeoutMillis)
    guard remaining > 0 else { throw AgentNativeToolInvocationError.timedOut }
    let now = nowMillis()
    let end = now.addingReportingOverflow(remaining)
    let deadline = min(parent.deadlineEpochMillis, end.overflow ? Int64.max : end.partialValue)
    return AgentNativeToolInvocation(descriptor: parent.descriptor, input: input, context: parent.context,
      startedAtEpochMillis: now, deadlineEpochMillis: deadline, hardDeadlineEpochMillis: deadline,
      nowMillis: nowMillis, cancellationRequested: { parent.isCancellationRequested || isCancelled() || self.expired },
      progressReporter: { _, _ in })
  }
}

enum AgentIOSWebSearchProfile: String {
  case fast, balanced, deep
  var fanout: Int { self == .fast ? 6 : (self == .deep ? 32 : 18) }
  var timeoutMillis: Int64 { self == .fast ? 6_000 : (self == .deep ? 35_000 : 15_000) }
}

enum AgentIOSWebSearchEnginePolicy {
  static var supported: Set<String> {
    Set(["bing", "baidu", "duckduckgo", "sogou_image"] +
      AgentIOSWebIntelligenceSourceCatalog.officialDocumentationSources.map(\.id))
  }
  static func canResolve(_ engines: [String]) -> Bool {
    engines.allSatisfy { supported.contains($0) || isLearnedID($0) }
  }
  private static func isLearnedID(_ value: String) -> Bool {
    value.hasPrefix("learned_") && value.count == 24 && value.dropFirst(8).allSatisfy { "0123456789abcdef".contains($0) }
  }
  static func accepts(_ engines: [String], learnedSources: [AgentIOSLearnedWebSource] = []) -> Bool {
    let allowed = supported.union(learnedSources.filter(\.isSearchEligible).map(\.sourceID))
    return engines.allSatisfy { allowed.contains($0) }
  }
}
