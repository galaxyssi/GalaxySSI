import XCTest
@testable import SignalASI

@MainActor
final class SignalASIBackupTests: XCTestCase {
  func testPBKDF2SHA256MatchesKnownVector() throws {
    let key = try SignalASIBackupManager.pbkdf2SHA256(
      password: "password",
      salt: Data("salt".utf8),
      iterations: 1,
      keyByteCount: 32
    )

    XCTAssertEqual(key.hexString(), "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
  }

  func testEncryptedBackupRootUsesAndroidCompatibleEnvelope() throws {
    let data = try SignalASIBackupManager.exportBackup(
      store: makeStore(),
      password: "password123",
      includeContacts: true,
      includeMessages: true,
      iterations: 32
    )
    let root = try SignalASIBackupManager.decodeRoot(from: data)

    XCTAssertEqual(SignalASIBackupManager.iterations, 180_000)
    XCTAssertEqual(root.version, 1)
    XCTAssertEqual(root.type, "signalasi_backup")
    XCTAssertEqual(root.kdf, "pbkdf2-hmac-sha256")
    XCTAssertEqual(root.cipher, "aes-256-gcm")
    XCTAssertEqual(root.iterations, 32)
    XCTAssertEqual(Data(base64Encoded: root.salt)?.count, 16)
    XCTAssertEqual(Data(base64Encoded: root.iv)?.count, 12)
    XCTAssertGreaterThan(Data(base64Encoded: root.ciphertext)?.count ?? 0, 16)
  }

  func testBackupRestoresCloudAPISecretsAndLocalState() throws {
    let store = makeStore()
    store.updateProfileName("Alice")
    _ = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.example.com/v1/chat/completions",
      apiKey: "sk-test",
      apiStyle: .openAICompatible
    )
    store.updateVoiceSettings {
      $0.wakeListeningEnabled = true
      $0.preferredLocaleIdentifier = "en-US"
    }
    store.updateLanguagePolicy {
      $0.responseLanguage = "zh-CN"
      $0.asrLanguage = "en-US"
      $0.ttsLanguage = "zh-TW"
    }
    _ = try store.addServerLink(from: pairingQRCode())
    store.markServerPaired(desktopId: "desktop-test")
    store.appendIncoming("desktop hello", from: "hermes")
    store.markContactRead("hermes", at: Date(timeIntervalSince1970: 2_000_000_000))
    store.appendOutgoing("hello desktop", to: "hermes", status: .sent)

    let encrypted = try SignalASIBackupManager.exportBackup(
      store: store,
      password: "password123",
      includeContacts: true,
      includeMessages: true,
      iterations: 32
    )
    let payload = try SignalASIBackupManager.importBackup(data: encrypted, password: "password123")
    let restored = makeStore()
    try restored.restoreBackupPayload(payload)

    XCTAssertEqual(restored.profile.name, "Alice")
    XCTAssertEqual(restored.voiceSettings.preferredLocaleIdentifier, "en_US")
    XCTAssertEqual(restored.languagePolicy.responseLanguage, "zh-CN")
    XCTAssertEqual(restored.languagePolicy.ttsLanguage, "zh-TW")
    XCTAssertTrue(restored.voiceSettings.wakeListeningEnabled)
    XCTAssertEqual(restored.serverLinks.first?.desktopId, "desktop-test")
    XCTAssertEqual(restored.messages(for: "hermes").last?.content, "hello desktop")
    XCTAssertEqual(restored.conversationSummary(for: "hermes").unreadCount, 0)
    let cloudContact = try XCTUnwrap(restored.contact(id: "cloud:openai"))
    XCTAssertEqual(cloudContact.cloudModels.count, 1)
    XCTAssertEqual(restored.apiKey(for: cloudContact.cloudModels[0]), "sk-test")
  }

  func testBackupRejectsWrongPassword() throws {
    let encrypted = try SignalASIBackupManager.exportBackup(
      store: makeStore(),
      password: "password123",
      includeContacts: true,
      includeMessages: true,
      iterations: 32
    )

    XCTAssertThrowsError(try SignalASIBackupManager.importBackup(data: encrypted, password: "not-right"))
  }

  func testBackupRejectsShortPassword() {
    XCTAssertThrowsError(try SignalASIBackupManager.exportBackup(
      store: makeStore(),
      password: "short",
      includeContacts: true,
      includeMessages: true,
      iterations: 32
    ))
  }

  private func makeStore() -> SignalASIStore {
    let suite = "SignalASIBackupTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return SignalASIStore(defaults: defaults, secrets: InMemorySecretStore())
  }

  private func pairingQRCode() -> PairingQRCode {
    PairingQRCode(
      desktopId: "desktop-test",
      desktopName: "Test Mac",
      desktopFingerprint: String(repeating: "a", count: 64),
      serverRouteId: "abcdefghijklmnopqrstuv",
      pairingTopic: "signalasichat/v1/abcdefghijklmnopqrstuv/pair",
      pairingToken: String(repeating: "t", count: 32),
      pairingSecret: Data(repeating: 3, count: 32),
      access: PairingAccess(
        profile: SignalASILinkProtocol.accessRestricted,
        scopes: [
          SignalASILinkProtocol.scopeAgentChat,
          SignalASILinkProtocol.scopeExplicitAttachments,
          SignalASILinkProtocol.scopeTaskWorkspace
        ]
      ),
      controlAuthorizationToken: "",
      raw: [:]
    )
  }
}
