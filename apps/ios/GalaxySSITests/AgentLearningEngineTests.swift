import Foundation
import XCTest
@testable import GalaxySSI

final class AgentLearningEngineTests: XCTestCase {
  func testAgentLearningAnalyzerLearnsPreferenceCorrectionAndFailureFamily() {
    let left = AgentLearningAnalyzer.taskFamily("Summarize C:\\Work\\private\\alpha.pdf for 12 people")
    let right = AgentLearningAnalyzer.taskFamily("Summarize C:\\Temp\\beta.pdf for 28 people")

    XCTAssertEqual(left, right)
    XCTAssertFalse(left.contains("private"))
    XCTAssertFalse(left.contains("12"))
    XCTAssertEqual(AgentLearningAnalyzer.explicitPreference("I prefer concise answers"), "concise answers")
    XCTAssertNil(AgentLearningAnalyzer.explicitPreference("Remember that api_key=secret-value"))
    XCTAssertEqual(
      AgentLearningAnalyzer.correctionFeedback("No, use the local tool instead"),
      "No, use the local tool instead"
    )
    XCTAssertNil(AgentLearningAnalyzer.correctionFeedback("No"))

    let first = failedRun("failure-1", "Summarize C:\\Work\\alpha.pdf")
    let second = failedRun("failure-2", "Summarize C:\\Temp\\beta.pdf")
    let unrelated = failedRun("failure-3", "Turn on the flashlight")
    XCTAssertNil(AgentLearningAnalyzer.repeatedFailureFamily(run: first, recentRuns: [first]))
    XCTAssertEqual(
      AgentLearningAnalyzer.taskFamily(second.originalRequest),
      AgentLearningAnalyzer.repeatedFailureFamily(run: second, recentRuns: [first, second, unrelated])
    )
  }

  func testAgentLearningAnalyzerTrustsCompletedRuntimeReceiptAndRejectsUnsafeEvidence() {
    let trusted = runtimeCall(exitCode: 0)
    let missingReceipt = AgentToolCallRecord(
      id: "runtime-missing",
      toolName: AgentIOSOnDeviceRuntimeNativeToolCatalog.execute,
      status: .succeeded,
      result: ["exit_code": .int(0)]
    )
    let failedReceipt = runtimeCall(exitCode: 7)

    XCTAssertTrue(AgentLearningAnalyzer.hasTrustedExecutionEvidence(trusted))
    XCTAssertFalse(AgentLearningAnalyzer.hasTrustedExecutionEvidence(missingReceipt))
    XCTAssertFalse(AgentLearningAnalyzer.hasTrustedExecutionEvidence(failedReceipt))
    XCTAssertTrue(AgentLearningAnalyzer.hasTrustedExecutionEvidence(AgentToolCallRecord(
      id: "non-runtime",
      toolName: "test.echo",
      status: .succeeded
    )))
    XCTAssertFalse(AgentLearningAnalyzer.runExecutionEvidenceTrusted(completedRun(
      "runtime-failed",
      request: "Run code",
      toolCalls: [failedReceipt]
    )))
  }

  func testAgentLearningEngineCreatesMemoryAndSkillProposalThenReviews() throws {
    let descriptor = try nativeDescriptor("test.echo")
    let runtime = AgentSkillRuntime(availableNativeToolIds: [descriptor.id], clock: { 1_000 })
    let memoryStore = InMemoryAgentMemoryStore(nowMillis: { 1_000 })
    let proposalStore = InMemoryAgentLearningProposalStore()
    var nextId = 0
    let engine = AgentLearningEngine(
      memoryStore: memoryStore,
      skillRuntime: runtime,
      skillCompiler: AgentConversationSkillCompiler(runtime) { [descriptor] },
      proposalStore: proposalStore,
      nowMillis: { 2_000 },
      idFactory: {
        nextId += 1
        return "proposal-\(nextId)"
      }
    )

    let preference = completedRun("preference", request: "I prefer concise answers", toolCalls: [])
    let preferenceOutcome = engine.observeCompletedRun(
      run: preference,
      recentRuns: [preference],
      privateMode: false,
      memoryCaptureEnabled: true
    )
    XCTAssertEqual(preferenceOutcome.memories.singleValue().item?.value, "concise answers")

    let runs = [
      completedRun("run-1", request: "Summarize C:\\Work\\alpha.pdf for 12 people"),
      completedRun("run-2", request: "Summarize C:\\Temp\\beta.pdf for 28 people"),
      completedRun("run-3", request: "Summarize C:\\Docs\\gamma.pdf for 31 people")
    ]
    let outcome = engine.observeCompletedRun(
      run: runs[2],
      recentRuns: runs,
      privateMode: false,
      memoryCaptureEnabled: false
    )
    let proposal = outcome.proposals.singleValue()
    let manifest = try XCTUnwrap(AgentSkillManifestCodec.decode(proposal.manifestJson))
    let approved = try XCTUnwrap(engine.approve(proposalId: proposal.id))

    XCTAssertEqual(proposal.kind, .skill)
    XCTAssertEqual(proposal.evidenceRunIds, ["run-1", "run-2", "run-3"])
    XCTAssertEqual(proposal.status, .pending)
    XCTAssertEqual(manifest.source, "automatic_learning_proposal")
    XCTAssertFalse(manifest.autoInvoke)
    XCTAssertEqual(approved.id, manifest.id)
    XCTAssertTrue(approved.enabled)
    XCTAssertEqual(engine.proposals(status: .approved).singleValue().id, proposal.id)
    XCTAssertFalse(engine.reject(proposalId: proposal.id))
  }

  func testAgentLearningEngineCreatesSkillUpgradeProposalFromFeedback() throws {
    let descriptor = try nativeDescriptor("test.echo")
    let runtime = AgentSkillRuntime(availableNativeToolIds: [descriptor.id], clock: { 1_000 })
    let base = try runtime.install(skillManifest(toolId: descriptor.id))
    let engine = AgentLearningEngine(
      memoryStore: InMemoryAgentMemoryStore(),
      skillRuntime: runtime,
      skillCompiler: AgentConversationSkillCompiler(runtime) { [descriptor] },
      proposalStore: InMemoryAgentLearningProposalStore(),
      nowMillis: { 3_000 },
      idFactory: { "upgrade-proposal" }
    )
    let corrected = AgentRecordedRun(
      runId: "corrected",
      conversationId: "conversation",
      taskThreadId: "thread",
      originalRequest: "Run the workflow with the remote source",
      toolCalls: [AgentToolCallRecord(id: "call", toolName: descriptor.id, status: .succeeded)],
      renderSpec: ["view": .string("compact")],
      userFeedback: ["Use the local source instead"],
      activeSkillId: base.id,
      status: .completed
    )

    let proposal = try XCTUnwrap(engine.observeFeedback(run: corrected, recentRuns: [corrected]))
    let manifest = try XCTUnwrap(AgentSkillManifestCodec.decode(proposal.manifestJson))
    let approved = try XCTUnwrap(engine.approve(proposalId: proposal.id))
    let encoded = AgentLearningProposalJSONCodec.encode([proposal])

    XCTAssertEqual(proposal.kind, .skillUpgrade)
    XCTAssertEqual(proposal.id, "upgrade-proposal")
    XCTAssertEqual(manifest.version, "1.1.0")
    XCTAssertTrue(manifest.instructions.contains("Use the local source instead"))
    XCTAssertEqual(approved.version, "1.1.0")
    XCTAssertTrue(encoded.contains(#""evidence_run_ids":["corrected"]"#))
    XCTAssertTrue(encoded.contains(#""manifest_json":"#))
  }

  private func completedRun(
    _ id: String,
    request: String,
    toolCalls: [AgentToolCallRecord]? = nil
  ) -> AgentRecordedRun {
    AgentRecordedRun(
      runId: id,
      conversationId: "conversation",
      taskThreadId: "thread",
      originalRequest: request,
      toolCalls: toolCalls ?? [
        AgentToolCallRecord(
          id: "call-\(id)",
          toolName: "test.echo",
          status: .succeeded,
          arguments: ["value": .string(request)]
        )
      ],
      status: .completed,
      completedAtMillis: Int64(String(id.suffix(1))) ?? 0
    )
  }

  private func failedRun(_ id: String, _ request: String) -> AgentRecordedRun {
    AgentRecordedRun(
      runId: id,
      conversationId: "conversation",
      taskThreadId: "thread",
      originalRequest: request,
      status: .failed
    )
  }

  private func runtimeCall(exitCode: Int64) -> AgentToolCallRecord {
    AgentToolCallRecord(
      id: "runtime-\(exitCode)",
      toolName: AgentIOSOnDeviceRuntimeNativeToolCatalog.execute,
      status: .succeeded,
      result: [
        "execution_receipt": .object([
          "request_id": .string("request-1"),
          "status": .string("completed"),
          "exit_code": .int(exitCode),
          "source_sha256": .string(String(repeating: "a", count: 64)),
          "stdout_sha256": .string(String(repeating: "b", count: 64)),
          "stderr_sha256": .string(String(repeating: "c", count: 64)),
          "created_at_millis": .int(1_000),
          "completed_at_millis": .int(1_100)
        ])
      ]
    )
  }

  private func skillManifest(toolId: String) -> AgentSkillManifest {
    AgentSkillManifest(
      id: "example.echo",
      name: "Echo",
      version: "1.0.0",
      summary: "Echo a request",
      instructions: "Echo the request using a native tool.",
      nativeTools: [toolId],
      parameters: .objectSchema(
        properties: ["request": .string(minLength: 0, maxLength: 1_024)],
        required: []
      ),
      steps: [AgentSkillStep(id: "run", toolId: toolId, input: ["value": .string("{{parameters.request}}")])],
      autoInvoke: true,
      triggerExamples: ["Echo this"]
    )
  }

  private func nativeDescriptor(_ id: String) throws -> AgentNativeToolDescriptor {
    try AgentNativeToolDescriptor(
      id: id,
      version: "1.0.0",
      title: "Echo",
      description: "Echoes bounded input.",
      location: .application,
      risk: .low,
      requiredPermissions: [AgentNativePermissionRequirement(id: "test.echo", required: true)]
    )
  }
}

private extension Array {
  func singleValue(file: StaticString = #filePath, line: UInt = #line) -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    return self[0]
  }
}
