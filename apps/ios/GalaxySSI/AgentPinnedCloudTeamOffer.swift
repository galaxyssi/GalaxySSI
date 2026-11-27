import Foundation

enum AgentPinnedCloudTeamOffer {
  static let name = "answer_with_optional_team_review"
  static let invalidCode = "INVALID_TEAM_REVIEW_ANSWER"
  struct Frames {
    private var id = ""
    private var valid = true
    var singleNativeSlot: Bool { valid && !id.isBlank }
    mutating func reject() { valid = false }
    mutating func observe(_ payload: ToolCallPayload) {
      valid = valid && payload.singleNativeFunction && payload.index == 0 &&
        (id.isEmpty || payload.callId.isEmpty || payload.callId == id)
      if id.isEmpty { id = payload.callId }
    }
  }
  static func advertise(_ request: ModelStreamRequest) throws -> ModelStreamRequest {
    guard request.provider == .openAICompatible,
      var body = try JSONSerialization.jsonObject(with: Data(request.bodyJson.utf8)) as? [String: Any],
      var tools = body["tools"] as? [[String: Any]], !tools.isEmpty, body["tool_choice"] as? String == "auto",
      !tools.contains(where: { ($0["function"] as? [String: Any])?["name"] as? String == name }) else { return request }
    tools.append(["type": "function", "function": ["name": name,
      "description": "Optional FINAL answer format, not an action. Only for a self-contained textual task where independent review could materially change the answer. Give the complete ordinary answer now, in the user's language. No other calls or message text. Omit for private, context-dependent or solo requests, or when actions or research are needed. The phone may offer review; no work has started.",
      "parameters": ["type": "object", "properties": ["answer": ["type": "string"],
        "propose_team_review": ["type": "boolean", "enum": [true]]],
        "required": ["answer", "propose_team_review"], "additionalProperties": false]]])
    body["tools"] = tools
    var result = request
    result.bodyJson = String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
    return result
  }
  static func answer(_ calls: [AssembledToolCall], frames: Frames, finish: String?, hasText: Bool) -> String? {
    guard calls.count == 1, let call = calls.first, frames.singleNativeSlot, !hasText,
      finish == "tool_calls", call.name == name, call.index == 0, !call.callId.isBlank,
      call.argumentsJson.utf8.count <= 64_000,
      let object = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(call.argumentsJson.utf8)),
      Set(object.keys) == ["answer", "propose_team_review"], object["propose_team_review"] == .bool(true),
      let answer = object["answer"]?.strictStringValue, !answer.isBlank, answer.utf16.count <= 8_000,
      !answer.contains("```galaxyssi-rich"), !CloudSupervisedResearch.isControlPayload(answer),
      !CloudWebGrounding.containsInternalToolProtocol(answer) else { return nil }
    return answer.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
