import Foundation
import XCTest
@testable import GalaxySSI

@MainActor
final class AgentMemoryTrustAndLabRuntimeTests: XCTestCase {
  func testCoreMemoryCapturesProvenanceAndRecordsPromptUsage() {
    let suite = "AgentCoreMemoryTrustTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    let memoryStore = InMemoryAgentMemoryStore()
    let trustStore = AgentMemoryTrustStore(defaults: defaults, secrets: InMemorySecretStore())
    let coordinator = AgentIOSCoreMemoryCoordinator(store: memoryStore, trustStore: trustStore)

    let captured = coordinator.captureExplicit(
      "My name is Ada",
      conversationId: "conversation-1",
      eventId: "event-1"
    )
    let prompt = coordinator.compilePrompt(
      conversationId: "conversation-1",
      turnId: "turn-1",
      query: "What is my name?"
    )

    XCTAssertEqual(captured.first?.originConversationId, "conversation-1")
    XCTAssertEqual(captured.first?.originEventId, "event-1")
    XCTAssertTrue(prompt.contains("Ada"))
    XCTAssertEqual(trustStore.recent().first?.memoryIds, captured.map(\.id))
  }

  func testPrivateMemoryIsExcludedFromRecallAndRecent() {
    let store = InMemoryAgentMemoryStore()
    let visible = AgentMemoryItem(kind: .knowledge, value: "Visible project note", id: "visible", key: "visible-note")
    let privateItem = AgentMemoryItem(
      kind: .knowledge,
      value: "Private project note",
      id: "private",
      key: "private-note",
      privateMemory: true
    )
    _ = store.remember(visible)
    _ = store.remember(privateItem)

    XCTAssertEqual(store.recall(query: "project note").map(\.id), ["visible"])
    XCTAssertEqual(store.recent(limit: 10).map(\.id), ["visible"])
    XCTAssertTrue(store.setPrivate(itemId: "visible", privateMemory: true))
    XCTAssertTrue(store.recall(query: "project note").isEmpty)
    XCTAssertTrue(store.deprecate(itemId: "private"))
    XCTAssertEqual(store.snapshot().historyItems.map(\.id), ["private"])
  }

  func testMemoryTrustDeduplicatesSelectionAndAttachesAnswer() {
    let suite = "AgentMemoryTrustTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    var now: Int64 = 1_000
    let trust = AgentMemoryTrustStore(
      defaults: defaults,
      secrets: InMemorySecretStore(),
      nowMillis: { now }
    )
    let memory = AgentMemoryItem(
      kind: .preference,
      value: "Prefer concise answers",
      id: "memory-1",
      source: "explicit_core_memory",
      whyRemembered: "User preference",
      originConversationId: "conversation-1",
      originEventId: "event-1"
    )

    let first = trust.recordSelection(
      memories: [memory],
      conversationId: "conversation-1",
      turnId: "turn-1",
      query: "Summarize this",
      runId: "run-1"
    )
    now += 10_000
    let duplicate = trust.recordSelection(
      memories: [memory],
      conversationId: "conversation-1",
      turnId: "turn-1",
      query: "Summarize this",
      runId: "run-1"
    )
    let answered = trust.attachAnswer(
      conversationId: "conversation-1",
      runId: "run-1",
      answer: "A concise summary",
      answeredAtMillis: now
    )

    XCTAssertEqual(first?.id, duplicate?.id)
    XCTAssertEqual(trust.recent().count, 1)
    XCTAssertEqual(answered, 1)
    XCTAssertEqual(trust.recent().first?.answerPreview, "A concise summary")
    XCTAssertEqual(trust.profile(memory: memory).whyRemembered, "User preference")
  }

  func testLabStoreResetsInterruptedTrialsAndCancelsPendingWork() {
    let suite = "AgentLabRuntimeTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = AgentLabStore(defaults: defaults, secrets: InMemorySecretStore())
    let campaign = store.create(task: "Compare responses", agentIds: ["agent-a", "agent-b"], repetitions: 1)!
    let firstTrial = campaign.trials[0]
    _ = store.bindRun(campaignId: campaign.id, trialId: firstTrial.id, runId: "run-a")

    let reset = store.resetInterruptedTrials(campaignId: campaign.id)
    XCTAssertEqual(reset?.status, .draft)
    XCTAssertEqual(reset?.trials.first(where: { $0.id == firstTrial.id })?.status, .pending)
    XCTAssertEqual(reset?.trials.first(where: { $0.id == firstTrial.id })?.runId, "")

    let cancelled = store.cancel(campaignId: campaign.id)
    XCTAssertEqual(cancelled?.status, .cancelled)
    XCTAssertTrue(cancelled?.trials.allSatisfy { $0.status == .cancelled } ?? false)
  }
}
