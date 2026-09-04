import XCTest
@testable import GalaxySSI

final class AgentDataDisclosureLedgerTests: XCTestCase {
  func testTextClassifierSeparatesPromptHistorySystemAndToolData() {
    let kinds = AgentDataDisclosureClassifier.classifyText(
      text: "Use current screen_context with recalled memory and device status",
      includeHistory: true,
      includeSystemInstructions: true,
      includeToolOutput: true
    )

    XCTAssertTrue(kinds.contains(.messageText))
    XCTAssertTrue(kinds.contains(.conversationHistory))
    XCTAssertTrue(kinds.contains(.systemInstructions))
    XCTAssertTrue(kinds.contains(.toolOutput))
    XCTAssertTrue(kinds.contains(.screenContext))
    XCTAssertTrue(kinds.contains(.memoryContext))
    XCTAssertTrue(kinds.contains(.deviceContext))
  }

  func testAttachmentClassifierCoversMediaDocumentsAndUnknownFiles() {
    XCTAssertEqual(
      AgentDataDisclosureClassifier.attachmentKind(mimeType: "image/jpeg", displayName: "photo.jpg"),
      .image
    )
    XCTAssertEqual(
      AgentDataDisclosureClassifier.attachmentKind(mimeType: "audio/m4a", displayName: "voice.m4a"),
      .audio
    )
    XCTAssertEqual(
      AgentDataDisclosureClassifier.attachmentKind(mimeType: "video/mp4", displayName: "clip.mp4"),
      .video
    )
    XCTAssertEqual(
      AgentDataDisclosureClassifier.attachmentKind(
        mimeType: "application/octet-stream",
        displayName: "report.xlsx"
      ),
      .document
    )
    XCTAssertEqual(
      AgentDataDisclosureClassifier.attachmentKind(
        mimeType: "application/octet-stream",
        displayName: "archive.bin"
      ),
      .otherFile
    )
  }

  func testStoreUpdatesReceiptWithoutRetainingRequestContent() throws {
    let store = InMemoryAgentDataDisclosureStore()
    let record = disclosureRecord(destinationId: "deepseek", textCharacters: 1_240)

    store.append(record)
    store.update(eventId: record.eventId, status: .sent)

    let stored = try XCTUnwrap(store.find(eventId: record.eventId))
    XCTAssertEqual(stored.status, .sent)
    XCTAssertEqual(stored.textCharacters, 1_240)
    XCTAssertEqual(stored.dataKinds, [.messageText])
    XCTAssertTrue(stored.failureReason.isEmpty)
  }

  func testDestinationBlockSurvivesHistoryClear() {
    let store = InMemoryAgentDataDisclosureStore()
    let record = disclosureRecord(destinationId: "desktop-codex")
    store.append(record)
    store.setDestinationBlocked(destinationId: record.destinationId, blocked: true)

    store.clearHistory()

    XCTAssertTrue(store.blockedDestinationIds().contains(record.destinationId))
    XCTAssertTrue(store.list().isEmpty)
    XCTAssertNil(store.find(eventId: record.eventId))
    store.setDestinationBlocked(destinationId: record.destinationId, blocked: false)
    XCTAssertFalse(store.blockedDestinationIds().contains(record.destinationId))
  }

  func testSummaryDistinguishesCloudDesktopAndBlockedFlows() {
    let records = [
      disclosureRecord(
        destinationId: "cloud-openai",
        location: .cloud,
        status: .sent
      ),
      disclosureRecord(
        destinationId: "desktop-codex",
        location: .trustedDesktop,
        status: .sent
      ),
      disclosureRecord(
        destinationId: "cloud-openai",
        location: .cloud,
        status: .blocked
      )
    ]

    let summary = AgentDataDisclosureLedger.summary(records)

    XCTAssertEqual(summary.total, 3)
    XCTAssertEqual(summary.cloud, 2)
    XCTAssertEqual(summary.trustedDesktop, 1)
    XCTAssertEqual(summary.blocked, 1)
    XCTAssertEqual(summary.destinations, 2)
  }

  func testBeginCloudRequestBlocksConfiguredDestinationAndHashesIds() throws {
    let store = InMemoryAgentDataDisclosureStore()
    store.setDestinationBlocked(destinationId: "cloud-contact", blocked: true)

    let ticket = AgentDataDisclosureLedger.beginCloudRequest(
      store: store,
      destination: AgentDataDisclosureCloudDestination(
        contactId: "cloud-contact",
        providerId: "openai",
        modelId: "gpt-5",
        endpoint: "https://api.openai.example/v1",
        displayName: "OpenAI"
      ),
      text: "Use knowledge source and battery_percent in the request",
      historyCount: 2,
      systemInstructions: true,
      toolOutput: true,
      purpose: "Planner request",
      conversationId: "conversation-raw",
      taskId: "task-raw",
      turnId: "turn-raw"
    )

    XCTAssertFalse(ticket.allowed)
    let stored = try XCTUnwrap(store.find(eventId: ticket.eventId))
    XCTAssertEqual(stored.status, .blocked)
    XCTAssertEqual(stored.destinationTitle, "OpenAI")
    XCTAssertEqual(stored.providerId, "openai")
    XCTAssertEqual(stored.modelId, "gpt-5")
    XCTAssertEqual(stored.location, .cloud)
    XCTAssertTrue(stored.dataKinds.contains(.conversationHistory))
    XCTAssertTrue(stored.dataKinds.contains(.systemInstructions))
    XCTAssertTrue(stored.dataKinds.contains(.toolOutput))
    XCTAssertTrue(stored.dataKinds.contains(.knowledgeContext))
    XCTAssertTrue(stored.dataKinds.contains(.deviceContext))
    XCTAssertEqual(stored.conversationIdHash.count, 64)
    XCTAssertNotEqual(stored.conversationIdHash, "conversation-raw")
    XCTAssertEqual(stored.taskIdHash.count, 64)
    XCTAssertEqual(stored.turnIdHash.count, 64)
  }

  func testFileStorePersistsRecordsAndBlockedDestinations() throws {
    let fileURL = temporaryLedgerURL()
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
    let store = FileAgentDataDisclosureStore(fileURL: fileURL)

    let ticket = AgentDataDisclosureLedger.beginDesktopRequest(
      store: store,
      contactId: "desktop-codex",
      providerId: "codex",
      title: "Codex Desktop",
      text: "Summarize this document",
      attachments: [
        AgentDataDisclosureAttachment(displayName: "report.pdf", mimeType: "application/pdf", sizeBytes: 2_048)
      ],
      conversationId: "conversation-1",
      taskId: "task-1",
      turnId: "turn-1"
    )
    AgentDataDisclosureLedger.update(store: store, ticket: ticket, status: .sent)
    store.setDestinationBlocked(destinationId: "desktop-codex", blocked: true)
    store.clearHistory()

    let reloaded = FileAgentDataDisclosureStore(fileURL: fileURL)
    XCTAssertTrue(reloaded.list().isEmpty)
    XCTAssertTrue(reloaded.blockedDestinationIds().contains("desktop-codex"))
  }

  func testFileStoreDestroyPersistentStoreRemovesHistoryAndBlocks() throws {
    let fileURL = temporaryLedgerURL()
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
    let store = FileAgentDataDisclosureStore(fileURL: fileURL)
    let record = disclosureRecord(destinationId: "cloud-openai")
    store.append(record)
    store.setDestinationBlocked(destinationId: "cloud-openai", blocked: true)

    FileAgentDataDisclosureStore.destroyPersistentStore(fileURL: fileURL)

    let reloaded = FileAgentDataDisclosureStore(fileURL: fileURL)
    XCTAssertTrue(reloaded.list().isEmpty)
    XCTAssertTrue(reloaded.blockedDestinationIds().isEmpty)
  }

  private func disclosureRecord(
    destinationId: String,
    location: AgentResourceLocation = .cloud,
    status: AgentDisclosureStatus = .preparing,
    textCharacters: Int = 10
  ) -> AgentDataDisclosureRecord {
    AgentDataDisclosureRecord(
      destinationId: destinationId,
      destinationTitle: destinationId,
      location: location,
      trust: location == .trustedDesktop ? .verifiedPaired : .cloudConfigured,
      protection: location == .trustedDesktop ? .signalE2EE : .tls,
      purpose: "Test",
      dataKinds: [.messageText],
      textCharacters: textCharacters,
      status: status
    )
  }

  private func temporaryLedgerURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent("agent-data-disclosure-ledger.json")
  }
}
