import Foundation

enum GalaxySSIHealthCareHistoryTool {
  static let function = "galaxyssi_health_history_read"
  static let maximumPages = 4
  static let pageBudget = 12_000
  static let requestBudget = 180_000
  static let instructions = """
    Only the approved concern's contiguous measurement_history is available. To read the next older page,
    call galaxyssi_health_history_read with the exact input_version and cursor from next in the latest page.
    Use only returned evidence. Explain gaps in coverage and comparability; never infer clinical stability from numbers.
    Do not count a corrected record twice. If a plan is requested, its call must be final and not parallel with history.
    """

  struct Output: Equatable {
    let payload: AgentMcpJSONObject
    let cursor: GalaxySSIHealthCareSeries.Cursor?
    let token: String?

    func authorizes(_ input: AgentMcpJSONObject, turn: UUID) -> Bool {
      guard let token, cursor != nil else { return false }
      return input == ["input_version": .string(turn.uuidString), "cursor": .string(token)]
    }
  }

  struct Approval {
    let binding: GalaxySSIHealthCareSeries.Binding
    let recent: Output
  }

  static func output(_ page: GalaxySSIHealthCareSeries.Page, metric: GalaxySSIHealthMetric,
                     turn: UUID, remaining: Int) throws -> Output {
    let cursor = remaining > 0 ? page.next : nil
    let token = cursor.map { _ in UUID().uuidString }
    let rows: [AgentMcpJSONValue] = try page.rows.map { row in
      guard let time = Int64(exactly: (row.measuredAt.timeIntervalSince1970 * 1_000).rounded(.down))
      else { throw invalid }
      return .object(["measured_at_unix_ms": .int(time), "result": .string(row.result), "unit": .string(row.unit),
        "gaps_against_current": .array(row.gaps.map { .string($0.rawValue) })])
    }
    let payload: AgentMcpJSONObject = [
      "protocol": .string(GalaxySSIHealthCareSeries.wireProtocol), "input_version": .string(turn.uuidString),
      "metric": .string(metric.rawValue), "samples": .array(rows), "has_earlier": .bool(page.next != nil),
      "stability_verified": .bool(false), "next": token.map {
        .object(["input_version": .string(turn.uuidString), "cursor": .string($0)])
      } ?? .null
    ]
    guard AgentMcpJSONCodec.stringify(payload).utf8.count <= pageBudget else { throw invalid }
    return .init(payload: payload, cursor: cursor, token: token)
  }

  static func configure(_ body: inout [String: Any], style: GalaxySSICloudAPIStyle,
                        proposesPlan: Bool, historyAvailable: Bool, allowsMaintenance: Bool = false,
                        questionsAvailable: Bool = false, asksQuestions: Bool = false, feedbackAvailable: Bool = false,
                        journalAvailable: Bool = false) {
    for key in ["tools", "tool_choice", "toolConfig", "parallel_tool_calls"] { body.removeValue(forKey: key) }
    let plan = GalaxySSIHealthCarePlan.tool
    let schema: [String: Any] = [
      "type": "object", "required": ["input_version", "cursor"], "additionalProperties": false,
      "properties": ["input_version": ["type": "string"], "cursor": ["type": "string"]]
    ]
    var tools: [(String, String, [String: Any])] = []
    if journalAvailable {
      let journal = GalaxySSIHealthVisitJournalRead.self
      tools.append((journal.providerName, journal.instructions, journal.schema))
    }
    if historyAvailable { tools.append((function, instructions, schema)) }
    if questionsAvailable {
      tools.append((GalaxySSIHealthCareQuestions.readTool, GalaxySSIHealthCareQuestions.readInstruction, schema))
    }
    if feedbackAvailable {
      let feedback = GalaxySSIHealthCareFeedbackTool.self
      tools.append((feedback.function, feedback.instructions, feedback.schema))
    }
    if asksQuestions {
      tools.append((GalaxySSIHealthCareQuestions.tool, GalaxySSIHealthCareQuestions.instruction, GalaxySSIHealthCareQuestions.schema))
    }
    if proposesPlan {
      tools.append((plan, GalaxySSIHealthCarePlan.description,
        GalaxySSIHealthCarePlan.schema(allowsMaintenance: allowsMaintenance)))
    }
    guard !tools.isEmpty else { return }
    let required = !historyAvailable && !questionsAvailable && !feedbackAvailable && !journalAvailable ? tools.first?.0 : nil
    switch style {
    case .openAICompatible:
      body["tools"] = tools.map {
        ["type": "function", "function": ["name": $0.0, "description": $0.1, "parameters": $0.2] as [String: Any]]
          as [String: Any]
      }
      if let required { body["tool_choice"] = ["type": "function", "function": ["name": required]] }
    case .anthropic:
      body["tools"] = tools.map { ["name": $0.0, "description": $0.1, "input_schema": $0.2] as [String: Any] }
      if let required {
        body["tool_choice"] = ["type": "tool", "name": required, "disable_parallel_tool_use": true]
      } else { body["tool_choice"] = ["type": "auto", "disable_parallel_tool_use": true] }
    case .gemini:
      body["tools"] = [["functionDeclarations": tools.map {
        ["name": $0.0, "description": $0.1, "parametersJsonSchema": $0.2] as [String: Any]
      }]]
      if let required { body["toolConfig"] = ["functionCallingConfig": ["mode": "ANY", "allowedFunctionNames": [required]]] }
    }
  }

  struct Call {
    let name: String
    let arguments: AgentMcpJSONObject
    let message: AgentMcpJSONObject
    let id: String?
  }

  static func call(_ bytes: Data, style: GalaxySSICloudAPIStyle, proposesPlan: Bool,
                   allowsQuestionRead: Bool = false, asksQuestions: Bool = false,
                   allowsAnswerDraft: Bool = false, allowsFeedbackRead: Bool = false,
                   allowsJournalRead: Bool = false) throws -> Call? {
    let root = try JSONDecoder().decode(AgentMcpJSONObject.self, from: bytes)
    let message: AgentMcpJSONObject
    let calls: [AgentMcpJSONObject]
    let terminal: Bool
    switch style {
    case .openAICompatible:
      guard let choices = root["choices"]?.arrayValue, choices.count == 1,
            let choice = choices.first?.objectValue, let response = choice["message"]?.objectValue else { throw invalid }
      message = response
      terminal = choice.string("finish_reason") == "tool_calls"
      if let raw = response["tool_calls"], raw != .null {
        guard let array = raw.arrayValue, array.allSatisfy({ $0.objectValue != nil }) else { throw invalid }
        calls = array.compactMap(\.objectValue)
      } else { calls = [] }
      if terminal && calls.isEmpty { throw invalid }
    case .anthropic:
      guard let content = root["content"]?.arrayValue, (1...8).contains(content.count) else { throw invalid }
      message = ["role": .string("assistant"), "content": .array(content)]
      guard content.allSatisfy({ $0.objectValue != nil }) else { throw invalid }
      calls = content.compactMap(\.objectValue).filter { $0.string("type") == "tool_use" }
      terminal = root.string("stop_reason") == "tool_use"
      if terminal && calls.isEmpty { throw invalid }
    case .gemini:
      guard let candidates = root["candidates"]?.arrayValue, candidates.count == 1,
            let candidate = candidates.first?.objectValue, let response = candidate["content"]?.objectValue,
            let parts = response["parts"]?.arrayValue, (1...8).contains(parts.count) else { throw invalid }
      message = response
      guard parts.allSatisfy({ part in
        guard let object = part.objectValue else { return false }
        return object["functionCall"].map { $0.objectValue != nil } ?? true
      }) else { throw invalid }
      calls = parts.compactMap { $0.objectValue?["functionCall"]?.objectValue }
      terminal = candidate.string("finishReason") == "STOP"
    }
    if calls.isEmpty { return nil }
    guard terminal, calls.count == 1, let entry = calls.first else { throw invalid }
    let spec = style == .openAICompatible ? entry["function"]?.objectValue : entry
    guard let spec else { throw invalid }
    let name = spec.string("name")
    if proposesPlan && name == GalaxySSIHealthCarePlan.tool || asksQuestions && name == GalaxySSIHealthCareQuestions.tool {
      return nil
    }
    let answerDraft = allowsAnswerDraft && name == GalaxySSIHealthCareAnswerDraft.tool
    guard name == function || (allowsQuestionRead && name == GalaxySSIHealthCareQuestions.readTool) ||
          answerDraft || (allowsFeedbackRead && name == GalaxySSIHealthCareFeedbackTool.function) ||
          (allowsJournalRead && name == GalaxySSIHealthVisitJournalRead.providerName) else { throw invalid }
    let id = entry["id"]?.strictStringValue
    guard (style == .gemini && id == nil) || id.map({ !$0.isBlank && $0.utf8.count <= 256 }) == true else { throw invalid }
    let args: AgentMcpJSONObject
    switch style {
    case .openAICompatible:
      guard entry.string("type") == "function", let raw = spec["arguments"]?.strictStringValue,
            raw.utf8.count <= (answerDraft ? 25_000 : 1_024)
      else { throw invalid }
      args = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(raw.utf8))
    case .anthropic:
      guard let input = spec["input"]?.objectValue else { throw invalid }
      args = input
    case .gemini:
      guard let input = spec["args"]?.objectValue else { throw invalid }
      args = input
    }
    return Call(name: name, arguments: args, message: message, id: id)
  }

  static func continuing(_ request: URLRequest, with call: Call, output: Output, style: GalaxySSICloudAPIStyle,
                         proposesPlan: Bool, historyAvailable: Bool, allowsMaintenance: Bool = false) throws -> URLRequest {
    try continuing(request, with: call, payload: output.payload, style: style, proposesPlan: proposesPlan,
      historyAvailable: historyAvailable, allowsMaintenance: allowsMaintenance)
  }

  static func continuing(_ request: URLRequest, with call: Call, payload: AgentMcpJSONObject, style: GalaxySSICloudAPIStyle,
      proposesPlan: Bool, historyAvailable: Bool, allowsMaintenance: Bool, questionsAvailable: Bool = false,
      asksQuestions: Bool = false, feedbackAvailable: Bool = false, journalAvailable: Bool = false) throws -> URLRequest {
    guard let bytes = request.httpBody, var body = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
    else { throw invalid }
    let channel = style == .gemini ? "contents" : "messages"
    guard var messages = body[channel] as? [[String: Any]] else { throw invalid }
    let assistant = try JSONSerialization.jsonObject(with: Data(AgentMcpJSONCodec.stringify(call.message).utf8))
    guard var message = assistant as? [String: Any] else { throw invalid }
    message["role"] = style == .gemini ? "model" : "assistant"
    messages.append(message)
    let text = AgentMcpJSONCodec.stringify(payload)
    switch style {
    case .openAICompatible:
      guard let id = call.id else { throw invalid }
      messages.append(["role": "tool", "tool_call_id": id, "content": text])
    case .anthropic:
      guard let id = call.id else { throw invalid }
      messages.append(["role": "user", "content": [["type": "tool_result", "tool_use_id": id, "content": text]]])
    case .gemini:
      var result: [String: Any] = ["name": call.name, "response": try JSONSerialization.jsonObject(with: Data(text.utf8))]
      if let id = call.id { result["id"] = id }
      messages.append(["role": "user", "parts": [["functionResponse": result]]])
    }
    body[channel] = messages
    configure(&body, style: style, proposesPlan: proposesPlan, historyAvailable: historyAvailable,
      allowsMaintenance: allowsMaintenance, questionsAvailable: questionsAvailable, asksQuestions: asksQuestions,
      feedbackAvailable: feedbackAvailable, journalAvailable: journalAvailable)
    let data = try JSONSerialization.data(withJSONObject: body)
    guard data.count <= requestBudget else { throw invalid }
    var next = request
    next.httpBody = data
    return next
  }

  private static let invalid = GalaxySSIHealthRecords.Failure.invalid
}
