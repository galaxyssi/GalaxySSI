import Foundation

struct AgentProviderContinuation: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
  let provider: AgentModelToolProvider
  private let payload: AgentMcpJSONObject
  private var binding: String
  private var route: String?

  var description: String { "AgentProviderContinuation(\(provider.rawValue))" }
  var debugDescription: String { description }
  var estimatedTokens: Int { ConversationContextCompactor.estimateTokens(AgentMcpJSONCodec.stringify(payload)) }

  init(provider: AgentModelToolProvider, payload: AgentMcpJSONObject, response: AgentModelResponse) {
    self.provider = provider
    self.payload = payload
    self.binding = Self.fingerprint(response.assistantText, calls: response.toolCalls)
  }

  func bound(to route: String) -> Self {
    var copy = self
    copy.route = route
    return copy
  }

  func transport(for route: String) -> Self? {
    guard self.route == route else { return nil }
    var copy = self
    copy.route = nil
    return copy
  }

  func forHistory(_ response: AgentModelResponse, admitted: [AgentModelToolCall]) throws -> Self {
    try validate(text: response.assistantText, calls: response.toolCalls)
    guard Self.shape(response.toolCalls) == Self.shape(admitted) else { throw Self.changed }
    var copy = self
    copy.binding = Self.fingerprint(response.assistantText, calls: admitted)
    return copy
  }

  fileprivate func payload(for message: AgentModelMessage, provider target: AgentModelToolProvider) throws -> AgentMcpJSONObject? {
    guard provider == target, route == nil else { return nil }
    try validate(text: message.text, calls: message.toolCalls)
    return payload
  }

  private func validate(text: String, calls: [AgentModelToolCall]) throws {
    guard binding == Self.fingerprint(text, calls: calls) else { throw Self.changed }
  }

  private static func fingerprint(_ text: String, calls: [AgentModelToolCall]) -> String {
    AgentModelLoopRecoveryIdentity.sha256(["text": .string(text), "calls": .array(
      zip(shape(calls), calls).map { value, call in
        var item = value
        item["call_id"] = .string(call.callId)
        return .object(item)
      }
    )] as AgentMcpJSONObject)
  }

  private static func shape(_ calls: [AgentModelToolCall]) -> [AgentMcpJSONObject] {
    calls.map {
      ["tool": .string($0.toolId), "arguments": .object($0.arguments),
       "version": $0.toolVersion.map(AgentMcpJSONValue.string) ?? .null,
       "effect": $0.idempotencyKey.map(AgentMcpJSONValue.string) ?? .null, "depth": .int(Int64($0.depth))]
    }
  }

  fileprivate static let changed = AgentModelToolProtocolError(
    code: "continuation_history_changed", message: "Provider continuation no longer matches the assistant turn.")
}

struct AgentProviderCallAdmission {
  let calls: [AgentModelToolCall]
  let rejectedIDs: Set<String>

  init(_ incoming: [AgentModelToolCall], previous: Set<String>, round: Int) {
    var used = previous
    var reserved = used.union(incoming.map(\.callId))
    var calls: [AgentModelToolCall] = []
    var rejected: Set<String> = []
    for (index, proposed) in incoming.enumerated() {
      var call = proposed
      if !used.insert(call.callId).inserted {
        var replacement = "provider_rejected_\(round)_\(index)"
        while !reserved.insert(replacement).inserted { replacement += "_x" }
        call.callId = replacement
        used.insert(replacement)
        rejected.insert(replacement)
      }
      calls.append(call)
    }
    self.calls = calls
    self.rejectedIDs = rejected
  }
}

struct AgentProviderTranscript {
  private struct WireCall {
    let id: String?
    let name: String
  }

  private var assistants: [Int: AgentMcpJSONObject] = [:]
  private var replies: [String: WireCall] = [:]

  init(_ messages: [AgentModelMessage], adapter: StrictAgentModelToolProtocolAdapter) throws {
    for (index, message) in messages.enumerated() where message.role == .assistant {
      guard let payload = try message.providerContinuation?.payload(for: message, provider: adapter.provider) else { continue }
      let path = "messages[\(index)]"
      try adapter.checkCallCount(message.toolCalls.count, path: path)
      let calls = Self.calls(in: payload, provider: adapter.provider)
      guard calls.count == message.toolCalls.count else { throw AgentProviderContinuation.changed }
      for (offset, pair) in zip(calls, message.toolCalls).enumerated() {
        let (wire, call) = pair
        try adapter.checkedOutboundCall(call, path: "\(path).tool_calls[\(offset)]")
        let function = adapter.provider == .openAICompatible ? wire["function"]?.objectValue : wire
        guard let name = function?["name"]?.strictStringValue else { throw AgentProviderContinuation.changed }
        replies[call.callId] = WireCall(id: wire["id"]?.strictStringValue, name: name)
      }
      assistants[index] = payload
    }
  }

  func assistant(at index: Int) -> AgentMcpJSONObject? { assistants[index] }

  func replyId(_ callId: String) -> String? {
    if let wire = replies[callId] { return wire.id }
    return callId
  }

  func replyName(_ result: AgentModelToolResultContent) -> String {
    replies[result.callId]?.name ?? result.toolId
  }

  private static func calls(in payload: AgentMcpJSONObject, provider: AgentModelToolProvider) -> [AgentMcpJSONObject] {
    switch provider {
    case .openAICompatible:
      return payload["tool_calls"]?.arrayValue?.compactMap(\.objectValue) ?? []
    case .anthropic:
      return payload["content"]?.arrayValue?.compactMap(\.objectValue).filter { $0["type"] == .string("tool_use") } ?? []
    case .gemini:
      return payload["parts"]?.arrayValue?.compactMap { $0.objectValue?["functionCall"]?.objectValue } ?? []
    }
  }
}

struct AgentProviderRouteAdapter: AgentModelToolProtocolAdapter {
  let base: AgentModelToolProtocolAdapter
  let route: String
  var provider: AgentModelToolProvider { base.provider }

  func encodeToolCatalog(_ catalog: [AgentNativeToolDescriptor]) throws -> [AgentMcpJSONValue] {
    try base.encodeToolCatalog(catalog)
  }

  func encodeConversation(_ messages: [AgentModelMessage]) throws -> AgentMcpJSONObject {
    try base.encodeConversation(messages.map { message in
      var copy = message
      copy.providerContinuation = message.providerContinuation?.transport(for: route)
      return copy
    })
  }

  func decodeResponse(_ responseJSON: String, catalog: [AgentNativeToolDescriptor]) throws -> AgentModelResponse {
    var response = try base.decodeResponse(responseJSON, catalog: catalog)
    response.providerContinuation = response.providerContinuation?.bound(to: route)
    return response
  }
}
