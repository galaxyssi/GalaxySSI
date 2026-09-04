import Foundation
import XCTest
@testable import GalaxySSI

@MainActor
final class AgentEvalBenchmarkTests: XCTestCase {
  func testStandardSuiteHasSixtyUniqueCasesAndTenPerDimension() {
    let suite = AgentEvalBenchmarkCatalog.standard

    XCTAssertEqual(suite.cases.count, 60)
    XCTAssertEqual(Set(suite.cases.map(\.id)).count, 60)
    for dimension in AgentBenchmarkDimension.allCases {
      XCTAssertEqual(suite.cases.filter { $0.dimension == dimension }.count, 10)
    }
    XCTAssertEqual(suite.minimumRepetitions, 3)
    XCTAssertEqual(suite.maximumRepetitions, 10)
    XCTAssertEqual(suite.targetPassRate, 0.90, accuracy: 0.0001)
  }

  func testAllocationIsExactlyNinetyTenInEveryDimension() throws {
    let suite = AgentEvalBenchmarkCatalog.standard
    let codex = registration(id: "desktop:codex", name: "Codex", provider: "openai")
    let deepSeek = registration(id: "cloud:deepseek", name: "DeepSeek", provider: "deepseek")

    let allocation = try AgentBenchmarkAllocationPolicy.codexDeepSeek90To10(
      suite: suite,
      available: [codex, deepSeek]
    )

    XCTAssertEqual(allocation.resourceIdsByCase.values.filter { $0 == [codex.agentId] }.count, 54)
    XCTAssertEqual(allocation.resourceIdsByCase.values.filter { $0 == [deepSeek.agentId] }.count, 6)
    for dimension in AgentBenchmarkDimension.allCases {
      let ids = suite.cases.filter { $0.dimension == dimension }.map(\.id)
      XCTAssertEqual(ids.filter { allocation.resourceIdsByCase[$0] == [codex.agentId] }.count, 9)
      XCTAssertEqual(ids.filter { allocation.resourceIdsByCase[$0] == [deepSeek.agentId] }.count, 1)
    }
  }

  func testAllocationRequiresBothNamedResources() {
    XCTAssertThrowsError(try AgentBenchmarkAllocationPolicy.codexDeepSeek90To10(
      suite: AgentEvalBenchmarkCatalog.standard,
      available: [registration(id: "desktop:codex", name: "Codex", provider: "openai")]
    ))
  }

  func testScorecardIsProvisionalUntilEveryRepetitionIsPresent() {
    let session = makeSession(repetitions: 3)
    let incomplete = [result(trial: "t1", repetition: 1, passed: true)]

    let provisional = AgentBenchmarkStatistics.scorecard(
      session: session,
      suite: AgentEvalBenchmarkCatalog.standard,
      allResults: incomplete
    )
    let complete = AgentBenchmarkStatistics.scorecard(
      session: session,
      suite: AgentEvalBenchmarkCatalog.standard,
      allResults: incomplete + [
        result(trial: "t2", repetition: 2, passed: true),
        result(trial: "t3", repetition: 3, passed: true)
      ]
    )

    XCTAssertFalse(provisional.overall.qualified)
    XCTAssertNil(provisional.overall.passPowerK)
    XCTAssertTrue(complete.overall.qualified)
    XCTAssertEqual(complete.overall.passAt1, 1)
    XCTAssertEqual(complete.overall.passPowerK, 1)
    XCTAssertTrue(complete.overall.targetMet)
  }

  func testFailedRepetitionPreventsPassPowerKTarget() {
    let session = makeSession(repetitions: 3)
    let score = AgentBenchmarkStatistics.scorecard(
      session: session,
      suite: AgentEvalBenchmarkCatalog.standard,
      allResults: [
        result(trial: "t1", repetition: 1, passed: true),
        result(trial: "t2", repetition: 2, passed: false),
        result(trial: "t3", repetition: 3, passed: true)
      ]
    )

    XCTAssertTrue(score.overall.qualified)
    XCTAssertEqual(score.overall.passAt1 ?? -1, 2.0 / 3.0, accuracy: 0.0001)
    XCTAssertEqual(score.overall.passPowerK, 0)
    XCTAssertFalse(score.overall.targetMet)
  }

  func testTrialEvaluatorRequiresExactOutputAndEvidence() throws {
    let item = try XCTUnwrap(AgentEvalBenchmarkCatalog.standard.benchmarkCase(id: "quality-01"))
    let session = makeSession(repetitions: 3)
    let trial = AgentLabTrial(agentId: "desktop:codex", blindAlias: "Agent A", repetition: 1, runId: "run")
    let campaign = AgentLabCampaign(
      task: item.taggedPrompt,
      outcomeContract: AgentOutcomeContractCompiler.compile(runId: "run", goal: item.taggedPrompt),
      trials: [trial]
    )
    let run = AgentRecordedRun(
      runId: "run", conversationId: "benchmark", taskThreadId: trial.id,
      originalRequest: item.taggedPrompt, finalOutput: ["message": .string("379")],
      executionResourceId: trial.agentId, status: .completed, createdAtMillis: 1, completedAtMillis: 100
    )
    let sample = evalSample(runId: run.runId, resourceId: trial.agentId)

    let evaluated = AgentBenchmarkTrialEvaluator.evaluate(
      session: session, benchmarkCase: item, campaign: campaign, trial: trial,
      run: run, sample: sample, events: [], iosWorldResult: nil
    )

    XCTAssertTrue(evaluated.passed)
    XCTAssertTrue(evaluated.verified)
    XCTAssertTrue(evaluated.failureReasons.isEmpty)
  }

  func testIOSWorldResultMustBeForTheSameTaskAndExposeObservedValue() throws {
    let item = try XCTUnwrap(AgentEvalBenchmarkCatalog.standard.benchmarkCase(id: "ios-world-04"))
    let session = makeSession(caseId: item.id, repetitions: 3)
    let trial = AgentLabTrial(agentId: "desktop:codex", blindAlias: "Agent A", repetition: 1, runId: "world-run")
    let campaign = AgentLabCampaign(
      task: item.taggedPrompt,
      outcomeContract: AgentOutcomeContractCompiler.compile(runId: "world-run", goal: item.taggedPrompt),
      trials: [trial]
    )
    let run = AgentRecordedRun(
      runId: "world-run", conversationId: "benchmark", taskThreadId: trial.id,
      originalRequest: item.taggedPrompt, finalOutput: ["message": .string("Installed version is 1.0.0")],
      executionResourceId: trial.agentId, status: .completed, createdAtMillis: 1, completedAtMillis: 100
    )
    var sample = evalSample(runId: run.runId, resourceId: trial.agentId)
    sample.evidenceKinds.insert(.programmaticVerifier)
    let world = AgentIOSWorldResult(
      id: "world", taskId: item.id, runId: run.runId, passed: true,
      verifierResults: [AgentIOSWorldVerifierResult(verifierId: "version", passed: true, actual: "1.0.0", reason: "verified")],
      completedAtMillis: 100
    )

    let evaluated = AgentBenchmarkTrialEvaluator.evaluate(
      session: session, benchmarkCase: item, campaign: campaign, trial: trial,
      run: run, sample: sample, events: [], iosWorldResult: world
    )

    XCTAssertTrue(evaluated.passed)
  }

  func testBenchmarkStoreEncryptsSessionAndResults() {
    let suiteName = "AgentBenchmarkStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = AgentBenchmarkStore(defaults: defaults, secrets: InMemorySecretStore())
    let session = makeSession(repetitions: 3)
    store.saveSession(session)
    store.saveResult(result(trial: "secret-trial", repetition: 1, passed: true))

    XCTAssertEqual(store.sessions().first?.id, session.id)
    XCTAssertEqual(store.results(sessionId: session.id).first?.trialId, "secret-trial")
    let encrypted = defaults.data(forKey: "\(AgentBenchmarkStore.defaultKey).encrypted.v1")
    XCTAssertNotNil(encrypted)
    XCTAssertFalse(encrypted.map { String(decoding: $0, as: UTF8.self).contains("secret-trial") } ?? true)
  }

  func testComparisonRequiresSameSuiteTasksRepetitionsAndShape() {
    let left = makeSession(repetitions: 3)
    var right = left
    right.id = "right"
    XCTAssertTrue(AgentBenchmarkComparisonPolicy.comparable(left, right))
    right.repetitions = 5
    XCTAssertFalse(AgentBenchmarkComparisonPolicy.comparable(left, right))
  }

  private func registration(id: String, name: String, provider: String) -> AgentRegistration {
    AgentRegistration(
      agentId: id, installationId: "install", deviceId: "device", providerId: provider,
      displayName: name, status: .online, capabilities: [.chat], activeRuns: 0,
      maxParallelRuns: 2, updatedAtMillis: 100
    )
  }

  private func makeSession(caseId: String = "quality-01", repetitions: Int) -> AgentBenchmarkSession {
    AgentBenchmarkSession(
      id: "session", suiteId: AgentEvalBenchmarkCatalog.standard.id,
      suiteVersion: AgentEvalBenchmarkCatalog.standard.version, appVersionName: "1.0.0",
      appBuildNumber: "1", deviceModel: "iPhone", systemVersion: "18.0",
      repetitions: repetitions, targetPassRate: 0.9, caseIds: [caseId],
      resources: [AgentBenchmarkResourceSnapshot(resourceId: "desktop:codex", displayName: "Codex",
        providerId: "openai", modelId: "codex", adapterType: "test", capabilitiesHash: "hash")],
      resourceIdsByCase: [caseId: ["desktop:codex"]], campaignIdsByCase: [caseId: "campaign"],
      createdAtMillis: 1, updatedAtMillis: 1
    )
  }

  private func result(trial: String, repetition: Int, passed: Bool) -> AgentBenchmarkTrialResult {
    AgentBenchmarkTrialResult(
      sessionId: "session", caseId: "quality-01", campaignId: "campaign",
      trialId: trial, runId: "run-\(trial)", resourceId: "desktop:codex", repetition: repetition,
      passed: passed, verified: true, failureReasons: [], durationMillis: 100,
      reportedCostMicros: 0, batteryDeltaPercent: 0, peakThermalStatus: 0,
      completedAtMillis: Int64(repetition)
    )
  }

  private func evalSample(runId: String, resourceId: String) -> AgentEvalSample {
    AgentEvalSample(
      runId: runId, scenarioId: "quality-01", taskClass: .general, resourceId: resourceId,
      verdict: .passed, contractSatisfied: true, verified: true, durationMillis: 99,
      failureReasons: [], evidenceKinds: [.finalResponse], completedAtMillis: 100
    )
  }
}
