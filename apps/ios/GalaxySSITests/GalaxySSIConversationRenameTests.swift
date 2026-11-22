import XCTest
@testable import GalaxySSI

final class GalaxySSIConversationRenameTests: XCTestCase {
  func testNormalizationUsesAndroidUTF16LimitAndSingleLinePolicy() {
    typealias Policy = GalaxySSIConversationRenamePolicy
    XCTAssertEqual(Policy.normalize("  Name  "), "Name")
    XCTAssertEqual(Policy.normalize("\nName\n"), "Name")
    XCTAssertNotNil(Policy.normalize(String(repeating: "x", count: 72)))
    XCTAssertNil(Policy.normalize(String(repeating: "x", count: 73)))
    XCTAssertNotNil(Policy.normalize(String(repeating: "\u{1F680}", count: 36)))
    XCTAssertNil(Policy.normalize(String(repeating: "\u{1F680}", count: 37)))
    for raw in ["", "  ", "a\nb", "a\tb", "a\u{7F}b", "a\u{85}b", "a\u{2028}b", "a\u{2029}b"] {
      XCTAssertNil(Policy.normalize(raw))
    }
  }

  func testAtomicAgentRenamePreservesEveryOtherFieldAndDraftStatus() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = AgentConversationDatabase(fileURL: directory.appendingPathComponent("sessions.sqlite"), secrets: InMemorySecretStore())
    let original = AgentConversation(id: "session", title: "Before", createdAt: 1, updatedAt: 100,
      selectedModelOrAgent: "model", contextPolicy: "extended", summary: "summary", status: .archived,
      pinned: true, privateMode: true, inputTokens: 9, outputTokens: 10, trackingPaused: true, latestDialogueAt: 80)
    XCTAssertTrue(database.upsert(original))
    XCTAssertTrue(database.renameTitle(id: original.id, expected: "Before", title: "After"))
    var expected = original; expected.title = "After"
    XCTAssertEqual(database.read(original.id), expected)
    XCTAssertFalse(database.renameTitle(id: original.id, expected: "Before", title: "Stale"))
    XCTAssertFalse(database.renameTitle(id: "deleted", expected: "Before", title: "Resurrected"))
    XCTAssertFalse(database.renameTitle(id: original.id, expected: "After", title: "bad\nname"))
    let draft = AgentConversation(id: "draft", title: "Draft", createdAt: 2, updatedAt: 2)
    XCTAssertTrue(database.saveDraft(draft))
    XCTAssertTrue(database.renameTitle(id: "draft", expected: "Draft", title: "Renamed draft"))
    XCTAssertNil(database.read("draft"))
    XCTAssertEqual(database.readDraft("draft")?.title, "Renamed draft")
  }

  func testRowPatchKeepsIdentityPreviewsStatusAndSearchWhileSeparatingKinds() {
    let agent = GalaxySSIConversationHubItem(id: "same", kind: .agent, title: "Before", subtitle: "model",
      preview: "reply", updatedAt: Date(timeIntervalSince1970: 4), pinned: true, archived: false, searchableMetadata: "provider", unreadCount: 3)
    var contact = agent; contact.kind = .contact; contact.pinned = false
    let source = GalaxySSIConversationHubSections(pinned: [agent], recent: [contact])
    let patched = GalaxySSIConversationHubModels.renamedRows(source, kind: .agent, id: "same", title: "After", query: "reply")
    var expected = agent; expected.title = "After"
    XCTAssertEqual(patched.pinned, [expected])
    XCTAssertEqual(patched.recent, [contact])
    XCTAssertTrue(GalaxySSIConversationHubModels.renamedRows(source, kind: .agent, id: "same", title: "After", query: "Before").pinned.isEmpty)
    let renamed = GalaxySSIConversationHubModels.renamedRows(source, kind: .agent, id: "same", title: "After", query: "")
    XCTAssertTrue(GalaxySSIConversationHubModels.filteredRows(renamed, query: "After").recent.isEmpty)
    XCTAssertEqual(GalaxySSIConversationHubModels.filteredRows(renamed, query: "After").pinned.map(\.id), ["same"])
    XCTAssertEqual(GalaxySSIConversationHubModels.filteredRows(renamed, query: "Before").recent.map(\.kind), [.contact])
  }

  @MainActor
  func testContactPreparationPreservesUnknownRootFieldsAndCASRejectsConcurrentSave() throws {
    let suite = "rename-fixture-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let secrets = InMemorySecretStore(), contact = fixtureContact()
    let object = try JSONSerialization.jsonObject(with: JSONEncoder.galaxySSI.encode(contact))
    var root: [String: Any] = ["profile": ["identityFingerprint": "owner"], "contacts": [object],
      "messagesByContact": ["untouched": ["message"]], "future_field": ["keep": true]]
    XCTAssertTrue(GalaxySSIEncryptedStateStore.write(try JSONSerialization.data(withJSONObject: root), defaults: defaults, secrets: secrets))
    let input = try XCTUnwrap(GalaxySSIEncryptedStateStore.contactRenameInput(defaults: defaults, secrets: secrets, owner: "owner", contact: contact, name: "Remark"))
    let prepared = try input.prepare()
    root["future_field"] = ["newer": true]
    XCTAssertTrue(GalaxySSIEncryptedStateStore.write(try JSONSerialization.data(withJSONObject: root), defaults: defaults, secrets: secrets))
    XCTAssertFalse(GalaxySSIEncryptedStateStore.commitContactRename(prepared, input: input, defaults: defaults))
    let fresh = try XCTUnwrap(GalaxySSIEncryptedStateStore.contactRenameInput(defaults: defaults, secrets: secrets, owner: "owner", contact: contact, name: "Remark"))
    XCTAssertTrue(try GalaxySSIEncryptedStateStore.commitContactRename(fresh.prepare(), input: fresh, defaults: defaults))
    let loaded = try XCTUnwrap(GalaxySSIEncryptedStateStore.load(defaults: defaults, secrets: secrets))
    let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: loaded) as? [String: Any])
    XCTAssertEqual((decoded["future_field"] as? [String: Bool])?["newer"], true)
    let contacts = try XCTUnwrap(decoded["contacts"] as? [[String: Any]])
    let changed = try JSONDecoder.galaxySSI.decode(GalaxySSIContact.self, from: JSONSerialization.data(withJSONObject: contacts[0]))
    var expected = contact; expected.name = "Remark"; expected.displayName = "Remark"; expected.updatedAt = changed.updatedAt
    XCTAssertEqual(changed, expected)
    let wrongOwner = try XCTUnwrap(GalaxySSIEncryptedStateStore.contactRenameInput(defaults: defaults, secrets: secrets, owner: "other", contact: changed, name: "Blocked"))
    XCTAssertThrowsError(try wrongOwner.prepare())
    var deleted = contact; deleted.deleted = true
    XCTAssertNil(GalaxySSIEncryptedStateStore.contactRenameInput(defaults: defaults, secrets: secrets, owner: "owner", contact: deleted, name: "Blocked"))
  }

  private func fixtureContact() -> GalaxySSIContact {
    .init(id: "contact", galaxySSIId: "peer", name: "Alice", displayName: "Alice", type: "human", agentKind: "",
      deliveryMode: .link, trustState: .verified, desktopId: "", desktopName: "", identityFingerprint: "peer-fingerprint",
      setupStatus: "ready", setupDetail: "", cloudProvider: "", cloudModels: [], selectedCloudModelId: "",
      deleted: false, createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2))
  }
}
