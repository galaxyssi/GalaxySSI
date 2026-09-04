import XCTest
@testable import GalaxySSI

final class AgentIOSPr2643RealReplyAcceptanceTests: XCTestCase {
  func testCorpusContainsTwentyCasesInEachOfFiveCategories() {
    let cases = AgentIOSPr2643AcceptanceCorpus.cases

    XCTAssertEqual(cases.count, 100)
    XCTAssertEqual(Set(cases.map(\.index)), Set(1...100))
    XCTAssertEqual(Set(cases.map(\.marker)).count, 100)
    XCTAssertEqual(Dictionary(grouping: cases, by: \.category).mapValues(\.count), [
      "arithmetic": 20,
      "string": 20,
      "classification": 20,
      "formatting": 20,
      "reasoning": 20
    ])
  }

  func testSelectsOnlyAvailableChatCapableCodexDesktopAgent() throws {
    let unavailable = target(id: "desktop:codex", status: .disconnected)
    let generic = target(id: "desktop:other")
    let codex = target(id: "desktop-device:codex")

    XCTAssertEqual(
      AgentIOSPr2643TargetSelector.codexDesktopTarget([unavailable, generic, codex]),
      codex
    )
  }

  func testRunsFiveCaseBatchesAndRetriesOnlyTransientFailures() async throws {
    let target = target(id: "desktop-device:codex")
    let executor = ScriptedPr2643Executor(transientFailures: [23, 41, 42])
    let runner = AgentIOSPr2643AcceptanceRunner(executor: executor)
    var callbackCheckpoints: [AgentIOSPr2643SuiteCheckpoint] = []

    let result = await runner.run(
      cases: AgentIOSPr2643AcceptanceCorpus.cases,
      target: target,
      checkpoint: { callbackCheckpoints.append($0) }
    )

    XCTAssertEqual(result.results.count, 100)
    XCTAssertTrue(result.results.allSatisfy(\.passed))
    XCTAssertEqual(result.invocationCount, 103)
    XCTAssertEqual(result.checkpoints.count, 20)
    XCTAssertEqual(callbackCheckpoints, result.checkpoints)
    XCTAssertEqual(result.checkpoints.last?.passedCases, 100)
  }

  func testVerifierRejectsLocalFastPathAndWrongResource() {
    let testCase = AgentIOSPr2643AcceptanceCorpus.cases[0]
    let target = target(id: "desktop-device:codex")
    let observation = ScriptedPr2643Executor.observation(
      testCase: testCase,
      target: target,
      includeFastLocal: true,
      resourceID: "desktop-device:other"
    )

    let result = AgentIOSPr2643ReplyVerifier.evaluate(
      testCase: testCase,
      target: target,
      observation: observation,
      attempt: 1
    )

    XCTAssertFalse(result.passed)
    XCTAssertTrue(result.failures.contains("fast_local_path"))
    XCTAssertTrue(result.failures.contains("wrong_execution_resource"))
  }

  private func target(
    id: String,
    status: AgentConnectorStatus = .available
  ) -> AgentCallableTarget {
    AgentCallableTarget(
      id: id,
      title: id,
      kind: .agent,
      status: status,
      capabilities: [.chat]
    )
  }
}

private final class ScriptedPr2643Executor: AgentIOSPr2643RealReplyExecuting {
  private let transientFailures: Set<Int>

  init(transientFailures: Set<Int>) {
    self.transientFailures = transientFailures
  }

  func execute(
    _ testCase: AgentIOSPr2643AcceptanceCase,
    target: AgentCallableTarget,
    attempt: Int
  ) async -> AgentIOSPr2643ReplyObservation {
    if transientFailures.contains(testCase.index) && attempt == 1 {
      return AgentIOSPr2643ReplyObservation(
        response: nil,
        entries: [],
        recordedRun: nil,
        latencyMillis: 50_000
      )
    }
    return Self.observation(testCase: testCase, target: target)
  }

  static func observation(
    testCase: AgentIOSPr2643AcceptanceCase,
    target: AgentCallableTarget,
    includeFastLocal: Bool = false,
    resourceID: String? = nil
  ) -> AgentIOSPr2643ReplyObservation {
    let turnID = "pr2643-turn-\(testCase.index)"
    var entries = [
      AgentTranscriptEntry(
        id: "\(turnID)-process",
        role: .process,
        text: "Connector completed",
        timestampMillis: 1,
        dedupeKey: "connector-event:\(turnID)",
        conversationId: "pr2643-conversation-\(testCase.index)",
        turnId: turnID
      )
    ]
    if includeFastLocal {
      entries.append(AgentTranscriptEntry(
        id: "\(turnID)-fast",
        role: .process,
        text: "Local response",
        timestampMillis: 2,
        dedupeKey: "fast-local:\(turnID)",
        conversationId: "pr2643-conversation-\(testCase.index)",
        turnId: turnID
      ))
    }
    let response = AgentTranscriptEntry(
      id: "\(turnID)-assistant",
      role: .assistant,
      text: "\(testCase.marker) | \(testCase.expected)",
      timestampMillis: 3,
      dedupeKey: "assistant-final:turn:\(turnID)",
      conversationId: "pr2643-conversation-\(testCase.index)",
      turnId: turnID
    )
    entries.append(response)
    return AgentIOSPr2643ReplyObservation(
      response: response,
      entries: entries,
      recordedRun: AgentRecordedRun(
        runId: "pr2643-run-\(testCase.index)",
        conversationId: response.conversationId,
        taskThreadId: turnID,
        originalRequest: testCase.prompt,
        executionResourceId: resourceID ?? target.id,
        status: .completed,
        createdAtMillis: 1,
        completedAtMillis: 3
      ),
      latencyMillis: 29_000
    )
  }
}
