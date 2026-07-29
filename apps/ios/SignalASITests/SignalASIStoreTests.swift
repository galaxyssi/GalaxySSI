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

  private func makeStore() -> SignalASIStore {
    let suite = "SignalASIStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return SignalASIStore(defaults: defaults, secrets: InMemorySecretStore())
  }
}
