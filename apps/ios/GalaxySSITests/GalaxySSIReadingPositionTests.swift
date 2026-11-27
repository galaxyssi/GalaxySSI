import XCTest
@testable import GalaxySSI

final class GalaxySSIReadingPositionTests: XCTestCase {
  typealias Policy = GalaxySSIReadingPosition
  private let at = Date(timeIntervalSince1970: 1_800_000_000)

  func testInitialHydrationAndScopeChangesDoNotSignalArrivals() {
    let current = snapshot([entry("answer", reply: true)])
    XCTAssertFalse(Policy.newReply(previous: nil, current: current))
    XCTAssertFalse(Policy.newReply(previous: snapshot([]), current: current))
    XCTAssertFalse(Policy.newReply(previous: current, current: snapshot([])))
    XCTAssertFalse(Policy.newReply(previous: snapshot([entry("old")], scope: "other-owner:conversation"), current: current))
  }
  func testFirstTurnBodyNotifiesButStreamingReplacementDoesNot() {
    let request = entry("request", turn: "turn", request: true)
    let first = entry("first", turn: "turn", seconds: 1, reply: true)
    XCTAssertTrue(Policy.newReply(previous: snapshot([request]), current: snapshot([request, first])))
    let revised = entry("replacement", turn: "turn", seconds: 2, reply: true)
    XCTAssertFalse(Policy.newReply(previous: snapshot([request, first]), current: snapshot([request, revised])))
  }
  func testOpenTurnMayFinishBehindANewerUnrelatedMessage() {
    let request = entry("request", turn: "open", request: true)
    let other = entry("other", seconds: 20)
    let reply = entry("reply", turn: "open", seconds: 2, reply: true)
    XCTAssertTrue(Policy.newReply(previous: snapshot([request, other]), current: snapshot([request, reply, other])))
  }
  func testOlderHistoryAndEqualTimestampPrependAreNotNew() {
    let existing = entry("existing", seconds: 10)
    for time in [1.0, 10.0] {
      XCTAssertFalse(Policy.newReply(previous: snapshot([existing]),
        current: snapshot([entry("old", seconds: time, reply: true), existing])))
    }
  }
  func testEqualTimestampAppendIsNew() {
    let existing = entry("existing", seconds: 10)
    XCTAssertTrue(Policy.newReply(previous: snapshot([existing]),
      current: snapshot([existing, entry("new", seconds: 10, reply: true)])))
  }
  func testWaitingUserSystemFailurePreviewAndEmptyBodiesAreExcluded() {
    let messages = [message("User", mine: true), message("System", system: true),
      message("Failed", status: .failed), message("Preview", remote: "agent-stream-preview-1"),
      message("Waiting", remote: AgentReplyWaitingIndicatorPolicy.dedupePrefix + "turn"), message("")]
    XCTAssertTrue(Policy.Snapshot(scope: "owner:conversation", messages: messages).entries.allSatisfy { !$0.reply })
  }
  func testProductionSnapshotContainsOnlyIdentityTimeAndClassificationNotText() {
    let value = Policy.Snapshot(scope: "owner:conversation", messages: [
      message("Synthetic private question", mine: true, turn: "actual"),
      message("Synthetic private answer", turn: "actual")])
    XCTAssertTrue(value.entries[0].request)
    XCTAssertFalse(value.entries[0].reply)
    XCTAssertTrue(value.entries[1].reply)
    XCTAssertEqual(value.entries[1].turn, "actual")
    XCTAssertFalse(String(describing: value).contains("Synthetic private"))
  }
  func testNearestMetricPrefersFollowingSurvivorAtEqualDistance() {
    let ordered = Policy.nearestKeys(["a", "b", "c", "d", "e"], index: 2)
    XCTAssertEqual(ordered, ["c", "d", "b", "e", "a"])
    XCTAssertEqual(ordered.first { ["a", "d"].contains($0) }, "d")
    XCTAssertEqual(ordered.first { ["a", "e"].contains($0) }, "e")
  }
  func testNearestMetricEmptyAndBoundaryInputsAreBounded() {
    XCTAssertEqual(Policy.nearestKeys([], index: 0), [])
    XCTAssertEqual(Policy.nearestKeys(["a"], index: -1), [])
    XCTAssertEqual(Policy.nearestKeys(["a"], index: 1), [])
    XCTAssertEqual(Policy.nearestKeys(["a", "b", "c"], index: 0), ["a", "b", "c"])
    XCTAssertEqual(Policy.nearestKeys(["a", "b", "c"], index: 2), ["c", "b", "a"])
  }
  func testClosedTurnDoesNotNotifyAgainOrForAnUnchangedSnapshot() {
    let request = entry("request", turn: "turn", request: true)
    let first = entry("first", turn: "turn", seconds: 1, reply: true)
    let previous = snapshot([request, first])
    XCTAssertFalse(Policy.newReply(previous: previous, current: previous))
    XCTAssertFalse(Policy.newReply(previous: previous,
      current: snapshot([request, first, entry("second", turn: "turn", seconds: 3, reply: true)])))
  }

  private func entry(_ id: String, turn: String? = nil, seconds: TimeInterval = 0,
                     reply: Bool = false, request: Bool = false) -> Policy.Entry {
    .init(id: id, turn: turn ?? id, at: at.addingTimeInterval(seconds), reply: reply, request: request)
  }
  private func snapshot(_ entries: [Policy.Entry], scope: String = "owner:conversation") -> Policy.Snapshot {
    .init(scope: scope, entries: entries)
  }
  private func message(_ text: String, mine: Bool = false, system: Bool = false,
                       status: ChatDeliveryStatus = .delivered, remote: String = "", turn: String = "") -> ChatMessage {
    .init(contactId: "fixture", content: text, isMine: mine, isSystem: system, createdAt: at,
      deliveryStatus: status, conversationId: "conversation", turnId: turn, remoteMessageId: remote)
  }
}
