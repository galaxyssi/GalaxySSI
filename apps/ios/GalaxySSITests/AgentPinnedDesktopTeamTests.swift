import XCTest
@testable import GalaxySSI

final class AgentPinnedDesktopTeamTests: XCTestCase {
  private var route: AgentPinnedDesktopTeam.Route {
    .init(target: "desktop:codex", desktop: "desktop", fingerprint: "fingerprint", clientRoute: "client",
      name: "Desktop", model: "gpt-5.4", effort: .high)
  }
  private func group() -> (AgentPinnedDesktopTeam.Binding, AgentCollaborationRoster) {
    let primary = UUID(), researcher = UUID()
    let pin = AgentPinnedDesktopTeam.Binding(owner: "owner", conversation: "ios-agent-" + UUID().uuidString.lowercased(),
      turn: UUID().uuidString.lowercased(), objective: "Research public battery designs", route: route,
      coordinator: primary, researcher: researcher)
    var roster = AgentCollaborationRoster(members: [
      .init(id: primary, name: "Coordinator", resourceId: route.target, modelId: route.model, reasoningEffort: "high"),
      .init(id: researcher, name: "Researcher", resourceId: route.target, modelId: route.model, reasoningEffort: "high")
    ], coordinatorId: primary, workflow: .research)
    roster.pinnedDesktop = pin
    return (pin, roster)
  }
  func testExactTwoMemberResearchRoster() {
    let (pin, roster) = group()
    XCTAssertTrue(roster.isValid)
    XCTAssertTrue(pin.matches(roster))
    XCTAssertEqual(pin.teamID, pin.conversation + ":desktop-team")
  }
  func testChangedMemberModelRejected() {
    var (pin, roster) = group()
    roster.members[1].modelId = "other-model"
    XCTAssertFalse(pin.matches(roster))
  }
  func testChangedEffortRejected() {
    var (pin, roster) = group()
    roster.members[1].reasoningEffort = "low"
    XCTAssertFalse(pin.matches(roster))
  }
  func testExtraOrMissingPersonRejected() {
    let (pin, original) = group()
    var roster = original
    roster.members.append(.init(name: "Extra", resourceId: route.target, modelId: route.model))
    XCTAssertFalse(pin.matches(roster))
    roster = original
    roster.members.removeLast()
    XCTAssertFalse(pin.matches(roster))
  }
  func testCoordinatorAndWorkflowCannotChange() {
    var (pin, roster) = group()
    roster.coordinatorId = pin.researcher
    XCTAssertFalse(pin.matches(roster))
    roster.coordinatorId = pin.coordinator
    roster.workflow = .parallel
    XCTAssertFalse(pin.matches(roster))
  }
  func testMentionOnlyMemberCannotBecomePinnedWorker() {
    var (pin, roster) = group()
    roster.members[1].mentionOnly = true
    XCTAssertFalse(pin.matches(roster))
  }
  func testRouteDigestBindsIdentityModelAndEffort() {
    let original = route
    for changed in [
      AgentPinnedDesktopTeam.Route(target: "other:codex", desktop: original.desktop, fingerprint: original.fingerprint,
        clientRoute: original.clientRoute, name: original.name, model: original.model, effort: original.effort),
      .init(target: original.target, desktop: original.desktop, fingerprint: "changed", clientRoute: original.clientRoute,
        name: original.name, model: original.model, effort: original.effort),
      .init(target: original.target, desktop: original.desktop, fingerprint: original.fingerprint, clientRoute: "changed",
        name: original.name, model: original.model, effort: original.effort),
      .init(target: original.target, desktop: original.desktop, fingerprint: original.fingerprint,
        clientRoute: original.clientRoute, name: original.name, model: "other-model", effort: original.effort),
      .init(target: original.target, desktop: original.desktop, fingerprint: original.fingerprint,
        clientRoute: original.clientRoute, name: original.name, model: original.model, effort: .low)
    ] { XCTAssertNotEqual(original.digest, changed.digest) }
  }
  func testOptionalBindingRoundTripsWithoutChangingOldRoster() throws {
    let (pin, roster) = group()
    XCTAssertEqual(try JSONDecoder().decode(AgentCollaborationRoster.self, from: JSONEncoder().encode(roster)), roster)
    XCTAssertEqual(roster.pinnedDesktop, pin)
    let old = Data(#"{"members":[],"independentReview":false}"#.utf8)
    XCTAssertNil(try JSONDecoder().decode(AgentCollaborationRoster.self, from: old).pinnedDesktop)
  }
  @MainActor func testReviewCanBeConsumedOnlyOnceEvenAfterRouteDrift() {
    let id = UUID(), review = AgentPinnedDesktopTeam.Review(launch: UUID(), route: route)
    XCTAssertFalse(review.claim(launch: id, current: route))
    XCTAssertFalse(review.claim(launch: review.launch, current: route))
    let valid = AgentPinnedDesktopTeam.Review(launch: id, route: route)
    XCTAssertTrue(valid.claim(launch: id, current: route))
    XCTAssertFalse(valid.claim(launch: id, current: route))
  }
  func testObjectiveScreeningBeforeDisclosure() {
    XCTAssertTrue(AgentPinnedDesktopTeam.eligibleObjective("Research public battery designs", language: "en"))
    XCTAssertFalse(AgentPinnedDesktopTeam.eligibleObjective("Research treatment for patient id: 123", language: "en"))
    XCTAssertFalse(AgentPinnedDesktopTeam.eligibleObjective("Research MRN=123", language: "en"))
    XCTAssertFalse(AgentPinnedDesktopTeam.eligibleObjective("Research patient name: Example", language: "en"))
  }
  private func spec(_ pin: AgentPinnedDesktopTeam.Binding, roster: AgentCollaborationRoster) -> AgentTeamDispatchSpec {
    let members = roster.members.map { entry in
      let primary = entry.id == pin.coordinator
      let id = entry.id.uuidString.lowercased()
      return AgentTeamMember(agentId: pin.route.target, deliveryMode: primary ? .respond : .observe,
        requiredCapabilities: [], role: entry.name, objective: pin.objective,
        dependsOnAgentIds: primary ? [pin.researcher.uuidString.lowercased()] : [], context: [
          "_galaxyssi_selection_source": "collaboration_roster",
          AgentCollaborationMemberIdentity.contextKey: id,
          "_galaxyssi_member_model_id": pin.route.model,
          AgentCollaborationReasoningSelection.contextKey: "high",
          "_galaxyssi_research_stage": primary ? "DELIVER" : "EXPLORE",
          AgentPinnedDesktopTeam.pinKey: pin.route.digest, AgentPinnedDesktopTeam.personKey: id
        ], instanceId: id)
    }
    return .init(definition: AgentTeamDefinition(teamId: pin.teamID, primaryAgentId: pin.route.target,
      members: members, visibilityMode: .background, collectiveCapabilities: [],
      primaryInstanceId: pin.coordinator.uuidString.lowercased()),
      supervisorRunId: AgentTeamDispatchIds.supervisorRunId(teamId: pin.teamID))
  }
  func testExactResearchSpecAndStableRetryIdentity() {
    let (pin, roster) = group(), original = spec(pin, roster: roster)
    XCTAssertTrue(AgentPinnedDesktopTeam.owns(original, binding: pin, roster: roster))
    let action = AgentAction(id: "pinned", kind: .callConnector, target: "Desktop", risk: .low,
      status: .pendingConfirmation, description: "Research", parameters: [
        AgentPinnedDesktopTeam.pinKey: pin.route.digest,
        agentTeamSpecParameter: AgentTeamDispatchSpecCodec.encode(original)
      ], requiresConfirmation: false)
    XCTAssertEqual(AgentTeamPlanCompiler.rekeyAgentTeamForRetry(action), action)
  }
  func testWrongTeamPersonOrStageCannotOwnPinnedRun() {
    let (pin, roster) = group(), original = spec(pin, roster: roster)
    var changed = original
    changed.definition.teamId = "other-team"
    XCTAssertFalse(AgentPinnedDesktopTeam.owns(changed, binding: pin, roster: roster))
    changed = original
    changed.definition.members[0].context[AgentPinnedDesktopTeam.personKey] = UUID().uuidString.lowercased()
    XCTAssertFalse(AgentPinnedDesktopTeam.owns(changed, binding: pin, roster: roster))
    changed = original
    changed.definition.members[1].context["_galaxyssi_research_stage"] = "DELIVER"
    XCTAssertFalse(AgentPinnedDesktopTeam.owns(changed, binding: pin, roster: roster))
  }
  func testWorkspaceContractRequiresManagedRosterOwnership() {
    let (pin, roster) = group(), original = spec(pin, roster: roster)
    var context = AgentOutboundTeamContext(teamId: pin.teamID, supervisorRunId: original.supervisorRunId,
      primaryInstanceId: original.definition.primaryMemberId, member: original.definition.members[0],
      sourceMessageId: UUID().uuidString, isManagedCollaboration: true)
    XCTAssertTrue(AgentPinnedDesktopTeam.owns(context, binding: pin, roster: roster))
    var payload: [String: Any] = [:]
    context.apply(to: &payload, workspaceRoster: roster)
    XCTAssertEqual(payload["result_contract"] as? String, AgentOutboundTeamContext.workspaceResultContract)
    context.isManagedCollaboration = false
    XCTAssertFalse(AgentPinnedDesktopTeam.owns(context, binding: pin, roster: roster))
    context.apply(to: &payload, workspaceRoster: roster)
    XCTAssertNil(payload["result_contract"])
  }
}
