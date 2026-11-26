import XCTest
@testable import GalaxySSI

final class AgentNativeConnectorRichReplyTests: XCTestCase {
  private struct Fixture {
    var outgoing: ChatMessage
    var task: AgentTaskRecord
    var action: AgentAction
    var record: AgentManagedResponseRecord
    var result: AgentActionResult
    func rich(profile: String = "profile") -> String? {
      AgentNativeConnectorRichReplyPolicy.validated(result: result, action: action,
        outgoing: outgoing, task: task, profile: profile, record: record)
    }
  }

  private func fixture() throws -> Fixture {
    let outgoing = ChatMessage(contactId: "hermes", content: "Return report", isMine: true,
      conversationId: "conversation", turnId: "turn")
    let task = AgentTaskRecord(taskId: "turn", sessionId: "conversation", goal: outgoing.content,
      phase: .waitingResponse, routeKind: .localSystem, targetTitle: "Codex", risk: .low, blocked: false)
    let action = AgentAction(id: "action", kind: .callConnector, target: "desktop", risk: .low,
      status: .proposed, description: task.goal, parameters: ["connector_id": "desktop",
        "_galaxyssi_conversation_id": "conversation", "_galaxyssi_turn_id": "turn", "_galaxyssi_task_id": "turn",
        AgentIOSConnectorDispatch.sourceKey: outgoing.id.uuidString, AgentIOSConnectorDispatch.profileKey: "profile"])
    let owner = AgentControlPlaneActionExecutor.connectorRunId(action: action, agentId: "codex")
    let rich = AgentRichContentCodec.encode([AgentRichBlock(id: "report", type: .file, title: "Report", uri: "artifact://report")])
    let response = AgentConnectorResponse(sourceMessageId: 41, contactId: "desktop", content: "Report ready",
      conversationId: "conversation", turnId: "turn", taskId: "remote-task", richOutputJson: rich,
      taskStatus: "completed", executionGeneration: 2)
    let record = AgentManagedResponseRecord(ownerRunId: owner, supervisorRunId: "", agentId: "codex", deliveryMode: .respond,
      sourceMessageId: 41, contactId: "desktop", conversationId: "conversation", turnId: "turn", taskId: "remote-task",
      executionGeneration: 2, state: .completed, response: response)
    let pending = AgentActionResult(actionId: action.id, success: true, message: "Waiting", metadata: [
      "awaiting_response": "true", "source_message_id": "41", "contact_id": "desktop", "conversation_id": "conversation",
      "turn_id": "turn", "task_id": "remote-task", "execution_generation": "2",
      "control_plane_run_id": owner, "control_plane_agent_id": "codex"])
    let result = try XCTUnwrap(AgentNativeConnectorContinuation.settle(pending, record: record))
    return Fixture(outgoing: outgoing, task: task, action: action, record: record, result: result)
  }

  func testCommittedAndAppliedNativeRepliesRetainRichBlocks() throws {
    var f = try fixture()
    XCTAssertEqual(f.rich(), AgentRichContentCodec.normalize(f.record.response!.richOutputJson))
    f.record.state = .applied
    XCTAssertNotNil(f.rich())
    f.result.metadata["non_retriable"] = "true"
    XCTAssertNotNil(f.rich(), "Retry policy alone must not suppress an owned successful presentation")
  }

  func testPendingFailedUnknownAndUncommittedBodiesCannotEnterTranscript() throws {
    let original = try fixture()
    var f = original
    f.record.state = .pending
    XCTAssertNil(f.rich())
    f = original; f.record.response = nil
    XCTAssertNil(f.rich())
    f = original; f.record.response?.success = false
    XCTAssertNil(f.rich())
    f = original; f.result.metadata["effect_outcome_unknown"] = "true"
    XCTAssertNil(f.rich())
    f = original; f.result.message = "Replacement"
    XCTAssertNil(f.rich())
    f = original; f.result.metadata["rich_output"] = "[]"
    XCTAssertNil(f.rich())
  }

  func testEverySettledOwnerDimensionMustMatch() throws {
    for key in ["control_plane_run_id", "control_plane_agent_id", "source_message_id", "contact_id",
                "conversation_id", "turn_id", "task_id", "execution_generation"] {
      var f = try fixture()
      f.result.metadata[key] = "other"
      XCTAssertNil(f.rich(), key)
    }
    var f = try fixture()
    f.record.response?.executionGeneration = 1
    XCTAssertNil(f.rich())
    f = try fixture(); f.record.response?.taskStatus = "cancelled"
    XCTAssertNil(f.rich())
  }

  func testLocalActionSourceProfileAndTranscriptContextAreRequired() throws {
    for key in [AgentIOSConnectorDispatch.sourceKey, AgentIOSConnectorDispatch.profileKey,
                "_galaxyssi_task_id", "_galaxyssi_turn_id", "_galaxyssi_conversation_id", "connector_id"] {
      var f = try fixture()
      f.action.parameters[key] = "other"
      XCTAssertNil(f.rich(), key)
    }
    var f = try fixture()
    XCTAssertNil(f.rich(profile: "other"))
    f.outgoing.isMine = false
    XCTAssertNil(f.rich())
    f = try fixture(); f.action.parameters["_galaxyssi_agent_team_spec"] = "team"
    XCTAssertNil(f.rich())
  }

  private func update() throws -> GalaxySSIPeerAttachmentTransferUpdate {
    try XCTUnwrap(GalaxySSIPeerAttachmentTransferUpdate(payload: ["transfer_id": "transfer", "source_message_id": "41", "peer_chat": false,
      "client_route_id": "route", "desktop_id": "desktop-id", "conversation_id": "conversation",
      "task_id": "remote-task", "turn_id": "turn", "execution_generation": 2, "size_bytes": 123,
      "sha256": String(repeating: "a", count: 64), "uri": "artifact://report", "state": "complete"]))
  }

  private func metadata(_ update: GalaxySSIPeerAttachmentTransferUpdate) -> [String: String] {
    ["blob_client_route_id": update.clientRouteId, "blob_desktop_id": update.desktopId,
      "blob_conversation_id": update.conversationId, "blob_task_id": update.taskId, "blob_turn_id": update.turnId,
      "blob_execution_generation": String(update.executionGeneration), "transfer_id": update.transferId,
      "artifact_source_uri": update.uri, "sha256": update.sha256, "size_bytes": String(update.sizeBytes)]
  }

  func testLaterIneligibleMessageCannotHideOriginalArtifactReply() throws {
    let event = try update()
    var incoming = ChatMessage(contactId: "hermes", content: "Report", isMine: false,
      conversationId: "conversation", turnId: "turn")
    incoming.richOutputJson = AgentRichContentCodec.encode([AgentRichBlock(id: "file", type: .file,
      uri: event.uri, metadata: metadata(event))])
    var otherConversation = incoming
    otherConversation.conversationId = "other"
    var outgoing = incoming
    outgoing.isMine = true
    var otherTask = incoming
    var wrong = metadata(event)
    wrong["blob_task_id"] = "other"
    otherTask.richOutputJson = AgentRichContentCodec.encode([AgentRichBlock(id: "file", type: .file, uri: event.uri, metadata: wrong)])
    XCTAssertEqual(GalaxySSIPeerAttachmentTransferProgress.agentArtifactMessage(event,
      messages: [incoming, otherTask, outgoing, otherConversation]), incoming)
    XCTAssertNil(GalaxySSIPeerAttachmentTransferProgress.agentArtifactMessage(event,
      messages: [otherTask, outgoing, otherConversation]))
  }

  func testArtifactAndGalleryMatchingRequireExactVerifiedMetadata() throws {
    let event = try update()
    for key in metadata(event).keys {
      var wrong = metadata(event)
      wrong[key] = "other"
      let file = AgentRichBlock(id: "file", type: .file, uri: event.uri, metadata: wrong)
      XCTAssertFalse(GalaxySSIPeerAttachmentTransferProgress.matchesArtifactUpdate(event,
        richOutput: AgentRichContentCodec.encode([file])), key)
    }
    let item = String(decoding: try JSONEncoder().encode(metadata(event)), as: UTF8.self)
    let gallery = AgentRichBlock(id: "images", type: .gallery, metadata: ["blob_item_0": item])
    XCTAssertTrue(GalaxySSIPeerAttachmentTransferProgress.matchesArtifactUpdate(event,
      richOutput: AgentRichContentCodec.encode([gallery])))
    var peer = event
    peer.peerChat = true
    XCTAssertFalse(GalaxySSIPeerAttachmentTransferProgress.matchesArtifactUpdate(peer,
      richOutput: AgentRichContentCodec.encode([gallery])))
  }

  func testNumericArtifactScopeRequiresExistingExactManagedGeneration() throws {
    let f = try fixture()
    let manifest: [String: Any] = ["source_message_id": "41", "contact_id": "desktop",
      "conversation_id": "conversation", "turn_id": "turn", "task_id": "remote-task", "execution_generation": 2]
    XCTAssertTrue(AgentManagedArtifactScopePolicy.authorizes(manifest, record: f.record))
    var pending = f.record
    pending.state = .pending; pending.response = nil
    XCTAssertTrue(AgentManagedArtifactScopePolicy.authorizes(manifest, record: pending))
    XCTAssertFalse(AgentManagedArtifactScopePolicy.authorizes(manifest, record: nil))
    for key in manifest.keys {
      var wrong = manifest
      if key == "execution_generation" { wrong[key] = 1 } else { wrong[key] = "other" }
      XCTAssertFalse(AgentManagedArtifactScopePolicy.authorizes(wrong, record: f.record), key)
    }
    for source in ["041", "0", "-1", "9007199254740992", UUID().uuidString] {
      var wrong = manifest
      wrong["source_message_id"] = source
      XCTAssertFalse(AgentManagedArtifactScopePolicy.authorizes(wrong, record: f.record))
    }
    var failed = f.record
    failed.response?.success = false
    XCTAssertFalse(AgentManagedArtifactScopePolicy.authorizes(manifest, record: failed))
  }
}
