import Foundation

final class AgentTeamWriterFormatSession: @unchecked Sendable {
  private struct Endpoint: Equatable {
    let scheme: String, host: String
    let port: Int?
    init?(_ value: String) {
      guard AgentTeamPlanWire.canonicalEndpoint(value), let parts = URLComponents(string: value),
        let scheme = parts.scheme, let host = parts.host else { return nil }
      self.scheme = scheme; self.host = host; port = parts.port
    }
  }
  private let lock = NSLock()
  private var confirmed: Endpoint?

  func observe(endpoint: String, responseURL: String, server: String?) {
    let source = Endpoint(endpoint), destination = Endpoint(responseURL)
    let product = server?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let recognized = product.utf8.count <= 128 &&
      product.range(of: #"^llama\.cpp(?:/[A-Za-z0-9._-]+)?$"#, options: [.regularExpression, .caseInsensitive]) != nil
    lock.lock(); defer { lock.unlock() }
    confirmed = source != nil && source == destination && recognized ? source : nil
  }
  func format(system: String, endpoint: String, stage: String) -> AgentMcpJSONObject? {
    lock.lock(); let known = confirmed; lock.unlock()
    guard let known, known == Endpoint(endpoint), system == AgentTeamPredictionContrast.writer,
      ["synthesis", "rewrite"].contains(stage) else { return nil }
    let text: AgentMcpJSONValue = .object(["type": .string("string")])
    let direction: AgentMcpJSONValue = .object(["type": .string("string"), "enum": .array(["higher", "lower"].map(AgentMcpJSONValue.string))])
    func record(_ fields: AgentMcpJSONObject) -> AgentMcpJSONValue {
      .object(["type": .string("object"), "properties": .object(fields),
        "required": .array(fields.keys.sorted().map(AgentMcpJSONValue.string)), "additionalProperties": .bool(false)])
    }
    let claim = record(["purpose": text, "input": text, "input_direction": direction, "readout": text,
      "expected_direction": direction, "alternative": text, "gap": text])
    let schema = stage == "rewrite" ? claim : .object(["anyOf": .array([claim, record(["answer": text])])])
    return ["type": .string("json_schema"), "json_schema": .object(["name": .string("team_prediction"),
      "strict": .bool(true), "schema": schema])]
  }
  func apply(to request: ModelStreamRequest, system: String, stage: String) throws -> ModelStreamRequest {
    guard request.provider == .openAICompatible, let format = format(system: system, endpoint: request.endpoint, stage: stage) else { return request }
    guard var body = try JSONSerialization.jsonObject(with: Data(request.bodyJson.utf8)) as? [String: Any] else {
      throw AgentConversationGoal.Failure.invalid
    }
    body["response_format"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(format))
    var result = request
    result.bodyJson = String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
    return result
  }
}
