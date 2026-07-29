import XCTest
@testable import SignalASI

@MainActor
final class SignalASIStoreTests: XCTestCase {
  func testInitialStoreContainsAndroidParityContacts() {
    let store = makeStore()

    XCTAssertNotNil(store.contact(id: "hermes"))
    XCTAssertEqual(store.contact(id: "system")?.trustState, .verified)
    XCTAssertTrue(store.profile.identityFingerprint.count == 64)
  }

  func testContactSearchMatchesAndroidNameAndIdFiltering() throws {
    let store = makeStore()
    let request = store.addFriendRequest(makeFriendRequest(signalASIId: "friend-alice", name: "Alice"))
    XCTAssertTrue(store.approveFriendRequest(id: request.id))
    _ = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "gpt-5",
      endpoint: "https://api.example.com/v1/chat/completions",
      apiKey: "key-a",
      apiStyle: .openAICompatible
    )

    XCTAssertEqual(store.visibleContacts(matching: "alice").map(\.id), ["friend-alice"])
    XCTAssertEqual(store.visibleContacts(matching: "cloud:openai").map(\.id), ["cloud:openai"])
    XCTAssertEqual(store.contactList(matching: "gpt-5").map(\.id), ["cloud:openai"])
    XCTAssertTrue(store.visibleContacts(matching: "missing-contact").isEmpty)
  }

  func testCloudModelContactsAreGroupedByProvider() throws {
    let store = makeStore()

    _ = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.example.com/v1/chat/completions",
      apiKey: "key-a",
      apiStyle: .openAICompatible
    )
    let contact = try store.addCloudModelContact(
      displayName: "Model B",
      provider: "OpenAI",
      modelId: "model-b",
      endpoint: "https://api.example.com/v1/chat/completions",
      apiKey: "key-b",
      apiStyle: .openAICompatible
    )

    XCTAssertEqual(contact.id, "cloud:openai")
    XCTAssertEqual(contact.cloudModels.count, 2)
    XCTAssertEqual(store.contacts.filter { $0.id == "cloud:openai" }.count, 1)
    XCTAssertEqual(store.apiKey(for: contact.cloudModels[1]), "key-b")
  }

  func testRenamesContactLocally() {
    let store = makeStore()
    let request = store.addFriendRequest(makeFriendRequest(signalASIId: "friend-alice", name: "Alice"))
    XCTAssertTrue(store.approveFriendRequest(id: request.id))

    XCTAssertTrue(store.renameContact(id: "friend-alice", displayName: "  Alice Remark  "))

    let contact = store.contact(id: "friend-alice")
    XCTAssertEqual(contact?.name, "Alice Remark")
    XCTAssertEqual(contact?.displayName, "Alice Remark")
  }

  func testDeleteContactSoftDeletesAndOptionallyRemovesMessages() {
    let store = makeStore()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let request = store.addFriendRequest(makeFriendRequest(signalASIId: "friend-bob", name: "Bob"))
    XCTAssertTrue(store.approveFriendRequest(id: request.id))
    store.appendOutgoing("hello", to: "friend-bob")

    XCTAssertTrue(store.deleteContact(id: "friend-bob", deleteMessages: true, now: now))

    let contact = store.contact(id: "friend-bob")
    XCTAssertEqual(contact?.deleted, true)
    XCTAssertEqual(contact?.trustState, .deleted)
    XCTAssertEqual(contact?.deletedAt, now)
    XCTAssertTrue(store.messages(for: "friend-bob").isEmpty)
    XCTAssertEqual(store.friendRequest(id: request.id)?.status, .deleted)
    XCTAssertEqual(store.friendRequest(id: request.id)?.readdRequired, true)
  }

  func testDeleteMessageRemovesOnlyTargetMessage() {
    let store = makeStore()
    let first = store.appendOutgoing("first", to: "hermes")
    let second = store.appendOutgoing("second", to: "hermes")

    XCTAssertTrue(store.deleteMessage(first.id, contactId: "hermes"))

    XCTAssertEqual(store.messages(for: "hermes").map(\.content), [
      "Pair SignalASI Desktop to start a trusted Link conversation.",
      "second"
    ])
    XCTAssertFalse(store.deleteMessage(first.id, contactId: "hermes"))
    XCTAssertEqual(store.messages(for: "hermes").last?.id, second.id)
  }

  func testDeleteChatHistoryKeepsContact() {
    let store = makeStore()
    store.appendOutgoing("hello", to: "hermes")

    store.deleteMessages(for: "hermes")

    XCTAssertTrue(store.messages(for: "hermes").isEmpty)
    XCTAssertNotNil(store.contact(id: "hermes"))
    XCTAssertEqual(store.contact(id: "hermes")?.deleted, false)
  }

  func testDeliveryTraceStageLabelsMatchAndroidActions() {
    XCTAssertEqual(DeliveryTraceEvent(stage: "mqtt_published").displayTitle, "Published to MQTT")
    XCTAssertEqual(DeliveryTraceEvent(stage: "desktop_decrypted").displayTitle, "Desktop decrypted")
    XCTAssertEqual(DeliveryTraceEvent(stage: "cloud_request").displayTitle, "Model request")
    XCTAssertEqual(DeliveryTraceEvent(stage: "unknown_stage").displayTitle, "unknown_stage")
  }

  func testMessageStatusUpdatesExposeReadableDeliveryTrace() {
    let store = makeStore()
    let message = store.appendOutgoing("hello", to: "hermes")

    store.markMessage(message.id, contactId: "hermes", status: .sent, detail: "QoS accepted")

    let updated = store.messages(for: "hermes").first { $0.id == message.id }
    XCTAssertEqual(updated?.deliveryTrace.map(\.displayTitle), ["Queued", "Sent"])
    XCTAssertEqual(updated?.deliveryTrace.last?.detail, "QoS accepted")
  }

  func testAppendDeliveryTraceUpdatesStatusAndKeepsPriorStages() {
    let store = makeStore()
    let message = store.appendOutgoing("hello", to: "hermes")

    XCTAssertTrue(store.appendDeliveryTrace(
      message.id,
      contactId: "hermes",
      stage: "mqtt_published",
      detail: "signalasi/topic",
      status: .sent
    ))

    let updated = store.messages(for: "hermes").first { $0.id == message.id }
    XCTAssertEqual(updated?.deliveryStatus, .sent)
    XCTAssertEqual(updated?.deliveryTrace.map(\.stage), ["queued", "mqtt_published"])
    XCTAssertEqual(updated?.deliveryTrace.last?.detail, "signalasi/topic")
  }

  func testDeletingHermesClearsServerLinks() throws {
    let store = makeStore()
    _ = try store.addServerLink(from: makePairingQRCode())

    XCTAssertEqual(store.serverLinks.count, 1)
    XCTAssertTrue(store.deleteContact(id: "hermes"))

    XCTAssertTrue(store.serverLinks.isEmpty)
    XCTAssertEqual(store.contact(id: "hermes")?.trustState, .deleted)
  }

  func testDestroyAllPrivateDataRegeneratesIdentityAndClearsSecrets() throws {
    let secrets = InMemorySecretStore()
    let store = makeStore(secrets: secrets)
    let originalSignalASIId = store.profile.signalASIId
    let originalIdentitySecret = secrets.string(account: "identity.p256.private")
    let contact = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.example.com/v1/chat/completions",
      apiKey: "secret-key",
      apiStyle: .openAICompatible
    )
    let keychainAccount = contact.cloudModels[0].keychainAccount
    _ = try store.addServerLink(from: makePairingQRCode())
    store.appendOutgoing("private note", to: "hermes")
    store.updateVoiceSettings { settings in
      settings.wakeListeningEnabled = true
    }

    store.destroyAllPrivateData()

    XCTAssertNotEqual(store.profile.signalASIId, originalSignalASIId)
    XCTAssertNotEqual(secrets.string(account: "identity.p256.private"), originalIdentitySecret)
    XCTAssertNil(secrets.string(account: keychainAccount))
    XCTAssertNotNil(store.contact(id: "hermes"))
    XCTAssertNil(store.contact(id: "cloud:openai"))
    XCTAssertTrue(store.friendRequests.isEmpty)
    XCTAssertTrue(store.serverLinks.isEmpty)
    XCTAssertEqual(store.messages(for: "hermes").count, 1)
    XCTAssertEqual(store.voiceSettings, .default)
  }

  func testSelectingCloudModelChangesProviderActiveModel() throws {
    let store = makeStore()

    _ = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.openai.com/v1/chat/completions",
      apiKey: "key-a",
      apiStyle: .openAICompatible
    )
    _ = try store.addCloudModelContact(
      displayName: "Model B",
      provider: "OpenAI",
      modelId: "model-b",
      endpoint: "https://api.openai.com/v1/chat/completions",
      apiKey: "key-b",
      apiStyle: .openAICompatible
    )

    XCTAssertTrue(store.setSelectedCloudModel(contactId: "cloud:openai", modelId: "model-b"))

    let contact = store.contact(id: "cloud:openai")
    XCTAssertEqual(contact?.selectedCloudModelId, "model-b")
    XCTAssertEqual(contact?.selectedCloudModel?.displayName, "Model B")
  }

  func testDeletingSelectedCloudModelRemovesSecretAndFallsBack() throws {
    let secrets = InMemorySecretStore()
    let store = makeStore(secrets: secrets)
    _ = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.openai.com/v1/chat/completions",
      apiKey: "key-a",
      apiStyle: .openAICompatible
    )
    _ = try store.addCloudModelContact(
      displayName: "Model B",
      provider: "OpenAI",
      modelId: "model-b",
      endpoint: "https://api.openai.com/v1/chat/completions",
      apiKey: "key-b",
      apiStyle: .openAICompatible
    )
    XCTAssertTrue(store.setSelectedCloudModel(contactId: "cloud:openai", modelId: "model-b"))
    let removedAccount = store.contact(id: "cloud:openai")!.cloudModels[1].keychainAccount

    XCTAssertTrue(store.deleteCloudModel(contactId: "cloud:openai", modelId: "model-b"))

    let contact = store.contact(id: "cloud:openai")
    XCTAssertNil(secrets.string(account: removedAccount))
    XCTAssertEqual(contact?.cloudModels.map(\.modelId), ["model-a"])
    XCTAssertEqual(contact?.selectedCloudModelId, "model-a")
    XCTAssertEqual(contact?.deleted, false)
  }

  func testDeletingLastCloudModelHidesProviderContact() throws {
    let store = makeStore()
    _ = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.openai.com/v1/chat/completions",
      apiKey: "key-a",
      apiStyle: .openAICompatible
    )

    XCTAssertTrue(store.deleteCloudModel(contactId: "cloud:openai", modelId: "model-a"))

    XCTAssertEqual(store.contact(id: "cloud:openai")?.deleted, true)
    XCTAssertTrue(store.cloudModelContacts.isEmpty)
  }

  func testCloudModelCredentialPolicyRejectsPlaceholders() {
    XCTAssertFalse(CloudModelCredentialPolicy.isStoredCredential(""))
    XCTAssertFalse(CloudModelCredentialPolicy.isStoredCredential("****-key"))
    XCTAssertFalse(CloudModelCredentialPolicy.isStoredCredential("your-api-key"))
    XCTAssertFalse(CloudModelCredentialPolicy.isAutoRoutableCredential("sk-signalasi-smoke-key"))
    XCTAssertTrue(CloudModelCredentialPolicy.isStoredCredential("sk-live-key"))
  }

  func testCloudClientRejectsPlaceholderCredentialBeforeNetwork() async throws {
    let secrets = InMemorySecretStore()
    let store = makeStore(secrets: secrets)
    let contact = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.openai.com/v1/chat/completions",
      apiKey: "sk-live-key",
      apiStyle: .openAICompatible
    )
    let model = contact.cloudModels[0]
    try secrets.setString("your-api-key", account: model.keychainAccount)

    do {
      _ = try await CloudModelClient().send(
        contact: store.contact(id: "cloud:openai")!,
        store: store,
        turns: [ChatMessage(contactId: "cloud:openai", content: "hello", isMine: true)]
      )
      XCTFail("Expected placeholder credentials to fail before a network request.")
    } catch SignalASIError.missingAPIKey {
      XCTAssertTrue(true)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private func makeStore() -> SignalASIStore {
    makeStore(secrets: InMemorySecretStore())
  }

  private func makeStore(secrets: SignalASISecretStore) -> SignalASIStore {
    let suite = "SignalASIStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return SignalASIStore(defaults: defaults, secrets: secrets)
  }

  private func makeFriendRequest(signalASIId: String, name: String) -> SignalASIFriendRequest {
    SignalASIFriendRequest(
      id: "req-\(signalASIId)",
      signalASIId: signalASIId,
      name: name,
      type: "person",
      identityPublicKey: "public-key-\(signalASIId)",
      identityFingerprint: String(repeating: "a", count: 64),
      mqttTopic: "signalasi/contact/\(signalASIId)",
      mqttInboxTopic: "signalasi/contact/\(signalASIId)/inbox"
    )
  }

  private func makePairingQRCode() -> PairingQRCode {
    PairingQRCode(
      desktopId: "desktop-1",
      desktopName: "SignalASI Desktop",
      desktopFingerprint: String(repeating: "f", count: 64),
      serverRouteId: "abcdefghijklmnopqrstuv",
      pairingTopic: "signalasi/pair",
      pairingToken: "pairing-token",
      pairingSecret: Data(repeating: 1, count: 32),
      access: PairingAccess(
        profile: SignalASILinkProtocol.accessDesktopExecutor,
        scopes: [SignalASILinkProtocol.scopeDesktopExecutor]
      ),
      controlAuthorizationToken: "control-token",
      raw: [:]
    )
  }
}
