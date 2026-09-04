import Foundation
@testable import SignalASI

struct AgentIOSPr2643AcceptanceCase: Equatable {
  var index: Int
  var category: String
  var marker: String
  var prompt: String
  var expected: String
}

struct AgentIOSPr2643ReplyObservation {
  var response: AgentTranscriptEntry?
  var entries: [AgentTranscriptEntry]
  var recordedRun: AgentRecordedRun?
  var latencyMillis: Int64
}

struct AgentIOSPr2643CaseResult: Equatable {
  var testCase: AgentIOSPr2643AcceptanceCase
  var attempt: Int
  var latencyMillis: Int64
  var passed: Bool
  var failures: [String]
}

struct AgentIOSPr2643SuiteCheckpoint: Equatable {
  var completedBatches: Int
  var completedCases: Int
  var passedCases: Int
  var invocationCount: Int
}

struct AgentIOSPr2643SuiteResult: Equatable {
  var results: [AgentIOSPr2643CaseResult]
  var invocationCount: Int
  var checkpoints: [AgentIOSPr2643SuiteCheckpoint]
}

protocol AgentIOSPr2643RealReplyExecuting {
  func execute(
    _ testCase: AgentIOSPr2643AcceptanceCase,
    target: AgentCallableTarget,
    attempt: Int
  ) async -> AgentIOSPr2643ReplyObservation
}

enum AgentIOSPr2643TargetSelector {
  static func codexDesktopTarget(_ targets: [AgentCallableTarget]) -> AgentCallableTarget? {
    targets.first {
      $0.status == .available &&
        $0.kind == .agent &&
        $0.capabilities.contains(.chat) &&
        $0.id.lowercased().hasSuffix(":codex")
    }
  }
}

enum AgentIOSPr2643ReplyVerifier {
  static func evaluate(
    testCase: AgentIOSPr2643AcceptanceCase,
    target: AgentCallableTarget,
    observation: AgentIOSPr2643ReplyObservation,
    attempt: Int
  ) -> AgentIOSPr2643CaseResult {
    var failures: [String] = []
    let expectedLine = "\(testCase.marker) | \(testCase.expected)"
    guard let response = observation.response else {
      return AgentIOSPr2643CaseResult(
        testCase: testCase,
        attempt: attempt,
        latencyMillis: observation.latencyMillis,
        passed: false,
        failures: ["timeout_without_assistant_reply"]
      )
    }
    if response.text.trimmingCharacters(in: .whitespacesAndNewlines) != expectedLine {
      failures.append("answer_mismatch")
    }
    if !response.dedupeKey.hasPrefix("assistant-final:") {
      failures.append("not_final_response")
    }
    if observation.entries.contains(where: { $0.dedupeKey.hasPrefix("fast-local:") }) {
      failures.append("fast_local_path")
    }
    let connectorEvidence = observation.entries.contains {
      $0.role == .process &&
        ($0.dedupeKey.hasPrefix("connector-event:") || $0.dedupeKey.hasPrefix("execution-loop:"))
    }
    if !connectorEvidence { failures.append("missing_connector_evidence") }
    if observation.recordedRun?.status != .completed { failures.append("run_not_completed") }
    if observation.recordedRun?.executionResourceId != target.id { failures.append("wrong_execution_resource") }
    return AgentIOSPr2643CaseResult(
      testCase: testCase,
      attempt: attempt,
      latencyMillis: observation.latencyMillis,
      passed: failures.isEmpty,
      failures: failures
    )
  }
}

final class AgentIOSPr2643AcceptanceRunner {
  static let batchSize = 5
  static let maximumAttempts = 2

  private let executor: AgentIOSPr2643RealReplyExecuting

  init(executor: AgentIOSPr2643RealReplyExecuting) {
    self.executor = executor
  }

  func run(
    cases: [AgentIOSPr2643AcceptanceCase],
    target: AgentCallableTarget,
    checkpoint: (AgentIOSPr2643SuiteCheckpoint) -> Void
  ) async -> AgentIOSPr2643SuiteResult {
    var results: [Int: AgentIOSPr2643CaseResult] = [:]
    var invocationCount = 0
    var checkpoints: [AgentIOSPr2643SuiteCheckpoint] = []
    let batches = stride(from: 0, to: cases.count, by: Self.batchSize).map {
      Array(cases[$0..<min($0 + Self.batchSize, cases.count)])
    }
    for (batchIndex, batch) in batches.enumerated() {
      var pending = batch
      for attempt in 1...Self.maximumAttempts where !pending.isEmpty {
        var nextPending: [AgentIOSPr2643AcceptanceCase] = []
        for testCase in pending {
          invocationCount += 1
          let observation = await executor.execute(testCase, target: target, attempt: attempt)
          let result = AgentIOSPr2643ReplyVerifier.evaluate(
            testCase: testCase,
            target: target,
            observation: observation,
            attempt: attempt
          )
          results[testCase.index] = result
          if !result.passed { nextPending.append(testCase) }
        }
        pending = nextPending
      }
      let value = AgentIOSPr2643SuiteCheckpoint(
        completedBatches: batchIndex + 1,
        completedCases: results.count,
        passedCases: results.values.filter(\.passed).count,
        invocationCount: invocationCount
      )
      checkpoints.append(value)
      checkpoint(value)
    }
    return AgentIOSPr2643SuiteResult(
      results: results.values.sorted { $0.testCase.index < $1.testCase.index },
      invocationCount: invocationCount,
      checkpoints: checkpoints
    )
  }
}

enum AgentIOSPr2643AcceptanceCorpus {
  static let cases: [AgentIOSPr2643AcceptanceCase] = categories.enumerated().flatMap { categoryOffset, category in
    (1...20).map { variant in
      let index = categoryOffset * 20 + variant
      let marker = String(format: "IOS_LLM_%03d", index)
      let expected = expectedValue(category: category, variant: variant)
      return AgentIOSPr2643AcceptanceCase(
        index: index,
        category: category,
        marker: marker,
        prompt: "Do not use tools. Reply with exactly one line: \(marker) | \(expected)",
        expected: expected
      )
    }
  }

  private static func expectedValue(category: String, variant: Int) -> String {
    switch category {
    case "arithmetic": return String(variant + variant * 2)
    case "string": return "TOKEN-\(variant)"
    case "classification": return variant.isMultiple(of: 2) ? "EVEN" : "ODD"
    case "formatting": return String(format: "%04d", variant)
    default: return variant < 20 ? String(UnicodeScalar(64 + variant + 1)!) : "A"
    }
  }

  private static let categories = [
    "arithmetic", "string", "classification", "formatting", "reasoning"
  ]
}
