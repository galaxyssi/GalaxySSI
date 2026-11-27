import Foundation
import XCTest
@testable import GalaxySSI

final class AgentKnowledgePublicationCancellationTests: XCTestCase {
  private final class Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let database: AgentKnowledgeDatabase
    let item = AgentKnowledgeItem(id: "source", kind: .note, title: "Fixture", content: "orbital procedure", updatedAtMillis: 1)
    let spec = AgentKnowledgeVectorProvenance(modelSHA256: String(repeating: "b", count: 64), dimensions: 2,
      contextTokens: 512, chunkingContract: AgentKnowledgeEmbeddingChunker.contract)
    init() throws {
      database = AgentKnowledgeDatabase(fileURL: root.appendingPathComponent("knowledge.sqlite"), secrets: InMemorySecretStore())
      guard database.replaceAll([item]) else { throw AgentKnowledgeDatabaseError.unavailable }
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    var hit: AgentKnowledgeHit { .init(item: item, score: 1, excerpt: item.content, matchedTerms: ["orbital"]) }
  }
  private final class Counter {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
  }
  // Only the native graph boundary is simulated; the lexical SQLite validation is real.
  private final class Session: AgentKnowledgeNativeSession {
    let state: AgentKnowledgeNativeCheckpoint
    init(epoch: String) { state = .init(epoch: epoch, last: nil, pending: nil) }
    func checkpoint() throws -> AgentKnowledgeNativeCheckpoint { state }
    func begin(_ event: AgentKnowledgeNativeEvent, skip: Bool) throws -> AgentKnowledgeNativeCheckpoint { throw AgentKnowledgeNativeError.invalidRecord }
    func append(_ page: AgentKnowledgeVectorReplayPage) throws -> AgentKnowledgeNativeCheckpoint { throw AgentKnowledgeNativeError.invalidRecord }
    func search(_ query: [Float], count: Int, breadth: Int) throws -> [AgentKnowledgeNativeMatch] { [] }
    func recordsPartitioned() throws -> Bool { true }
    func migrateRecords(limit: Int) throws -> Bool { true }
    func cancel() {}
    func close() {}
  }
  private func make(_ f: Fixture, admission: AgentKnowledgeRetrievalAdmission,
                    embedded: Counter = Counter(), before: @escaping () -> Void = {}) -> AgentKnowledgeSemanticSearch {
    AgentKnowledgeSemanticSearch(database: f.database, provenance: f.spec, admission: admission,
      nativeFactory: { stamp, _, _ in
        let epoch = try AgentKnowledgeNativeWire.epoch(stamp.epoch).map { String(format: "%02x", $0) }.joined()
        return Session(epoch: epoch)
      }, beforePublication: before, embedQuery: { _ in embedded.increment(); return [0.6, 0.8] })
  }

  func testBusyFallbackReturnsFreshLexicalWithoutEmbedding() async throws {
    let f = try Fixture(), admission = AgentKnowledgeRetrievalAdmission(), embedded = Counter()
    let holder = try XCTUnwrap(admission.acquire(timeoutMillis: 0)); defer { holder.release() }
    let search = make(f, admission: admission, embedded: embedded)
    let hits = try await search.search(query: "orbital", lexicalHits: [f.hit])
    XCTAssertEqual(hits.map(\.item.id), [f.item.id]); XCTAssertEqual(embedded.count, 0)
  }

  func testCancelledBusyFallbackCannotPublishAfterSQLiteValidation() async throws {
    let f = try Fixture(), admission = AgentKnowledgeRetrievalAdmission(), embedded = Counter()
    let holder = try XCTUnwrap(admission.acquire(timeoutMillis: 0)); defer { holder.release() }
    let validated = expectation(description: "Busy fallback validated"), release = DispatchSemaphore(value: 0)
    let search = make(f, admission: admission, embedded: embedded, before: {
      validated.fulfill(); _ = release.wait(timeout: .now() + 3)
    })
    let token = f.database.nativeFiles.activeToken()
    let request = Task { try await search.search(query: "orbital", lexicalHits: [f.hit]) }
    await fulfillment(of: [validated], timeout: 3)
    request.cancel(); release.signal()
    do { _ = try await request.value; XCTFail("Cancelled fallback published evidence") }
    catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    XCTAssertEqual(embedded.count, 0)
    XCTAssertEqual(f.database.nativeFiles.activeToken(), token)
  }

  func testCancelledHybridCannotPublishAfterSQLiteValidation() async throws {
    let f = try Fixture(), admission = AgentKnowledgeRetrievalAdmission()
    let validated = expectation(description: "Hybrid validated"), release = DispatchSemaphore(value: 0)
    let search = make(f, admission: admission, before: {
      validated.fulfill(); _ = release.wait(timeout: .now() + 3)
    })
    let request = Task { try await search.search(query: "orbital", lexicalHits: [f.hit]) }
    await fulfillment(of: [validated], timeout: 3)
    request.cancel(); release.signal()
    do { _ = try await request.value; XCTFail("Cancelled hybrid published evidence") }
    catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    XCTAssertNotNil(admission.acquire(timeoutMillis: 0))
  }

  func testLifecycleInvalidationWithholdsBothPublicationPaths() async throws {
    for busy in [false, true] {
      let f = try Fixture(), admission = AgentKnowledgeRetrievalAdmission()
      let holder = busy ? admission.acquire(timeoutMillis: 0) : nil
      defer { holder?.release() }
      let search = make(f, admission: admission, before: { f.database.nativeFiles.invalidate() })
      do { _ = try await search.search(query: "orbital", lexicalHits: [f.hit]); XCTFail("Invalid scope published evidence") }
      catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
  }

  func testAlreadyCancelledFallbackDoesNotStartValidationOrEmbedding() async throws {
    let f = try Fixture(), admission = AgentKnowledgeRetrievalAdmission(), embedded = Counter(), published = Counter()
    let holder = try XCTUnwrap(admission.acquire(timeoutMillis: 0)); defer { holder.release() }
    let search = make(f, admission: admission, embedded: embedded, before: { published.increment() })
    let start = DispatchSemaphore(value: 0)
    let request = Task {
      _ = start.wait(timeout: .now() + 3)
      return try await search.search(query: "orbital", lexicalHits: [f.hit])
    }
    request.cancel(); start.signal()
    do { _ = try await request.value; XCTFail("Cancelled request started") }
    catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    XCTAssertEqual(embedded.count, 0); XCTAssertEqual(published.count, 0)
  }

  func testSuccessfulHybridRetainsRankingAndReleasesAdmission() async throws {
    let f = try Fixture(), admission = AgentKnowledgeRetrievalAdmission(), embedded = Counter()
    let search = make(f, admission: admission, embedded: embedded)
    let hits = try await search.search(query: "orbital", lexicalHits: [f.hit])
    XCTAssertEqual(hits.map(\.item.id), [f.item.id]); XCTAssertEqual(embedded.count, 1)
    XCTAssertNotNil(admission.acquire(timeoutMillis: 0))
  }
}
