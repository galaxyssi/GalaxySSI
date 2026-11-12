import CryptoKit
import Darwin
import XCTest
@testable import GalaxySSI

final class AgentSingleDeliveryCalibrationTests: XCTestCase {
  private let goal = "  Inspect the supplied fixture.\n\nPreserve the original conditions.\r\n"
  private let selection = AgentModelSelection(mode: .manual, targetId: "fixture:codex",
    modelId: "selected-model", reasoningEffort: .xhigh)

  func testFreeRunningSingleDispatchReopensExactDeliveryWithoutResearchEnrollment() async throws {
    let plan = try fixturePlan()
    let report = try await run(plan, selected: selection)
    XCTAssertTrue(report.passes(plan))
    var changed = report
    changed.resultDigest = Self.digest("Altered response")
    XCTAssertFalse(changed.passes(plan))
    changed = report; changed.memberID = "foreign-member"
    XCTAssertFalse(changed.passes(plan))
    changed = report; changed.cleanupConfirmed = false
    XCTAssertFalse(changed.passes(plan))
    changed = report; changed.goalVerifiedByExternalEvaluator = true
    XCTAssertFalse(changed.passes(plan))
    changed = report; changed.dispatches = 2
    XCTAssertFalse(changed.passes(plan))
    changed = report; changed.selectionPreserved = false
    XCTAssertFalse(changed.passes(plan))
  }

  func testPlanRequiresExplicitSingleDispatchAndExactSelection() throws {
    let invalidFields: [[String: Any]] = [
      ["format": "galaxyssi.single-agent-research-calibration.v1"], ["maximumDispatches": 2],
      ["objective": " \n"], ["objective": String(repeating: "a", count: 8_001)],
      ["timeoutMillis": 0], ["reasoningEffort": "unknown"], ["coordinator": "extra"]
    ]
    for fields in invalidFields {
      XCTAssertThrowsError(try fixturePlan(fields))
    }
    let plan = try fixturePlan()
    XCTAssertEqual(Data(plan.objective.utf8), Data(goal.utf8))
    XCTAssertEqual(plan.assignment, "Inspect the supplied fixture.\n\nPreserve the original conditions.")
    XCTAssertNoThrow(try plan.checkSelection(selection))
    XCTAssertThrowsError(try plan.checkSelection(.init()))
    XCTAssertThrowsError(try plan.checkSelection(.init(mode: .manual, targetId: selection.targetId,
      modelId: selection.modelId, reasoningEffort: .low)))
  }

  func testAdmissionRejectsChangedGoalOrIncompletePreparedPromptBeforeDispatch() throws {
    let plan = try fixturePlan(), run = "frozen-run"
    let request = makeRequest(plan, run: run)
    let definition = makeDefinition(plan, run: run)
    let member = try XCTUnwrap(definition.members.first)
    var child = request
    child.parentRunId = run
    child.runId = AgentTeamExecutionRuntime.stableChildRunId(supervisorRunId: run, instanceId: member.memberId)
    child.idempotencyKey += ":" + member.memberId
    child.context["_galaxyssi_member_model_id"] = .string(plan.modelID)
    child.context[AgentCollaborationReasoningSelection.contextKey] = .string(plan.reasoningEffort)
    let prompt = AgentTeamDispatchText.memberPrompt(goal: request.goal, member: member,
      primaryInstanceId: member.memberId, dependencyLines: [])
    XCTAssertNoThrow(try plan.checkDispatch(member: member, child: child, parent: request, prompt: prompt))
    XCTAssertThrowsError(try plan.checkDispatch(member: member, child: child, parent: request,
      prompt: prompt.replacingOccurrences(of: "\n\nPreserve", with: "\nPreserve")))
    var changed = member
    changed.objective = "Inspect the supplied fixture."
    XCTAssertThrowsError(try plan.checkDispatch(member: changed, child: child, parent: request, prompt: prompt))
    changed = member; changed.context["_galaxyssi_research_stage"] = "REVIEW"
    XCTAssertThrowsError(try plan.checkDispatch(member: changed, child: child, parent: request, prompt: prompt))
    child.goal = plan.assignment
    XCTAssertThrowsError(try plan.checkDispatch(member: member, child: child, parent: request, prompt: prompt))
  }

  func testOptInDeviceBoundSingleDeliveryCalibration() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let path = env["GALAXYSSI_SINGLE_DELIVERY_PLAN"] else { throw XCTSkip("Device calibration is opt-in") }
    #if targetEnvironment(simulator)
    throw Failure.invalidDevice
    #else
    let file = URL(fileURLWithPath: path)
    let size = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard size.isRegularFile == true, let bytes = size.fileSize, bytes <= 64_000 else { throw Failure.invalidPlan }
    let data = try Data(contentsOf: file)
    guard Self.digest(data) == env["GALAXYSSI_SINGLE_DELIVERY_PLAN_SHA256"] else { throw Failure.invalidPlan }
    let plan = try Plan.decode(data)
    var hardware = utsname()
    guard uname(&hardware) == 0 else { throw Failure.invalidDevice }
    let model = withUnsafeBytes(of: hardware.machine) {
      String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
    }
    guard plan.deviceModel == model, env["GALAXYSSI_SINGLE_DELIVERY_DEVICE_MODEL"] == model,
          let target = env["GALAXYSSI_SINGLE_DELIVERY_TARGET"],
          let modelID = env["GALAXYSSI_SINGLE_DELIVERY_MODEL"],
          let effort = env["GALAXYSSI_SINGLE_DELIVERY_EFFORT"].flatMap(AgentModelReasoningEffort.init(rawValue:))
    else { throw Failure.invalidDevice }
    let report = try await run(plan, selected: .init(mode: .manual, targetId: target, modelId: modelID,
      reasoningEffort: effort))
    XCTAssertTrue(report.passes(plan))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let bytesToAttach = try encoder.encode(report)
    let attachment = XCTAttachment(data: bytesToAttach, uniformTypeIdentifier: "public.json")
    attachment.name = "Single-agent delivery-only report"
    attachment.lifetime = .keepAlways
    add(attachment)
    print("GALAXYSSI_SINGLE_DELIVERY_REPORT_SHA256=\(Self.digest(bytesToAttach))")
    #endif
  }

  private enum Failure: Error { case invalidPlan, invalidDevice, selection, dispatch, incomplete }

  private struct Plan: Decodable {
    static let formatID = "galaxyssi.single-agent-calibration.v1"
    let format: String
    let deviceModel: String
    let targetID: String
    let modelID: String
    let reasoningEffort: String
    let memberID: String
    let objective: String
    let timeoutMillis: Int
    let maximumDispatches: Int

    var assignment: String { objective.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func decode(_ data: Data) throws -> Self {
      guard data.count <= 64_000, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            Set(object.keys) == ["format", "deviceModel", "targetID", "modelID", "reasoningEffort", "memberID",
                                 "objective", "timeoutMillis", "maximumDispatches"] else { throw Failure.invalidPlan }
      let plan = try JSONDecoder().decode(Self.self, from: data)
      guard plan.format == formatID, plan.maximumDispatches == 1, (1...600_000).contains(plan.timeoutMillis),
            plan.deviceModel.range(of: #"\Ai(?:Phone|Pad|Pod)[0-9]+,[0-9]+\z"#, options: .regularExpression) != nil,
            plan.memberID.range(of: #"\A[A-Za-z0-9][A-Za-z0-9_-]{0,47}\z"#, options: .regularExpression) != nil,
            plan.targetID.range(of: #"\A[A-Za-z0-9_.-]{1,120}:codex\z"#, options: .regularExpression) != nil,
            plan.modelID.range(of: #"\A[A-Za-z0-9][A-Za-z0-9_.:/-]{0,255}\z"#, options: .regularExpression) != nil,
            AgentModelReasoningEffort(rawValue: plan.reasoningEffort) != nil, !plan.assignment.isEmpty,
            plan.objective.utf8.count <= 60_000,
            plan.assignment.count <= AgentTeamDispatchText.objectiveCharacters else { throw Failure.invalidPlan }
      return plan
    }

    func checkSelection(_ selected: AgentModelSelection) throws {
      guard selected.mode == .manual, selected.targetId == targetID, selected.modelId == modelID,
            selected.reasoningEffort.rawValue == reasoningEffort else { throw Failure.selection }
    }

    func checkDispatch(member: AgentTeamMember, child: AgentRunRequest, parent: AgentRunRequest,
        prompt: String) throws {
      guard member.agentId == targetID, child.context.string("_galaxyssi_member_model_id") == modelID,
            child.context.string(AgentCollaborationReasoningSelection.contextKey) == reasoningEffort
      else { throw Failure.selection }
      let allowedKeys: Set<String> = ["_galaxyssi_member_model_id", AgentCollaborationReasoningSelection.contextKey]
      guard Set(member.context.keys) == allowedKeys, member.memberId == memberID,
            member.deliveryMode == .respond, member.dependsOnAgentIds.isEmpty,
            member.objective.utf8.elementsEqual(assignment.utf8), child.goal.utf8.elementsEqual(objective.utf8),
            parent.goal.utf8.elementsEqual(objective.utf8), child.conversationId == parent.conversationId,
            child.messageId == parent.messageId, child.taskId == parent.taskId, child.parentRunId == parent.runId,
            child.runId == AgentTeamExecutionRuntime.stableChildRunId(supervisorRunId: parent.runId, instanceId: memberID),
            child.idempotencyKey == parent.idempotencyKey + ":" + memberID,
            prompt.utf8.starts(with: (objective + "\n\n").utf8) else { throw Failure.dispatch }
    }
  }

  private struct Report: Encodable {
    let executionMode = "single_agent"
    let testScope = "execution_delivery_only"
    let status = "single_agent_returned_goal_unverified"
    let providerIOPerformed = false
    let equalBudgetComparison = false
    let scientificCapabilityGainProven = false
    let delegationAudited = false
    var goalVerifiedByExternalEvaluator = false
    let runID: String
    let childRunID: String
    var memberID: String
    let targetID: String
    let modelID: String
    let reasoningEffort: String
    let goalDigest: String
    let result: String
    var resultDigest: String
    var dispatches: Int
    var cleanupConfirmed: Bool
    var selectionPreserved: Bool

    func passes(_ plan: Plan) -> Bool {
      !goalVerifiedByExternalEvaluator && dispatches == 1 && cleanupConfirmed && selectionPreserved &&
        memberID == plan.memberID && targetID == plan.targetID && modelID == plan.modelID &&
        reasoningEffort == plan.reasoningEffort &&
        !runID.isEmpty && childRunID == AgentTeamExecutionRuntime.stableChildRunId(supervisorRunId: runID, instanceId: memberID) &&
        goalDigest == AgentSingleDeliveryCalibrationTests.digest(plan.objective) &&
        !result.isEmpty && resultDigest == AgentSingleDeliveryCalibrationTests.digest(result)
    }
  }

  private actor Admission {
    private var child: String?
    func reserve(_ run: String) throws {
      guard child == nil else { throw Failure.dispatch }
      child = run
    }
    func dispatchedRun() -> String? { child }
  }

  private func run(_ plan: Plan, selected: AgentModelSelection) async throws -> Report {
    try plan.checkSelection(selected)
    let runID = UUID().uuidString.lowercased(), suite = "ios-single-delivery-" + runID
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let secrets = InMemorySecretStore()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let conversationFile = root.appendingPathComponent("conversations.sqlite3")
    func conversationStore() -> AgentConversationDatabase { .init(fileURL: conversationFile, secrets: secrets) }
    func reopen() -> UserDefaultsAgentTeamExecutionStore { .init(defaults: defaults, key: suite, secrets: secrets) }
    let runtime = AgentTeamExecutionRuntime(store: reopen(), mailbox: InMemoryAgentTeamMailbox(),
      limits: .init(maxChildren: 1, maxConcurrency: 1))
    defer { runtime.close() }
    let request = makeRequest(plan, run: runID)
    let definition = makeDefinition(plan, run: runID)
    let original = AgentConversation(id: "selected-fixture", title: "Selection", createdAt: 1, updatedAt: 1)
    let pilot = AgentConversation(id: request.conversationId, title: "Calibration", createdAt: 2, updatedAt: 2)
    let conversations = conversationStore()
    guard conversations.upsert(original) else { throw Failure.incomplete }
    conversations.setActiveConversationId(original.id)
    guard conversations.upsert(pilot), conversations.activeConversationId == original.id else { throw Failure.incomplete }
    let admission = Admission()
    let result = "Synthetic result: execution and delivery only."
    let handle = try runtime.start(definition: definition, request: request,
      worker: ClosureAgentTeamMemberWorker { context in
        guard !context.handoff.truncated, context.handoff.dependencies.isEmpty else { throw Failure.dispatch }
        let prompt = AgentTeamDispatchText.memberPrompt(goal: context.request.goal, member: context.member,
          primaryInstanceId: definition.primaryMemberId, dependencyLines: [])
        try plan.checkDispatch(member: context.member, child: context.request, parent: request, prompt: prompt)
        try await admission.reserve(context.request.runId)
        return AgentSubagentOutput(content: result)
      })
    let watchdog = Task {
      do { try await Task.sleep(nanoseconds: UInt64(plan.timeoutMillis) * 1_000_000) } catch { return }
      handle.cancel(reason: "Single-delivery calibration deadline")
    }
    defer { watchdog.cancel() }
    let delivered = try await handle.wait()
    let persisted = try XCTUnwrap(reopen().snapshot(supervisorRunId: runID))
    guard let childRun = await admission.dispatchedRun(), !handle.isActive,
          persisted == delivered, persisted.state == .succeeded,
          persisted.members.count == 1, let member = persisted.members.first,
          member.memberId == plan.memberID, member.agentId == plan.targetID, member.status == .succeeded,
          member.researchStage == nil, member.output.utf8.elementsEqual(result.utf8),
          persisted.finalOutput.utf8.elementsEqual(result.utf8),
          persisted.goal.utf8.elementsEqual(plan.objective.utf8) else { throw Failure.incomplete }
    runtime.close()
    reopen().remove(supervisorRunId: runID)
    let after = conversationStore()
    let originalSelectionRetained = after.activeConversationId == original.id && after.read(original.id) == original
    let removed = after.delete(pilot.id) == pilot && after.confirmsAbsent(pilot.id)
    return .init(runID: runID, childRunID: childRun, memberID: member.memberId, targetID: member.agentId,
      modelID: selected.modelId, reasoningEffort: selected.reasoningEffort.rawValue, goalDigest: Self.digest(persisted.goal),
      result: persisted.finalOutput, resultDigest: Self.digest(result), dispatches: 1,
      cleanupConfirmed: reopen().snapshots().isEmpty && removed,
      selectionPreserved: originalSelectionRetained && after.activeConversationId == original.id)
  }

  private func makeDefinition(_ plan: Plan, run: String) -> AgentTeamDefinition {
    .init(teamId: run + "-team", primaryAgentId: plan.targetID, members: [
      .init(agentId: plan.targetID, deliveryMode: .respond, requiredCapabilities: [], role: "Researcher",
        objective: plan.assignment, dependsOnAgentIds: [], context: ["_galaxyssi_member_model_id": plan.modelID,
          AgentCollaborationReasoningSelection.contextKey: plan.reasoningEffort], instanceId: plan.memberID)
    ], visibilityMode: .background, collectiveCapabilities: [], primaryInstanceId: plan.memberID)
  }

  private func makeRequest(_ plan: Plan, run: String) -> AgentRunRequest {
    .init(conversationId: "fixture-" + run, messageId: run + "-turn", taskId: run + "-task", runId: run,
      parentRunId: "", goal: plan.objective, deliveryMode: .respond, requiredCapabilities: [], context: [:],
      idempotencyKey: run, createdAtMillis: 1)
  }

  private func fixturePlan(_ overrides: [String: Any] = [:]) throws -> Plan {
    let fields: [String: Any] = ["format": Plan.formatID, "deviceModel": "iPhone16,2", "targetID": selection.targetId,
      "modelID": selection.modelId, "reasoningEffort": selection.reasoningEffort.rawValue, "memberID": "researcher",
      "objective": goal, "timeoutMillis": 15_000, "maximumDispatches": 1]
    return try Plan.decode(JSONSerialization.data(withJSONObject: fields.merging(overrides) { _, new in new }))
  }

  private static func digest(_ value: String) -> String { digest(Data(value.utf8)) }
  private static func digest(_ value: Data) -> String {
    SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
  }
}
