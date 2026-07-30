import Foundation

enum AgentModelToolProvider: String, Codable, CaseIterable, Identifiable {
  case openAICompatible = "openai_compatible"
  case anthropic
  case gemini

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentModelToolProvider {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .openAICompatible
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try? container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentModelToolProtocolLimits: Codable, Equatable {
  static let defaultLimits = AgentModelToolProtocolLimits()

  var maxToolCalls: Int
  var maxCallIdCharacters: Int
  var maxToolNameCharacters: Int
  var maxArgumentsCharacters: Int
  var maxToolResultCharacters: Int
  var maxResponseCharacters: Int
  var maxJsonDepth: Int

  init(
    maxToolCalls: Int = 32,
    maxCallIdCharacters: Int = 256,
    maxToolNameCharacters: Int = 128,
    maxArgumentsCharacters: Int = 65_536,
    maxToolResultCharacters: Int = 8_192,
    maxResponseCharacters: Int = 1_048_576,
    maxJsonDepth: Int = 64
  ) {
    precondition(maxToolCalls > 0)
    precondition(maxCallIdCharacters > 0)
    precondition(maxToolNameCharacters > 0)
    precondition(maxArgumentsCharacters > 1)
    precondition(maxToolResultCharacters >= 128)
    precondition(maxResponseCharacters > 1)
    precondition(maxJsonDepth > 0)
    self.maxToolCalls = maxToolCalls
    self.maxCallIdCharacters = maxCallIdCharacters
    self.maxToolNameCharacters = maxToolNameCharacters
    self.maxArgumentsCharacters = maxArgumentsCharacters
    self.maxToolResultCharacters = maxToolResultCharacters
    self.maxResponseCharacters = maxResponseCharacters
    self.maxJsonDepth = maxJsonDepth
  }

  enum CodingKeys: String, CodingKey {
    case maxToolCalls = "max_tool_calls"
    case maxCallIdCharacters = "max_call_id_characters"
    case maxToolNameCharacters = "max_tool_name_characters"
    case maxArgumentsCharacters = "max_arguments_characters"
    case maxToolResultCharacters = "max_tool_result_characters"
    case maxResponseCharacters = "max_response_characters"
    case maxJsonDepth = "max_json_depth"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      maxToolCalls: try container.decodeIfPresent(Int.self, forKey: .maxToolCalls) ?? 32,
      maxCallIdCharacters: try container.decodeIfPresent(Int.self, forKey: .maxCallIdCharacters) ?? 256,
      maxToolNameCharacters: try container.decodeIfPresent(Int.self, forKey: .maxToolNameCharacters) ?? 128,
      maxArgumentsCharacters: try container.decodeIfPresent(Int.self, forKey: .maxArgumentsCharacters) ?? 65_536,
      maxToolResultCharacters: try container.decodeIfPresent(Int.self, forKey: .maxToolResultCharacters) ?? 8_192,
      maxResponseCharacters: try container.decodeIfPresent(Int.self, forKey: .maxResponseCharacters) ?? 1_048_576,
      maxJsonDepth: try container.decodeIfPresent(Int.self, forKey: .maxJsonDepth) ?? 64
    )
  }
}

struct AgentModelUsage: Codable, Equatable {
  var inputTokens: Int64
  var outputTokens: Int64

  var totalTokens: Int64 {
    AgentModelToolProtocolJSON.saturatingSum(inputTokens, outputTokens)
  }

  init(inputTokens: Int64 = 0, outputTokens: Int64 = 0) {
    precondition(inputTokens >= 0)
    precondition(outputTokens >= 0)
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
  }

  enum CodingKeys: String, CodingKey {
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      inputTokens: try container.decodeIfPresent(Int64.self, forKey: .inputTokens) ?? 0,
      outputTokens: try container.decodeIfPresent(Int64.self, forKey: .outputTokens) ?? 0
    )
  }
}

struct AgentModelResponse: Codable, Equatable {
  var assistantText: String
  var toolCalls: [AgentModelToolCall]
  var usage: AgentModelUsage
  var providerMetadata: AgentMcpJSONObject

  init(
    assistantText: String = "",
    toolCalls: [AgentModelToolCall] = [],
    usage: AgentModelUsage = AgentModelUsage(),
    providerMetadata: AgentMcpJSONObject = [:]
  ) {
    precondition(!assistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !toolCalls.isEmpty)
    self.assistantText = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
    self.toolCalls = toolCalls
    self.usage = usage
    self.providerMetadata = providerMetadata
  }

  enum CodingKeys: String, CodingKey {
    case assistantText = "assistant_text"
    case toolCalls = "tool_calls"
    case usage
    case providerMetadata = "provider_metadata"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      assistantText: try container.decodeIfPresent(String.self, forKey: .assistantText) ?? "",
      toolCalls: try container.decodeIfPresent([AgentModelToolCall].self, forKey: .toolCalls) ?? [],
      usage: try container.decodeIfPresent(AgentModelUsage.self, forKey: .usage) ?? AgentModelUsage(),
      providerMetadata: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .providerMetadata) ?? [:]
    )
  }
}

struct AgentModelToolProtocolError: Error, LocalizedError, Equatable {
  var code: String
  var message: String

  var errorDescription: String? { message }
}

protocol AgentModelToolProtocolAdapter {
  var provider: AgentModelToolProvider { get }

  func encodeToolCatalog(_ catalog: [AgentNativeToolDescriptor]) throws -> [AgentMcpJSONValue]

  func encodeConversation(_ messages: [AgentModelMessage]) throws -> AgentMcpJSONObject

  func decodeResponse(
    _ responseJSON: String,
    catalog: [AgentNativeToolDescriptor]
  ) throws -> AgentModelResponse
}

extension AgentModelToolProtocolAdapter {
  func encodeTools(_ catalog: [AgentNativeToolDescriptor]) throws -> [AgentMcpJSONValue] {
    try encodeToolCatalog(catalog)
  }

  func encodeMessages(_ messages: [AgentModelMessage]) throws -> AgentMcpJSONObject {
    try encodeConversation(messages)
  }

  func parseResponse(
    _ responseJSON: String,
    catalog: [AgentNativeToolDescriptor]
  ) throws -> AgentModelResponse {
    try decodeResponse(responseJSON, catalog: catalog)
  }
}

enum AgentModelToolProtocolAdapters {
  static func adapter(
    for provider: AgentModelToolProvider,
    limits: AgentModelToolProtocolLimits = .defaultLimits
  ) -> AgentModelToolProtocolAdapter {
    switch provider {
    case .openAICompatible:
      return OpenAiCompatibleAgentModelToolProtocolAdapter(limits: limits)
    case .anthropic:
      return AnthropicAgentModelToolProtocolAdapter(limits: limits)
    case .gemini:
      return GeminiAgentModelToolProtocolAdapter(limits: limits)
    }
  }

  static func openAiCompatible(
    limits: AgentModelToolProtocolLimits = .defaultLimits
  ) -> OpenAiCompatibleAgentModelToolProtocolAdapter {
    OpenAiCompatibleAgentModelToolProtocolAdapter(limits: limits)
  }

  static func anthropic(
    limits: AgentModelToolProtocolLimits = .defaultLimits
  ) -> AnthropicAgentModelToolProtocolAdapter {
    AnthropicAgentModelToolProtocolAdapter(limits: limits)
  }

  static func gemini(
    limits: AgentModelToolProtocolLimits = .defaultLimits
  ) -> GeminiAgentModelToolProtocolAdapter {
    GeminiAgentModelToolProtocolAdapter(limits: limits)
  }
}
