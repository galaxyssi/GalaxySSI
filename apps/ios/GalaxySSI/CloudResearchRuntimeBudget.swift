import Foundation

struct CloudResearchConfiguration: Codable, Hashable {
  var toolCalls: Int?
  var modelRounds: Int?
  var activeMinutes: Int?
  var toolTimeoutSeconds: Int?
  var modelTimeoutSeconds: Int?
  var evidenceCharacters: Int?

  private enum CodingKeys: String, CodingKey {
    case toolCalls = "tool_calls"
    case modelRounds = "model_rounds"
    case activeMinutes = "active_minutes"
    case toolTimeoutSeconds = "tool_timeout_seconds"
    case modelTimeoutSeconds = "model_timeout_seconds"
    case evidenceCharacters = "evidence_chars"
  }

  init(from decoder: Decoder) throws {
    let values = try? decoder.container(keyedBy: CodingKeys.self)
    func integer(_ key: CodingKeys) -> Int? {
      if let number = try? values?.decode(Int.self, forKey: key) { return number }
      if let text = try? values?.decode(String.self, forKey: key) { return Int(text) }
      return nil
    }
    toolCalls = integer(.toolCalls)
    modelRounds = integer(.modelRounds)
    activeMinutes = integer(.activeMinutes)
    toolTimeoutSeconds = integer(.toolTimeoutSeconds)
    modelTimeoutSeconds = integer(.modelTimeoutSeconds)
    evidenceCharacters = integer(.evidenceCharacters)
  }
}

final class CloudResearchRuntimeBudget {
  struct Limits {
    var tools = 128
    var rounds = 64
    var activeMillis: Int64 = 20 * 60_000
    var toolMillis: Int64 = 45_000
    var modelMillis: Int64 = 120_000
    var evidenceCharacters = 2_000_000

    static func configured(_ configuration: CloudResearchConfiguration?) -> Self {
      guard let configuration else { return .init() }
      func limit(_ value: Int?, fallback: Int, range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value ?? fallback))
      }
      return Self(
        tools: limit(configuration.toolCalls, fallback: 128, range: 4...512),
        rounds: limit(configuration.modelRounds, fallback: 64, range: 4...256),
        activeMillis: Int64(limit(configuration.activeMinutes, fallback: 20, range: 1...120)) * 60_000,
        toolMillis: Int64(limit(configuration.toolTimeoutSeconds, fallback: 45, range: 5...180)) * 1_000,
        modelMillis: Int64(limit(configuration.modelTimeoutSeconds, fallback: 120, range: 15...300)) * 1_000,
        evidenceCharacters: limit(configuration.evidenceCharacters, fallback: 2_000_000, range: 24_000...8_000_000)
      )
    }
  }

  let limits: Limits
  private let clock: () -> Int64
  private let started: Int64
  private(set) var toolCalls = 0
  private(set) var modelRounds = 0
  private(set) var evidenceCharacters = 0
  private(set) var stalledBatches = 0
  private var sources = Set<String>()
  private var observations = Set<String>()
  private var triedInterruptedSynthesis = false
  private var triedEmptySynthesis = false

  init(limits: Limits = .init(), clock: @escaping () -> Int64 = { Int64(ProcessInfo.processInfo.systemUptime * 1_000) }) {
    self.limits = limits
    self.clock = clock
    started = clock()
  }

  var stopReason: String? {
    if toolCalls >= limits.tools { return "tool_limit" }
    if modelRounds >= limits.rounds { return "round_limit" }
    if clock() - started >= limits.activeMillis { return "active_time_limit" }
    if evidenceCharacters >= limits.evidenceCharacters { return "evidence_limit" }
    if stalledBatches >= 3 { return "no_new_evidence" }
    return nil
  }

  func beginRound() { modelRounds += 1 }

  func reserveTools(_ count: Int) -> Bool {
    guard stopReason == nil, count >= 0, count <= limits.tools - toolCalls else { return false }
    toolCalls += count
    return true
  }

  static func isRetrievalTool(_ name: String) -> Bool {
    if name.lowercased() == "web_weather" { return true }
    guard let operation = CloudWebGrounding.operation(forToolName: name) else { return false }
    return [.search, .fetch, .research, .agent, .crawl, .extract, .findSimilar, .diff].contains(operation)
  }

  @discardableResult
  func observe(tool: String, output: String) -> Bool {
    guard Self.isRetrievalTool(tool) else { return false }
    evidenceCharacters += min(output.utf16.count, limits.evidenceCharacters)
    guard let object = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(output.utf8)) else { return false }
    let pack = object["evidence_pack"]?.objectValue ?? object
    guard pack["protocol"] == .string(AgentIOSWebEvidencePack.protocolId) else { return false }
    var changed = false
    for value in pack["items"]?.arrayValue ?? [] {
      guard let item = value.objectValue, let url = item["url"]?.stringValue, !url.isEmpty,
            let hash = item["content_sha256"]?.stringValue, hash.utf8.count == 64 else { continue }
      let canonical = AgentIOSWebEvidencePack.canonicalURL(url)
      sources.insert(canonical)
      var identity = canonical + "\n" + hash
      if let window = object["reading_window"]?.objectValue,
         let start = window["offset"]?.intValue, let end = window["end_offset"]?.intValue, end > start {
        identity += "\n\(window.string("document_sha256")):\(start):\(end)"
      }
      if observations.insert(identity).inserted { changed = true }
    }
    return changed
  }

  func finishRetrievalBatch(madeProgress: Bool) {
    stalledBatches = madeProgress ? 0 : stalledBatches + 1
  }

  func requestInterruptedSynthesis(hasEvidence: Bool, finalizing: Bool) -> Bool {
    guard hasEvidence, !finalizing, !triedInterruptedSynthesis else { return false }
    triedInterruptedSynthesis = true
    return true
  }

  func requestEmptySynthesis(_ draft: String, hasEvidence: Bool) -> Bool {
    guard hasEvidence, draft.isBlank, !triedEmptySynthesis else { return false }
    triedEmptySynthesis = true
    return true
  }

  static func hasCitableEvidence(_ evidence: [(String, String)]) -> Bool {
    AgentIOSWebEvidenceVerification.validateAnswer("", encodedToolResults: evidence).verifiedEvidenceItemCount > 0
  }

  static func canRecover(_ error: ModelStreamError) -> Bool {
    error.retryable && error.code != "CANCELLED" && error.httpStatus != 429
  }

  static func canRecover(_ error: Error) -> Bool {
    if let failure = error as? CloudHTTPFailure { return failure.statusCode == 408 || (500...599).contains(failure.statusCode) }
    guard let network = error as? URLError else { return false }
    return [.timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet]
      .contains(network.code)
  }

  func guidance(stopped reason: String? = nil) -> String {
    let state = "Research state: \(sources.count) distinct source URLs and \(toolCalls) executed tool calls. "
    if let reason {
      return state + "Retrieval stopped (\(reason)). Do not call tools. Synthesize a concise answer supported by the existing passages, " +
        "and state material unresolved questions. Do not imply complete coverage or independent verification."
    }
    return state + "Search again only for a specific unresolved question or material conflict. Source count is not proof. " +
      "When names are ambiguous, disambiguate before asserting an identity or relationship. Lead with any uncertainty."
  }
}

enum CloudResearchRoundDeadline {
  static func run<T: Sendable>(millis: Int64, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask(operation: operation)
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(millis) * 1_000_000)
        throw URLError(.timedOut)
      }
      defer { group.cancelAll() }
      guard let result = try await group.next() else { throw CancellationError() }
      return result
    }
  }

  static func stream(_ source: AsyncThrowingStream<ModelStreamEvent, Error>, millis: Int64)
    -> AsyncThrowingStream<ModelStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let timeout = Task {
        do {
          try await Task.sleep(nanoseconds: UInt64(millis) * 1_000_000)
          continuation.finish(throwing: URLError(.timedOut))
        } catch {}
      }
      let reader = Task {
        defer { timeout.cancel() }
        do {
          for try await event in source {
            try Task.checkCancellation()
            continuation.yield(event)
          }
          continuation.finish()
        } catch { continuation.finish(throwing: error) }
      }
      continuation.onTermination = { _ in
        reader.cancel()
        timeout.cancel()
      }
    }
  }
}
