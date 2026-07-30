import Foundation
import XCTest
@testable import SignalASI

@MainActor
final class CloudModelAgentPlanningProviderTests: XCTestCase {
  func testCloudModelAgentPlanningProviderForwardsStructuredInvocation() async throws {
    let secrets = InMemorySecretStore()
    let store = makeStore(secrets: secrets)
    let contact = try store.addCloudModelContact(
      displayName: "Planner",
      provider: "OpenAI",
      modelId: "planner-model",
      endpoint: "https://api.openai.com/v1/chat/completions",
      apiKey: "sk-live-key",
      apiStyle: .openAICompatible
    )
    let sender = RecordingStructuredSender(raw: #"{"actions":[{"kind":"READ_SCREEN","parameters":{}}]}"#)
    let provider = CloudModelAgentPlanningProvider(contact: contact, store: store, sender: sender)

    let raw = try await provider.rawPlan(invocation: invocation(systemPrompt: "system", prompt: "planner prompt"))

    let call = sender.calls.singleValue()
    XCTAssertEqual(raw, #"{"actions":[{"kind":"READ_SCREEN","parameters":{}}]}"#)
    XCTAssertEqual(call.contact.id, contact.id)
    XCTAssertTrue(call.store === store)
    XCTAssertEqual(call.systemPrompt, "system")
    XCTAssertEqual(call.prompt, "planner prompt")
  }

  func testCloudModelClientStructuredRejectsPlaceholderCredentialBeforeNetwork() async throws {
    let secrets = InMemorySecretStore()
    let store = makeStore(secrets: secrets)
    let contact = try store.addCloudModelContact(
      displayName: "Planner",
      provider: "OpenAI",
      modelId: "planner-model",
      endpoint: "https://api.openai.com/v1/chat/completions",
      apiKey: "sk-live-key",
      apiStyle: .openAICompatible
    )
    let model = contact.cloudModels[0]
    try secrets.setString("your-api-key", account: model.keychainAccount)

    do {
      _ = try await CloudModelClient().sendStructured(
        contact: contact,
        store: store,
        systemPrompt: AgentModelPlanningPrompt.systemPrompt,
        prompt: "Return a JSON plan"
      )
      XCTFail("Expected placeholder credentials to fail before a network request.")
    } catch SignalASIError.missingAPIKey {
      XCTAssertTrue(true)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private func invocation(systemPrompt: String, prompt: String) -> AgentModelPlanningInvocation {
    AgentModelPlanningInvocation(
      systemPrompt: systemPrompt,
      prompt: prompt,
      nativeTools: [],
      request: AgentModelPlanningPromptRequest(
        planRequest: AgentPlanRequest(
          goal: "Plan this task",
          screen: AgentScreenContext(foregroundApp: "SignalASI"),
          targets: [],
          contextDigest: "cloud-planning-provider-test"
        )
      )
    )
  }

  private func makeStore(secrets: SignalASISecretStore) -> SignalASIStore {
    let suite = "CloudModelAgentPlanningProviderTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return SignalASIStore(defaults: defaults, secrets: secrets)
  }
}

private final class RecordingStructuredSender: CloudModelStructuredSending {
  struct Call {
    var contact: SignalASIContact
    var store: SignalASIStore
    var systemPrompt: String
    var prompt: String
  }

  var raw: String
  var calls: [Call] = []

  init(raw: String) {
    self.raw = raw
  }

  func sendStructured(
    contact: SignalASIContact,
    store: SignalASIStore,
    systemPrompt: String,
    prompt: String
  ) async throws -> String {
    calls.append(Call(contact: contact, store: store, systemPrompt: systemPrompt, prompt: prompt))
    return raw
  }
}

private extension Array {
  func singleValue(file: StaticString = #filePath, line: UInt = #line) -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    return self[0]
  }
}
