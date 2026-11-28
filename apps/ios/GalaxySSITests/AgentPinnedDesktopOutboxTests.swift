import XCTest
@testable import GalaxySSI

@MainActor
final class AgentPinnedDesktopOutboxTests: XCTestCase {
  private func fixture() -> (MqttDesktopConnectorProjection.TaskOwner, [String: Any], AgentPinnedDesktopTeam.Binding) {
    let pin = AgentPinnedDesktopTeam.Binding(owner: "owner", conversation: "ios-agent-" + UUID().uuidString.lowercased(),
      turn: UUID().uuidString.lowercased(), objective: "Research public battery designs",
      route: .init(target: "desktop:codex", desktop: "desktop", fingerprint: "fingerprint", clientRoute: "route",
        name: "Desktop", model: "gpt-5.4", effort: .high), coordinator: UUID(), researcher: UUID())
    let message = ChatMessage(contactId: "hermes", content: pin.objective, isMine: true,
      conversationId: pin.conversation, turnId: pin.turn)
    let team = AgentTeamReplyOwner(supervisorRunId: AgentTeamDispatchIds.supervisorRunId(teamId: pin.teamID),
      memberId: pin.coordinator.uuidString.lowercased(), conversationId: pin.conversation, turnId: pin.turn,
      sourceMessageId: UUID().uuidString, contactId: pin.route.target, deliveryMode: .respond)
    let owner = MqttDesktopConnectorProjection.TaskOwner(message: message, team: team, teamID: pin.teamID, pinnedDesktop: pin)
    let payload: [String: Any] = ["agent_team_message": true, "agent_instance_id": team.memberId,
      "team_id": pin.teamID, "delivery_mode": AgentDeliveryMode.respond.rawValue, "run_id": team.supervisorRunId,
      "conversation_id": pin.conversation, "turn_id": pin.turn, "client_route_id": pin.route.clientRoute,
      "contact_id": pin.route.target, "desktop_id": pin.route.desktop,
      "result_contract": AgentOutboundTeamContext.workspaceResultContract,
      "agent_invocation": AgentInvocationRequestJsonCodec.encode(modelId: pin.route.model, reasoningEffort: pin.route.effort)!,
      AgentPinnedDesktopTeam.pinKey: pin.route.digest, AgentPinnedDesktopTeam.personKey: team.memberId]
    return (owner, payload, pin)
  }
  func testQueuedOwnerRetainsExactPinnedPayload() {
    let (owner, payload, _) = fixture()
    XCTAssertTrue(owner.matches(payload))
  }
  func testPayloadCannotSwitchAnyPinnedIdentityDimension() {
    let (owner, payload, _) = fixture()
    for key in ["agent_instance_id", "team_id", "delivery_mode", "run_id", "conversation_id", "turn_id",
      "client_route_id", "contact_id", "desktop_id", "result_contract", AgentPinnedDesktopTeam.pinKey,
      AgentPinnedDesktopTeam.personKey] {
      var changed = payload
      changed[key] = "changed"
      XCTAssertFalse(owner.matches(changed), key)
    }
  }
  func testPinnedModelAndEffortNeverDefaultOrNormalize() {
    let (owner, payload, _) = fixture()
    for invocation in [["model_id": "other", "reasoning_effort": "high"],
      ["model_id": "gpt-5.4", "reasoning_effort": "low"], ["model_id": "gpt-5.4"]] {
      var changed = payload
      changed["agent_invocation"] = invocation
      XCTAssertFalse(owner.matches(changed))
    }
  }
  func testMissingPersistedBindingCannotInterpretPinAsOrdinaryTeam() {
    var (owner, payload, _) = fixture()
    owner.pinnedDesktop = nil
    XCTAssertFalse(owner.matches(payload))
  }
  func testAttachmentsCannotAppearAfterConfirmation() {
    let (owner, payload, _) = fixture()
    var changed = payload
    changed["attachments"] = [["id": "private-file"]]
    XCTAssertFalse(owner.matches(changed))
  }
  func testTeamSnapshotPreservesPinAndOldSnapshotsStillDecode() throws {
    let (_, _, pin) = fixture()
    var snapshot = AgentTeamExecutionSnapshot(supervisorRunId: AgentTeamDispatchIds.supervisorRunId(teamId: pin.teamID),
      teamId: pin.teamID, conversationId: pin.conversation, taskId: pin.turn,
      primaryAgentId: pin.route.target, goal: pin.objective, state: .running)
    let old = try JSONEncoder().encode(snapshot)
    XCTAssertNil(try JSONDecoder().decode(AgentTeamExecutionSnapshot.self, from: old).pinnedDesktop)
    snapshot.pinnedDesktop = pin
    XCTAssertEqual(try JSONDecoder().decode(AgentTeamExecutionSnapshot.self,
      from: JSONEncoder().encode(snapshot)).pinnedDesktop, pin)
  }
  func testLegacyQueueScopeRoundTripsWithoutCopyingObjective() throws {
    let (_, _, pin) = fixture(), now = Date()
    var item = PendingLinkMessage(messageId: UUID().uuidString, topic: "topic", wirePayload: "ciphertext",
      status: "queued", attempts: 0, nextAttemptAt: now, createdAt: now, updatedAt: now)
    let old = try JSONEncoder().encode(item)
    XCTAssertNil(try JSONDecoder().decode(PendingLinkMessage.self, from: old).pinnedDesktopRunID)
    item.pinnedDesktopRunID = AgentTeamDispatchIds.supervisorRunId(teamId: pin.teamID)
    let data = try JSONEncoder().encode(item)
    XCTAssertEqual(try JSONDecoder().decode(PendingLinkMessage.self, from: data).pinnedDesktopRunID, item.pinnedDesktopRunID)
    XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(pin.objective))
  }
}
