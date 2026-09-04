import XCTest
@testable import SignalASI

final class AgentGlobalRunSlotsTests: XCTestCase {
  func testTenConversationsShareOneRuntimeCapacity() {
    let ledger = AgentGlobalRunSlotLedger()
    for index in 0..<10 {
      XCTAssertTrue(ledger.acquire(
        ownerId: "conversation-\(index)",
        runtimeKey: "desktop-a:codex",
        maxParallelRuns: 10,
        nowMillis: Int64(index)
      ))
    }
    XCTAssertEqual(ledger.activeCount(runtimeKey: "desktop-a:codex"), 10)
    XCTAssertFalse(ledger.acquire(
      ownerId: "conversation-11",
      runtimeKey: "desktop-a:codex",
      maxParallelRuns: 10,
      nowMillis: 11
    ))
    XCTAssertTrue(ledger.acquire(
      ownerId: "deepseek-1",
      runtimeKey: "cloud-model:deepseek",
      maxParallelRuns: 10,
      nowMillis: 11
    ))
  }

  func testTerminalSourceReleasesAndStreamActivityRenewsSlot() {
    let ledger = AgentGlobalRunSlotLedger()
    XCTAssertTrue(ledger.acquire(
      ownerId: "run-1",
      runtimeKey: "desktop-a:codex",
      maxParallelRuns: 10,
      nowMillis: 1_000
    ))
    XCTAssertTrue(ledger.bindSourceMessage(ownerId: "run-1", sourceMessageId: "42"))
    XCTAssertTrue(ledger.touch(sourceMessageId: "42", nowMillis: 5_000))
    XCTAssertFalse(ledger.prune(before: 4_000))
    XCTAssertTrue(ledger.release(sourceMessageId: "42"))
    XCTAssertEqual(ledger.activeCount(runtimeKey: "desktop-a:codex"), 0)
  }

  func testMentionSelectionHidesGenericAliasAndHonorsReservations() {
    let generic = target(id: "codex", title: "Codex", domain: "builtin:codex")
    let concrete = target(id: "desktop-a:codex", title: "Codex Agent · DESKTOP-A", domain: "desktop-a:codex")
    let registrations = [generic, concrete].map { AgentMentionCandidatePolicy.registration(for: $0) }

    XCTAssertEqual(
      AgentMentionCandidatePolicy.select(
        targets: [generic, concrete],
        registrations: registrations,
        reservedByAgentId: [:],
        limit: 12
      ).map(\.agentId),
      ["desktop-a:codex"]
    )
    XCTAssertTrue(AgentMentionCandidatePolicy.select(
      targets: [generic, concrete],
      registrations: registrations,
      reservedByAgentId: ["desktop-a:codex": 10],
      limit: 12
    ).isEmpty)
  }

  func testDesktopDisplayNamePrefersHostname() {
    XCTAssertEqual(
      SignalASIDesktopDeviceMetadata.displayName(from: [
        "desktop_display_name": "Windows PC",
        "desktop_device": [
          "host_name": "DESKTOP-T14",
          "display_name": "ThinkPad"
        ]
      ]),
      "DESKTOP-T14"
    )
  }

  private func target(id: String, title: String, domain: String) -> AgentCallableTarget {
    AgentCallableTarget(
      id: id,
      title: title,
      kind: .agent,
      status: .available,
      capabilities: [.chat, .taskExecution],
      failureDomain: domain,
      runtimeFailureDomain: domain,
      adapterType: "codex-app-server-or-cli"
    )
  }
}
