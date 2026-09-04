import Foundation

struct AgentIOSWebEvidenceFetchedDocument {
  var document: AgentMcpJSONObject
  var receipt: AgentMcpJSONObject
}

struct AgentIOSWebEvidenceReadBatch {
  var documents: [AgentMcpJSONObject]
  var receipts: [AgentMcpJSONObject]
  var candidateCount: Int
  var completedCount: Int
  var domainCount: Int
  var sufficient: Bool
  var earlyCompleted: Bool
  var completionReason: String
  var elapsedMillis: Int64
}

struct AgentIOSWebEvidenceFetchError: Error {
  var code: String
  var message: String
  var retryable: Bool
}

enum AgentIOSWebEvidenceCompletionPolicy {
  static let minimumSubstantialContentCharacters = 600

  static func hasSufficientEvidence(
    documents: [AgentMcpJSONObject],
    evidenceLimit: Int
  ) -> Bool {
    let requiredDocuments = min(max(evidenceLimit, 2), 4)
    guard documents.count >= requiredDocuments else { return false }
    let substantial = documents.filter {
      content($0).count >= minimumSubstantialContentCharacters
    }
    guard substantial.count >= requiredDocuments else { return false }
    let domains = Set(documents.compactMap { document in
      URL(string: documentURL(document))?.host?.lowercased()
    }.filter { !$0.isEmpty })
    let evidenceCharacters = documents.reduce(0) {
      $0 + min(content($1).count, 2_500)
    }
    return domains.count >= min(requiredDocuments, 3) &&
      evidenceCharacters >= requiredDocuments * minimumSubstantialContentCharacters
  }

  private static func content(_ document: AgentMcpJSONObject) -> String {
    document["content"]?.stringValue ?? document["text"]?.stringValue ?? ""
  }

  private static func documentURL(_ document: AgentMcpJSONObject) -> String {
    document["url"]?.stringValue ?? document["final_url"]?.stringValue ?? ""
  }
}

struct AgentIOSWebEvidenceReader {
  typealias FetchDocument = (
    _ url: String,
    _ timeoutMillis: Int64,
    _ isCancellationRequested: @escaping () -> Bool
  ) throws -> AgentIOSWebEvidenceFetchedDocument

  private struct Candidate {
    var index: Int
    var url: String
    var host: String
  }

  private struct Outcome {
    var index: Int
    var document: AgentMcpJSONObject?
    var receipt: AgentMcpJSONObject
  }

  private final class State {
    private let lock = NSLock()
    private var outcomes: [Int: Outcome] = [:]
    private var cancelled = false

    func record(_ outcome: Outcome) -> Bool {
      lock.lock()
      defer { lock.unlock() }
      guard !cancelled, outcomes[outcome.index] == nil else { return false }
      outcomes[outcome.index] = outcome
      return true
    }

    func snapshot() -> [Int: Outcome] {
      lock.lock()
      defer { lock.unlock() }
      return outcomes
    }

    func cancel() {
      lock.lock()
      cancelled = true
      lock.unlock()
    }

    func isCancelled() -> Bool {
      lock.lock()
      defer { lock.unlock() }
      return cancelled
    }
  }

  private final class HostGates {
    private let lock = NSLock()
    private var values: [String: DispatchSemaphore] = [:]
    private let permits: Int

    init(permits: Int) {
      self.permits = max(1, permits)
    }

    func gate(for host: String) -> DispatchSemaphore {
      lock.lock()
      defer { lock.unlock() }
      if let existing = values[host] { return existing }
      let created = DispatchSemaphore(value: permits)
      values[host] = created
      return created
    }
  }

  var uptimeMillis: () -> Int64 = {
    Int64((ProcessInfo.processInfo.systemUptime * 1_000).rounded())
  }

  func read(
    results: [AgentMcpJSONObject],
    evidenceLimit: Int,
    parallelism: Int,
    perHostParallelism: Int,
    timeoutMillis: Int64,
    maxRequestTimeoutMillis: Int64 = 12_000,
    earlyComplete: Bool,
    isCancellationRequested: @escaping () -> Bool = { false },
    checkpoint: @escaping () throws -> Void = {},
    fetchDocument: @escaping FetchDocument
  ) throws -> AgentIOSWebEvidenceReadBatch {
    let boundedEvidenceLimit = max(1, min(evidenceLimit, 24))
    let workerCount = max(1, min(parallelism, 6))
    let candidates = candidateList(
      results: results,
      limit: min(24, max(boundedEvidenceLimit * 2, boundedEvidenceLimit + workerCount))
    )
    guard !candidates.isEmpty else {
      return AgentIOSWebEvidenceReadBatch(
        documents: [],
        receipts: [],
        candidateCount: 0,
        completedCount: 0,
        domainCount: 0,
        sufficient: false,
        earlyCompleted: false,
        completionReason: "no_candidates",
        elapsedMillis: 0
      )
    }

    let started = uptimeMillis()
    let deadline = started + max(1, timeoutMillis)
    let clock = uptimeMillis
    let state = State()
    let hostGates = HostGates(permits: max(1, min(perHostParallelism, 2)))
    let completions = DispatchSemaphore(value: 0)
    let queue = OperationQueue()
    queue.name = "galaxyssi.ios.web-evidence"
    queue.qualityOfService = .userInitiated
    queue.maxConcurrentOperationCount = min(workerCount, candidates.count)

    for candidate in candidates {
      queue.addOperation {
        let cancelled = {
          state.isCancelled() || isCancellationRequested()
        }
        guard !cancelled() else { return }
        let gate = hostGates.gate(for: candidate.host)
        guard waitForGate(gate, deadline: deadline, uptimeMillis: clock, cancelled: cancelled) else {
          let outcome = Outcome(
            index: candidate.index,
            document: nil,
            receipt: deadlineReceipt(url: candidate.url, rank: candidate.index + 1)
          )
          if state.record(outcome) { completions.signal() }
          return
        }
        defer { gate.signal() }
        guard !cancelled() else { return }
        let remaining = max(0, deadline - clock())
        guard remaining > 0 else {
          let outcome = Outcome(
            index: candidate.index,
            document: nil,
            receipt: deadlineReceipt(url: candidate.url, rank: candidate.index + 1)
          )
          if state.record(outcome) { completions.signal() }
          return
        }
        let requestTimeout = max(1_000, min(maxRequestTimeoutMillis, remaining))
        let requestStarted = clock()
        let outcome: Outcome
        do {
          try checkpoint()
          let fetched = try fetchDocument(candidate.url, requestTimeout, cancelled)
          var receipt = fetched.receipt
          receipt["source_id"] = receipt["source_id"] ?? .string(sourceID(candidate.url))
          receipt["url"] = receipt["url"] ?? .string(candidate.url)
          receipt["rank"] = .int(Int64(candidate.index + 1))
          receipt["status"] = .string("completed")
          receipt["duration_millis"] = .int(max(0, clock() - requestStarted))
          receipt["result_count"] = .int(1)
          outcome = Outcome(index: candidate.index, document: fetched.document, receipt: receipt)
        } catch {
          outcome = Outcome(
            index: candidate.index,
            document: nil,
            receipt: errorReceipt(
              url: candidate.url,
              rank: candidate.index + 1,
              durationMillis: max(0, clock() - requestStarted),
              error: error
            )
          )
        }
        if state.record(outcome) { completions.signal() }
      }
    }

    var completionReason = "all_candidates_read"
    var earlyCompleted = false
    do {
      while state.snapshot().count < candidates.count {
        if isCancellationRequested() {
          throw AgentNativeToolInvocationError.cancelled
        }
        try checkpoint()
        let remaining = deadline - uptimeMillis()
        if remaining <= 0 {
          completionReason = "shared_deadline"
          break
        }
        if completions.wait(timeout: .now() + .milliseconds(Int(min(remaining, 100)))) == .timedOut {
          continue
        }
        let outcomes = state.snapshot()
        let documents = rankedDocuments(outcomes, limit: boundedEvidenceLimit)
        let sufficient = AgentIOSWebEvidenceCompletionPolicy.hasSufficientEvidence(
          documents: documents,
          evidenceLimit: boundedEvidenceLimit
        )
        if documents.count >= boundedEvidenceLimit {
          completionReason = "evidence_limit_reached"
          earlyCompleted = outcomes.count < candidates.count
          break
        }
        if earlyComplete && sufficient {
          completionReason = "sufficient_diverse_evidence"
          earlyCompleted = outcomes.count < candidates.count
          break
        }
      }
    } catch {
      state.cancel()
      queue.cancelAllOperations()
      throw error
    }

    state.cancel()
    queue.cancelAllOperations()
    let outcomes = state.snapshot()
    let documents = rankedDocuments(outcomes, limit: boundedEvidenceLimit)
    if completionReason == "all_candidates_read", documents.count >= boundedEvidenceLimit {
      completionReason = "evidence_limit_reached"
    }
    let receipts = candidates.map { candidate in
      outcomes[candidate.index]?.receipt ?? unfinishedReceipt(
        url: candidate.url,
        rank: candidate.index + 1,
        completionReason: completionReason
      )
    }
    let domains = Set(documents.compactMap {
      URL(string: $0["url"]?.stringValue ?? "")?.host?.lowercased()
    }.filter { !$0.isEmpty })
    return AgentIOSWebEvidenceReadBatch(
      documents: documents,
      receipts: receipts,
      candidateCount: candidates.count,
      completedCount: outcomes.count,
      domainCount: domains.count,
      sufficient: AgentIOSWebEvidenceCompletionPolicy.hasSufficientEvidence(
        documents: documents,
        evidenceLimit: boundedEvidenceLimit
      ),
      earlyCompleted: earlyCompleted,
      completionReason: completionReason,
      elapsedMillis: max(0, uptimeMillis() - started)
    )
  }

  private func candidateList(results: [AgentMcpJSONObject], limit: Int) -> [Candidate] {
    var seen = Set<String>()
    var candidates: [Candidate] = []
    for result in results {
      let rawURL = result["url"]?.stringValue ?? ""
      guard let url = canonicalURL(rawURL), seen.insert(url).inserted else { continue }
      candidates.append(
        Candidate(index: candidates.count, url: url, host: URL(string: url)?.host?.lowercased() ?? "")
      )
      if candidates.count >= limit { break }
    }
    return candidates
  }

  private func rankedDocuments(_ outcomes: [Int: Outcome], limit: Int) -> [AgentMcpJSONObject] {
    outcomes.keys.sorted().compactMap { outcomes[$0]?.document }.prefix(limit).map { $0 }
  }

  private func canonicalURL(_ value: String) -> String? {
    guard var components = URLComponents(
      string: value.trimmingCharacters(in: .whitespacesAndNewlines)
    ), components.scheme?.lowercased() == "https", let host = components.host?.lowercased(), !host.isEmpty else {
      return nil
    }
    components.scheme = "https"
    components.host = host
    components.fragment = nil
    if components.path.isEmpty { components.path = "/" }
    return components.string
  }
}

private func waitForGate(
  _ gate: DispatchSemaphore,
  deadline: Int64,
  uptimeMillis: () -> Int64,
  cancelled: () -> Bool
) -> Bool {
  while !cancelled() {
    let remaining = deadline - uptimeMillis()
    guard remaining > 0 else { return false }
    if gate.wait(timeout: .now() + .milliseconds(Int(min(remaining, 50)))) == .success {
      return true
    }
  }
  return false
}

private func sourceID(_ url: String) -> String {
  "research:\(AgentMcpJSONCodec.sha256(["url": .string(url)]).prefix(12))"
}

private func deadlineReceipt(url: String, rank: Int) -> AgentMcpJSONObject {
  [
    "source_id": .string(sourceID(url)),
    "url": .string(url),
    "rank": .int(Int64(rank)),
    "status": .string("timeout"),
    "duration_millis": .int(0),
    "result_count": .int(0),
    "error_code": .string("shared_deadline"),
    "error_message": .string("Shared evidence-read deadline elapsed"),
    "retryable": .bool(true)
  ]
}

private func unfinishedReceipt(url: String, rank: Int, completionReason: String) -> AgentMcpJSONObject {
  if completionReason == "shared_deadline" {
    return deadlineReceipt(url: url, rank: rank)
  }
  return [
    "source_id": .string(sourceID(url)),
    "url": .string(url),
    "rank": .int(Int64(rank)),
    "status": .string("cancelled"),
    "duration_millis": .int(0),
    "result_count": .int(0),
    "error_code": .string("sufficient_evidence"),
    "error_message": .string("Evidence target was met before this page was needed"),
    "retryable": .bool(false)
  ]
}

private func errorReceipt(
  url: String,
  rank: Int,
  durationMillis: Int64,
  error: Error
) -> AgentMcpJSONObject {
  let code: String
  let message: String
  let retryable: Bool
  if let fetchError = error as? AgentIOSWebEvidenceFetchError {
    code = fetchError.code
    message = fetchError.message
    retryable = fetchError.retryable
  } else if let invocationError = error as? AgentNativeToolInvocationError {
    switch invocationError {
    case .cancelled:
      code = "cancelled"
    case .timedOut:
      code = "timeout"
    }
    message = String(describing: invocationError)
    retryable = invocationError == .timedOut
  } else {
    code = "fetch_failed"
    message = error.localizedDescription
    retryable = false
  }
  let status: String
  if code == "cancelled" {
    status = "cancelled"
  } else if code.contains("timeout") {
    status = "timeout"
  } else if code.contains("private") || code.contains("blocked") {
    status = "blocked"
  } else {
    status = "failed"
  }
  return [
    "source_id": .string(sourceID(url)),
    "url": .string(url),
    "rank": .int(Int64(rank)),
    "status": .string(status),
    "duration_millis": .int(max(0, durationMillis)),
    "result_count": .int(0),
    "error_code": .string(code),
    "error_message": .string(String(message.prefix(1_000))),
    "retryable": .bool(retryable)
  ]
}
