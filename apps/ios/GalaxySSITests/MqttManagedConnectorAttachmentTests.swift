import XCTest
@testable import GalaxySSI

final class MqttManagedConnectorAttachmentTests: XCTestCase {
  private func fixture(source: String = "77", blob: Bool = false) throws -> (files: ChunkFixture, journal: MqttSignalStateJournal,
    body: MqttSignalSendRequest, transfers: [AgentPreparedOutboundAttachment]) {
    let files = try ChunkFixture()
    let bodyID = UUID().uuidString
    let scope = try AgentAttachmentTransferScope(contactId: "agent", desktopId: "desktop", clientRouteId: sendTopic,
      conversationId: "conversation", taskId: bodyID, turnId: "turn", clientMessageId: source)
    let store = AgentOutboundAttachmentTransferStore(rootURL: files.root.appendingPathComponent("attachments"),
      cipher: GalaxySSIAttachmentAtRestCipher(secrets: files.secrets))
    let transfers = try store.prepare(scope: scope, attachments: [
      .init(displayName: "one.bin", mimeType: "application/octet-stream", data: Data([1])),
      .init(displayName: "two.bin", mimeType: "application/octet-stream", data: Data([2]))
    ], mediaProfile: AgentMediaNetworkPolicy.profile(for: .normal), preserveOriginalBytes: true)
    let payload: [String: Any] = ["type": "text", "message_id": bodyID, "source_message_id": source, "client_message_id": source,
      "contact_id": "agent", "desktop_id": "desktop", "client_route_id": sendTopic, "conversation_id": "conversation",
      "task_id": bodyID, "turn_id": "turn", "attachments": transfers.map { $0.descriptor() }]
    let body = try MqttSignalSendRequest(identity: sendTestIdentity(), payload: payload, remoteName: "desktop", topic: sendTopic,
      clientRouteID: sendTopic, attachmentDependencies: transfers.map(\.transferId), sourceMessageID: source, contactID: "agent",
      blobAttachmentDependencies: blob ? [transfers[0].transferId] : [])
    let journal = try MqttSignalStateJournal(fileURL: files.url, secrets: files.secrets)
    try journal.outbox.enqueueDeferred(body, now: Date())
    return (files, journal, body, transfers)
  }

  private func receipt(_ transfer: AgentPreparedOutboundAttachment, body: MqttSignalSendRequest,
                       journal: MqttSignalStateJournal, source: String? = nil) throws -> MqttBusinessInbox.Pending {
    let id = UUID().uuidString
    var payload = transfer.manifestPayload(resume: false)
    payload["type"] = "input_attachment_receipt"
    payload["message_id"] = id
    payload["status"] = "stored"
    payload["source_message_id"] = source ?? body.sourceMessageID
    let digest = MqttRouteProtocol.digest(Data(id.utf8))
    _ = try journal.inbox.accept(identity: body.identity, messageID: id, payload: payload,
      ciphertextDigest: digest, wireHash: digest, receiptRequired: true)
    return try XCTUnwrap(journal.inbox.pending().first { $0.messageID == id })
  }

  func testNumericSourceUsesOriginalTaskUUIDWithoutRewritingSourceIdentity() {
    let task = UUID().uuidString
    XCTAssertEqual(MqttAttachmentBodyIdentity.bodyID(source: "77", taskID: task), task)
    XCTAssertEqual(MqttAttachmentBodyIdentity.bodyID(source: "9007199254740991", taskID: task), task)
    let source = UUID().uuidString
    XCTAssertEqual(MqttAttachmentBodyIdentity.bodyID(source: source, taskID: "legacy-task"), source)
  }

  func testUnsafeOrAmbiguousNumericSourcesAndNonUUIDTasksAreRejected() {
    let task = UUID().uuidString
    for source in ["", "0", "-1", "077", "+77", " 77", "9007199254740992", "9223372036854775808"] {
      XCTAssertNil(MqttAttachmentBodyIdentity.bodyID(source: source, taskID: task), source)
    }
    XCTAssertNil(MqttAttachmentBodyIdentity.bodyID(source: "77", taskID: "invented-body"))
  }

  func testStoredRequestBindsNumericSourceRouteContactAndExactTransferScope() throws {
    let f = try fixture()
    let transfer = try XCTUnwrap(f.transfers.first)
    XCTAssertTrue(try MqttAttachmentBodyIdentity.matches(f.body, transfer: transfer, bodyID: f.body.messageID))
    for field in ["source", "contact", "desktop", "route", "conversation", "task", "turn"] {
      var changed = transfer
      switch field {
      case "source": changed.scope.clientMessageId = "78"
      case "contact": changed.scope.contactId = "other"
      case "desktop": changed.scope.desktopId = "other"
      case "route": changed.scope.clientRouteId = String(repeating: "x", count: 43)
      case "conversation": changed.scope.conversationId = "other"
      case "task": changed.scope.taskId = UUID().uuidString
      default: changed.scope.turnId = "other"
      }
      XCTAssertFalse(try MqttAttachmentBodyIdentity.matches(f.body, transfer: changed, bodyID: f.body.messageID), field)
    }
    XCTAssertFalse(try MqttAttachmentBodyIdentity.matches(f.body, bodyID: UUID().uuidString))
  }

  func testNumericDependencyReleaseWaitsForEveryStoredAttachmentAndSurvivesReopen() throws {
    let f = try fixture()
    let first = try XCTUnwrap(f.transfers.first), second = try XCTUnwrap(f.transfers.last)
    try f.journal.consumeStoredAttachment(receipt(first, body: f.body, journal: f.journal), bodyID: f.body.messageID, transfer: first)
    let reopened = try MqttSignalStateJournal(fileURL: f.files.url, secrets: f.files.secrets)
    XCTAssertEqual(try reopened.outbox.entry(identity: f.body.identity, messageID: f.body.messageID)?.message.blockedByAttachmentTransferIds, [second.transferId])
    try reopened.consumeStoredAttachment(receipt(second, body: f.body, journal: reopened), bodyID: f.body.messageID, transfer: second)
    let ready = try XCTUnwrap(reopened.outbox.entry(identity: f.body.identity, messageID: f.body.messageID))
    XCTAssertTrue(ready.message.blockedByAttachmentTransferIds.isEmpty)
    XCTAssertFalse(ready.isPrepared)
    XCTAssertEqual(ready.message.clientSourceMessageId, "77")
  }

  func testForeignNumericReceiptCannotReleaseOriginalBody() throws {
    let f = try fixture()
    let transfer = try XCTUnwrap(f.transfers.first)
    let wrong = try receipt(transfer, body: f.body, journal: f.journal, source: "78")
    XCTAssertThrowsError(try f.journal.consumeStoredAttachment(wrong, bodyID: f.body.messageID, transfer: transfer))
    XCTAssertEqual(try f.journal.outbox.entry(identity: f.body.identity, messageID: f.body.messageID)?.message.blockedByAttachmentTransferIds,
      f.body.attachmentDependencies)
    XCTAssertTrue(try f.journal.inbox.pending().contains { $0.messageID == wrong.messageID })
  }

  func testNumericReleaseAndInboxConsumptionRollBackTogether() throws {
    let f = try fixture()
    let transfer = try XCTUnwrap(f.transfers.first)
    let item = try receipt(transfer, body: f.body, journal: f.journal)
    try f.files.execute("CREATE TRIGGER fail_managed_receipt BEFORE UPDATE ON mqtt_business_inbox WHEN NEW.completed=1 BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertThrowsError(try f.journal.consumeStoredAttachment(item, bodyID: f.body.messageID, transfer: transfer))
    XCTAssertEqual(try f.journal.outbox.entry(identity: f.body.identity, messageID: f.body.messageID)?.message.blockedByAttachmentTransferIds,
      f.body.attachmentDependencies)
    XCTAssertTrue(try f.journal.inbox.pending().contains { $0.messageID == item.messageID })
  }

  func testAttachmentDeliveryFailureIsNotRecordedAsProviderFailure() throws {
    let f = try fixture()
    let pending = AgentActionResult(actionId: "action", success: true, message: "Queued", metadata: [
      "awaiting_response": "true", "source_message_id": "77", "contact_id": "agent", "conversation_id": "conversation",
      "task_id": f.body.messageID, "turn_id": "turn", "execution_generation": "1"
    ])
    let response = AgentConnectorResponse(sourceMessageId: 77, contactId: "agent", content: "Input attachment expired",
      conversationId: "conversation", turnId: "turn", taskId: f.body.messageID, success: false, deliveryFailureCode: "blob_expired")
    let result = try XCTUnwrap(AgentConnectorResponseResolver.settle(pending: pending, response: response)?.result)
    XCTAssertEqual(result.metadata["delivery_failure_code"], "blob_expired")
    XCTAssertEqual(result.metadata["provider_failure_attribution"], "local_transport")
    XCTAssertEqual(result.metadata["awaiting_response"], "false")
    XCTAssertFalse(AgentLocalTransportFailure.shouldRecord(result))
  }

  func testKnownNumericBlobFailureRetainsEvidenceUntilTransactionalBodyCleanup() throws {
    let f = try fixture(blob: true)
    let transfer = try XCTUnwrap(f.transfers.first)
    let id = UUID().uuidString
    var payload = transfer.manifestPayload(resume: false)
    payload["type"] = "input_attachment_receipt"
    payload["message_id"] = id
    payload["status"] = "failed"
    payload["error_code"] = "blob_expired"
    payload["source_message_id"] = "77"
    let hash = MqttRouteProtocol.digest(Data(id.utf8))
    _ = try f.journal.inbox.accept(identity: f.body.identity, messageID: id, payload: payload,
      ciphertextDigest: hash, wireHash: hash, receiptRequired: true)
    let item = try XCTUnwrap(f.journal.inbox.pending().first { $0.messageID == id })
    let failures = AgentAttachmentDeliveryFailureStore(applicationSupportDirectory: f.files.root,
      cipher: GalaxySSIAttachmentAtRestCipher(secrets: f.files.secrets))
    _ = try failures.record(receipt: payload, attachment: transfer)
    try f.files.execute("CREATE TRIGGER fail_managed_cleanup BEFORE DELETE ON mqtt_business_outbox BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertThrowsError(try f.journal.consumeFailedBlobAttachment(item, bodyID: f.body.messageID, transfer: transfer))
    XCTAssertNotNil(try f.journal.outbox.entry(identity: f.body.identity, messageID: f.body.messageID))
    XCTAssertTrue(try f.journal.inbox.pending().contains { $0.messageID == id })
    XCTAssertEqual(failures.observations().first?.sourceMessageId, "77")
    try f.files.execute("DROP TRIGGER fail_managed_cleanup")
    try f.journal.consumeFailedBlobAttachment(item, bodyID: f.body.messageID, transfer: transfer)
    XCTAssertNil(try f.journal.outbox.entry(identity: f.body.identity, messageID: f.body.messageID))
    XCTAssertFalse(try f.journal.inbox.pending().contains { $0.messageID == id })
    XCTAssertEqual(failures.observations().first?.errorCode, "blob_expired")
  }
}

extension GalaxySSIStoreTests {
  @MainActor
  func testManagedNumericAttachmentsRequireAnExplicitCurrentOwnerAndExactOriginalBody() throws {
    let store = makeStore()
    let link = try store.addServerLink(from: makePairingQRCode())
    store.markServerPaired(desktopId: link.desktopId)
    let desktop = try XCTUnwrap(store.contacts.first { $0.isDesktopDeviceContact && $0.desktopId == link.desktopId })
    let contact = try XCTUnwrap(store.contact(id: "\(link.desktopId):codex"))
    let target = try XCTUnwrap(MqttPeerChatProjection(store: store, localFingerprint: link.routes.localFingerprint).destination(for: desktop))
    let session = store.createAgentSession(title: "Managed attachment")
    let message = store.appendOutgoing("Inspect file", to: "hermes", turnId: "turn", conversationOverride: session.id)
    let task = UUID().uuidString
    let identities = AgentTaskIdentityStore(defaults: store.defaults, storageKeyPrefix: "managed-attachment-test")
    XCTAssertTrue(identities.register(contactId: contact.id, sourceMessageId: "77", identity: .init(clientRouteId: target.routeId,
      conversationId: session.id, taskId: task, turnId: message.turnId)))
    let files = try ChunkFixture()
    let transfers = try AgentOutboundAttachmentTransferStore(rootURL: files.root.appendingPathComponent("native"),
      cipher: GalaxySSIAttachmentAtRestCipher(secrets: files.secrets)).prepare(scope: AgentAttachmentTransferScope(
        contactId: contact.id, desktopId: link.desktopId, clientRouteId: target.routeId, conversationId: session.id,
        taskId: task, turnId: message.turnId, clientMessageId: "77"), attachments: [
          .init(displayName: "input.bin", mimeType: "application/octet-stream", data: Data([1, 2, 3]))
        ], mediaProfile: AgentMediaNetworkPolicy.profile(for: .normal), preserveOriginalBytes: true)
    let payload: [String: Any] = ["type": "text", "message_id": task, "source_message_id": "77", "client_message_id": "77",
      "content": message.content, "contact_id": contact.id, "desktop_id": link.desktopId, "agent_id": contact.connectorAgentId,
      "client_route_id": target.routeId, "conversation_id": session.id, "task_id": task, "turn_id": message.turnId, "time": 1_000]
    var projection = MqttDesktopConnectorProjection(store: store, identities: identities, commitResponse: { _, _ in })
    XCTAssertThrowsError(try projection.outgoingRequests(payload, target: target, attachments: transfers, blobTransfers: []))
    var current = true
    projection.resolveManagedAttachmentOwner = { _, _, _, _ in
      .init(message: message, maySend: current, managedOwnerRunID: "owner")
    }
    let requests = try projection.outgoingRequests(payload, target: target, attachments: transfers, blobTransfers: [])
    let body = try XCTUnwrap(requests.last), transfer = try XCTUnwrap(transfers.first)
    XCTAssertEqual(requests.count, 2)
    XCTAssertEqual(body.sourceMessageID, "77")
    XCTAssertEqual(body.messageID, task)
    XCTAssertEqual(try projection.attachmentOwner(transfer, body: body, target: target)?.message.id, message.id)
    current = false
    XCTAssertFalse(try projection.managedAttachmentSendIsCurrent(body, target: target))
    XCTAssertThrowsError(try projection.outgoingRequests(payload, target: target, attachments: transfers, blobTransfers: []))
    var wrong = payload
    wrong["message_id"] = UUID().uuidString
    current = true
    XCTAssertThrowsError(try projection.outgoingRequests(wrong, target: target, attachments: transfers, blobTransfers: []))
  }
}
