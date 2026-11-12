import XCTest
@testable import GalaxySSI

final class AgentCollaborationPilotIdentityTests: XCTestCase {
  private struct ProtocolInput: Decodable {
    enum IdentityPolicy: String, Decodable { case production, runScoped = "run_scoped" }
    let policy: IdentityPolicy

    private enum CodingKeys: String, CodingKey { case policy = "initial_identity_policy" }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      policy = container.contains(.policy) ? try container.decode(IdentityPolicy.self, forKey: .policy) : .production
    }

    func definition(_ original: AgentTeamDefinition, pilot: String, group: String, run: String) throws -> AgentTeamDefinition {
      guard policy == .runScoped else { return original }
      let ids = original.members.map(\.memberId)
      guard !pilot.isBlank, !group.isBlank, !run.isBlank, Set(ids).count == ids.count else {
        throw AgentTeamExecutionRuntimeError.invalid("Pilot requires a unique initial graph and exact scope")
      }
      let nodes = Dictionary(uniqueKeysWithValues: ids.map { id in
        let name = AgentMcpJSONCodec.stringify(.array(["pilot-initial-identity.v1", pilot, group, run, id].map(AgentMcpJSONValue.string)))
        return (id, AgentTeamDispatchIds.nameBasedUUID(name).uuidString.lowercased())
      })
      func node(_ id: String) throws -> String {
        guard let value = nodes[id] else { throw AgentTeamExecutionRuntimeError.invalid("Unknown pilot node") }
        return value
      }
      var scoped = original
      scoped.primaryInstanceId = try node(original.primaryMemberId)
      scoped.members = try original.members.map { member in
        var copy = member
        copy.instanceId = try node(member.memberId)
        copy.dependsOnAgentIds = try Set(member.dependsOnAgentIds.map(node))
        return copy
      }
      return scoped
    }
  }

  private actor Admissions {
    private var nodes: [String] = []
    func record(_ node: String) { nodes.append(node) }
    func read() -> [String] { nodes }
  }

  private let goal = "Compare the original data without substituting a different objective."
  private let group = "retained-pilot-group"

  private func input(_ raw: String) throws -> ProtocolInput {
    try JSONDecoder().decode(ProtocolInput.self, from: Data(raw.utf8))
  }

  private func original(single: Bool = false) -> AgentTeamDefinition {
    let lead = AgentTeamMember(agentId: "fixture-model", deliveryMode: .respond, requiredCapabilities: [],
      role: "Investigator", objective: goal, dependsOnAgentIds: single ? [] : ["peer"],
      context: [AgentCollaborationMemberIdentity.contextKey: "lead", "_galaxyssi_member_model_id": "lead-model"], instanceId: "lead")
    let peer = AgentTeamMember(agentId: "fixture-model", deliveryMode: .observe, requiredCapabilities: [],
      role: "Evidence", objective: "Collect the specified evidence", dependsOnAgentIds: [],
      context: [AgentCollaborationMemberIdentity.contextKey: "peer", "_galaxyssi_member_model_id": "peer-model"], instanceId: "peer")
    return .init(teamId: "pilot-team", primaryAgentId: lead.agentId, members: single ? [lead] : [lead, peer],
      visibilityMode: .background, collectiveCapabilities: [], primaryInstanceId: lead.memberId)
  }

  func testIdentityPolicyDefaultsToProductionAndOnlyRewritesExecutionNodes() throws {
    let original = self.original()
    for raw in ["{}", #"{"initial_identity_policy":"production"}"#] {
      XCTAssertEqual(try input(raw).definition(original, pilot: "p1", group: group, run: "r1"), original)
    }
    for raw in [#"{"initial_identity_policy":"other"}"#, #"{"initial_identity_policy":true}"#, #"{"initial_identity_policy":null}"#] {
      XCTAssertThrowsError(try input(raw))
    }
    let protocolInput = try input(#"{"initial_identity_policy":"run_scoped"}"#)
    let first = try protocolInput.definition(original, pilot: "p1", group: group, run: "r1")
    XCTAssertEqual(first, try protocolInput.definition(original, pilot: "p1", group: group, run: "r1"))
    XCTAssertEqual(first.primaryMemberId, first.members[0].memberId)
    XCTAssertEqual(first.members[0].dependsOnAgentIds, [first.members[1].memberId])
    XCTAssertEqual(first.primaryAgentId, original.primaryAgentId)
    for (before, after) in zip(original.members, first.members) {
      XCTAssertNotEqual(before.memberId, after.memberId)
      var restored = after
      restored.instanceId = before.instanceId
      restored.dependsOnAgentIds = before.dependsOnAgentIds
      XCTAssertEqual(restored, before)
    }
    let firstNodes = Set(first.members.map(\.memberId))
    for (pilot, group, run) in [("p2", group, "r1"), ("p1", "other-group", "r1"), ("p1", group, "r2")] {
      let distinct = try protocolInput.definition(original, pilot: pilot, group: group, run: run)
      XCTAssertTrue(firstNodes.isDisjoint(with: distinct.members.map(\.memberId)))
    }
  }

  func testScopedNodeIdentitiesKeepDurableHandoffsSeparateAcrossTwoRuns() async throws {
    let suite = "pilot-node-identities-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let secrets = InMemorySecretStore()
    let protocolInput = try input(#"{"initial_identity_policy":"run_scoped"}"#)
    func open() -> UserDefaultsAgentTeamExecutionStore { .init(defaults: defaults, secrets: secrets) }
    let first = try await execute(protocolInput.definition(original(), pilot: "p1", group: group, run: "r1"),
      run: "r1", store: open())
    XCTAssertEqual(open().snapshot(supervisorRunId: "r1"), first)
    let second = try await execute(protocolInput.definition(original(), pilot: "p1", group: group, run: "r2"),
      run: "r2", store: open())
    XCTAssertEqual(open().snapshot(supervisorRunId: "r1"), first)
    XCTAssertEqual(open().snapshot(supervisorRunId: "r2"), second)
    XCTAssertTrue(Set(first.members.map(\.memberId)).isDisjoint(with: second.members.map(\.memberId)))
    XCTAssertEqual(first.conversationId, second.conversationId)
    XCTAssertEqual(first.goal, second.goal)
  }

  func testScopedSingleInvestigatorRemainsOneUnmodifiedAssignment() async throws {
    let protocolInput = try input(#"{"initial_identity_policy":"run_scoped"}"#)
    let scoped = try protocolInput.definition(original(single: true), pilot: "solo", group: group, run: "r1")
    XCTAssertEqual(scoped.members.count, 1)
    XCTAssertTrue(scoped.members[0].dependsOnAgentIds.isEmpty)
    XCTAssertEqual(scoped.members[0].objective, goal)
    XCTAssertNil(scoped.members[0].context["_galaxyssi_research_stage"])
    XCTAssertNotEqual(scoped.primaryMemberId, "lead")
    _ = try await execute(scoped, run: "r1", store: InMemoryAgentTeamExecutionStore())
  }

  private func execute(_ definition: AgentTeamDefinition, run: String, store: AgentTeamExecutionStore) async throws
    -> AgentTeamExecutionSnapshot {
    let goal = self.goal
    let group = self.group
    let admissions = Admissions()
    let runtime = AgentTeamExecutionRuntime(store: store, mailbox: InMemoryAgentTeamMailbox(),
      limits: .init(maxChildren: 2, maxConcurrency: 1))
    defer { runtime.close() }
    let request = AgentRunRequest(conversationId: group, messageId: "turn-" + run, taskId: "turn-" + run,
      runId: run, parentRunId: "", goal: goal, deliveryMode: .respond, requiredCapabilities: [],
      context: [:], idempotencyKey: run, createdAtMillis: 1)
    let handle = try runtime.start(definition: definition, request: request, worker: ClosureAgentTeamMemberWorker { context in
      await admissions.record(context.member.memberId)
      let expected = try XCTUnwrap(definition.members.first { $0.memberId == context.member.memberId })
      XCTAssertEqual(context.member, expected)
      XCTAssertEqual(context.request.conversationId, group)
      XCTAssertEqual(context.request.parentRunId, run)
      XCTAssertEqual(context.request.goal, goal)
      XCTAssertEqual(context.request.context["team_instance_id"], .string(expected.memberId))
      for (key, value) in expected.context { XCTAssertEqual(context.request.context[key], .string(value)) }
      XCTAssertEqual(Set(context.handoff.dependencies.map(\.childId)), expected.dependsOnAgentIds)
      if expected.deliveryMode == .respond, definition.members.count == 2 {
        XCTAssertEqual(context.handoff.dependencies.map(\.output), ["evidence-" + run])
      }
      return .init(content: (expected.deliveryMode == .observe ? "evidence-" : "delivery-") + run)
    })
    let result = try await handle.wait()
    let actual = await admissions.read()
    let expected = definition.members.sorted { $0.deliveryMode == .observe && $1.deliveryMode == .respond }.map(\.memberId)
    XCTAssertEqual(actual, expected)
    XCTAssertEqual(result.state, .succeeded)
    XCTAssertEqual(result.primaryMemberId, definition.primaryMemberId)
    XCTAssertEqual(result.finalOutput, "delivery-" + run)
    return result
  }
}
