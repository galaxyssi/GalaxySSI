import CryptoKit
import Foundation

struct ParsedAgentModelToolCall {
  var id: String
  var name: String
  var arguments: AgentMcpJSONObject
}

struct BoundedAgentModelToolResult {
  var jsonText: String
  var value: AgentMcpJSONObject
}

class StrictAgentModelToolProtocolAdapter: AgentModelToolProtocolAdapter {
  let provider: AgentModelToolProvider
  let limits: AgentModelToolProtocolLimits

  init(provider: AgentModelToolProvider, limits: AgentModelToolProtocolLimits) {
    self.provider = provider
    self.limits = limits
  }

  func encodeToolCatalog(_ catalog: [AgentNativeToolDescriptor]) throws -> [AgentMcpJSONValue] {
    fatalError("Subclasses must implement encodeToolCatalog(_:)")
  }

  func encodeConversation(_ messages: [AgentModelMessage]) throws -> AgentMcpJSONObject {
    fatalError("Subclasses must implement encodeConversation(_:)")
  }

  func decodeResponse(
    _ responseJSON: String,
    catalog: [AgentNativeToolDescriptor]
  ) throws -> AgentModelResponse {
    fatalError("Subclasses must implement decodeResponse(_:catalog:)")
  }

  func checkedCatalog(_ catalog: [AgentNativeToolDescriptor]) throws -> [String: AgentNativeToolDescriptor] {
    var result: [String: AgentNativeToolDescriptor] = [:]
    for (index, descriptor) in catalog.enumerated() {
      try checkedToolName(descriptor.id, path: "catalog[\(index)].id")
      if result[descriptor.id] != nil {
        throw protocolError("duplicate_tool", "Catalog contains duplicate tool \(descriptor.id)")
      }
      result[descriptor.id] = descriptor
    }
    return result
  }

  func parseRoot(_ responseJSON: String) throws -> AgentMcpJSONObject {
    if responseJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw protocolError("malformed_response", "Provider response is blank")
    }
    if responseJSON.count > limits.maxResponseCharacters {
      throw protocolError(
        "oversized_response",
        "Provider response exceeds \(limits.maxResponseCharacters) characters"
      )
    }
    guard let data = responseJSON.data(using: .utf8) else {
      throw protocolError("malformed_response", "Provider response is not UTF-8")
    }
    do {
      let decoded = try JSONDecoder().decode(AgentMcpJSONValue.self, from: data)
      guard let object = decoded.objectValue else {
        throw protocolError("malformed_response", "Provider response is not a JSON object")
      }
      return object
    } catch let error as AgentModelToolProtocolError {
      throw error
    } catch {
      throw protocolError("malformed_response", "Provider response is not a JSON object")
    }
  }

  func parseArgumentString(_ value: String, path: String) throws -> AgentMcpJSONObject {
    if value.count > limits.maxArgumentsCharacters {
      throw protocolError("oversized_tool_call", "\(path) exceeds \(limits.maxArgumentsCharacters) characters")
    }
    guard let data = value.data(using: .utf8) else {
      throw protocolError("malformed_tool_call", "\(path) is not UTF-8")
    }
    do {
      let decoded = try JSONDecoder().decode(AgentMcpJSONValue.self, from: data)
      guard let object = decoded.objectValue else {
        throw protocolError("malformed_tool_call", "\(path) is not a JSON object")
      }
      return try checkedArguments(object, path: path)
    } catch let error as AgentModelToolProtocolError {
      throw error
    } catch {
      throw protocolError("malformed_tool_call", "\(path) is not a JSON object")
    }
  }

  func checkedArguments(_ arguments: AgentMcpJSONObject, path: String) throws -> AgentMcpJSONObject {
    try checkJSONCompatible(
      .object(arguments),
      path: path,
      depth: 0,
      oversizedCode: "oversized_tool_call",
      malformedCode: "malformed_tool_call"
    )
    let size = AgentMcpJSONCodec.stringify(arguments).count
    if size > limits.maxArgumentsCharacters {
      throw protocolError("oversized_tool_call", "\(path) exceeds \(limits.maxArgumentsCharacters) characters")
    }
    return arguments
  }

  func checkedOutboundCall(_ call: AgentModelToolCall, path: String) throws {
    try checkedCallId(call.callId, path: "\(path).id")
    try checkedToolName(call.toolId, path: "\(path).name")
    _ = try checkedArguments(call.arguments, path: "\(path).arguments")
  }

  func checkCallCount(_ count: Int, path: String) throws {
    if count > limits.maxToolCalls {
      throw protocolError(
        "oversized_tool_call",
        "\(path) contains \(count) tool calls; maximum is \(limits.maxToolCalls)"
      )
    }
  }

  func parseCalls(
    _ calls: [AgentMcpJSONValue],
    catalog: [AgentNativeToolDescriptor],
    parser: (AgentMcpJSONObject, String) throws -> ParsedAgentModelToolCall
  ) throws -> [AgentModelToolCall] {
    try checkCallCount(calls.count, path: "response")
    let catalogById = try checkedCatalog(catalog)
    var callIds = Set<String>()
    var parsed: [AgentModelToolCall] = []
    for index in calls.indices {
      let path = "response.tool_calls[\(index)]"
      do {
        let item = try calls.protocolRequiredObject(index, path: "response.tool_calls")
        parsed.append(try checkedParsedCall(
          try parser(item, path),
          path: path,
          catalogById: catalogById,
          callIds: &callIds
        ))
      } catch let error as AgentModelToolProtocolError {
        throw error.asMalformedToolCall(path: path)
      }
    }
    return parsed
  }

  func checkedParsedCall(
    _ call: ParsedAgentModelToolCall,
    path: String,
    catalogById: [String: AgentNativeToolDescriptor],
    callIds: inout Set<String>
  ) throws -> AgentModelToolCall {
    try checkedCallId(call.id, path: "\(path).id")
    try checkedToolName(call.name, path: "\(path).name")
    if callIds.contains(call.id) {
      throw protocolError("malformed_tool_call", "Duplicate tool call id \(call.id)")
    }
    callIds.insert(call.id)
    guard let descriptor = catalogById[call.name] else {
      throw protocolError("unknown_tool", "Provider requested unknown tool \(call.name)")
    }
    return AgentModelToolCall(
      callId: call.id,
      toolId: descriptor.id,
      arguments: try checkedArguments(call.arguments, path: "\(path).arguments"),
      toolVersion: descriptor.version
    )
  }

  func boundedResult(_ result: AgentModelToolResultContent, path: String) throws -> BoundedAgentModelToolResult {
    try checkedCallId(result.callId, path: "\(path).tool_call_id")
    try checkedToolName(result.toolId, path: "\(path).tool_id")
    if result.status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw protocolError("malformed_tool_result", "\(path).status must not be blank")
    }

    let full = protocolObject(for: result)
    try checkJSONCompatible(
      .object(full),
      path: path,
      depth: 0,
      oversizedCode: "oversized_tool_result",
      malformedCode: "malformed_tool_result"
    )
    let fullText = AgentMcpJSONCodec.stringify(full)
    if fullText.count <= limits.maxToolResultCharacters {
      return BoundedAgentModelToolResult(jsonText: fullText, value: full)
    }

    var summary: AgentMcpJSONObject = [
      "tool_call_id": .string(result.callId),
      "tool_id": .string(result.toolId),
      "status": .string(result.status),
      "truncated": .bool(true),
      "original_characters": .int(Int64(fullText.count))
    ]
    var summaryText = AgentMcpJSONCodec.stringify(summary)
    if summaryText.count > limits.maxToolResultCharacters {
      throw protocolError(
        "oversized_tool_result",
        "\(path) identity exceeds \(limits.maxToolResultCharacters) characters"
      )
    }

    if !result.message.isBlank {
      var low = 0
      var high = result.message.count
      while low < high {
        let middle = (low + high + 1) / 2
        summary["message"] = .string(String(result.message.prefix(middle)))
        if AgentMcpJSONCodec.stringify(summary).count <= limits.maxToolResultCharacters {
          low = middle
        } else {
          high = middle - 1
        }
      }
      if low > 0 {
        summary["message"] = .string(String(result.message.prefix(low)))
      } else {
        summary.removeValue(forKey: "message")
      }
      summaryText = AgentMcpJSONCodec.stringify(summary)
    }

    return BoundedAgentModelToolResult(jsonText: summaryText, value: summary)
  }

  func metadata(_ finishReason: String?) -> AgentMcpJSONObject {
    var result: AgentMcpJSONObject = ["provider": .string(provider.rawValue)]
    if let finishReason {
      result["finish_reason"] = .string(finishReason)
    }
    return result
  }

  func modelResponse(
    text: String,
    calls: [AgentModelToolCall],
    usage: AgentModelUsage,
    metadata: AgentMcpJSONObject
  ) throws -> AgentModelResponse {
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && calls.isEmpty {
      throw protocolError("empty_response", "Provider response contains neither text nor tool calls")
    }
    return AgentModelResponse(
      assistantText: text,
      toolCalls: calls,
      usage: usage,
      providerMetadata: metadata
    )
  }

  func protocolError(_ code: String, _ message: String) -> AgentModelToolProtocolError {
    AgentModelToolProtocolError(code: code, message: message)
  }

  private func checkedCallId(_ callId: String, path: String) throws {
    if callId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw protocolError("malformed_tool_call", "\(path) must not be blank")
    }
    if callId.count > limits.maxCallIdCharacters {
      throw protocolError("oversized_tool_call", "\(path) exceeds \(limits.maxCallIdCharacters) characters")
    }
  }

  private func checkedToolName(_ name: String, path: String) throws {
    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw protocolError("malformed_tool_call", "\(path) must not be blank")
    }
    if name.count > limits.maxToolNameCharacters {
      throw protocolError("oversized_tool_call", "\(path) exceeds \(limits.maxToolNameCharacters) characters")
    }
  }

  private func checkJSONCompatible(
    _ value: AgentMcpJSONValue,
    path: String,
    depth: Int,
    oversizedCode: String,
    malformedCode: String
  ) throws {
    if depth > limits.maxJsonDepth {
      throw protocolError(oversizedCode, "\(path) exceeds JSON depth \(limits.maxJsonDepth)")
    }
    switch value {
    case .double(let value) where !value.isFinite:
      throw protocolError(malformedCode, "\(path) is not finite")
    case .array(let values):
      for (index, item) in values.enumerated() {
        try checkJSONCompatible(
          item,
          path: "\(path)[\(index)]",
          depth: depth + 1,
          oversizedCode: oversizedCode,
          malformedCode: malformedCode
        )
      }
    case .object(let object):
      for key in object.keys.sorted() {
        try checkJSONCompatible(
          object[key] ?? .null,
          path: "\(path).\(key)",
          depth: depth + 1,
          oversizedCode: oversizedCode,
          malformedCode: malformedCode
        )
      }
    case .string, .int, .double, .bool, .null:
      break
    }
  }

  private func protocolObject(for result: AgentModelToolResultContent) -> AgentMcpJSONObject {
    var object: AgentMcpJSONObject = [
      "tool_call_id": .string(result.callId),
      "tool_id": .string(result.toolId),
      "status": .string(result.status),
      "output": .object(result.output),
      "message": .string(result.message)
    ]
    if let error = result.error {
      object["error"] = .object([
        "code": .string(error.code),
        "message": .string(error.message),
        "retryable": .bool(error.retryable),
        "details": .object(error.details)
      ])
    } else if !result.errorMessage.isBlank {
      object["error"] = .string(result.errorMessage)
    }
    if let invocationId = result.invocationId {
      object["invocation_id"] = .string(invocationId)
    }
    object["retry_count"] = .int(Int64(result.retryCount))
    if let nativeResult = result.nativeResult {
      object["native_result"] = nativeResult.toJsonValue()
    }
    return object
  }
}

typealias OpenAICompatibleAgentModelToolProtocolAdapter =
  OpenAiCompatibleAgentModelToolProtocolAdapter

extension AgentModelToolProtocolError {
  func asMalformedToolCall(path: String) -> AgentModelToolProtocolError {
    if code == "malformed_response" {
      return AgentModelToolProtocolError(
        code: "malformed_tool_call",
        message: "Malformed tool call at \(path): \(message)"
      )
    }
    return self
  }
}

enum AgentModelToolProtocolJSON {
  static func sha256(_ value: String) -> String {
    let digest = SHA256.hash(data: Data(value.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  static func saturatingSum(_ values: Int64...) -> Int64 {
    values.reduce(Int64(0)) { total, value in
      if Int64.max - total < value {
        return Int64.max
      }
      return total + value
    }
  }
}

extension Dictionary where Key == String, Value == AgentMcpJSONValue {
  func protocolOptionalValue(_ key: String) -> AgentMcpJSONValue? {
    guard let value = self[key], value != .null else {
      return nil
    }
    return value
  }

  func protocolRequiredValue(_ key: String, path: String) throws -> AgentMcpJSONValue {
    guard let value = protocolOptionalValue(key) else {
      throw AgentModelToolProtocolError(code: "malformed_response", message: "\(path).\(key) is required")
    }
    return value
  }

  func protocolRequiredString(_ key: String, path: String) throws -> String {
    let value = try protocolRequiredValue(key, path: path)
    guard let string = value.strictStringValue, !string.isBlank else {
      throw AgentModelToolProtocolError(
        code: "malformed_response",
        message: "\(path).\(key) must be a non-blank string"
      )
    }
    return string
  }

  func protocolOptionalString(_ key: String, path: String) throws -> String? {
    guard let value = protocolOptionalValue(key) else {
      return nil
    }
    guard let string = value.strictStringValue else {
      throw AgentModelToolProtocolError(code: "malformed_response", message: "\(path).\(key) must be a string")
    }
    return string
  }

  func protocolRequiredObject(_ key: String, path: String) throws -> AgentMcpJSONObject {
    let value = try protocolRequiredValue(key, path: path)
    guard let object = value.objectValue else {
      throw AgentModelToolProtocolError(code: "malformed_response", message: "\(path).\(key) must be an object")
    }
    return object
  }

  func protocolOptionalObject(_ key: String, path: String) throws -> AgentMcpJSONObject? {
    guard let value = protocolOptionalValue(key) else {
      return nil
    }
    guard let object = value.objectValue else {
      throw AgentModelToolProtocolError(code: "malformed_response", message: "\(path).\(key) must be an object")
    }
    return object
  }

  func protocolRequiredArray(_ key: String, path: String) throws -> [AgentMcpJSONValue] {
    let value = try protocolRequiredValue(key, path: path)
    guard let array = value.arrayValue else {
      throw AgentModelToolProtocolError(code: "malformed_response", message: "\(path).\(key) must be an array")
    }
    return array
  }

  func protocolOptionalArray(_ key: String, path: String) throws -> [AgentMcpJSONValue]? {
    guard let value = protocolOptionalValue(key) else {
      return nil
    }
    guard let array = value.arrayValue else {
      throw AgentModelToolProtocolError(code: "malformed_response", message: "\(path).\(key) must be an array")
    }
    return array
  }

  func protocolTokenCount(_ primaryKey: String, fallbackKey: String? = nil, path: String) throws -> Int64 {
    let selectedKey: String
    let value: AgentMcpJSONValue
    if let primary = protocolOptionalValue(primaryKey) {
      selectedKey = primaryKey
      value = primary
    } else if let fallbackKey, let fallback = protocolOptionalValue(fallbackKey) {
      selectedKey = fallbackKey
      value = fallback
    } else {
      return 0
    }

    let count: Int64
    switch value {
    case .int(let intValue):
      count = intValue
    case .double(let doubleValue) where doubleValue.isFinite &&
        doubleValue.rounded(.towardZero) == doubleValue &&
        doubleValue <= Double(Int64.max):
      count = Int64(doubleValue)
    default:
      throw AgentModelToolProtocolError(
        code: "malformed_response",
        message: "\(path).\(selectedKey) must be an integer"
      )
    }
    if count < 0 {
      throw AgentModelToolProtocolError(
        code: "malformed_response",
        message: "\(path).\(selectedKey) must be non-negative"
      )
    }
    return count
  }
}

extension Array where Element == AgentMcpJSONValue {
  func protocolRequiredObject(_ index: Int, path: String) throws -> AgentMcpJSONObject {
    guard indices.contains(index), let object = self[index].objectValue else {
      throw AgentModelToolProtocolError(code: "malformed_response", message: "\(path)[\(index)] must be an object")
    }
    return object
  }
}
