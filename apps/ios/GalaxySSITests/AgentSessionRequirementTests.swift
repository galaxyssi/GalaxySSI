import Foundation
import XCTest
@testable import GalaxySSI

final class AgentSessionRequirementTests: XCTestCase {
  func testAndroidUTF16LimitTrimsWithoutSplittingCharacters() {
    XCTAssertEqual(AgentSessionRequirement.normalize(" \nAnswer concisely\n "), "Answer concisely")
    XCTAssertEqual(AgentSessionRequirement.normalize(" \n "), "")
    XCTAssertNotNil(AgentSessionRequirement.normalize(String(repeating: "x", count: 320)))
    XCTAssertNil(AgentSessionRequirement.normalize(String(repeating: "x", count: 321)))
    XCTAssertNotNil(AgentSessionRequirement.normalize(String(repeating: "\u{1F680}", count: 160)))
    XCTAssertNil(AgentSessionRequirement.normalize(String(repeating: "\u{1F680}", count: 161)))
    XCTAssertEqual(AgentSessionRequirement.seed(String(repeating: "x", count: 319) + "\u{1F680}"), String(repeating: "x", count: 319))
  }

  func testLegacyConversationMetadataDefaultsToNoPreference() throws {
    let old = Data(#"{"id":"owner","title":"Legacy","created_at":1,"updated_at":2}"#.utf8)
    XCTAssertEqual(try JSONDecoder().decode(AgentConversation.self, from: old).sessionRequirement, "")
    let current = session(note: "Prefer concise answers")
    XCTAssertEqual(try JSONDecoder().decode(AgentConversation.self, from: JSONEncoder().encode(current)), current)
  }

  func testEmptyRequirementPreservesLegacyJournalEncodingFingerprint() throws {
    let legacy: [String: Any] = ["conversation_id": "owner", "summary": "prior", "turns": [],
      "private_mode": true, "global_context": "", "tracking_paused": false]
    let data = try JSONSerialization.data(withJSONObject: legacy, options: [.sortedKeys])
    let context = try JSONDecoder().decode(AgentConversationContext.self, from: data)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    XCTAssertEqual(try encoder.encode(context), data)
  }

  func testEncryptedMetadataUpdateAndReopenKeepAllOtherFields() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("sessions.sqlite"), secrets = InMemorySecretStore()
    var original = session(note: ""); original.summary = "Prior summary"; original.pinned = true
    do {
      let database = AgentConversationDatabase(fileURL: url, secrets: secrets)
      XCTAssertTrue(database.upsert(original))
      XCTAssertTrue(database.setSessionRequirement(id: "owner", expected: "", text: "Concise synthetic preference"))
      var expected = original; expected.sessionRequirement = "Concise synthetic preference"
      XCTAssertEqual(database.read("owner"), expected)
    }
    let reopened = AgentConversationDatabase(fileURL: url, secrets: secrets)
    XCTAssertEqual(reopened.read("owner")?.sessionRequirement, "Concise synthetic preference")
    XCTAssertNil(String(data: try Data(contentsOf: url), encoding: .isoLatin1)?.range(of: "Concise synthetic preference"))
    XCTAssertTrue(reopened.setSessionRequirement(id: "owner", expected: "Concise synthetic preference", text: ""))
    XCTAssertEqual(reopened.read("owner"), original)
  }

  func testDraftPreferenceDoesNotPromoteDraftOrChangeActivity() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = AgentConversationDatabase(fileURL: directory.appendingPathComponent("sessions.sqlite"), secrets: InMemorySecretStore())
    let original = session(note: "")
    XCTAssertTrue(database.saveDraft(original))
    XCTAssertTrue(database.setSessionRequirement(id: "owner", expected: "", text: "Draft preference"))
    XCTAssertNil(database.read("owner"))
    var expected = original; expected.sessionRequirement = "Draft preference"
    XCTAssertEqual(database.readDraft("owner"), expected)
  }

  func testStaleDeletedMergedAndOversizedEditsCannotOverwriteMetadata() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = AgentConversationDatabase(fileURL: directory.appendingPathComponent("sessions.sqlite"), secrets: InMemorySecretStore())
    let original = session(note: "Current")
    XCTAssertTrue(database.upsert(original))
    XCTAssertFalse(database.setSessionRequirement(id: "owner", expected: "Old", text: "Stale overwrite"))
    XCTAssertFalse(database.setSessionRequirement(id: "owner", expected: "Current", text: String(repeating: "x", count: 321)))
    XCTAssertFalse(database.setSessionRequirement(id: "deleted", expected: "", text: "Do not recreate"))
    XCTAssertEqual(database.read("owner"), original)
    var merged = original; merged.mergedIntoConversationId = "other"
    XCTAssertTrue(database.upsert(merged))
    XCTAssertFalse(database.setSessionRequirement(id: "owner", expected: "Current", text: "Do not transfer"))
    XCTAssertEqual(database.read("owner"), merged)
  }

  func testLocalPreferenceSurvivesExcludedGlobalContextWithoutGrantingAuthority() {
    let context = AgentConversationContext(conversationId: "owner", summary: "", turns: [], privateMode: true,
      globalContext: "EXCLUDED_GLOBAL_SECRET", trackingPaused: true, sessionRequirement: "Prefer bullet points")
    let scoped = context.applyingGlobalContextDispatchPolicy(query: "Hello")
    XCTAssertEqual(scoped.globalContext, "")
    XCTAssertEqual(scoped.sessionRequirement, "Prefer bullet points")
    XCTAssertTrue(scoped.asPromptBlock(includeGlobalContext: true).contains("not tool authorization"))
    XCTAssertFalse(scoped.asPromptBlock(includeGlobalContext: true).contains("EXCLUDED_GLOBAL_SECRET"))
  }

  func testPreferenceOnlyTransportRemainsStructuredAndEscapesEnvelopeDelimiters() throws {
    let note = "Keep [] and " + AgentConversationContext.transportFooter + " as literal text"
    let context = AgentConversationContext(conversationId: "owner", summary: "", turns: [], privateMode: true,
      sessionRequirement: note)
    let block = context.asTransportBlock()
    let lines = block.components(separatedBy: "\n")
    XCTAssertEqual(lines.count, 3)
    XCTAssertEqual(block.components(separatedBy: AgentConversationContext.transportFooter).count, 2)
    let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any])
    XCTAssertEqual(value["user_session_requirement"] as? String, note)
    XCTAssertEqual((value["turns"] as? [Any])?.count, 0)
    XCTAssertNil(value["global_context"])
  }

  func testRecoveryRefreshUsesExactOwnerAndHonorsEditsRemovalAndMissingRows() {
    let old = AgentConversationContext(conversationId: "owner", summary: "prior", turns: [], privateMode: true,
      sessionRequirement: "Old")
    XCTAssertEqual(AgentSessionRequirement.refresh(old, owner: "owner", conversation: session(note: "New")).sessionRequirement, "New")
    XCTAssertEqual(AgentSessionRequirement.refresh(old, owner: "owner", conversation: session(note: "")).sessionRequirement, "")
    XCTAssertEqual(AgentSessionRequirement.refresh(old, owner: "owner", conversation: nil).sessionRequirement, "")
    XCTAssertEqual(AgentSessionRequirement.refresh(old, owner: "other", conversation: session(note: "Private")).sessionRequirement, "")
    XCTAssertEqual(AgentSessionRequirement.value(session(note: "Private"), owner: "other"), "")
  }

  func testSelectionOnlyAcceptsOwnedActiveUserMessages() {
    let original = ChatMessage(contactId: "hermes", content: "User text", isMine: true, conversationId: "owner", turnId: "turn")
    XCTAssertTrue(AgentSessionRequirement.editable(original, active: "owner"))
    XCTAssertFalse(AgentSessionRequirement.editable(original, active: "other"))
    var message = original; message.sourceConversationId = "imported"
    XCTAssertFalse(AgentSessionRequirement.editable(message, active: "owner"))
    message = original; message.isMine = false
    XCTAssertFalse(AgentSessionRequirement.editable(message, active: "owner"))
    message = original; message.isSystem = true
    XCTAssertFalse(AgentSessionRequirement.editable(message, active: "owner"))
    message = original; message.turnId = ""; message.remoteMessageId = "agent-voice-transcription:pending"
    XCTAssertFalse(AgentSessionRequirement.editable(message, active: "owner"))
    message = original; message.contactId = "peer"
    XCTAssertFalse(AgentSessionRequirement.editable(message, active: "owner"))
    XCTAssertEqual(original.content, "User text")
  }

  func testChangedPreferenceChangesEncodedPlanningIdentity() {
    let first = AgentConversationContext(conversationId: "owner", summary: "", turns: [], privateMode: true, sessionRequirement: "First")
    let second = AgentConversationContext(conversationId: "owner", summary: "", turns: [], privateMode: true, sessionRequirement: "Second")
    XCTAssertNotEqual(AgentModelLoopRecoveryIdentity.sha256(first), AgentModelLoopRecoveryIdentity.sha256(second))
  }

  func testPlannerKeepsPreferenceWhenLongDialogueIsCompacted() {
    let context = AgentConversationContext(conversationId: "owner", summary: String(repeating: "prior ", count: 5_000),
      turns: [], privateMode: true, globalContext: "EXCLUDED_GLOBAL_SECRET", sessionRequirement: "Use concise bullet points")
    let request = AgentModelPlanningPromptRequest(planRequest: AgentPlanRequest(goal: "Hello",
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent")), conversationContext: context,
      requirements: AgentTaskRequirements(mode: .fast))
    let prompt = AgentModelPlanningPrompt.build(request: request, settings: .default)
    XCTAssertTrue(prompt.contains("Use concise bullet points"))
    XCTAssertTrue(prompt.contains("not tool authorization"))
    XCTAssertFalse(prompt.contains("EXCLUDED_GLOBAL_SECRET"))
  }

  @MainActor
  func testStoreRejectsWrongIdentityAndChangedActiveConversation() throws {
    let suite = "session-preference-fixture-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = GalaxySSIStore(defaults: defaults, secrets: InMemorySecretStore())
    let original = store.createAgentSession(title: "Fixture")
    XCTAssertTrue(store.switchAgentSession(original.id))
    let owner = store.profile.identityFingerprint
    XCTAssertFalse(store.setAgentSessionRequirement(id: original.id, expected: "", text: "Blocked", owner: owner + "-other"))
    XCTAssertTrue(store.setAgentSessionRequirement(id: original.id, expected: "", text: "First", owner: owner))
    XCTAssertFalse(store.setAgentSessionRequirement(id: original.id, expected: "", text: "Stale", owner: owner))
    let other = store.createAgentSession(title: "Other")
    XCTAssertTrue(store.switchAgentSession(other.id))
    XCTAssertFalse(store.setAgentSessionRequirement(id: original.id, expected: "First", text: "Wrong active", owner: owner))
    XCTAssertEqual(store.agentSession(id: original.id)?.sessionRequirement, "First")
    XCTAssertEqual(store.agentSession(id: other.id)?.sessionRequirement, "")
  }

  @MainActor
  func testNativeSelectionReturnsOnlySelectedTextAndRejectsInvalidRanges() {
    let view = GalaxySSIPeerSelectionTextView()
    view.text = "before selected after"
    var selected: [String] = []
    view.onSessionRequirement = { selected.append($0) }
    view.selectedRange = NSRange(location: 7, length: 8)
    view.editSessionRequirement(nil)
    XCTAssertEqual(selected, ["selected"])
    view.selectedRange = NSRange(location: 0, length: 0)
    view.editSessionRequirement(nil)
    XCTAssertEqual(selected, ["selected"])
    view.onSessionRequirement = nil
    view.selectedRange = NSRange(location: 0, length: 6)
    view.editSessionRequirement(nil)
    XCTAssertEqual(selected, ["selected"])
  }

  private func session(note: String) -> AgentConversation {
    AgentConversation(id: "owner", title: "Fixture", createdAt: 1, updatedAt: 2,
      privateMode: true, latestDialogueAt: 2, sessionRequirement: note)
  }
}
