import Foundation

enum CloudModelStreamJSON {
  static func any(_ value: AgentMcpJSONValue) -> Any {
    switch value {
    case .string(let value):
      return value
    case .int(let value):
      return value
    case .double(let value):
      return value
    case .bool(let value):
      return value
    case .object(let object):
      return object.reduce(into: [String: Any]()) { result, entry in
        result[entry.key] = any(entry.value)
      }
    case .array(let values):
      return values.map(any)
    case .null:
      return NSNull()
    }
  }

  static func object(_ value: AgentMcpJSONObject) -> [String: Any] {
    any(.object(value)) as? [String: Any] ?? [:]
  }

  static func object(from json: String) throws -> [String: Any] {
    let data = Data(json.utf8)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw GalaxySSIError.invalidPayload("Tool arguments must be a JSON object.")
    }
    return object
  }

  static func mcpObject(from json: String) throws -> AgentMcpJSONObject {
    let data = Data(json.utf8)
    return try JSONDecoder().decode(AgentMcpJSONObject.self, from: data)
  }

  static func string(_ object: [String: Any]) throws -> String {
    let data = try GalaxySSILinkProtocol.jsonData(object)
    guard let body = String(data: data, encoding: .utf8) else {
      throw GalaxySSIError.invalidPayload("Cloud request body is not valid UTF-8.")
    }
    return body
  }
}

enum CloudModelStreamToolSchemas {
  static func tools(for provider: ModelStreamProvider) -> [[String: Any]] {
    switch provider {
    case .openAICompatible:
      return openAITools()
    case .anthropic:
      return anthropicTools()
    case .gemini:
      return geminiTools()
    }
  }

  static func openAITools(includeImageAnnotation: Bool = false) -> [[String: Any]] {
    var tools = CloudWebGrounding.openAITools().map(CloudModelStreamJSON.object)
    if includeImageAnnotation { tools.append(imageAnnotationTool()) }
    return tools
  }

  static func anthropicTools(includeImageAnnotation: Bool = false) -> [[String: Any]] {
    openAITools(includeImageAnnotation: includeImageAnnotation).compactMap { tool in
      guard let function = tool["function"] as? [String: Any] else { return nil }
      return [
        "name": function["name"] ?? "",
        "description": function["description"] ?? "",
        "input_schema": function["parameters"] ?? [:]
      ]
    }
  }

  static func geminiTools(includeImageAnnotation: Bool = false) -> [[String: Any]] {
    let declarations = openAITools(includeImageAnnotation: includeImageAnnotation).compactMap { tool -> [String: Any]? in
      guard let function = tool["function"] as? [String: Any] else { return nil }
      return [
        "name": function["name"] ?? "",
        "description": function["description"] ?? "",
        "parameters": geminiSchema(function["parameters"] ?? [:])
      ]
    }
    return [["functionDeclarations": declarations]]
  }

  private static func imageAnnotationTool() -> [String: Any] {
    let coordinate: [String: Any] = ["type": "number", "minimum": 0, "maximum": 1]
    let mark: [String: Any] = [
      "type": "object",
      "additionalProperties": false,
      "required": ["left", "top", "right", "bottom", "verdict", "note", "correction"],
      "properties": [
        "left": coordinate, "top": coordinate, "right": coordinate, "bottom": coordinate,
        "verdict": ["type": "string", "enum": ["correct", "incorrect", "uncertain", "note"]],
        "note": ["type": "string", "minLength": 1, "maxLength": 160],
        "correction": ["type": "string", "maxLength": 40]
      ]
    ]
    return [
      "type": "function",
      "function": [
        "name": CloudImageAnnotationPlan.toolName,
        "description": "Grade the original image with small ticks, crosses, and short corrections without boxes or extra pages.",
        "parameters": [
          "type": "object",
          "additionalProperties": false,
          "required": ["image_index", "marks"],
          "properties": [
            "image_index": ["type": "integer", "minimum": 0],
            "marks": ["type": "array", "minItems": 1, "maxItems": 24, "items": mark]
          ]
        ]
      ]
    ]
  }

  private static func geminiSchema(_ value: Any, key: String? = nil) -> Any {
    if let object = value as? [String: Any] {
      return object.reduce(into: [String: Any]()) { result, entry in
        guard entry.key != "additionalProperties" else { return }
        result[entry.key] = geminiSchema(entry.value, key: entry.key)
      }
    }
    if let array = value as? [Any] {
      return array.map { geminiSchema($0, key: key) }
    }
    if key == "type", let type = value as? String {
      return type.uppercased()
    }
    return value
  }
}
