import Foundation

struct ParsedModelStreamFrame: Equatable {
  var textDeltas: [String] = []
  var toolDeltas: [ToolCallPayload] = []
  var usage: ModelUsage?
  var finishReason: String?
  var terminal = false
  var error: ModelStreamError?
  var providerSequence: Int64?
}

protocol ModelStreamProviderAdapter {
  func parse(data: String, eventName: String?) -> ParsedModelStreamFrame
  func parseCompleteJSON(data: String) -> ParsedModelStreamFrame
}

enum ModelStreamProviderAdapters {
  static func create(provider: ModelStreamProvider) -> ModelStreamProviderAdapter {
    switch provider {
    case .openAICompatible:
      return OpenAIModelStreamAdapter()
    case .anthropic:
      return AnthropicModelStreamAdapter()
    case .gemini:
      return GeminiModelStreamAdapter()
    }
  }
}

private final class OpenAIModelStreamAdapter: ModelStreamProviderAdapter {
  func parse(data: String, eventName: String?) -> ParsedModelStreamFrame {
    if data.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
      return ParsedModelStreamFrame(terminal: true)
    }
    guard let json = Self.object(data, invalidCode: "INVALID_STREAM_JSON") else {
      return ParsedModelStreamFrame(error: Self.invalidJSON(data, code: "INVALID_STREAM_JSON"))
    }
    let type = json.string("type").ifBlank(eventName ?? "")
    if type == "error" || json.object("error") != nil {
      return providerError(json)
    }
    if type == "response.output_text.delta" {
      return ParsedModelStreamFrame(
        textDeltas: [json.string("delta")],
        providerSequence: json.optionalSequence()
      )
    }
    if type == "response.function_call_arguments.delta" {
      return ParsedModelStreamFrame(
        toolDeltas: [
          ToolCallPayload(
            callId: json.string("item_id").ifBlank(json.string("call_id")),
            index: json.int("output_index"),
            nameDelta: json.string("name"),
            argumentsDelta: json.string("delta")
          )
        ],
        providerSequence: json.optionalSequence()
      )
    }
    if type == "response.completed" {
      let response = json.object("response") ?? json
      return ParsedModelStreamFrame(
        usage: response.object("usage")?.openAIUsage(),
        finishReason: response.string("status").ifBlank("stop"),
        terminal: true,
        providerSequence: json.optionalSequence()
      )
    }
    let choice = json.array("choices").firstObject
    let delta = choice?.object("delta")
    let text = modelStreamTextValue(delta?["content"])
    let tools = (delta?.array("tool_calls") ?? []).enumerated().compactMap { offset, value -> ToolCallPayload? in
      guard let call = value as? [String: Any] else { return nil }
      let function = call.object("function")
      return ToolCallPayload(
        callId: call.string("id"),
        index: call.int("index", fallback: offset),
        nameDelta: function?.string("name") ?? "",
        argumentsDelta: function?.string("arguments") ?? ""
      )
    }
    return ParsedModelStreamFrame(
      textDeltas: text.isEmpty ? [] : [text],
      toolDeltas: tools,
      usage: json.object("usage")?.openAIUsage(),
      finishReason: choice?.string("finish_reason").nonBlank,
      providerSequence: json.optionalSequence()
    )
  }

  func parseCompleteJSON(data: String) -> ParsedModelStreamFrame {
    guard let json = Self.object(data, invalidCode: "INVALID_RESPONSE_JSON") else {
      return ParsedModelStreamFrame(error: Self.invalidJSON(data, code: "INVALID_RESPONSE_JSON"))
    }
    if json.object("error") != nil {
      return providerError(json)
    }
    let choice = json.array("choices").firstObject
    let message = choice?.object("message")
    let text = modelStreamTextValue(message?["content"])
      .ifBlank(choice?.string("text") ?? "")
      .ifBlank(json.string("output_text"))
    let tools = (message?.array("tool_calls") ?? []).enumerated().compactMap { offset, value -> ToolCallPayload? in
      guard let call = value as? [String: Any] else { return nil }
      let function = call.object("function")
      return ToolCallPayload(
        callId: call.string("id"),
        index: call.int("index", fallback: offset),
        nameDelta: function?.string("name") ?? "",
        argumentsDelta: function?.string("arguments") ?? ""
      )
    }
    return ParsedModelStreamFrame(
      textDeltas: text.isEmpty ? [] : [text],
      toolDeltas: tools,
      usage: json.object("usage")?.openAIUsage(),
      finishReason: choice?.string("finish_reason").nonBlank,
      terminal: true
    )
  }
}

private final class AnthropicModelStreamAdapter: ModelStreamProviderAdapter {
  private struct ToolBlock {
    var id: String
    var name: String
  }

  private var toolBlocks: [Int: ToolBlock] = [:]

  func parse(data: String, eventName: String?) -> ParsedModelStreamFrame {
    guard let json = Self.object(data, invalidCode: "INVALID_STREAM_JSON") else {
      return ParsedModelStreamFrame(error: Self.invalidJSON(data, code: "INVALID_STREAM_JSON"))
    }
    let type = json.string("type").ifBlank(eventName ?? "")
    if type == "error" {
      return providerError(json)
    }
    switch type {
    case "message_start":
      return ParsedModelStreamFrame(
        usage: json.object("message")?.object("usage")?.anthropicUsage(),
        providerSequence: json.optionalSequence()
      )
    case "content_block_start":
      let index = json.int("index")
      guard let block = json.object("content_block"), block.string("type") == "tool_use" else {
        return ParsedModelStreamFrame(providerSequence: json.optionalSequence())
      }
      let tool = ToolBlock(id: block.string("id"), name: block.string("name"))
      toolBlocks[index] = tool
      let input = (block.object("input")?.jsonString() ?? "").ifBlank("")
      return ParsedModelStreamFrame(
        toolDeltas: [ToolCallPayload(callId: tool.id, index: index, nameDelta: tool.name, argumentsDelta: input)],
        providerSequence: json.optionalSequence()
      )
    case "content_block_delta":
      let index = json.int("index")
      let delta = json.object("delta") ?? [:]
      switch delta.string("type") {
      case "text_delta":
        return ParsedModelStreamFrame(
          textDeltas: [delta.string("text")],
          providerSequence: json.optionalSequence()
        )
      case "input_json_delta":
        let tool = toolBlocks[index] ?? ToolBlock(id: "tool-\(index)", name: "")
        return ParsedModelStreamFrame(
          toolDeltas: [
            ToolCallPayload(
              callId: tool.id,
              index: index,
              nameDelta: tool.name,
              argumentsDelta: delta.string("partial_json")
            )
          ],
          providerSequence: json.optionalSequence()
        )
      default:
        return ParsedModelStreamFrame(providerSequence: json.optionalSequence())
      }
    case "message_delta":
      return ParsedModelStreamFrame(
        usage: json.object("usage")?.anthropicUsage(),
        finishReason: json.object("delta")?.string("stop_reason").nonBlank,
        providerSequence: json.optionalSequence()
      )
    case "message_stop":
      return ParsedModelStreamFrame(terminal: true, providerSequence: json.optionalSequence())
    default:
      return ParsedModelStreamFrame(providerSequence: json.optionalSequence())
    }
  }

  func parseCompleteJSON(data: String) -> ParsedModelStreamFrame {
    guard let json = Self.object(data, invalidCode: "INVALID_RESPONSE_JSON") else {
      return ParsedModelStreamFrame(error: Self.invalidJSON(data, code: "INVALID_RESPONSE_JSON"))
    }
    if json.object("error") != nil {
      return providerError(json)
    }
    var texts: [String] = []
    var tools: [ToolCallPayload] = []
    for (index, value) in json.array("content").enumerated() {
      guard let block = value as? [String: Any] else { continue }
      switch block.string("type") {
      case "text":
        texts.append(block.string("text"))
      case "tool_use":
        tools.append(
          ToolCallPayload(
            callId: block.string("id"),
            index: index,
            nameDelta: block.string("name"),
            argumentsDelta: block.object("input")?.jsonString() ?? ""
          )
        )
      default:
        continue
      }
    }
    return ParsedModelStreamFrame(
      textDeltas: texts,
      toolDeltas: tools,
      usage: json.object("usage")?.anthropicUsage(),
      finishReason: json.string("stop_reason").nonBlank,
      terminal: true
    )
  }
}

private final class GeminiModelStreamAdapter: ModelStreamProviderAdapter {
  func parse(data: String, eventName _: String?) -> ParsedModelStreamFrame {
    parseJSON(data, terminal: false)
  }

  func parseCompleteJSON(data: String) -> ParsedModelStreamFrame {
    parseJSON(data, terminal: true)
  }

  private func parseJSON(_ data: String, terminal: Bool) -> ParsedModelStreamFrame {
    guard let json = Self.object(data, invalidCode: "INVALID_RESPONSE_JSON") else {
      return ParsedModelStreamFrame(error: Self.invalidJSON(data, code: "INVALID_RESPONSE_JSON"))
    }
    if json.object("error") != nil {
      return providerError(json)
    }
    let candidate = json.array("candidates").firstObject
    let parts = candidate?.object("content")?.array("parts") ?? []
    var texts: [String] = []
    var tools: [ToolCallPayload] = []
    for (index, value) in parts.enumerated() {
      guard let part = value as? [String: Any] else { continue }
      if !part.string("text").isEmpty {
        texts.append(part.string("text"))
      }
      guard let function = part.object("functionCall") else { continue }
      tools.append(
        ToolCallPayload(
          callId: function.string("id").ifBlank("gemini-\(index)"),
          index: index,
          nameDelta: function.string("name"),
          argumentsDelta: function.object("args")?.jsonString() ?? "",
          argumentsMode: .snapshot
        )
      )
    }
    let finishReason = candidate?.string("finishReason").nonBlank
    return ParsedModelStreamFrame(
      textDeltas: texts,
      toolDeltas: tools,
      usage: json.object("usageMetadata")?.geminiUsage(),
      finishReason: finishReason,
      terminal: terminal || finishReason != nil,
      providerSequence: json.optionalSequence()
    )
  }
}

private extension ModelStreamProviderAdapter {
  static func object(_ data: String, invalidCode _: String) -> [String: Any]? {
    guard let jsonData = data.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
      return nil
    }
    return object
  }

  static func invalidJSON(_ data: String, code: String) -> ModelStreamError {
    ModelStreamError(
      code: code,
      message: data.trimmingCharacters(in: .whitespacesAndNewlines).prefixText(1_000).ifBlank("Invalid JSON")
    )
  }
}

private func providerError(_ json: [String: Any]) -> ParsedModelStreamFrame {
  let error = json.object("error") ?? json
  let code = error.string("code")
    .ifBlank(error.string("type"))
    .ifBlank("PROVIDER_ERROR")
  return ParsedModelStreamFrame(
    error: ModelStreamError(
      code: code,
      message: error.string("message").ifBlank(json.jsonString().prefixText(1_000)),
      retryable: error.int("code") >= 500
    )
  )
}

private func modelStreamTextValue(_ value: Any?) -> String {
  if let text = value as? String {
    return text
  }
  if let array = value as? [Any] {
    return array.map(modelStreamTextValue).joined()
  }
  if let object = value as? [String: Any] {
    return object.string("text")
  }
  return ""
}

private extension Dictionary where Key == String, Value == Any {
  func int(_ key: String, fallback: Int = 0) -> Int {
    if let value = self[key] as? Int {
      return value
    }
    if let value = self[key] as? NSNumber {
      return value.intValue
    }
    if let value = self[key] as? String, let parsed = Int(value) {
      return parsed
    }
    return fallback
  }

  func int64(_ key: String, fallback: Int64 = 0) -> Int64 {
    if let value = self[key] as? Int64 {
      return value
    }
    if let value = self[key] as? Int {
      return Int64(value)
    }
    if let value = self[key] as? NSNumber {
      return value.int64Value
    }
    if let value = self[key] as? String, let parsed = Int64(value) {
      return parsed
    }
    return fallback
  }

  func object(_ key: String) -> [String: Any]? {
    self[key] as? [String: Any]
  }

  func array(_ key: String) -> [Any] {
    self[key] as? [Any] ?? []
  }

  func optionalSequence() -> Int64? {
    if keys.contains("sequence") {
      return int64("sequence")
    }
    if keys.contains("seq") {
      return int64("seq")
    }
    return nil
  }

  func openAIUsage() -> ModelUsage {
    ModelUsage(
      inputTokens: int64("prompt_tokens", fallback: int64("input_tokens")),
      outputTokens: int64("completion_tokens", fallback: int64("output_tokens")),
      cachedInputTokens: object("prompt_tokens_details")?.int64("cached_tokens") ?? 0
    )
  }

  func anthropicUsage() -> ModelUsage {
    ModelUsage(
      inputTokens: int64("input_tokens"),
      outputTokens: int64("output_tokens"),
      cachedInputTokens: int64("cache_read_input_tokens")
    )
  }

  func geminiUsage() -> ModelUsage {
    ModelUsage(
      inputTokens: int64("promptTokenCount"),
      outputTokens: int64("candidatesTokenCount"),
      cachedInputTokens: int64("cachedContentTokenCount")
    )
  }

  func jsonString() -> String {
    guard JSONSerialization.isValidJSONObject(self),
          let data = try? JSONSerialization.data(withJSONObject: self, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8) else {
      return "{}"
    }
    return text
  }
}

private extension Array where Element == Any {
  var firstObject: [String: Any]? {
    first as? [String: Any]
  }
}

private extension String {
  var nonBlank: String? {
    trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
  }

  func prefixText(_ limit: Int) -> String {
    String(prefix(max(0, limit)))
  }
}
