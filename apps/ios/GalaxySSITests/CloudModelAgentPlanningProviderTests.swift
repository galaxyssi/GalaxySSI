import Foundation
import XCTest
@testable import GalaxySSI

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
    let disclosureStore = InMemoryAgentDataDisclosureStore()
    let provider = CloudModelAgentPlanningProvider(
      contact: contact,
      store: store,
      sender: sender,
      disclosureStore: disclosureStore
    )

    let raw = try await provider.rawPlan(invocation: invocation(systemPrompt: "system", prompt: "planner prompt"))

    let call = sender.calls.singleValue()
    XCTAssertEqual(raw, #"{"actions":[{"kind":"READ_SCREEN","parameters":{}}]}"#)
    XCTAssertEqual(call.contact.id, contact.id)
    XCTAssertTrue(call.store === store)
    XCTAssertEqual(call.systemPrompt, "system")
    XCTAssertEqual(call.prompt, "planner prompt")
    let record = try XCTUnwrap(disclosureStore.list().first)
    XCTAssertEqual(record.destinationId, contact.id)
    XCTAssertEqual(record.status, .sent)
    XCTAssertEqual(record.purpose, "Agent planning request")
    XCTAssertTrue(record.dataKinds.contains(.messageText))
    XCTAssertTrue(record.dataKinds.contains(.systemInstructions))
    XCTAssertEqual(record.location, .cloud)
  }

  func testCloudModelAgentPlanningProviderBlocksDisallowedDestinationBeforeSending() async throws {
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
    let sender = RecordingStructuredSender(raw: "{}")
    let disclosureStore = InMemoryAgentDataDisclosureStore()
    disclosureStore.setDestinationBlocked(destinationId: contact.id, blocked: true)
    let provider = CloudModelAgentPlanningProvider(
      contact: contact,
      store: store,
      sender: sender,
      disclosureStore: disclosureStore
    )

    do {
      _ = try await provider.rawPlan(invocation: invocation(systemPrompt: "system", prompt: "planner prompt"))
      XCTFail("Expected blocked destinations to stop the model request.")
    } catch is AgentDataDisclosureBlockedError {
      XCTAssertTrue(true)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertTrue(sender.calls.isEmpty)
    let record = try XCTUnwrap(disclosureStore.list().first)
    XCTAssertEqual(record.status, .blocked)
    XCTAssertEqual(record.destinationId, contact.id)
  }

  func testCloudModelNativeToolAdapterForwardsNativeToolTurns() async throws {
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
    let catalog = [try nativeToolDescriptor(id: "phone.test.echo")]
    let sender = RecordingNativeToolSender(response: AgentModelResponse(assistantText: "Done"))
    let disclosureStore = InMemoryAgentDataDisclosureStore()
    let adapter = CloudModelNativeToolAdapter(
      contact: contact,
      store: store,
      catalog: catalog,
      sender: sender,
      disclosureStore: disclosureStore
    )
    let request = AgentModelRequest(
      sessionId: "session-1",
      conversationId: "conversation-1",
      turnId: "turn-1",
      taskId: "task-1",
      workspaceId: "workspace-1",
      round: 1,
      messages: [.user("Use the phone tool.")],
      toolManifestJson: "{}",
      toolManifestSha256: "hash",
      remainingToolCalls: 4,
      remainingTokens: 1_000,
      remainingTimeMillis: 10_000,
      maxDepth: 2,
      cancellationToken: .none
    )

    let response = try await adapter.complete(request)

    let call = try sender.calls.singleValue()
    XCTAssertEqual(response.assistantText, "Done")
    XCTAssertEqual(call.contact.id, contact.id)
    XCTAssertTrue(call.store === store)
    XCTAssertEqual(call.request.turnId, "turn-1")
    XCTAssertEqual(call.catalog.map(\.id), ["phone.test.echo"])
    let record = try XCTUnwrap(disclosureStore.list().first)
    XCTAssertEqual(record.destinationId, contact.id)
    XCTAssertEqual(record.status, .sent)
    XCTAssertEqual(record.purpose, "Model native tool turn")
    XCTAssertEqual(record.conversationIdHash.count, 64)
    XCTAssertTrue(record.dataKinds.contains(.messageText))
  }

  func testCloudModelNativeToolAdapterBlocksDisallowedDestinationBeforeSending() async throws {
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
    let sender = RecordingNativeToolSender(response: AgentModelResponse(assistantText: "Done"))
    let disclosureStore = InMemoryAgentDataDisclosureStore()
    disclosureStore.setDestinationBlocked(destinationId: contact.id, blocked: true)
    let adapter = CloudModelNativeToolAdapter(
      contact: contact,
      store: store,
      catalog: [try nativeToolDescriptor(id: "phone.test.echo")],
      sender: sender,
      disclosureStore: disclosureStore
    )
    let request = AgentModelRequest(
      sessionId: "session-1",
      conversationId: "conversation-1",
      turnId: "turn-1",
      taskId: "task-1",
      workspaceId: "workspace-1",
      round: 1,
      messages: [.user("Use the phone tool.")],
      toolManifestJson: "{}",
      toolManifestSha256: "hash",
      remainingToolCalls: 4,
      remainingTokens: 1_000,
      remainingTimeMillis: 10_000,
      maxDepth: 2,
      cancellationToken: .none
    )

    do {
      _ = try await adapter.complete(request)
      XCTFail("Expected blocked destinations to stop native tool model turns.")
    } catch is AgentDataDisclosureBlockedError {
      XCTAssertTrue(true)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertTrue(sender.calls.isEmpty)
    let record = try XCTUnwrap(disclosureStore.list().first)
    XCTAssertEqual(record.status, .blocked)
    XCTAssertEqual(record.destinationId, contact.id)
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
    } catch GalaxySSIError.missingAPIKey {
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
          screen: AgentScreenContext(foregroundApp: "GalaxySSI"),
          targets: [],
          contextDigest: "cloud-planning-provider-test"
        )
      )
    )
  }

  private func makeStore(secrets: GalaxySSISecretStore) -> GalaxySSIStore {
    let suite = "CloudModelAgentPlanningProviderTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return GalaxySSIStore(defaults: defaults, secrets: secrets)
  }

  private func nativeToolDescriptor(id: String) throws -> AgentNativeToolDescriptor {
    try AgentNativeToolDescriptor(
      id: id,
      version: "1.0.0",
      title: id,
      description: "Cloud native tool adapter test tool.",
      location: .phone,
      inputSchema: AgentNativeToolDescriptor.objectSchema(),
      outputSchema: AgentNativeToolDescriptor.objectSchema(),
      risk: .low
    )
  }
}

private final class RecordingStructuredSender: CloudModelStructuredSending {
  struct Call {
    var contact: GalaxySSIContact
    var store: GalaxySSIStore
    var systemPrompt: String
    var prompt: String
  }

  var raw: String
  var calls: [Call] = []

  init(raw: String) {
    self.raw = raw
  }

  func sendStructured(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    systemPrompt: String,
    prompt: String
  ) async throws -> String {
    calls.append(Call(contact: contact, store: store, systemPrompt: systemPrompt, prompt: prompt))
    return raw
  }
}

private final class RecordingNativeToolSender: CloudModelNativeToolSending {
  struct Call {
    var contact: GalaxySSIContact
    var store: GalaxySSIStore
    var request: AgentModelRequest
    var catalog: [AgentNativeToolDescriptor]
  }

  var response: AgentModelResponse
  var calls: [Call] = []

  init(response: AgentModelResponse) {
    self.response = response
  }

  func sendNativeToolTurn(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    request: AgentModelRequest,
    catalog: [AgentNativeToolDescriptor]
  ) async throws -> AgentModelResponse {
    calls.append(Call(contact: contact, store: store, request: request, catalog: catalog))
    return response
  }
}

private extension Array {
  func singleValue(file: StaticString = #filePath, line: UInt = #line) -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    return self[0]
  }
}
