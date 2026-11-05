import XCTest
@testable import GalaxySSI

final class PublicNewsBacklogTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  func testHistoryAndRetryGetTurnsEvenWithContinuousNewArrivals() throws {
    var ledger = PublicNewsBacklogLedger()
    let retry = article("retry", age: 90)
    let first = try XCTUnwrap(ledger.claim([retry], now: now.addingTimeInterval(-1_000)))
    ledger.finish(first, outcome: .retry, now: now.addingTimeInterval(-1_000))
    let oldest = article("oldest", age: 70_000)
    let articles = [oldest, retry, article("middle", age: 500)]
    var claimed = [String]()
    for attempt in 0..<8 {
      let arriving = article("arrival-\(attempt)", age: Double(-attempt))
      let claim = try XCTUnwrap(ledger.claim(articles + [arriving], now: now))
      claimed.append(claim.articleID)
      ledger.finish(claim, outcome: .ready, now: now)
    }
    XCTAssertTrue(claimed.prefix(4).contains(oldest.id))
    XCTAssertTrue(claimed.prefix(4).contains(retry.id))
    XCTAssertGreaterThanOrEqual(claimed.filter { $0.contains("arrival-") }.count, 5)
  }

  func testExpiredLeaseCanBeReclaimedAndStaleCompletionCannotOverwriteIt() throws {
    let candidate = article("fixture", age: 60)
    var ledger = PublicNewsBacklogLedger()
    let first = try XCTUnwrap(ledger.claim([candidate], now: now))
    XCTAssertNil(ledger.claim([candidate], now: now.addingTimeInterval(179)))
    ledger = try JSONDecoder().decode(PublicNewsBacklogLedger.self, from: JSONEncoder().encode(ledger))
    let later = now.addingTimeInterval(181)
    let second = try XCTUnwrap(ledger.claim([candidate], now: later))
    XCTAssertNotEqual(first.token, second.token)
    ledger.finish(first, outcome: .ready, now: later)
    XCTAssertEqual(ledger.entries[candidate.id]?.claim?.token, second.token)
    ledger.finish(second, outcome: .retry, now: later)
    XCTAssertNil(ledger.claim([candidate], now: later))
    XCTAssertNotNil(ledger.claim([candidate], now: later.addingTimeInterval(901)))
  }

  func testReconciliationAccountsForCompletedAndReplacedDocuments() throws {
    var ledger = PublicNewsBacklogLedger()
    let candidate = article("fixture", age: 0)
    ledger.reconcileReady([candidate.id], cachedReady: [candidate.id], now: now)
    XCTAssertNil(ledger.claim([candidate], now: now))
    XCTAssertEqual(ledger.counts(articleIDs: [candidate.id], cachedReady: [candidate.id], now: now).ready, 1)
    ledger.reconcileReady([candidate.id], cachedReady: [], now: now)
    XCTAssertEqual(ledger.counts(articleIDs: [candidate.id], cachedReady: [], now: now).waiting, 1)
    XCTAssertNotNil(ledger.claim([candidate], now: now))
  }

  private func article(_ id: String, age: TimeInterval) -> PublicNewsArticle {
    .init(url: URL(string: "https://github.blog/\(id)")!, title: id, summary: "", publisher: "Fixture",
      discoveredAt: now.addingTimeInterval(-age))
  }
}
