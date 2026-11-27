import Foundation

struct AgentTeamPlanWire: Sendable {
  let constrained: Bool
  static func canonicalEndpoint(_ endpoint: String) -> Bool {
    let pattern = #"^https?://(?:127\.0\.0\.1|\[::1\])(?::[0-9]{1,5})?/v1/chat/completions$"#
    guard endpoint.range(of: pattern, options: .regularExpression) != nil,
      let url = URLComponents(string: endpoint), url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
      url.percentEncodedPath == "/v1/chat/completions" else { return false }
    return url.port.map { (1...65_535).contains($0) } ?? true
  }
  static func select(system: String, endpoint: String, apiStyle: GalaxySSICloudAPIStyle, constrained: Bool) -> Self? {
    guard system == AgentConversationalTeamProtocol.planner, apiStyle == .openAICompatible, canonicalEndpoint(endpoint) else { return nil }
    return Self(constrained: constrained)
  }
  var system: String {
    """
    Plan, do not solve. Return only JSON: {"roles":[{"kind":"WORK","parents":[],"task":"assignment"}],"synthesis":"brief"}.
    Use roles: [] for simple work; otherwise choose the fewest useful roles (maximum 10). Do not copy placeholders.
    Kinds: WORK produces findings, REVIEW checks findings, CRITIC considers a counterposition.
    If the objective requests an independent review of the final answer, include a terminal REVIEW
    depending on relevant WORK. It sees the actual draft after synthesis. A worker cannot review itself.
    Parents are distinct one-based earlier role numbers, or []. Maximum three parents or children per role.
    Each task and synthesis is one nonblank line, at most 400 characters, no pipes. No other keys or prose.
    """ + "\n" + AgentConversationalTeamProtocol.boundary
  }
  var format: AgentMcpJSONObject {
    func array(_ items: AgentMcpJSONValue, max: Int64) -> AgentMcpJSONValue {
      .object(["type": .string("array"), "items": items, "maxItems": .int(max)])
    }
    func record(_ properties: AgentMcpJSONObject) -> AgentMcpJSONValue {
      .object(["type": .string("object"), "properties": .object(properties), "additionalProperties": .bool(false),
        "required": .array(properties.keys.sorted().map(AgentMcpJSONValue.string))])
    }
    let brief: AgentMcpJSONValue = .object(["type": .string("string"), "minLength": .int(1), "maxLength": .int(400)])
    let role = record(["kind": .object(["type": .string("string"), "enum": .array(["WORK", "REVIEW", "CRITIC"].map(AgentMcpJSONValue.string))]),
      "parents": array(.object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(10)]), max: 3), "task": brief])
    return ["type": .string("json_schema"), "json_schema": .object(["name": .string("team_plan"), "strict": .bool(true),
      "schema": record(["roles": array(role, max: 10), "synthesis": brief])])]
  }
  var requestFormat: AgentMcpJSONObject? { constrained ? format : nil }
  func apply(to request: ModelStreamRequest) throws -> ModelStreamRequest {
    guard let format = requestFormat else { return request }
    guard request.provider == .openAICompatible,
      var body = try JSONSerialization.jsonObject(with: Data(request.bodyJson.utf8)) as? [String: Any] else {
      throw AgentConversationalTeamProtocol.Failure.plan
    }
    body["response_format"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(format))
    var result = request; result.bodyJson = String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
    return result
  }
  func decode(_ reply: String) throws -> String {
    guard reply.utf16.count <= 6_000 else { throw AgentConversationalTeamProtocol.Failure.plan }
    let prefix = reply.components(separatedBy: "|").first ?? ""
    if !constrained, ["ROLE", "WORK", "REVIEW", "CRITIC", "SYNTHESIS"].contains(prefix) {
      let text = AgentConversationalTeamProtocol.trimLineEndings(reply)
      _ = try AgentConversationalTeamProtocol.plan(text); return text
    }
    var preflight = AgentTeamPlanJSONPreflight(reply); try preflight.validate()
    let object = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(reply.utf8))
    func brief(_ object: AgentMcpJSONObject, _ key: String) throws -> String {
      guard let value = object[key]?.strictStringValue, !value.isBlank, value.utf16.count <= 400,
        !value.contains("|"), !value.unicodeScalars.contains(where: {
          [.control, .format, .lineSeparator, .paragraphSeparator].contains($0.properties.generalCategory)
        }) else { throw AgentConversationalTeamProtocol.Failure.plan }
      return value
    }
    guard Set(object.keys) == ["roles", "synthesis"], let roles = object["roles"]?.arrayValue, roles.count <= 10 else {
      throw AgentConversationalTeamProtocol.Failure.plan
    }
    let lines: [String] = try roles.map { value in
      guard let role = value.objectValue, Set(role.keys) == ["kind", "parents", "task"],
        let kind = role["kind"]?.strictStringValue, ["WORK", "REVIEW", "CRITIC"].contains(kind),
        let parents = role["parents"]?.arrayValue else { throw AgentConversationalTeamProtocol.Failure.plan }
      let refs: [String] = try parents.map { value in
        guard case .int(let number) = value, (1...10).contains(number) else { throw AgentConversationalTeamProtocol.Failure.plan }
        return String(number)
      }
      return kind + "|" + (refs.isEmpty ? "-" : refs.joined(separator: ",")) + "|" + (try brief(role, "task"))
    }
    let canonical = (lines + ["SYNTHESIS|" + (try brief(object, "synthesis"))]).joined(separator: "\n")
    _ = try AgentConversationalTeamProtocol.plan(canonical)
    return canonical
  }
}
