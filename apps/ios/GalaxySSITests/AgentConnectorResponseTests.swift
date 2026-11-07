import XCTest
import CryptoKit
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testLargeResearchReplyKeepsOriginalBytesThroughBothResponseStores() throws {
    let note = String(repeating: "evidence ", count: 4_000)
    let raw = "  ```json\n{\"format\":\"galaxyssi.research-artifact.v1\",\"summary\":\"[Report](outputs/final.pdf)\","
      + "\"workspace\":[{\"id\":\"note\",\"kind\":\"evidence\",\"title\":\"Notes\","
      + "\"base_revision\":0,\"parents\":[],\"body\":{\"text\":\"\(note)\"}}]}\n```\r\n"
    let reply = try XCTUnwrap(AgentConnectorResponse.fromPayload([
      "source_message_id": "77", "contact_id": "codex", "content": raw, "task_status": "completed"
    ], nowMillis: 4_000))
    XCTAssertGreaterThan(raw.count, AgentConnectorResponse.maxContentCharacters)
    XCTAssertEqual(try AgentCollaborationResearchEnvelope.publication(in: raw)?.map(\.id), ["note"])
    XCTAssertEqual(Data(reply.content.utf8), Data(raw.utf8))
    let normalized = try XCTUnwrap(AgentConnectorResponseNormalizer.normalized(reply, nowMillis: 4_000))
    let reopened = try XCTUnwrap(AgentConnectorResponseStoreCodec.decode(
      AgentConnectorResponseStoreCodec.encode([normalized]), nowMillis: 4_000).first)
    XCTAssertEqual(Data(reopened.content.utf8), Data(raw.utf8))

    let record = AgentManagedResponseRecord(ownerRunId: "child", supervisorRunId: "parent",
      agentId: "codex", deliveryMode: .respond, sourceMessageId: 77, contactId: "codex",
      state: .completed, response: normalized, createdAtMillis: 1_000, completedAtMillis: 4_000)
    let managed = try XCTUnwrap(AgentManagedResponseCodec.decode(
      AgentManagedResponseCodec.encode([record])).first?.response)
    XCTAssertEqual(Data(managed.content.utf8), Data(raw.utf8))
    let codable = try JSONDecoder().decode(AgentConnectorResponse.self, from: JSONEncoder().encode(reply))
    XCTAssertEqual(Data(codable.content.utf8), Data(raw.utf8))
  }

  func testResearchReplyExceptionRejectsIncompleteOrOversizedContent() {
    let prefix = "{\"format\":\"galaxyssi.research-artifact.v1\",\"summary\":\""
    let incomplete = prefix + String(repeating: "a", count: 25_000)
    let oversized = prefix + String(repeating: "a", count: AgentCollaborationResearchEnvelope.maximumReplyBytes) + "\"}"
    let ordinary = String(repeating: "galaxyssi.research-artifact.v1 ", count: 1_000)
    for content in [incomplete, oversized, ordinary] {
      XCTAssertEqual(AgentConnectorResponse(sourceMessageId: 1, content: content).content.count,
        AgentConnectorResponse.maxContentCharacters)
    }
  }

  func testCodexSilenceBudgetRetriesTwoInitialAttemptsThenAlternativesAndOneFinalAttempt() throws {
    var budget = AgentCodexSilenceRecoveryPolicy.Budget(origin: "codex")
    XCTAssertEqual(budget.next(failed: "codex", attemptId: "one", confirmedTimeout: true, alternatives: ["other"]), "codex")
    XCTAssertNil(budget.next(failed: "codex", attemptId: "one", confirmedTimeout: true, alternatives: ["other"]))
    let disk = try JSONEncoder().encode(budget)
    budget = try JSONDecoder().decode(AgentCodexSilenceRecoveryPolicy.Budget.self, from: disk)
    XCTAssertEqual(budget.next(failed: "codex", attemptId: "two", confirmedTimeout: true, alternatives: ["other"]), "other")
    XCTAssertNil(budget.next(failed: "codex", attemptId: "stale", confirmedTimeout: true, alternatives: ["other"]))
    XCTAssertEqual(budget.next(failed: "other", attemptId: "three", confirmedTimeout: false, alternatives: ["other"]), "codex")
    XCTAssertNil(budget.next(failed: "codex", attemptId: "four", confirmedTimeout: true, alternatives: ["new"]))
    XCTAssertTrue(budget.exhausted)
  }

  func testOnlyAuthenticatedTerminalCodexNoProgressReasonQualifiesForRecovery() {
    XCTAssertTrue(AgentCodexSilenceRecoveryPolicy.confirmedTimeout(status: "failed",
      failureCode: "codex_no_progress_timeout", error: ""))
    XCTAssertTrue(AgentCodexSilenceRecoveryPolicy.confirmedTimeout(status: "timed_out",
      failureCode: "", error: "Codex task stalled"))
    XCTAssertFalse(AgentCodexSilenceRecoveryPolicy.confirmedTimeout(status: "running",
      failureCode: "codex_no_progress_timeout", error: ""))
    XCTAssertFalse(AgentCodexSilenceRecoveryPolicy.confirmedTimeout(status: "timed_out",
      failureCode: "codex_compaction_timeout", error: "Codex task stalled"))
    XCTAssertFalse(AgentCodexSilenceRecoveryPolicy.confirmedTimeout(status: "failed",
      failureCode: "", error: "Request timed out"))
  }

  func testCodexSilenceClockIgnoresStatusPollsAndReplayedEvents() {
    let binding = AgentDesktopReplyBinding(desktopId: "desktop", displayContactId: "hermes", sourceId: UUID(),
      contactId: "codex-contact", agentId: "codex",
      identity: AgentTaskIdentity(clientRouteId: "route", conversationId: "conversation", taskId: "task", turnId: "turn"))
    var record = AgentDesktopReplyRecoveryRecord(binding: binding, createdAt: 1_000)
    record.status = "running"
    record.lastResponseAt = 179_000
    XCTAssertFalse(record.isCodexSilent(now: 180_999))
    XCTAssertTrue(record.isCodexSilent(now: 181_000))
    var progress = AgentDesktopCodexProgress(generation: 1, sequence: -1, lastProgressAt: 1_000, eventIds: [])
    let genuine = AgentConnectorPublicProgress(eventId: "tool-finished", generation: 1, sequence: 2, text: "Read complete")
    progress.observe([genuine], now: 170_000)
    progress.observe([genuine], now: 175_000)
    var steering = genuine
    steering.eventId = "auto-replan"
    steering.sequence = 3
    steering.countsForCodexSilence = false
    progress.observe([steering], now: 180_000)
    record.codexProgress = progress
    XCTAssertEqual(progress.lastProgressAt, 170_000)
    XCTAssertFalse(record.isCodexSilent(now: 349_999))
    XCTAssertTrue(record.isCodexSilent(now: 350_000))
    record.status = "waiting_approval"
    XCTAssertFalse(record.isCodexSilent(now: 600_000))
  }

  func testManagedRecoveryPagesDoNotRepeatOrIncludeCompletedChildren() throws {
    let suite = "ManagedRecoveryPaging.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let ledger = UserDefaultsAgentManagedResponseLedger(defaults: defaults, nowMillis: { 10_000 },
      fileURL: root.appendingPathComponent("managed.sqlite3"), secrets: InMemorySecretStore())
    for id in 1...35 { try ledger.register(managedSQLiteRecord(Int64(id))) }
    XCTAssertNotNil(ledger.complete(AgentConnectorResponse(sourceMessageId: 1, contactId: "codex", content: "done",
      conversationId: "conversation", turnId: "turn", taskId: "task-1", receivedAtMillis: 9_000)))
    var cursor = ""
    var found: [Int64] = []
    for _ in 0..<4 {
      let page = try ledger.pendingRecoveryPage(after: cursor)
      XCTAssertLessThanOrEqual(page.records.count, 16)
      found += page.records.map(\.sourceMessageId)
      guard let next = page.next else { break }
      XCTAssertNotEqual(next, cursor)
      cursor = next
    }
    XCTAssertEqual(Set(found), Set((2...35).map { Int64($0) }))
    XCTAssertEqual(found.count, 34)
  }

  @MainActor
  func testManagedArchivedResultKeepsNumericScopeAndCommitsWithoutOrdinaryDelivery() throws {
    let suite = "ManagedArchive.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let ledger = UserDefaultsAgentManagedResponseLedger(defaults: defaults, nowMillis: { 10_000 },
      fileURL: root.appendingPathComponent("managed.sqlite3"), secrets: secrets)
    let child = managedSQLiteRecord(73)
    try ledger.register(child)
    let binding = try XCTUnwrap(AgentDesktopReplyBinding.managed(record: child, desktopId: "desktop", agentId: "codex",
      identity: AgentTaskIdentity(clientRouteId: "route", conversationId: "conversation", taskId: "task-73", turnId: "turn")))
    let engine = AgentDesktopResultRecovery(pages: AgentResultPageCheckpointStore(fileURL: root.appendingPathComponent("pages.sqlite3"), secrets: secrets),
      receipts: AgentResultReceiptJournal(fileURL: root.appendingPathComponent("receipts.sqlite3"), secrets: secrets))
    var record = AgentDesktopReplyRecoveryRecord(binding: binding, createdAt: 1_000)
    record.generation = 1
    record.sequence = 2
    record.status = "completed"
    var body: [String: Any] = binding.fields
    body.merge(["type": "text", "content": "recovered child", "task_status": "completed",
      "execution_generation": 1, "status_sequence": 2]) { _, new in new }
    let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let request = try XCTUnwrap(engine.request(record, now: 1_000))
    var page: [String: Any] = binding.fields
    page.merge(["type": "agent_task_result_page", "status": "ready", "request_id": request["request_id"]!,
      "execution_generation": 1, "page_index": 0, "page_count": 1, "total_bytes": data.count,
      "sha256": digest, "page_sha256": digest, "data_b64": data.base64EncodedString()]) { _, new in new }
    record.resultManifest = try XCTUnwrap(engine.receive(page, record: record, now: 2_000))
    let restored = try XCTUnwrap(engine.assembled(record))
    let response = try XCTUnwrap(AgentConnectorResponse.fromPayload(restored, nowMillis: 9_000))
    let sink = InMemoryAgentConnectorResponseStore()
    let bus = AgentConnectorResponseBus(registry: AgentManagedConnectorResponseRegistry(), managedLedger: ledger,
      store: sink, terminalStore: InMemoryAgentTerminalDeliveryStore(), nowMillis: { 10_000 })
    var notifications = 0
    let token = bus.addListener { _ in notifications += 1 }
    defer { bus.removeListener(token) }
    XCTAssertTrue(bus.publish(response))
    XCTAssertEqual(ledger.completedUnapplied().first?.response?.content, "recovered child")
    XCTAssertEqual(notifications, 0)
    XCTAssertTrue(sink.pending().isEmpty)
    let receipt = try XCTUnwrap(engine.receipt(record))
    XCTAssertEqual(receipt.sourceMessageId, "73")
    XCTAssertTrue(engine.receipts.insert(receipt))
    XCTAssertFalse(engine.cleanup(receipt))
  }

  func testManagedSQLiteLedgerSharesWritesAcrossInstancesAndPreservesPendingBeyond512() throws {
    let suite = "ManagedLedger.shared.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("managed.sqlite3")
    let first = UserDefaultsAgentManagedResponseLedger(defaults: defaults, nowMillis: { 10_000 }, fileURL: file, secrets: secrets)
    let second = UserDefaultsAgentManagedResponseLedger(defaults: defaults, nowMillis: { 10_000 }, fileURL: file, secrets: secrets)
    for index in 1...520 {
      try (index % 2 == 0 ? first : second).register(managedSQLiteRecord(Int64(index)))
    }
    XCTAssertEqual(first.pendingForSupervisor("supervisor").count, 520)
    XCTAssertEqual(second.pendingForSupervisor("supervisor").count, 520)
    let reopened = UserDefaultsAgentManagedResponseLedger(defaults: defaults, nowMillis: { 10_000 }, fileURL: file, secrets: secrets)
    XCTAssertEqual(reopened.pendingForSupervisor("supervisor").count, 520)
  }

  func testManagedSQLiteResponseCommitsBeforeConsumerAndDuplicatesRemainHidden() throws {
    let suite = "ManagedLedger.consume.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("managed.sqlite3")
    let ledger = UserDefaultsAgentManagedResponseLedger(defaults: defaults, nowMillis: { 10_000 }, fileURL: file, secrets: secrets)
    let reader = UserDefaultsAgentManagedResponseLedger(defaults: defaults, nowMillis: { 10_000 }, fileURL: file, secrets: secrets)
    try ledger.register(managedSQLiteRecord(73))
    let registry = AgentManagedConnectorResponseRegistry()
    var consumed = 0
    try registry.register(sourceMessageId: 73, contactId: "codex", ownerId: "child-73",
      conversationId: "conversation", turnId: "turn", taskId: "task-73") { response in
        consumed += 1
        XCTAssertEqual(reader.completedUnapplied().first?.response?.content, "private managed answer")
        return reader.acknowledge(response) != nil
      }
    let sink = InMemoryAgentConnectorResponseStore()
    let bus = AgentConnectorResponseBus(registry: registry, managedLedger: ledger, store: sink,
      terminalStore: InMemoryAgentTerminalDeliveryStore(), nowMillis: { 10_000 })
    var notifications = 0
    let token = bus.addListener { _ in notifications += 1 }
    defer { bus.removeListener(token) }
    var response = AgentConnectorResponse(sourceMessageId: 73, contactId: "codex", content: "private managed answer",
      conversationId: "conversation", turnId: "turn", taskId: "task-73", receivedAtMillis: 9_000)
    XCTAssertTrue(bus.publish(response))
    response.content = "duplicate must not replace the first body"
    XCTAssertTrue(bus.publish(response))
    XCTAssertEqual(consumed, 1)
    XCTAssertEqual(notifications, 0)
    XCTAssertTrue(sink.pending().isEmpty)
    XCTAssertEqual(AgentManagedResponseCodec.decode(reader.serializedSnapshot()).first?.response?.content, "private managed answer")
    try reader.register(managedSQLiteRecord(73))
    XCTAssertTrue(reader.pendingForSupervisor("supervisor").isEmpty)
    for url in [file, URL(fileURLWithPath: file.path + "-wal")] {
      if let data = try? Data(contentsOf: url) {
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private managed answer"))
      }
    }
  }

  func testManagedSQLiteMigrationRetriesAfterKeyFailureAndCannotResurrectAfterClear() throws {
    let suite = "ManagedLedger.migration.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let key = UserDefaultsAgentManagedResponseLedger.defaultStorageKey
    let raw = AgentManagedResponseCodec.encode([managedSQLiteRecord(91)])
    defaults.set(raw, forKey: key)
    let secrets = RejectableConnectorSecretStore()
    let file = root.appendingPathComponent("managed.sqlite3")
    let ledger = UserDefaultsAgentManagedResponseLedger(defaults: defaults, nowMillis: { 10_000 }, fileURL: file, secrets: secrets)
    XCTAssertThrowsError(try ledger.register(managedSQLiteRecord(92)))
    XCTAssertEqual(defaults.string(forKey: key), raw)
    secrets.reject = false
    XCTAssertEqual(ledger.pendingForSupervisor("supervisor").map(\.sourceMessageId), [91])
    XCTAssertNil(defaults.object(forKey: key))
    ledger.clear()
    defaults.set(raw, forKey: key)
    let reopened = UserDefaultsAgentManagedResponseLedger(defaults: defaults, nowMillis: { 10_000 }, fileURL: file, secrets: secrets)
    XCTAssertTrue(reopened.pendingForSupervisor("supervisor").isEmpty)
    XCTAssertNil(defaults.object(forKey: key))
  }

  func testManagedSQLiteSiblingScopeAndGenerationCannotConsumeAnotherChild() throws {
    let suite = "ManagedLedger.scope.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let ledger = UserDefaultsAgentManagedResponseLedger(defaults: defaults, nowMillis: { 10_000 },
      fileURL: root.appendingPathComponent("managed.sqlite3"), secrets: InMemorySecretStore())
    try ledger.register(managedSQLiteRecord(73))
    var response = AgentConnectorResponse(sourceMessageId: 73, contactId: "codex", content: "result",
      conversationId: "conversation", turnId: "turn", taskId: "task-74", receivedAtMillis: 9_000)
    XCTAssertFalse(try ledger.ownsResponse(response))
    XCTAssertNil(ledger.complete(response))
    response.taskId = "task-73"
    response.executionGeneration = 2
    XCTAssertFalse(try ledger.ownsResponse(response))
    XCTAssertNil(ledger.complete(response))
    response.executionGeneration = 1
    XCTAssertTrue(try ledger.ownsResponse(response))
    XCTAssertNotNil(ledger.complete(response))
  }

  private func managedSQLiteRecord(_ source: Int64) -> AgentManagedResponseRecord {
    AgentManagedResponseRecord(ownerRunId: "child-\(source)", supervisorRunId: "supervisor", agentId: "codex",
      deliveryMode: .observe, sourceMessageId: source, contactId: "codex", conversationId: "conversation",
      turnId: "turn", taskId: "task-\(source)", createdAtMillis: 1_000)
  }

  func testNormalDesktopReplyReceiptReadsSignedArchiveDigestWithUUIDSource() throws {
    let source = UUID().uuidString
    let digest = String(repeating: "a", count: 64)
    let payload: [String: Any] = ["type": "text", "task_status": "completed", "message_id": "normal-final",
      "client_route_id": "route", "conversation_id": "conversation", "task_id": source,
      "turn_id": "turn", "contact_id": "agent", "source_message_id": source, "agent_id": "codex",
      "execution_generation": 2, "result_recovery": ["sha256": digest]]
    let receipt = try XCTUnwrap(AgentResultReceipt.fromPayload(payload, desktopId: "desktop"))
    XCTAssertEqual(receipt.sourceMessageId, source)
    XCTAssertEqual(receipt.resultSHA256, digest)
    XCTAssertEqual(receipt.executionGeneration, 2)
    var confirmation = receipt.payload
    confirmation["type"] = "agent_task_result_receipt_confirmed"
    XCTAssertEqual(AgentResultReceipt.confirmedPayload(confirmation, desktopId: "desktop"), receipt)
  }

  func testLateStreamProbeRetainsRecoveredExecutionGeneration() throws {
    let update = try XCTUnwrap(AgentConnectorStreamUpdate(payload: ["type": "agent_task_event",
      "task_status": "running", "source_message_id": UUID().uuidString, "contact_id": "agent",
      "conversation_id": "conversation", "turn_id": "turn", "task_id": "task",
      "execution_generation": 2, "partial_result": ["text": "Late partial", "sequence": 10]]))
    XCTAssertEqual(update.executionGeneration, 2)
    let terminal = InMemoryAgentTerminalDeliveryStore()
    terminal.mark(AgentTerminalDelivery(sourceMessageId: 0, conversationId: "conversation", turnId: "turn",
      taskId: "task", contactId: "agent", reason: "completed", executionGeneration: 2))
    XCTAssertTrue(terminal.isTerminal(AgentConnectorResponse(sourceMessageId: 0, contactId: update.contactId,
      conversationId: update.conversationId, turnId: update.turnId, taskId: update.taskId,
      executionGeneration: update.executionGeneration)))
  }

  @MainActor
  func testDesktopResultPagesResumeValidateAndWaitForReceiptConfirmationBeforeCleanup() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let pagesURL = root.appendingPathComponent("pages.sqlite3")
    let receiptsURL = root.appendingPathComponent("receipts.sqlite3")
    func engine() -> AgentDesktopResultRecovery {
      AgentDesktopResultRecovery(pages: AgentResultPageCheckpointStore(fileURL: pagesURL, secrets: secrets),
        receipts: AgentResultReceiptJournal(fileURL: receiptsURL, secrets: secrets))
    }
    let binding = AgentDesktopReplyBinding(desktopId: "desktop", displayContactId: "hermes", sourceId: UUID(),
      contactId: "agent", agentId: "codex", identity: AgentTaskIdentity(clientRouteId: "route",
        conversationId: "conversation", taskId: "task", turnId: "turn"))
    var record = AgentDesktopReplyRecoveryRecord(binding: binding, createdAt: 1_000)
    record.generation = 2
    record.sequence = 3
    record.status = "completed"
    var body: [String: Any] = binding.fields
    body.merge(["type": "text", "message_id": "reply", "content": String(repeating: "answer ", count: 3_000),
      "task_status": "completed", "execution_generation": 2, "status_sequence": 3]) { _, new in new }
    let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    let pageSize = AgentResultPageCheckpointStore.maximumPageBytes
    let count = (data.count + pageSize - 1) / pageSize
    XCTAssertEqual(count, 2)
    func response(_ request: [String: Any], page: Int) -> [String: Any] {
      let chunk = data.subdata(in: (page * pageSize)..<min(data.count, (page + 1) * pageSize))
      var payload: [String: Any] = binding.fields
      payload.merge(["type": "agent_task_result_page", "request_id": request["request_id"]!, "status": "ready",
        "page_index": page, "page_count": count, "total_bytes": data.count, "execution_generation": 2,
        "sha256": digest(data), "page_sha256": digest(chunk), "data_b64": chunk.base64EncodedString()]) { _, new in new }
      return payload
    }
    let first = engine()
    let request = try XCTUnwrap(first.request(record, now: 1_000))
    let pageZero = response(request, page: 0)
    record.resultManifest = try XCTUnwrap(first.receive(pageZero, record: record, now: 2_000))
    XCTAssertNil(first.assembled(record))
    let reopened = engine()
    let next = try XCTUnwrap(reopened.request(record, now: 3_000))
    XCTAssertEqual(next["page_index"] as? Int, 1)
    let pageOne = response(next, page: 1)
    var corrupt = pageOne
    corrupt["data_b64"] = Data("corrupt".utf8).base64EncodedString()
    XCTAssertNil(reopened.receive(corrupt, record: record, now: 4_000))
    corrupt = pageOne
    corrupt["turn_id"] = "foreign"
    XCTAssertNil(reopened.receive(corrupt, record: record, now: 4_000))
    corrupt = pageOne
    corrupt["execution_generation"] = true
    XCTAssertNil(reopened.receive(corrupt, record: record, now: 4_000))
    XCTAssertNotNil(reopened.receive(pageOne, record: record, now: 4_000))
    let assembled = try XCTUnwrap(reopened.assembled(record))
    XCTAssertEqual(assembled["content"] as? String, body["content"] as? String)
    let receipt = try XCTUnwrap(reopened.receipt(record))
    XCTAssertEqual(AgentResultReceipt.fromPayload(receipt.payload, desktopId: "desktop"), receipt)
    XCTAssertTrue(reopened.receipts.insert(receipt))
    XCTAssertFalse(reopened.cleanup(receipt))
    XCTAssertNotNil(reopened.assembled(record))
    var confirmed = receipt.payload
    confirmed["type"] = "agent_task_result_receipt_confirmed"
    XCTAssertEqual(AgentResultReceipt.confirmedPayload(confirmed, desktopId: "desktop"), receipt)
    XCTAssertTrue(reopened.receipts.confirm(receipt))
    XCTAssertTrue(reopened.cleanup(receipt))
    XCTAssertNil(reopened.assembled(record))
    XCTAssertTrue(reopened.receipts.due(nowMillis: Int64.max).isEmpty)
  }

  func testResultReceiptBindsIdentityGenerationDigestAndConfirmation() throws {
    let payload: [String: Any] = [
      "client_route_id": "route-1",
      "conversation_id": "conversation-1",
      "task_id": "task-1",
      "turn_id": "turn-1",
      "contact_id": "agent-1",
      "source_message_id": "901",
      "agent_id": "agent-1",
      "execution_generation": 3,
      "sha256": String(repeating: "a", count: 64)
    ]
    let receipt = try XCTUnwrap(AgentResultReceipt.fromPayload(payload, desktopId: "desktop-1"))
    XCTAssertEqual(receipt.payload["receipt_id"] as? String, receipt.id)

    var confirmed = receipt.payload
    confirmed["type"] = "agent_task_result_receipt_confirmed"
    XCTAssertEqual(
      AgentResultReceipt.confirmedPayload(confirmed, desktopId: "desktop-1"),
      receipt
    )
    confirmed["execution_generation"] = 4
    XCTAssertNil(AgentResultReceipt.confirmedPayload(confirmed, desktopId: "desktop-1"))
  }

  func testEncryptedResultReceiptJournalRequiresApplicationConfirmationBeforeCleanup() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("receipts.sqlite3")
    let secrets = InMemorySecretStore()
    let receipt = try XCTUnwrap(AgentResultReceipt.fromPayload([
      "client_route_id": "route-1",
      "conversation_id": "conversation-1",
      "task_id": "task-1",
      "turn_id": "turn-1",
      "contact_id": "agent-1",
      "source_message_id": "902",
      "agent_id": "agent-1",
      "execution_generation": 2,
      "sha256": String(repeating: "b", count: 64)
    ], desktopId: "desktop-1"))

    var journal: AgentResultReceiptJournal? = AgentResultReceiptJournal(
      fileURL: fileURL,
      secrets: secrets
    )
    XCTAssertTrue(journal?.insert(receipt) ?? false)
    let initial = try XCTUnwrap(journal?.due(nowMillis: 10_000).first)
    XCTAssertEqual(initial.state, .pending)
    XCTAssertTrue(journal?.claim(initial, nowMillis: 10_000) ?? false)
    XCTAssertFalse(journal?.claim(initial, nowMillis: 10_000) ?? true)
    XCTAssertEqual(journal?.nextWakeMillis, 15_000)
    journal = nil

    let reopened = AgentResultReceiptJournal(fileURL: fileURL, secrets: secrets)
    XCTAssertTrue(reopened.due(nowMillis: 14_999).isEmpty)
    XCTAssertEqual(reopened.due(nowMillis: 15_000).first?.receipt, receipt)
    XCTAssertTrue(reopened.confirm(receipt))
    XCTAssertEqual(reopened.due(nowMillis: 15_000).first?.state, .confirmed)
    XCTAssertTrue(reopened.markCleaned(receipt))
    XCTAssertTrue(reopened.due(nowMillis: Int64.max).isEmpty)
  }

  func testTerminalFailureNeverAcceptsLateResult() {
    let messages = [connectorPolicyMessage(isMine: true, turnId: "turn-1")]

    XCTAssertFalse(AgentLateConnectorResponsePolicy.canAccept(
      sourceIsTerminal: true,
      exactTurnId: "turn-1",
      conversationMessages: messages
    ))
  }

  func testOrphanResponseWithoutExactIdentityNeverGuessesLatestTurn() {
    let messages = [connectorPolicyMessage(isMine: true, turnId: "turn-1")]

    XCTAssertNil(AgentLateConnectorResponsePolicy.exactTurnId(
      explicitTurnId: "",
      taskTurnId: "",
      indexedTurnId: "",
      conversationMessages: messages
    ))
  }

  func testExactUnansweredTurnAcceptsResponse() throws {
    let messages = [connectorPolicyMessage(isMine: true, turnId: "turn-1")]
    let turnId = AgentLateConnectorResponsePolicy.exactTurnId(
      explicitTurnId: "turn-1",
      taskTurnId: "",
      indexedTurnId: "",
      conversationMessages: messages
    )

    XCTAssertEqual(turnId, "turn-1")
    XCTAssertTrue(AgentLateConnectorResponsePolicy.canAccept(
      sourceIsTerminal: false,
      exactTurnId: turnId,
      conversationMessages: messages
    ))
  }

  func testAlreadyAnsweredTurnRejectsDuplicateLateResult() {
    let messages = [
      connectorPolicyMessage(isMine: true, turnId: "turn-1"),
      connectorPolicyMessage(isMine: false, turnId: "turn-1")
    ]

    XCTAssertFalse(AgentLateConnectorResponsePolicy.canAccept(
      sourceIsTerminal: false,
      exactTurnId: "turn-1",
      conversationMessages: messages
    ))
  }

  func testResponseCannotBindToUserTurnFromAnotherConversation() {
    let messages = [connectorPolicyMessage(isMine: true, turnId: "turn-2")]

    XCTAssertNil(AgentLateConnectorResponsePolicy.exactTurnId(
      explicitTurnId: "turn-1",
      taskTurnId: "",
      indexedTurnId: "",
      conversationMessages: messages
    ))
  }

  func testTerminalDeliveryStoreBoundsRecordsAndBusDropsQueuedLateResponse() {
    let terminals = InMemoryAgentTerminalDeliveryStore()
    for sourceMessageId in 1...520 {
      terminals.mark(AgentTerminalDelivery(
        sourceMessageId: Int64(sourceMessageId),
        terminalAtMillis: Int64(sourceMessageId)
      ))
    }
    XCTAssertEqual(terminals.records().count, InMemoryAgentTerminalDeliveryStore.maxRecords)
    XCTAssertNil(terminals.find(sourceMessageId: 1))
    XCTAssertEqual(terminals.find(sourceMessageId: 520)?.sourceMessageId, 520)

    let responses = AgentConnectorResponseStore(nowMillis: { 10_000 })
    responses.publish(AgentConnectorResponse(sourceMessageId: 520, content: "queued"))
    let bus = AgentConnectorResponseBus(
      registry: AgentManagedConnectorResponseRegistry(),
      managedLedger: nil,
      store: responses,
      terminalStore: terminals,
      nowMillis: { 10_000 }
    )
    var notifications = 0
    _ = bus.addListener { _ in notifications += 1 }

    XCTAssertTrue(bus.publish(AgentConnectorResponse(sourceMessageId: 520, content: "late")))
    XCTAssertTrue(responses.pending().isEmpty)
    XCTAssertEqual(notifications, 0)
  }

  func testIdentityTerminalRecordBlocksUnknownSourceForFailedIOSTurn() {
    let terminals = InMemoryAgentTerminalDeliveryStore()
    terminals.mark(AgentTerminalDelivery(
      sourceMessageId: 0,
      conversationId: "conversation-1",
      turnId: "turn-1",
      taskId: "task-1",
      contactId: "codex"
    ))

    XCTAssertTrue(terminals.isTerminal(AgentConnectorResponse(
      sourceMessageId: 99,
      contactId: "codex",
      conversationId: "conversation-1",
      turnId: "turn-1",
      taskId: "task-1",
      content: "late"
    )))
    XCTAssertFalse(terminals.isTerminal(AgentConnectorResponse(
      sourceMessageId: 100,
      contactId: "codex",
      conversationId: "conversation-2",
      turnId: "turn-1",
      taskId: "task-1",
      content: "different conversation"
    )))
  }

  func testTerminalDeliveryStorePersistsEncryptedRecords() {
    let suiteName = "AgentTerminalDeliveryStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let secrets = InMemorySecretStore()
    let storageKey = "terminal-test"
    defer {
      UserDefaultsAgentTerminalDeliveryStore(
        defaults: defaults,
        storageKey: storageKey,
        secrets: secrets
      ).clear()
      defaults.removePersistentDomain(forName: suiteName)
    }

    UserDefaultsAgentTerminalDeliveryStore(
      defaults: defaults,
      storageKey: storageKey,
      secrets: secrets
    ).mark(AgentTerminalDelivery(
      sourceMessageId: 81,
      conversationId: "conversation-1",
      turnId: "turn-1",
      reason: "transport failed"
    ))

    XCTAssertNil(defaults.object(forKey: storageKey))
    XCTAssertEqual(UserDefaultsAgentTerminalDeliveryStore(
      defaults: defaults,
      storageKey: storageKey,
      secrets: secrets
    ).find(sourceMessageId: 81)?.reason, "transport failed")
  }

  func testTerminalDeliveryStoreDestroyRemovesEncryptedRecords() {
    let suiteName = "AgentTerminalDeliveryDestroyTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let secrets = InMemorySecretStore()
    let storageKey = "terminal-destroy-test"
    defer { defaults.removePersistentDomain(forName: suiteName) }

    UserDefaultsAgentTerminalDeliveryStore(
      defaults: defaults,
      storageKey: storageKey,
      secrets: secrets
    ).mark(AgentTerminalDelivery(sourceMessageId: 82, reason: "cancelled"))

    UserDefaultsAgentTerminalDeliveryStore.destroyPersistentStore(
      defaults: defaults,
      storageKey: storageKey,
      secrets: secrets
    )

    XCTAssertNil(UserDefaultsAgentTerminalDeliveryStore(
      defaults: defaults,
      storageKey: storageKey,
      secrets: secrets
    ).find(sourceMessageId: 82))
  }

  func testRejectedResponseWriteKeepsManagedInterceptorAndRunSlotForReplay() throws {
    let registry = AgentManagedConnectorResponseRegistry()
    let sink = RejectableConnectorResponseSink()
    let slots = ConnectorResponseRunSlotSpy()
    var consumed = 0
    var notified = 0
    try registry.register(sourceMessageId: 73, contactId: "codex", ownerId: "child",
      conversationId: "conversation", turnId: "turn", taskId: "child-task") { _ in
        consumed += 1
        return true
      }
    let bus = AgentConnectorResponseBus(registry: registry, managedLedger: nil, store: sink,
      terminalStore: InMemoryAgentTerminalDeliveryStore(), globalRunSlots: slots, nowMillis: { 10_000 })
    let token = bus.addListener { _ in notified += 1 }
    defer { bus.removeListener(token) }
    let response = AgentConnectorResponse(sourceMessageId: 73, contactId: "codex", content: "result",
      conversationId: "conversation", turnId: "turn", taskId: "child-task", receivedAtMillis: 9_000)

    XCTAssertFalse(bus.publish(response))
    XCTAssertEqual(consumed, 0)
    XCTAssertEqual(notified, 0)
    XCTAssertTrue(registry.contains(response))
    XCTAssertTrue(slots.releasedSources.isEmpty)
    XCTAssertFalse(bus.wasRecorded(response))

    sink.reject = false
    XCTAssertTrue(bus.publish(response))
    XCTAssertEqual(consumed, 1)
    XCTAssertEqual(notified, 0)
    XCTAssertEqual(slots.releasedSources, ["73"])
    XCTAssertTrue(sink.pending().isEmpty)
  }

  func testRejectedOrdinaryResponseWriteDoesNotNotifyListeners() {
    let sink = RejectableConnectorResponseSink()
    let bus = AgentConnectorResponseBus(registry: AgentManagedConnectorResponseRegistry(),
      managedLedger: nil, store: sink, terminalStore: InMemoryAgentTerminalDeliveryStore(), nowMillis: { 10_000 })
    var notifications = 0
    let token = bus.addListener { _ in notifications += 1 }
    defer { bus.removeListener(token) }
    let response = AgentConnectorResponse(sourceMessageId: 74, contactId: "codex", content: "result",
      conversationId: "conversation", turnId: "turn", taskId: "task", receivedAtMillis: 9_000)
    XCTAssertFalse(bus.publish(response))
    XCTAssertEqual(notifications, 0)
    sink.reject = false
    XCTAssertFalse(bus.publish(response))
    XCTAssertEqual(notifications, 1)
    XCTAssertTrue(bus.wasRecorded(response))
  }

  func testAgentConnectorResponseBusInterceptsManagedResponsesOnce() throws {
    let registry = AgentManagedConnectorResponseRegistry()
    let store = AgentConnectorResponseStore(nowMillis: { 10_000 })
    let bus = AgentConnectorResponseBus(registry: registry, store: store, nowMillis: { 10_000 })
    var intercepted: [AgentConnectorResponse] = []
    try registry.register(
      sourceMessageId: 73,
      contactId: "codex",
      ownerId: "managed-run"
    ) { response in
      intercepted.append(response)
      return true
    }
    let response = AgentConnectorResponse(
      sourceMessageId: 73,
      contactId: "codex",
      content: "Reviewed result",
      inputTokens: 10,
      outputTokens: 4
    )

    XCTAssertTrue(bus.publish(response))
    XCTAssertFalse(registry.consume(response))
    XCTAssertEqual(intercepted.map(\.content), ["Reviewed result"])
    XCTAssertTrue(store.pending().isEmpty)

    XCTAssertFalse(bus.publish(response))
    XCTAssertEqual(store.pending().map(\.content), ["Reviewed result"])
  }

  func testManagedResponseRegistryAcceptsUnambiguousContactAlias() throws {
    let registry = AgentManagedConnectorResponseRegistry()
    var consumed = false
    try registry.register(
      sourceMessageId: 45,
      contactId: "desktop:codex",
      ownerId: "managed-child",
      conversationId: "managed-conversation",
      turnId: "managed-turn",
      taskId: "managed-task"
    ) { _ in
      consumed = true
      return true
    }
    let response = AgentConnectorResponse(
      sourceMessageId: 45,
      contactId: "desktop",
      content: "managed result",
      conversationId: "managed-conversation",
      turnId: "managed-turn",
      taskId: "managed-task"
    )

    XCTAssertTrue(registry.contains(response))
    XCTAssertTrue(registry.consume(response))
    XCTAssertTrue(consumed)
    XCTAssertFalse(registry.contains(response))
  }

  func testAgentConnectorResponseBusCompletesManagedLedgerBeforeStore() throws {
    let ledger = InMemoryAgentManagedResponseLedger()
    try ledger.register(AgentManagedResponseRecord(
      ownerRunId: "child-primary",
      supervisorRunId: "supervisor",
      agentId: "primary",
      deliveryMode: .respond,
      sourceMessageId: 9001,
      contactId: "primary",
      createdAtMillis: 1_000
    ))
    let store = AgentConnectorResponseStore(nowMillis: { 10_000 })
    let bus = AgentConnectorResponseBus(
      registry: AgentManagedConnectorResponseRegistry(),
      managedLedger: ledger,
      store: store,
      nowMillis: { 10_000 }
    )

    XCTAssertTrue(bus.publish(AgentConnectorResponse(
      sourceMessageId: 9001,
      contactId: "primary",
      content: "durable final answer",
      receivedAtMillis: 9_000
    )))
    XCTAssertTrue(store.pending().isEmpty)
    XCTAssertEqual(ledger.completedUnapplied().map(\.ownerRunId), ["child-primary"])

    XCTAssertTrue(bus.publish(AgentConnectorResponse(
      sourceMessageId: 9001,
      contactId: "primary",
      content: "duplicate",
      receivedAtMillis: 9_500
    )))
    XCTAssertTrue(store.pending().isEmpty)
  }

  func testAgentConnectorResponseBusFallbacksRichOutputAndNotifiesListeners() {
    let store = AgentConnectorResponseStore(nowMillis: { 10_000 })
    let bus = AgentConnectorResponseBus(
      registry: AgentManagedConnectorResponseRegistry(),
      store: store,
      nowMillis: { 10_000 }
    )
    let rich = #"{"version":1,"blocks":[{"type":"text","text":"Rendered rich answer","title":"","fallback_text":"","uri":""}]}"#
    var notified: [AgentConnectorResponse] = []
    let token = bus.addListener { notified.append($0) }
    defer { bus.removeListener(token) }

    XCTAssertFalse(bus.publish(AgentConnectorResponse(
      sourceMessageId: 501,
      contactId: "codex",
      content: "",
      richOutputJson: rich
    )))

    XCTAssertEqual(store.pending().map(\.content), ["Rendered rich answer"])
    XCTAssertEqual(notified.map(\.content), ["Rendered rich answer"])
    XCTAssertFalse(store.pending().first?.richOutputJson.isEmpty ?? true)
    XCTAssertFalse(bus.publish(AgentConnectorResponse(sourceMessageId: 0, content: "invalid")))
    XCTAssertFalse(bus.publish(AgentConnectorResponse(sourceMessageId: 502, content: "", richOutputJson: "{}")))
  }

  func testUnmanagedAgentResponseIsDurablyRecordedWithoutManagedConsumption() {
    let store = AgentConnectorResponseStore(nowMillis: { 10_000 })
    let bus = AgentConnectorResponseBus(
      registry: AgentManagedConnectorResponseRegistry(),
      managedLedger: nil,
      store: store,
      nowMillis: { 10_000 }
    )
    let response = AgentConnectorResponse(
      sourceMessageId: 503,
      contactId: "codex",
      content: "Background result",
      conversationId: "conversation-a",
      turnId: "turn-a",
      taskId: "task-a",
      receivedAtMillis: 9_000
    )

    XCTAssertFalse(bus.publish(response))
    XCTAssertTrue(bus.wasRecorded(response))
    XCTAssertEqual(store.pending(), [response])
    bus.remove(response)
    XCTAssertTrue(bus.wasRecorded(response))
  }

  func testAgentConnectorResponseStoreBoundsDedupeExpiryAndAndroidWireNames() throws {
    let store = AgentConnectorResponseStore(nowMillis: { 100_000 })
    for index in 0..<35 {
      store.append(AgentConnectorResponse(
        sourceMessageId: Int64(index + 1),
        contactId: "codex",
        content: "answer-\(index)",
        receivedAtMillis: Int64(index + 1)
      ))
    }
    XCTAssertEqual(store.pending().count, AgentConnectorResponseStore.maxResponses)
    XCTAssertEqual(store.pending().first?.sourceMessageId, 6)

    store.append(AgentConnectorResponse(
      sourceMessageId: 35,
      contactId: "codex",
      content: "replacement",
      receivedAtMillis: 101_000
    ))
    XCTAssertEqual(store.pending().filter { $0.sourceMessageId == 35 && $0.contactId == "codex" }.count, 1)
    XCTAssertEqual(store.pending().last?.content, "replacement")

    let encoded = store.serializedSnapshot()
    let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [[String: Any]])
    let object = try XCTUnwrap(array.last)
    XCTAssertEqual(object["source_message_id"] as? Int, 35)
    XCTAssertEqual(object["received_at"] as? Int, 101_000)
    XCTAssertNil(object["received_at_millis"])
    XCTAssertNil(object["sourceMessageId"])

    let stale = AgentConnectorResponseStoreCodec.encode([
      AgentConnectorResponse(
        sourceMessageId: 900,
        contactId: "codex",
        content: "old",
        receivedAtMillis: 100_000 - AgentConnectorResponseStore.maxResponseAgeMillis - 1
      )
    ])
    XCTAssertTrue(AgentConnectorResponseStore(serialized: stale, nowMillis: { 100_000 }).pending().isEmpty)

    store.remove(AgentConnectorResponse(sourceMessageId: 35, contactId: "codex", content: ""))
    XCTAssertFalse(store.pending().contains { $0.sourceMessageId == 35 && $0.contactId == "codex" })
  }

  func testAgentConnectorResponseStoreRetainsPendingBodiesAndUsesFullIdentity() {
    let store = AgentConnectorResponseStore(nowMillis: { 100_000 })
    let first = AgentConnectorResponse(
      sourceMessageId: 71,
      contactId: "codex",
      content: "first answer",
      conversationId: "conversation-a",
      turnId: "turn-a",
      taskId: "task-a",
      receivedAtMillis: 90_000
    )
    let second = AgentConnectorResponse(
      sourceMessageId: 71,
      contactId: "codex",
      content: "second answer",
      conversationId: "conversation-b",
      turnId: "turn-b",
      taskId: "task-b",
      receivedAtMillis: 91_000
    )

    XCTAssertTrue(store.append(first))
    XCTAssertTrue(store.append(second))
    XCTAssertEqual(store.pending().map(\.content), ["first answer", "second answer"])

    store.remove(first)
    XCTAssertEqual(store.pending().map(\.content), ["second answer"])
    XCTAssertTrue(store.hasReceivedDelivery(AgentTerminalDelivery(
      sourceMessageId: 0,
      conversationId: first.conversationId,
      turnId: first.turnId,
      taskId: first.taskId,
      contactId: first.contactId
    )))
    XCTAssertFalse(store.hasReceivedDelivery(AgentTerminalDelivery(
      sourceMessageId: 0,
      conversationId: "conversation-other",
      turnId: first.turnId,
      taskId: first.taskId,
      contactId: first.contactId
    )))
  }

  func testLateTransportFailureCannotReplaceConsumedReply() {
    let store = AgentConnectorResponseStore(nowMillis: { 100_000 })
    let terminals = InMemoryAgentTerminalDeliveryStore()
    let bus = AgentConnectorResponseBus(
      registry: AgentManagedConnectorResponseRegistry(),
      managedLedger: nil,
      store: store,
      terminalStore: terminals,
      nowMillis: { 100_000 }
    )
    let response = AgentConnectorResponse(
      sourceMessageId: 72,
      contactId: "codex",
      content: "durable answer",
      conversationId: "conversation",
      turnId: "turn",
      taskId: "task",
      receivedAtMillis: 99_000
    )
    XCTAssertFalse(bus.publish(response))
    bus.remove(response)

    XCTAssertFalse(bus.markTransportFailure(AgentTerminalDelivery(
      sourceMessageId: response.sourceMessageId,
      conversationId: response.conversationId,
      turnId: response.turnId,
      taskId: response.taskId,
      contactId: response.contactId,
      reason: "delivery_retry_exhausted"
    )))
    XCTAssertNil(terminals.find(sourceMessageId: response.sourceMessageId))
  }

  func testReceivedDeliveryProofSurvivesConsumptionAndStoreReopen() {
    let suite = "AgentConnectorResponseTests.received.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = "responses"
    let secrets = InMemorySecretStore()
    let response = AgentConnectorResponse(
      sourceMessageId: 73,
      contactId: "codex",
      content: "persisted answer",
      conversationId: "conversation",
      turnId: "turn",
      taskId: "task",
      receivedAtMillis: 99_000
    )
    let store = UserDefaultsAgentConnectorResponseStore(
      defaults: defaults,
      storageKey: key,
      secrets: secrets,
      nowMillis: { 100_000 }
    )
    XCTAssertTrue(store.publish(response))
    store.remove(response)
    XCTAssertTrue(store.pending().isEmpty)

    let reopened = UserDefaultsAgentConnectorResponseStore(
      defaults: defaults,
      storageKey: key,
      secrets: secrets,
      nowMillis: { 100_000 }
    )
    XCTAssertTrue(reopened.hasReceivedDelivery(AgentTerminalDelivery(
      sourceMessageId: response.sourceMessageId,
      conversationId: response.conversationId,
      turnId: response.turnId,
      taskId: response.taskId,
      contactId: response.contactId
    )))
  }

  func testProductionResponseStoreRejectsKeyFailureBeforePublishingAndCanRetry() {
    let suite = "AgentConnectorResponseTests.keyFailure.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let secrets = RejectableConnectorSecretStore()
    let store = UserDefaultsAgentConnectorResponseStore(defaults: defaults,
      storageKey: "responses", secrets: secrets, nowMillis: { 10_000 })
    let bus = AgentConnectorResponseBus(registry: AgentManagedConnectorResponseRegistry(),
      managedLedger: nil, store: store, terminalStore: InMemoryAgentTerminalDeliveryStore(), nowMillis: { 10_000 })
    var notifications = 0
    let token = bus.addListener { _ in notifications += 1 }
    defer { bus.removeListener(token) }
    let response = AgentConnectorResponse(sourceMessageId: 76, contactId: "codex", content: "sensitive result",
      conversationId: "conversation", turnId: "turn", taskId: "task", receivedAtMillis: 9_000)
    XCTAssertFalse(bus.publish(response))
    XCTAssertFalse(bus.wasRecorded(response))
    XCTAssertTrue(store.pending().isEmpty)
    XCTAssertEqual(notifications, 0)

    secrets.reject = false
    XCTAssertFalse(bus.publish(response))
    XCTAssertTrue(bus.wasRecorded(response))
    XCTAssertEqual(notifications, 1)
    XCTAssertEqual(store.pending().first?.content, response.content)
    XCTAssertNil(defaults.object(forKey: "responses"))
    XCTAssertNil(defaults.object(forKey: "responses.received_deliveries"))
    let ciphertext = defaults.data(forKey: "responses.snapshot.v1.encrypted.v1")!
    XCTAssertFalse(String(decoding: ciphertext, as: UTF8.self).contains(response.content))
  }

  func testResponseSnapshotMigratesLegacyOnlyAfterSuccessfulEncryptedWrite() {
    let suite = "AgentConnectorResponseTests.migration.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let response = AgentConnectorResponse(sourceMessageId: 77, contactId: "codex", content: "legacy answer",
      conversationId: "conversation", turnId: "turn", taskId: "task", receivedAtMillis: 9_000)
    let legacy = AgentConnectorResponseStoreCodec.encode([response])
    defaults.set(legacy, forKey: "responses")
    let secrets = RejectableConnectorSecretStore()
    let store = UserDefaultsAgentConnectorResponseStore(defaults: defaults, storageKey: "responses",
      secrets: secrets, nowMillis: { 10_000 })
    XCTAssertFalse(store.publish(response))
    XCTAssertEqual(defaults.string(forKey: "responses"), legacy)
    XCTAssertEqual(store.pending().count, 1)
    secrets.reject = false
    XCTAssertTrue(store.publish(response))
    XCTAssertNil(defaults.object(forKey: "responses"))
    let reopened = UserDefaultsAgentConnectorResponseStore(defaults: defaults, storageKey: "responses",
      secrets: secrets, nowMillis: { 10_000 })
    XCTAssertEqual(reopened.pending().first?.content, response.content)

    let corrupted = Data([0, 1, 2])
    defaults.set(corrupted, forKey: "responses.snapshot.v1.encrypted.v1")
    defaults.set(legacy, forKey: "responses")
    XCTAssertTrue(reopened.pending().isEmpty)
    XCTAssertFalse(reopened.publish(response))
    XCTAssertEqual(defaults.data(forKey: "responses.snapshot.v1.encrypted.v1"), corrupted)
    reopened.clear()
    XCTAssertNil(defaults.object(forKey: "responses.snapshot.v1.encrypted.v1"))
    XCTAssertNil(defaults.object(forKey: "responses"))
  }

  func testAgentConnectorFinalResultPersistsBeforeLiveStreamRetires() {
    var calls: [String] = []

    let result: Bool? = AgentConnectorStreamHandoff.persistThenRetire(
      persistFinal: {
        calls.append("persist")
        return true
      },
      retireLiveStream: { calls.append("retire") }
    )

    XCTAssertEqual(result, true)
    XCTAssertEqual(calls, ["persist", "retire"])
  }

  func testAgentConnectorFailedPersistenceKeepsLiveStreamVisible() {
    var retired = false

    let result: Bool? = AgentConnectorStreamHandoff.persistThenRetire(
      persistFinal: { nil },
      retireLiveStream: { retired = true }
    )

    XCTAssertNil(result)
    XCTAssertFalse(retired)
  }

  private func connectorPolicyMessage(isMine: Bool, turnId: String) -> ChatMessage {
    ChatMessage(
      contactId: "hermes",
      content: isMine ? "USER" : "ASSISTANT",
      isMine: isMine,
      conversationId: "conversation-1",
      turnId: turnId
    )
  }
}

private final class RejectableConnectorResponseSink: AgentConnectorResponseSink {
  var reject = true
  private let store = InMemoryAgentConnectorResponseStore()
  func publish(_ response: AgentConnectorResponse) -> Bool {
    !reject && store.publish(response)
  }
  func pending() -> [AgentConnectorResponse] { store.pending() }
  func remove(_ response: AgentConnectorResponse) { store.remove(response) }
  func hasReceivedDelivery(_ delivery: AgentTerminalDelivery) -> Bool { store.hasReceivedDelivery(delivery) }
  func clear() { store.clear() }
}

private final class ConnectorResponseRunSlotSpy: AgentGlobalRunSlotStoring {
  var releasedSources: [String] = []
  func acquire(registration: AgentRegistration, ownerId: String) -> Bool { true }
  func bindSourceMessage(ownerId: String, sourceMessageId: String) {}
  func release(ownerId: String) {}
  func release(sourceMessageId: String) { releasedSources.append(sourceMessageId) }
  func touch(sourceMessageId: String, nowMillis: Int64) {}
  func activeCounts() -> [String: Int] { [:] }
}

private final class RejectableConnectorSecretStore: GalaxySSISecretStore {
  var reject = true
  private let backing = InMemorySecretStore()
  private enum Failure: Error { case unavailable }
  func setString(_ value: String, account: String) throws {
    if reject { throw Failure.unavailable }
    try backing.setString(value, account: account)
  }
  func string(account: String) -> String? { backing.string(account: account) }
  func delete(account: String) { backing.delete(account: account) }
}
