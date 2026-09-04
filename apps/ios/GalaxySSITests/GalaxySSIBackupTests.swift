import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIBackupTests: XCTestCase {
  func testPBKDF2SHA256MatchesKnownVector() throws {
    let key = try GalaxySSIBackupManager.pbkdf2SHA256(
      password: "password",
      salt: Data("salt".utf8),
      iterations: 1,
      keyByteCount: 32
    )

    XCTAssertEqual(key.hexString(), "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
  }

  func testEncryptedBackupRootUsesAndroidCompatibleEnvelope() throws {
    let data = try GalaxySSIBackupManager.exportBackup(
      store: makeStore(),
      password: "password123",
      includeContacts: true,
      includeMessages: true,
      iterations: 32
    )
    let root = try GalaxySSIBackupManager.decodeRoot(from: data)

    XCTAssertEqual(GalaxySSIBackupManager.iterations, 180_000)
    XCTAssertEqual(root.version, 1)
    XCTAssertEqual(root.type, "galaxyssi_backup")
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
      $0.wakeWords = ["GalaxySSI", "custom wake"]
      $0.wakeProvider = .androidASR
      $0.wakeModel = VoiceSettings.defaultWakeModel
      $0.wakeThreshold = 0.72
      $0.welcomeText = "Ready for voice work."
      $0.asrProvider = .localWhisperCpp
      $0.asrModelId = "base"
      $0.asrRuntimeMode = .accurate
      $0.ttsProvider = .microsoftEdge
      $0.microsoftVoice = "zh-CN-YunxiNeural"
      $0.targetContactId = "cloud:openai"
      $0.speakReplies = false
      $0.routingMode = .contact
    }
    store.updateLanguagePolicy {
      $0.responseLanguage = "zh-CN"
      $0.asrLanguage = "en-US"
      $0.ttsLanguage = "zh-TW"
    }
    store.updateDisplaySettings {
      $0.textScale = .extraLarge
    }
    store.updateAgentSafetySettings {
      $0.taskExecutionMode = .planOnly
      $0.permissionMode = .autoLowRisk
      $0.highRiskGuard = false
      $0.memoryCapture = false
      $0.connectorCallsAllowed = false
      $0.executionPaused = true
    }
    store.selectAgentTaskBudgetProfile(.privateMode)
    store.updateAgentTaskBudget {
      $0.maxInputTokens = 42_000
      $0.networkPolicy = .offlineOnly
      $0.allowPaidProviders = false
    }
    store.upsertCustomDeviceConnector(
      CustomDeviceConnector(
        id: "custom-device-office",
        name: "Office Light",
        transport: .mqtt,
        endpoint: "mqtt://broker.local",
        commandTarget: "topic/light/office",
        username: "user",
        authToken: "device-token",
        risk: .high
      )
    )
    store.updateHomeAssistantSettings {
      $0.enabled = true
      $0.baseUrl = "http://homeassistant.local:8123/"
      $0.accessToken = "ha-token"
      $0.defaultEntityId = "light.office"
    }
    store.updateModelPlannerSettings {
      $0.enabled = true
      $0.cloudContactId = "cloud:openai"
      $0.dynamicReplanning = false
      $0.maxReplans = 5
      $0.shareAgentOutputsWithPlanner = true
      $0.maxToolCalls = 24
      $0.noProgressTimeoutSeconds = 600
    }
    _ = try store.addServerLink(from: pairingQRCode())
    store.markServerPaired(desktopId: "desktop-test")
    store.appendIncoming("desktop hello", from: "hermes")
    store.markContactRead("hermes", at: Date(timeIntervalSince1970: 2_000_000_000))
    store.appendOutgoing("hello desktop", to: "hermes", status: .sent)

    let encrypted = try GalaxySSIBackupManager.exportBackup(
      store: store,
      password: "password123",
      includeContacts: true,
      includeMessages: true,
      iterations: 32
    )
    let payload = try GalaxySSIBackupManager.importBackup(data: encrypted, password: "password123")
    XCTAssertTrue(payload.privacyManifest.includesDisplaySettings)
    XCTAssertTrue(payload.privacyManifest.includesAgentSafetySettings)
    XCTAssertTrue(payload.privacyManifest.includesAgentTaskBudget)
    XCTAssertTrue(payload.privacyManifest.includesCustomDeviceConnectors)
    XCTAssertTrue(payload.privacyManifest.includesHomeAssistantSettings)
    XCTAssertTrue(payload.privacyManifest.includesModelPlannerSettings)
    let restored = makeStore()
    try restored.restoreBackupPayload(payload)

    XCTAssertEqual(restored.profile.name, "Alice")
    XCTAssertEqual(restored.voiceSettings.preferredLocaleIdentifier, "en_US")
    XCTAssertEqual(restored.languagePolicy.responseLanguage, "zh-CN")
    XCTAssertEqual(restored.languagePolicy.ttsLanguage, "zh-TW")
    XCTAssertEqual(restored.displaySettings.textScale, .extraLarge)
    XCTAssertEqual(restored.agentSafetySettings.taskExecutionMode, .planOnly)
    XCTAssertEqual(restored.agentSafetySettings.permissionMode, .autoLowRisk)
    XCTAssertFalse(restored.agentSafetySettings.highRiskGuard)
    XCTAssertFalse(restored.agentSafetySettings.memoryCapture)
    XCTAssertFalse(restored.agentSafetySettings.connectorCallsAllowed)
    XCTAssertTrue(restored.agentSafetySettings.executionPaused)
    XCTAssertEqual(restored.agentTaskBudget.profile, .custom)
    XCTAssertEqual(restored.agentTaskBudget.maxInputTokens, 42_000)
    XCTAssertEqual(restored.agentTaskBudget.networkPolicy, .offlineOnly)
    XCTAssertFalse(restored.agentTaskBudget.allowPaidProviders)
    XCTAssertEqual(restored.customDeviceConnectors.count, 1)
    XCTAssertEqual(restored.customDeviceConnectors[0].id, "custom-device-office")
    XCTAssertEqual(restored.customDeviceConnectors[0].transport, .mqtt)
    XCTAssertEqual(restored.customDeviceConnectors[0].authToken, "device-token")
    XCTAssertEqual(restored.customDeviceConnectors[0].risk, .high)
    XCTAssertTrue(restored.homeAssistantSettings.configured)
    XCTAssertEqual(restored.homeAssistantSettings.baseUrl, "http://homeassistant.local:8123")
    XCTAssertEqual(restored.homeAssistantSettings.accessToken, "ha-token")
    XCTAssertEqual(restored.homeAssistantSettings.defaultEntityId, "light.office")
    XCTAssertTrue(restored.modelPlannerSettings.enabled)
    XCTAssertEqual(restored.modelPlannerSettings.cloudContactId, "cloud:openai")
    XCTAssertFalse(restored.modelPlannerSettings.dynamicReplanning)
    XCTAssertEqual(restored.modelPlannerSettings.maxReplans, 5)
    XCTAssertTrue(restored.modelPlannerSettings.shareAgentOutputsWithPlanner)
    XCTAssertEqual(restored.modelPlannerSettings.maxToolCalls, 24)
    XCTAssertEqual(restored.modelPlannerSettings.noProgressTimeoutSeconds, 600)
    XCTAssertTrue(restored.voiceSettings.wakeListeningEnabled)
    XCTAssertEqual(restored.voiceSettings.wakeWords, ["GalaxySSI", "custom wake"])
    XCTAssertEqual(restored.voiceSettings.wakeProvider, .androidASR)
    XCTAssertEqual(restored.voiceSettings.wakeModel, VoiceSettings.defaultWakeModel)
    XCTAssertEqual(restored.voiceSettings.wakeThreshold, 0.72)
    XCTAssertEqual(restored.voiceSettings.welcomeText, "Ready for voice work.")
    XCTAssertEqual(restored.voiceSettings.asrProvider, .localWhisperCpp)
    XCTAssertEqual(restored.voiceSettings.asrModelId, "base")
    XCTAssertEqual(restored.voiceSettings.asrRuntimeMode, .accurate)
    XCTAssertEqual(restored.voiceSettings.ttsProvider, .microsoftEdge)
    XCTAssertEqual(restored.voiceSettings.microsoftVoice, "zh-CN-YunxiNeural")
    XCTAssertEqual(restored.voiceSettings.targetContactId, "cloud:openai")
    XCTAssertFalse(restored.voiceSettings.speakReplies)
    XCTAssertEqual(restored.voiceSettings.routingMode, .contact)
    XCTAssertEqual(restored.serverLinks.first?.desktopId, "desktop-test")
    XCTAssertEqual(restored.messages(for: "hermes").last?.content, "hello desktop")
    XCTAssertEqual(restored.conversationSummary(for: "hermes").unreadCount, 0)
    let cloudContact = try XCTUnwrap(restored.contact(id: "cloud:openai"))
    XCTAssertEqual(cloudContact.cloudModels.count, 1)
    XCTAssertEqual(restored.apiKey(for: cloudContact.cloudModels[0]), "sk-test")
  }

  func testBackupRejectsWrongPassword() throws {
    let encrypted = try GalaxySSIBackupManager.exportBackup(
      store: makeStore(),
      password: "password123",
      includeContacts: true,
      includeMessages: true,
      iterations: 32
    )

    XCTAssertThrowsError(try GalaxySSIBackupManager.importBackup(data: encrypted, password: "not-right"))
  }

  func testBackupRejectsShortPassword() {
    XCTAssertThrowsError(try GalaxySSIBackupManager.exportBackup(
      store: makeStore(),
      password: "short",
      includeContacts: true,
      includeMessages: true,
      iterations: 32
    ))
  }

  private func makeStore() -> GalaxySSIStore {
    let suite = "GalaxySSIBackupTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return GalaxySSIStore(defaults: defaults, secrets: InMemorySecretStore())
  }

  private func pairingQRCode() -> PairingQRCode {
    PairingQRCode(
      desktopId: "desktop-test",
      desktopName: "Test Mac",
      desktopFingerprint: String(repeating: "a", count: 64),
      pairingTopic: GalaxySSILinkProtocol.pairingTopic(
        secret: Data(repeating: 3, count: 32).base64URLEncodedString()
      ),
      pairingToken: String(repeating: "t", count: 43),
      pairingSecret: Data(repeating: 3, count: 32),
      access: PairingAccess(
        profile: GalaxySSILinkProtocol.accessRestricted,
        scopes: [
          GalaxySSILinkProtocol.scopeAgentChat,
          GalaxySSILinkProtocol.scopeExplicitAttachments,
          GalaxySSILinkProtocol.scopeTaskWorkspace
        ]
      ),
      controlAuthorizationToken: "",
      raw: [:]
    )
  }
}
