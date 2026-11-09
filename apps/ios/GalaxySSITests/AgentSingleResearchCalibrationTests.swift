import Darwin
import XCTest
@testable import GalaxySSI

final class AgentSingleResearchCalibrationTests: XCTestCase {
  private let legacyFormat = "galaxyssi.single-agent-calibration.v1"
  private let objective = "  Inspect the supplied fixture.\n\nPreserve the original conditions.\n"
  private let selection = AgentModelSelection(mode: .manual, targetId: "fixture:codex",
    modelId: "selected-model", reasoningEffort: .high)

  func testResearchCalibrationRequiresExplicitProtocolSelectionAndSingleDispatch() {
    let scope = scope(run: "first", turn: "first-turn")
    func enroll(_ format: String, _ model: AgentModelSelection, _ limit: Int) -> AgentSingleResearchCalibration? {
      .init(format: format, scope: scope, selection: model, objective: objective, maximumDispatches: limit)
    }
    XCTAssertNil(enroll(legacyFormat, selection, 1))
    XCTAssertNil(enroll("unknown", selection, 1))
    XCTAssertNil(enroll(AgentSingleResearchCalibration.format, AgentModelSelection(), 1))
    XCTAssertNil(enroll(AgentSingleResearchCalibration.format, selection, 2))
    let enrolled = enroll(AgentSingleResearchCalibration.format, selection, 1)
    XCTAssertEqual(enrolled?.modelID, selection.modelId)
    XCTAssertEqual(enrolled?.reasoningEffort, selection.reasoningEffort)
  }

  func testSingleResearchAssignmentPublishesAndRecallsAnUnverifiedMethodAfterReopen() async throws {
    try await runCalibration(persistSelection: true)
  }

  func testCalibrationDoesNotCreateASelectionFromTheNewestConversation() async throws {
    try await runCalibration(persistSelection: false)
  }

  func testCalibrationDeviceBindingRejectsMissingAmbiguousAndMismatchedModels() throws {
    let actual = "iPhone16,2"
    XCTAssertNoThrow(try Self.requirePilotDevice(actual: actual, expected: actual))
    XCTAssertThrowsError(try Self.requirePilotDevice(actual: actual, expected: nil))
    XCTAssertThrowsError(try Self.requirePilotDevice(actual: actual, expected: "iPhone17,2"))
    for invalid in ["", " ", "*", "iPhone16,2,iPhone17,2", "iPhone16,2\n", " iPhone16,2", "iPhone16,2;iPhone17,2"] {
      XCTAssertThrowsError(try Self.requirePilotDevice(actual: invalid, expected: invalid))
    }
  }

  func testDeviceBoundCalibrationPreservesPersistedSelection() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["GALAXYSSI_CALIBRATION_DEVICE_TEST"] == "1" else {
      throw XCTSkip("Device-bound calibration is opt-in")
    }
    #if targetEnvironment(simulator)
    XCTFail("Device-bound calibration requires a physical iOS device")
    #else
    var hardware = utsname()
    guard uname(&hardware) == 0 else { throw PilotDeviceError.unavailable }
    let model = withUnsafeBytes(of: hardware.machine) {
      String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
    }
    try Self.requirePilotDevice(actual: model, expected: environment["GALAXYSSI_CALIBRATION_DEVICE_MODEL"])
    try await runCalibration(persistSelection: true)
    try await runCalibration(persistSelection: false)
    let attachment = XCTAttachment(string: "device_model=\(model)\nselection_check=persisted_conversation_selection")
    attachment.name = "Calibration device and check"
    attachment.lifetime = .keepAlways
    add(attachment)
    #endif
  }

  private enum PilotDeviceError: Error { case unavailable, invalid, mismatch }

  private static func requirePilotDevice(actual: String, expected: String?) throws {
    // A hardware identifier contains one comma; it is not a list of models.
    guard let expected,
          expected.utf8.count <= 128,
          expected.range(of: #"\Ai(?:Phone|Pad|Pod)[0-9]+,[0-9]+\z"#, options: .regularExpression) != nil
    else { throw PilotDeviceError.invalid }
    guard actual == expected else { throw PilotDeviceError.mismatch }
  }

  private func runCalibration(persistSelection: Bool) async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }
    let history = fixture.history()
    let scope = scope(run: "original-run", turn: "original-turn")
    let conversationFile = fixture.root.appendingPathComponent("conversations.sqlite3")
    let conversations = AgentConversationDatabase(fileURL: conversationFile, secrets: fixture.secrets)
    let existing = AgentConversation(id: "existing-conversation", title: "Existing conversation", createdAt: 1, updatedAt: 1)
    XCTAssertTrue(conversations.upsert(existing))
    if persistSelection { conversations.setActiveConversationId(existing.id) }
    let priorSelection = conversations.activeConversationId
    XCTAssertEqual(priorSelection, persistSelection ? existing.id : "")
    let pilot = AgentConversation(id: scope.conversationId, title: "Isolated calibration", createdAt: 2, updatedAt: 2)
    XCTAssertTrue(conversations.upsert(pilot))
    XCTAssertEqual(conversations.readAll().max { $0.updatedAt < $1.updatedAt }?.id, pilot.id)
    XCTAssertEqual(conversations.activeConversationId, priorSelection)
    let calibration = try XCTUnwrap(AgentSingleResearchCalibration(format: AgentSingleResearchCalibration.format,
      scope: scope, selection: selection, objective: objective, maximumDispatches: 1))
    let final = #"{"format":"galaxyssi.research-artifact.v1","summary":"Synthetic delivery only","milestones":["candidate"]}"#
    let plan = definition(scope: scope, research: true)
    let runtime = AgentTeamExecutionRuntime(store: InMemoryAgentTeamExecutionStore(), mailbox: InMemoryAgentTeamMailbox(),
      limits: .init(maxChildren: 1, maxConcurrency: 1))
    defer { runtime.close() }
    let counter = DispatchCounter()
    let request = AgentRunRequest(conversationId: scope.conversationId, messageId: scope.turnId, taskId: scope.turnId,
      runId: scope.runId, parentRunId: "", goal: objective, deliveryMode: .respond, requiredCapabilities: [],
      context: [:], idempotencyKey: scope.runId, createdAtMillis: 1)
    let assignment = activeSnapshot(scope, stage: AgentSingleResearchCalibration.stage)
    let handle = try runtime.start(definition: plan, request: request,
      worker: ClosureAgentTeamMemberWorker { context in
        try await counter.admit()
        XCTAssertEqual(Data(context.request.goal.utf8), Data(request.goal.utf8))
        XCTAssertEqual(context.member.objective, request.goal.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(context.member.deliveryMode, .respond)
        XCTAssertEqual(context.member.memberId, scope.memberId)
        XCTAssertTrue(context.member.dependsOnAgentIds.isEmpty)
        XCTAssertEqual(context.member.agentId, calibration.targetID)
        XCTAssertEqual(context.request.context.string("_galaxyssi_member_model_id"), calibration.modelID)
        XCTAssertEqual(context.request.context.string(AgentCollaborationReasoningSelection.contextKey),
          calibration.reasoningEffort.rawValue)
        XCTAssertEqual(context.request.context.string("_galaxyssi_research_stage"), AgentSingleResearchCalibration.stage)
        XCTAssertTrue(history.upsert(assignment))
        XCTAssertThrowsError(try history.publishCollaborationMilestone(["mode": .string("status")], scope: scope))
        try history.enrollSingleResearchCalibration(calibration)
        let reopened = fixture.history()
        let initial = try reopened.publishCollaborationMilestone(["mode": .string("list")], scope: scope)
        XCTAssertEqual(initial["milestones"]?.arrayValue, [])
        let receipt = try reopened.publishCollaborationMilestone([
          "mode": .string("publish"), "milestone_id": .string("candidate"), "artifact": .string(Self.method)
        ], scope: scope)
        XCTAssertEqual(receipt["status"], .string("published"))
        XCTAssertEqual(receipt["references"]?.arrayValue?.count, 1)
        XCTAssertEqual(reopened.snapshot(supervisorRunId: scope.runId)?.state, .running)
        let archive = try reopened.publishCollaborationMilestone(["mode": .string("list")], scope: scope)
        XCTAssertEqual(archive["next_cursor"], .null)
        await counter.archive(archive["milestones"]?.arrayValue ?? [])
        return AgentSubagentOutput(content: final)
      })
    let delivered = try await handle.wait()
    let count = await counter.count
    XCTAssertEqual(count, 1)
    XCTAssertEqual(delivered.members.count, 1)
    XCTAssertEqual(delivered.finalOutput, final)
    let archive = await counter.milestones
    let report = Self.deliveryReport(snapshot: delivered, dispatches: count, archive: archive)
    XCTAssertTrue(Self.acceptsDeliveryOnly(report))
    XCTAssertEqual(archive.first?.objectValue?.string("milestone_id"), "candidate")
    var overclaim = report
    overclaim["scientific_capability_gain_proven"] = .bool(true)
    XCTAssertFalse(Self.acceptsDeliveryOnly(overclaim))
    let committed = try XCTUnwrap(history.applyReply(supervisorRunId: scope.runId, source: scope.sourceId,
      conversation: scope.conversationId, turn: scope.turnId, task: scope.sourceId,
      contact: calibration.targetID, content: final, success: true, now: 2))
    XCTAssertEqual(committed.state, .succeeded)
    try history.publishSavedResearchReply(final, scope: scope)

    let reopened = fixture.history()
    let saved = try XCTUnwrap(reopened.committedResearchRevisions(scope: scope)?.first)
    let future = self.scope(run: "next-run", turn: "next-turn")
    XCTAssertTrue(reopened.upsert(activeSnapshot(future, stage: nil)))
    let page = try reopened.recallCollaborationOriginal(["mode": .string("workspace"),
      "object_id": .string(saved.reference.objectId), "revision": .int(saved.reference.revision),
      "sha256": .string(saved.reference.sha256)], scope: future)
    XCTAssertEqual(page["sha256"], .string(saved.reference.sha256))
    XCTAssertTrue(page.string("content").contains("Synthetic method, not learned"))
    let directory = try reopened.recallCollaborationOriginal(["mode": .string("capabilities")], scope: future)
    XCTAssertEqual(directory["capabilities"]?.arrayValue?.first?.objectValue?.string("state"), "unverified_candidate")
    XCTAssertEqual(directory["grants_permissions"], .bool(false))
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(["mode": .string("status")], scope: future))

    let persisted = AgentConversationDatabase(fileURL: conversationFile, secrets: fixture.secrets)
    XCTAssertEqual(persisted.activeConversationId, priorSelection)
    XCTAssertEqual(persisted.read(pilot.id), pilot)
    XCTAssertEqual(persisted.delete(pilot.id), pilot)
    XCTAssertTrue(persisted.confirmsAbsent(pilot.id))
    XCTAssertEqual(persisted.read(existing.id), existing)
    XCTAssertEqual(persisted.activeConversationId, priorSelection)
  }

  func testEnrollmentCannotAuthorizeChangedObjectiveMultipleMembersOrRevokedGroup() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }
    let history = fixture.history()
    let scope = scope(run: "guarded", turn: "guarded-turn")
    let enrollment = try XCTUnwrap(AgentSingleResearchCalibration(format: AgentSingleResearchCalibration.format,
      scope: scope, selection: selection, objective: objective, maximumDispatches: 1))
    var team = activeSnapshot(scope, stage: AgentSingleResearchCalibration.stage)
    team.goal = "A substituted task"
    XCTAssertFalse(enrollment.owns(team, member: team.members[0]))
    team = activeSnapshot(scope, stage: AgentSingleResearchCalibration.stage)
    team.members.append(.init(agentId: "another", sourceMessageId: "another-source"))
    XCTAssertFalse(enrollment.owns(team, member: team.members[0]))
    XCTAssertTrue(history.upsert(activeSnapshot(scope, stage: AgentSingleResearchCalibration.stage)))
    try history.enrollSingleResearchCalibration(enrollment)
    var foreign = scope
    foreign.sourceId = "foreign"
    XCTAssertThrowsError(try history.publishCollaborationMilestone(["mode": .string("status")], scope: foreign))
    history.removeResearchObjects(conversationId: scope.conversationId)
    XCTAssertThrowsError(try history.enrollSingleResearchCalibration(enrollment))
    XCTAssertThrowsError(try history.publishCollaborationMilestone(["mode": .string("status")], scope: scope))
  }

  private func scope(run: String, turn: String) -> AgentCollaborationToolEvidenceScope {
    .init(runId: run, conversationId: "isolated-calibration", turnId: turn, memberId: "solo", sourceId: run + "-source")
  }

  private func definition(scope: AgentCollaborationToolEvidenceScope, research: Bool) -> AgentTeamDefinition {
    var context = ["_galaxyssi_member_model_id": selection.modelId,
      AgentCollaborationReasoningSelection.contextKey: selection.reasoningEffort.rawValue]
    if research { context["_galaxyssi_research_stage"] = AgentSingleResearchCalibration.stage }
    return .init(teamId: scope.runId + "-team", primaryAgentId: selection.targetId, members: [
      .init(agentId: selection.targetId, deliveryMode: .respond, requiredCapabilities: [], role: "Researcher",
        objective: objective.trimmingCharacters(in: .whitespacesAndNewlines), dependsOnAgentIds: [],
        context: context, instanceId: scope.memberId)
    ], visibilityMode: .background, collectiveCapabilities: [], primaryInstanceId: scope.memberId)
  }

  private func activeSnapshot(_ scope: AgentCollaborationToolEvidenceScope, stage: String?) -> AgentTeamExecutionSnapshot {
    .init(supervisorRunId: scope.runId, teamId: scope.runId + "-team", conversationId: scope.conversationId,
      taskId: scope.turnId, primaryAgentId: selection.targetId, goal: objective, state: .running,
      members: [.init(agentId: selection.targetId, deliveryMode: .respond, status: .running, instanceId: scope.memberId,
        sourceMessageId: scope.sourceId, dispatchCheckpoint: .dispatching, researchStage: stage)],
      createdAtMillis: 1, updatedAtMillis: 1, primaryInstanceId: scope.memberId)
  }

  private func makeFixture() throws -> Fixture {
    let suite = "single-research-" + UUID().uuidString
    return try Fixture(suite: suite, defaults: XCTUnwrap(UserDefaults(suiteName: suite)),
      root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
  }

  private struct Fixture {
    let suite: String
    let defaults: UserDefaults
    let root: URL
    let secrets = InMemorySecretStore()

    func history() -> AgentTeamExecutionHistoryStore {
      AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
        executionStore: InMemoryAgentTeamExecutionStore(), fileURL: root.appendingPathComponent("history.sqlite3"))
    }

    func cleanup() {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: root)
    }
  }

  private actor DispatchCounter {
    private(set) var count = 0
    private(set) var milestones: [AgentMcpJSONValue] = []
    func admit() throws {
      guard count == 0 else { throw AgentTeamHistoryDatabase.Failure.stale }
      count += 1
    }
    func archive(_ values: [AgentMcpJSONValue]) { milestones = values }
  }

  private static func deliveryReport(snapshot: AgentTeamExecutionSnapshot, dispatches: Int,
                                     archive: [AgentMcpJSONValue]) -> AgentMcpJSONObject {
    ["execution_mode": .string("single_agent_research"), "test_scope": .string("execution_delivery_only"),
     "status": .string(snapshot.hasSuccessfulOutput ? "single_agent_returned_goal_unverified" : "interrupted_or_failed"),
     "phone_dispatches": .int(Int64(dispatches)), "goal_verified_by_external_evaluator": .bool(false),
     "scientific_capability_gain_proven": .bool(false), "milestones": .array(archive)]
  }

  private static func acceptsDeliveryOnly(_ report: AgentMcpJSONObject) -> Bool {
    report["execution_mode"] == .string("single_agent_research") &&
      report["test_scope"] == .string("execution_delivery_only") &&
      report["status"] == .string("single_agent_returned_goal_unverified") &&
      report["phone_dispatches"] == .int(1) && report["milestones"]?.arrayValue != nil &&
      report["goal_verified_by_external_evaluator"] == .bool(false) &&
      report["scientific_capability_gain_proven"] == .bool(false)
  }

  private static let method = """
  {"format":"galaxyssi.research-artifact.v1","summary":"Synthetic method, not learned",
   "workspace":[{"id":"inspection","base_revision":0,"kind":"workflow_method","title":"Synthetic method, not learned",
   "parents":[],"body":{"workflow_method":{"purpose":"Check an input","domain":"fixture","bottleneck":"stale data",
   "change_rationale":"Inspect before reuse","applies_when":"Input is readable","avoid_when":"Missing input",
   "risks":"Incomplete check","expected_gain":"Fewer stale results","falsifier":"A stale result is reused",
   "dimensions":["verification"],"roles":["analyst"],"inputs":["source"],"steps":[{"id":"inspect","role":"analyst",
   "stage":"EXECUTE","assignment":"Inspect the fixture before reuse","depends_on":[]}]}}}]}
  """
}
