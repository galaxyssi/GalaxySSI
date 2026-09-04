import Foundation

protocol CloudModelNativeToolSending {
  func sendNativeToolTurn(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    request: AgentModelRequest,
    catalog: [AgentNativeToolDescriptor]
  ) async throws -> AgentModelResponse
}

struct CloudModelNativeToolAdapter: AgentModelAdapter {
  var contact: GalaxySSIContact
  var store: GalaxySSIStore
  var catalog: [AgentNativeToolDescriptor]
  var sender: CloudModelNativeToolSending
  var disclosureStore: AgentDataDisclosureStore

  init(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    catalog: [AgentNativeToolDescriptor],
    sender: CloudModelNativeToolSending = CloudModelClient(),
    disclosureStore: AgentDataDisclosureStore = FileAgentDataDisclosureStore(
      fileURL: AgentDataDisclosureStorePaths.ledgerURL()
    )
  ) {
    self.contact = contact
    self.store = store
    self.catalog = catalog
    self.sender = sender
    self.disclosureStore = disclosureStore
  }

  func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
    let ticket = AgentDataDisclosureLedger.beginCloudRequest(
      store: disclosureStore,
      destination: AgentDataDisclosureCloudDestination(contact: contact),
      text: request.messages.map(\.text).joined(separator: "\n"),
      historyCount: request.messages.count,
      systemInstructions: request.messages.contains { $0.role == .system },
      toolOutput: request.messages.contains { $0.role == .tool },
      purpose: "Model native tool turn",
      conversationId: request.conversationId,
      taskId: request.taskId,
      turnId: request.turnId
    )
    guard ticket.allowed else {
      throw AgentDataDisclosureBlockedError(destination: contact.displayName)
    }

    do {
      let response = try await sender.sendNativeToolTurn(
        contact: contact,
        store: store,
        request: request,
        catalog: catalog
      )
      AgentDataDisclosureLedger.update(store: disclosureStore, ticket: ticket, status: .sent)
      return response
    } catch {
      AgentDataDisclosureLedger.update(
        store: disclosureStore,
        ticket: ticket,
        status: .failed,
        failureReason: error.localizedDescription
      )
      throw error
    }
  }
}

extension CloudModelClient: CloudModelNativeToolSending {
  func sendNativeToolTurn(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    request modelRequest: AgentModelRequest,
    catalog: [AgentNativeToolDescriptor]
  ) async throws -> AgentModelResponse {
    guard let model = contact.selectedCloudModel else {
      throw GalaxySSIError.missingCloudModel
    }
    guard let apiKey = await store.apiKey(for: model),
          CloudModelCredentialPolicy.isStoredCredential(apiKey) else {
      throw GalaxySSIError.missingAPIKey
    }

    let adapter = AgentModelToolProtocolAdapters.adapter(for: model.apiStyle.toolProvider)
    let request = try nativeToolRequest(
      model: model,
      apiKey: apiKey,
      modelRequest: modelRequest,
      catalog: catalog,
      adapter: adapter
    )
    let object = try await responseObject(for: request)
    let json = try CloudModelNativeToolJSON.responseString(object)
    return try adapter.decodeResponse(json, catalog: catalog)
  }

  private func nativeToolRequest(
    model: CloudModelConfig,
    apiKey: String,
    modelRequest: AgentModelRequest,
    catalog: [AgentNativeToolDescriptor],
    adapter: AgentModelToolProtocolAdapter
  ) throws -> URLRequest {
    switch model.apiStyle {
    case .openAICompatible:
      var request = try jsonRequest(url: model.endpoint, apiKey: apiKey)
      var body = try adapter.encodeConversation(modelRequest.messages)
      body["model"] = .string(model.modelId)
      body["tools"] = .array(try adapter.encodeToolCatalog(catalog))
      body["tool_choice"] = .string("auto")
      body["stream"] = .bool(false)
      request.httpBody = try CloudModelNativeToolJSON.requestData(body)
      return request

    case .anthropic:
      guard let url = URL(string: model.endpoint) else {
        throw GalaxySSIError.invalidPayload("Cloud endpoint is not a URL.")
      }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
      request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
      var body = try adapter.encodeConversation(modelRequest.messages)
      body["model"] = .string(model.modelId)
      body["tools"] = .array(try adapter.encodeToolCatalog(catalog))
      body["max_tokens"] = .int(CloudModelNativeToolJSON.outputTokenLimit(modelRequest.remainingTokens))
      request.httpBody = try CloudModelNativeToolJSON.requestData(body)
      return request

    case .gemini:
      var components = URLComponents(string: model.endpoint)
      var items = components?.queryItems ?? []
      items.append(URLQueryItem(name: "key", value: apiKey))
      components?.queryItems = items
      guard let url = components?.url else {
        throw GalaxySSIError.invalidPayload("Cloud endpoint is not a URL.")
      }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      var body = try adapter.encodeConversation(modelRequest.messages)
      body["tools"] = .array(try adapter.encodeToolCatalog(catalog))
      body["generationConfig"] = .object([
        "temperature": .double(0.1),
        "maxOutputTokens": .int(CloudModelNativeToolJSON.outputTokenLimit(modelRequest.remainingTokens))
      ])
      request.httpBody = try CloudModelNativeToolJSON.requestData(body)
      return request
    }
  }
}

private enum CloudModelNativeToolJSON {
  static func requestData(_ body: AgentMcpJSONObject) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(AgentMcpJSONValue.object(body))
  }

  static func responseString(_ object: [String: Any]) throws -> String {
    guard JSONSerialization.isValidJSONObject(object) else {
      throw GalaxySSIError.invalidPayload("Cloud tool response is not JSON encodable.")
    }
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    guard let text = String(data: data, encoding: .utf8) else {
      throw GalaxySSIError.unsupportedResponse
    }
    return text
  }

  static func outputTokenLimit(_ remainingTokens: Int64) -> Int64 {
    let positiveRemaining = remainingTokens > 0 ? remainingTokens : defaultOutputTokens
    return max(1, min(positiveRemaining, maximumOutputTokens))
  }

  private static let defaultOutputTokens: Int64 = 1_200
  private static let maximumOutputTokens: Int64 = 4_096
}

private extension GalaxySSICloudAPIStyle {
  var toolProvider: AgentModelToolProvider {
    switch self {
    case .openAICompatible:
      return .openAICompatible
    case .anthropic:
      return .anthropic
    case .gemini:
      return .gemini
    }
  }
}
