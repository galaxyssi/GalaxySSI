import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeSourcePreparationTests: XCTestCase {
  private final class Secrets: GalaxySSISecretStore {
    private let lock = NSLock()
    private var values: [String: String] = [:], callback: (() -> Void)?
    func onNextIndexRead(_ action: @escaping () -> Void) { lock.lock(); callback = action; lock.unlock() }
    func setString(_ value: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[account] = value }
    func string(account: String) -> String? {
      lock.lock()
      let value = values[account], action = account == "agent.knowledge.index.hmac256.v1" ? callback : nil
      if action != nil { callback = nil }
      lock.unlock(); action?(); return value
    }
    func delete(account: String) { lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: account) }
  }
  private final class PreparedBox {
    private let lock = NSLock()
    private var value: AgentKnowledgePreparedSourceReplacement?
    func put(_ value: AgentKnowledgePreparedSourceReplacement) { lock.lock(); self.value = value; lock.unlock() }
    func take() -> AgentKnowledgePreparedSourceReplacement? { lock.lock(); defer { lock.unlock() }; defer { value = nil }; return value }
  }
  private enum Fault: Error { case injected }
  private struct WebProvider: AgentIOSWebIntelligenceToolProviding {
    let implementationId = "synthetic.source-preparation"
    let engineCatalogSize = 1
    let rankerId = "synthetic"
    func availability(operation: AgentIOSWebIntelligenceOperation) -> AgentNativeToolAvailability { .init(status: .available) }
    func invoke(operation: AgentIOSWebIntelligenceOperation, input: AgentMcpJSONObject,
      invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
      .success(output: ["text": .string("Synthetic public source content"), "url": .string("https://example.com/source"), "title": .string("Synthetic")])
    }
  }
  private func item(_ id: String = "a", source: String = "A", body: String = "old") -> AgentKnowledgeItem {
    AgentKnowledgeItem(id: id, kind: .document, title: "Synthetic", content: body, source: source, summary: body,
      cloudAccess: .summaryOnly, updatedAtMillis: 10)
  }
  private func fixture(_ items: [AgentKnowledgeItem]? = nil,
    _ body: (AgentKnowledgeDatabase, URL, Secrets) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("knowledge.sqlite"), secrets = Secrets()
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    XCTAssertTrue(database.replaceAll(items ?? [item()]))
    try body(database, url, secrets)
  }
  private func prepare(_ database: AgentKnowledgeDatabase, _ items: [AgentKnowledgeItem], source: String = "A") throws -> AgentKnowledgePreparedSourceReplacement {
    var iterator = items.makeIterator()
    return try database.prepareSourceReplacement(source, next: { iterator.next() })
  }
  @discardableResult
  private func replace(_ database: AgentKnowledgeDatabase, _ items: [AgentKnowledgeItem], source: String = "A") throws -> Int {
    var iterator = items.makeIterator()
    let result = try database.replaceSource(source, next: { iterator.next() })
    defer { result.stage.close() }
    return result.changed
  }
  private func sql(_ url: URL, _ query: String) throws {
    var raw: OpaquePointer?
    guard sqlite3_open(url.path, &raw) == SQLITE_OK else { throw Fault.injected }
    defer { sqlite3_close(raw) }
    guard sqlite3_exec(raw, query, nil, nil, nil) == SQLITE_OK else { throw Fault.injected }
  }
  private func encryptedBody(_ url: URL) throws -> Data {
    var raw: OpaquePointer?, row: OpaquePointer?
    guard sqlite3_open_v2(url.path, &raw, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw Fault.injected }
    defer { sqlite3_finalize(row); sqlite3_close(raw) }
    guard sqlite3_prepare_v2(raw, "SELECT encrypted_payload FROM knowledge_items LIMIT 1", -1, &row, nil) == SQLITE_OK,
      sqlite3_step(row) == SQLITE_ROW, let bytes = sqlite3_column_blob(row, 0) else { throw Fault.injected }
    return Data(bytes: bytes, count: Int(sqlite3_column_bytes(row, 0)))
  }
  private func assertConflict(_ database: AgentKnowledgeDatabase, _ prepared: AgentKnowledgePreparedSourceReplacement) {
    XCTAssertThrowsError(try database.commitSourceReplacement(prepared)) { XCTAssertEqual($0 as? AgentKnowledgeDatabaseError, .sourceReplacementChanged) }
  }

  func testPreparationCompletesUnderHeldSourceWriterAndConflictsAfterItsCommit() throws {
    try fixture { database, _, secrets in
      let held = expectation(description: "uncommitted source writer held"), writerDone = expectation(description: "writer done")
      let staged = expectation(description: "preparation completed without writer monitor")
      let release = DispatchSemaphore(value: 0), joined = DispatchSemaphore(value: 0), box = PreparedBox()
      secrets.onNextIndexRead { held.fulfill(); _ = release.wait(timeout: .now() + 10) }
      let changed = item(body: "concurrent"), incoming = item(body: "replacement")
      DispatchQueue.global().async { XCTAssertTrue(database.replaceAll([changed])); writerDone.fulfill() }
      let admission = XCTWaiter.wait(for: [held], timeout: 3)
      if admission == .completed {
        DispatchQueue.global().async {
          do { var next: AgentKnowledgeItem? = incoming
            box.put(try database.prepareSourceReplacement("A", next: { defer { next = nil }; return next }))
          } catch { XCTFail("Preparation failed: \(error)") }
          staged.fulfill(); joined.signal()
        }
        let done = XCTWaiter.wait(for: [staged], timeout: 4)
        release.signal(); XCTAssertEqual(done, .completed)
        XCTAssertEqual(XCTWaiter.wait(for: [writerDone], timeout: 10), .completed)
        XCTAssertEqual(joined.wait(timeout: .now() + 10), .success)
        let prepared = try XCTUnwrap(box.take()); defer { prepared.close() }
        assertConflict(database, prepared)
        XCTAssertEqual(try database.all(), [changed])
      } else { release.signal(); XCTAssertEqual(admission, .completed); _ = XCTWaiter.wait(for: [writerDone], timeout: 10) }
    }
  }

  func testPagedPreparationAllowsUnrelatedSourceCommitAndKeepsItsSnapshot() throws {
    let original = (0..<130).map { item("a-\($0)", body: "old-\($0)") }
    try fixture(original + [item("b", source: "B")]) { database, _, _ in
      let incoming = original.map { value -> AgentKnowledgeItem in var value = value; value.content = "new"; value.summary = "new"; return value }
      var iterator = incoming.makeIterator(), pages: [Int64] = []
      let prepared = try database.prepareSourceReplacement("A", next: { iterator.next() }, onPage: { count in
        pages.append(count)
        if count == 64 { _ = try self.replace(database, [self.item("b", source: "B", body: "independent")], source: "B") }
      })
      defer { prepared.close() }
      XCTAssertEqual(pages, [64, 128, 130])
      let result = try database.commitSourceReplacement(prepared); defer { result.stage.close() }
      XCTAssertEqual(result.changed, 130)
      XCTAssertEqual(try database.items(ids: ["b"]).first?.content, "independent")
      XCTAssertEqual(try database.all().count, 131)
    }
  }

  func testSourceBodyAndPermissionChangesConflictWithoutOverwritingOrEmittingEvents() throws {
    for accessOnly in [false, true] {
      try fixture { database, _, _ in
        let prepared = try prepare(database, [item(body: "incoming")]); defer { prepared.close() }
        var changed = item()
        if accessOnly { changed.cloudAccess = .deny; changed.allowedAgentIds = ["reviewed"] }
        else { changed.content = "concurrent" }
        XCTAssertTrue(database.replaceAll([changed]))
        assertConflict(database, prepared)
        XCTAssertEqual(try database.all(), [changed])
        XCTAssertTrue(try database.pendingSourceObservations().isEmpty)
      }
    }
  }

  func testDeletionAndIdenticalRecreationAreNotAnABABypass() throws {
    try fixture { database, _, _ in
      let prepared = try prepare(database, [item(body: "incoming")]); defer { prepared.close() }
      _ = try replace(database, []); _ = try replace(database, [item()])
      XCTAssertEqual(try database.all(), [item()])
      assertConflict(database, prepared)
      XCTAssertEqual(try database.all(), [item()])
    }
  }

  func testInitiallyAbsentSourceDetectsCreationAndCreationDeletionABA() throws {
    for deleted in [false, true] {
      try fixture([]) { database, _, _ in
        let prepared = try prepare(database, [item()]); defer { prepared.close() }
        XCTAssertEqual(prepared.revision, 0)
        _ = try replace(database, [item("other")])
        if deleted { _ = try replace(database, []) }
        assertConflict(database, prepared)
      }
    }
  }

  func testIncomingIdentityClaimedElsewhereAfterPreparationIsRejectedInsideWriter() throws {
    try fixture { database, _, _ in
      let prepared = try prepare(database, [item("claimed")]); defer { prepared.close() }
      let other = item("claimed", source: "B")
      _ = try replace(database, [other], source: "B")
      let before = try database.pendingSourceObservations()
      XCTAssertThrowsError(try database.commitSourceReplacement(prepared))
      XCTAssertEqual(Set(try database.all().map(\.id)), Set(["a", "claimed"]))
      XCTAssertEqual(try database.pendingSourceObservations(), before)
    }
  }

  func testSuccessfulPreparedCommitIsSingleUseAndTransfersScratchLifetime() throws {
    try fixture { database, _, _ in
      let prepared = try prepare(database, [item(body: "incoming")])
      let result = try database.commitSourceReplacement(prepared); defer { result.stage.close() }
      prepared.close()
      var items: [AgentKnowledgeItem] = []
      try result.stage.scan(.incoming) { items.append($0) }
      XCTAssertEqual(items.first?.content, "incoming")
      XCTAssertThrowsError(try database.commitSourceReplacement(prepared)) { XCTAssertEqual($0 as? AgentKnowledgeDatabaseError, .sourceReplacementConsumed) }
      XCTAssertEqual(try database.pendingSourceObservations().count, 1)
    }
  }

  func testConflictConsumesPreparationAndRequiresFreshPreparation() throws {
    try fixture { database, _, _ in
      let prepared = try prepare(database, [item(body: "incoming")]); defer { prepared.close() }
      _ = try replace(database, [item(body: "concurrent")])
      assertConflict(database, prepared)
      XCTAssertThrowsError(try database.commitSourceReplacement(prepared)) { XCTAssertEqual($0 as? AgentKnowledgeDatabaseError, .sourceReplacementConsumed) }
      XCTAssertEqual(try replace(database, [item(body: "fresh incoming")]), 1)
    }
  }

  func testForeignDatabaseCannotConsumePreparedOperation() throws {
    try fixture { database, url, secrets in
      let prepared = try prepare(database, [item(body: "incoming")]); defer { prepared.close() }
      let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
      XCTAssertThrowsError(try reopened.commitSourceReplacement(prepared)) { XCTAssertEqual($0 as? AgentKnowledgeDatabaseError, .preparedSourceOwnerMismatch) }
      let result = try database.commitSourceReplacement(prepared); result.stage.close()
    }
  }

  func testCloseBeforeCommitRejectsAndCloseDuringApplyRollsBack() throws {
    try fixture { database, _, _ in
      let closed = try prepare(database, [item(body: "incoming")]); closed.close()
      XCTAssertThrowsError(try database.commitSourceReplacement(closed))
      let prepared = try prepare(database, [item(body: "incoming")]); defer { prepared.close() }
      XCTAssertThrowsError(try database.commitSourceReplacement(prepared, afterMutation: { _ in prepared.close() })) { XCTAssertTrue($0 is CancellationError) }
      XCTAssertEqual(try database.all(), [item()])
      XCTAssertTrue(try database.pendingSourceObservations().isEmpty)
    }
  }

  func testPreparationCallbackFailureLeavesCanonicalStoreUnchanged() throws {
    try fixture { database, _, _ in
      var next: AgentKnowledgeItem? = item(body: "incoming")
      XCTAssertThrowsError(try database.prepareSourceReplacement("A", next: { defer { next = nil }; return next }, onPage: { _ in throw Fault.injected }))
      XCTAssertEqual(try database.all(), [item()])
    }
  }

  func testNoopDoesNotInvalidateAnExistingPreparation() throws {
    try fixture { database, _, _ in
      let prepared = try prepare(database, [item(body: "incoming")]); defer { prepared.close() }
      var replay = item(); replay.updatedAtMillis = 999
      XCTAssertEqual(try replace(database, [replay]), 0)
      let result = try database.commitSourceReplacement(prepared); defer { result.stage.close() }
      XCTAssertEqual(result.changed, 1)
    }
  }

  func testLifecycleInvalidationAndApplyFailureRollbackAndConsume() throws {
    for lifecycle in [false, true] {
      try fixture { database, _, _ in
        let prepared = try prepare(database, [item(body: "incoming")]); defer { prepared.close() }
        XCTAssertThrowsError(try database.commitSourceReplacement(prepared, afterMutation: { _ in
          if lifecycle { database.nativeFiles.invalidate() } else { throw Fault.injected }
        }))
        XCTAssertEqual(try database.all(), [item()])
        XCTAssertTrue(try database.pendingSourceObservations().isEmpty)
        XCTAssertThrowsError(try database.commitSourceReplacement(prepared)) { XCTAssertEqual($0 as? AgentKnowledgeDatabaseError, .sourceReplacementConsumed) }
      }
    }
  }

  func testGenerationMigrationDoesNotRewriteExistingBodyCiphertext() throws {
    try fixture { database, url, secrets in
      try seedLegacyKnowledgePayloads([item()], url: url, secrets: secrets)
      let original = try encryptedBody(url)
      try sql(url, "DROP TRIGGER knowledge_source_generation_insert; DROP TRIGGER knowledge_source_generation_delete; DROP TRIGGER knowledge_source_generation_update; DROP TRIGGER knowledge_source_generation_move; DROP TABLE knowledge_source_generations; DELETE FROM knowledge_metadata WHERE key='source_generation_schema'")
      let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
      XCTAssertEqual(try encryptedBody(url), original)
      let prepared = try prepare(reopened, [item(body: "incoming")]); defer { prepared.close() }
      XCTAssertGreaterThan(prepared.revision, 0)
      let result = try reopened.commitSourceReplacement(prepared); result.stage.close()
      XCTAssertEqual(try database.all().first?.content, "incoming")
    }
  }

  func testGenerationOverflowFailsClosedWithoutLosingOriginalRecord() throws {
    try fixture { database, url, _ in
      try sql(url, "UPDATE knowledge_source_generations SET generation=9223372036854775807")
      let prepared = try prepare(database, [item(body: "incoming")]); defer { prepared.close() }
      XCTAssertThrowsError(try database.commitSourceReplacement(prepared))
      XCTAssertEqual(try database.all(), [item()])
      XCTAssertTrue(try database.pendingSourceObservations().isEmpty)
    }
  }

  func testNewVectorEvidenceDoesNotConflictButIsInvalidatedBySourceCommit() throws {
    try fixture { database, _, _ in
      let prepared = try prepare(database, [item(body: "incoming")]); defer { prepared.close() }
      let old = item(), spec = AgentKnowledgeVectorProvenance(modelSHA256: String(repeating: "a", count: 64), dimensions: 2,
        contextTokens: 512, chunkingContract: AgentKnowledgeEmbeddingChunker.contract)
      XCTAssertTrue(database.storeVectorCheckpoint(AgentKnowledgeVectorCheckpoint(itemId: old.id,
        sourceRevision: AgentKnowledgeVectorCheckpoint.sourceRevision(for: old), chunkIndex: 0, vector: [0.6, 0.8],
        provenance: spec, sourceStartUTF16: 0, sourceEndUTF16: old.content.utf16.count)))
      let result = try database.commitSourceReplacement(prepared); defer { result.stage.close() }
      XCTAssertTrue(try database.vectorCheckpoints(itemId: old.id, modelSHA256: spec.modelSHA256).isEmpty)
      XCTAssertEqual(try database.vectorChangePage(modelSHA256: spec.modelSHA256).events.last?.operation, .removal)
    }
  }

  func testWebImportReportsConflictWithoutAcknowledgingOrAutomaticallyRetrying() {
    for conflict in [false, true] {
      var calls = 0
      let importer = AgentIOSURLSessionWebKnowledgeImporter(provider: WebProvider(), nowMillis: { 100 }, store: { _, _, _, _ in
        calls += 1
        if conflict { throw AgentKnowledgeDatabaseError.sourceReplacementChanged }
        throw Fault.injected
      })
      let result = importer.importPage("https://example.com/source", actionId: "synthetic")
      XCTAssertFalse(result.success); XCTAssertEqual(calls, 1)
      XCTAssertEqual(result.metadata["error_code"], conflict ? "knowledge_source_changed" : "knowledge_store_failed")
      XCTAssertEqual(result.metadata["completion_verified"], "false")
    }
  }
}
