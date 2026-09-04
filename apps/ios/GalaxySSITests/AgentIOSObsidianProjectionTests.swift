import XCTest
@testable import GalaxySSI

final class AgentIOSObsidianProjectionTests: XCTestCase {
  func testPrivacyPolicyBlocksCredentialsAndAllowsOrdinaryKnowledge() {
    XCTAssertFalse(AgentIOSObsidianProjectionPrivacyPolicy.safeKnowledge("identity_key_sha256: abc123"))
    XCTAssertFalse(AgentIOSObsidianProjectionPrivacyPolicy.safeKnowledge("MQTT password is secret"))
    XCTAssertFalse(AgentIOSObsidianProjectionPrivacyPolicy.safeKnowledge("api_key=sk-private"))
    XCTAssertTrue(AgentIOSObsidianProjectionPrivacyPolicy.safeKnowledge(
      "GalaxySSI uses background cognition for memory evolution."
    ))
  }

  func testPrivacyPolicyBlocksCredentialMetadataAndRedactsTranscript() {
    XCTAssertFalse(AgentIOSObsidianProjectionPrivacyPolicy.safeMetadata(
      "https://example.test/article?access_token=secret"
    ))
    XCTAssertTrue(AgentIOSObsidianProjectionPrivacyPolicy.safeMetadata(
      "https://example.test/article?id=42"
    ))
    XCTAssertEqual(
      AgentIOSObsidianProjectionPrivacyPolicy.transcriptText("My private key is abc123"),
      "[Sensitive content omitted by GalaxySSI]"
    )
  }

  @MainActor
  func testGeneratedNoteOmitsUnsafeSourceMetadata() {
    let note = AgentIOSObsidianBridge.note(
      sourceKey: "knowledge:test",
      type: "knowledge",
      title: "Runtime notes",
      source: "https://example.test/?access_token=secret",
      updatedAtMillis: 1_000,
      tags: ["runtime"],
      body: "Public runtime architecture"
    )

    XCTAssertTrue(note.contains("managed_by: galaxyssi"))
    XCTAssertTrue(note.contains("# Runtime notes"))
    XCTAssertFalse(note.contains("access_token"))
  }

  func testStateStoreEncryptsProjectionState() throws {
    let suite = "AgentIOSObsidianProjectionTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let stateStore = AgentIOSObsidianStateStore(
      defaults: defaults,
      secrets: InMemorySecretStore(),
      key: "obsidian-test"
    )
    stateStore.saveSettings(.init(enabled: true, bookmarkData: Data([1, 2, 3]), vaultName: "Vault"))

    XCTAssertEqual(stateStore.settings().vaultName, "Vault")
    XCTAssertNil(defaults.data(forKey: "obsidian-test"))
    XCTAssertNotNil(defaults.data(forKey: "obsidian-test.encrypted.v1"))
  }

  func testLegacySkillDocumentMigratesWithoutLosingInstallation() throws {
    let suite = "AgentIOSSkillMigrationTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = "legacy-skills"
    let installation = AgentSkillInstallation(
      manifest: AgentSkillManifest(
        id: "daily-news",
        name: "Daily news",
        version: "1.0.0",
        summary: "Find current news"
      ),
      installedAtMillis: 1_000
    )
    defaults.set(AgentSkillStoreCodec.encode([installation]), forKey: key)
    let store = UserDefaultsAgentSkillStore(
      defaults: defaults,
      key: key,
      secrets: InMemorySecretStore()
    )

    XCTAssertEqual(store.list().first?.id, "daily-news")
    XCTAssertNil(defaults.string(forKey: key))
    XCTAssertNotNil(defaults.data(forKey: "\(key)-encrypted-v2.encrypted.v1"))
  }
}
