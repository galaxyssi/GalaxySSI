import Foundation

struct GalaxySSIHealthFollowUp {
  enum Topic: String, Codable, Hashable {
    case changes = "CHANGES", coverage = "COVERAGE", sources = "SOURCES"
  }
  enum Action: String, Codable, CaseIterable, Identifiable {
    case addRecord = "ADD_RECORD", recordReminder = "RECORD_REMINDER", weeklyReport = "WEEKLY_REPORT"
    var id: String { rawValue }
  }
  struct Answer {
    enum Status: String, Codable {
      case answered = "ANSWERED", partial = "PARTIAL", outOfScope = "OUT_OF_SCOPE"
    }
    struct Section: Codable, Identifiable {
      let topic: Topic
      let factIDs: [String]
      var id: Topic { topic }
      enum CodingKeys: String, CodingKey { case topic; case factIDs = "fact_ids" }
    }
    fileprivate let analysisID: UUID
    fileprivate let selection: Selection
    var status: Status { selection.status }
    var sections: [Section] { selection.sections }
    var actions: [Action] { selection.actions }
  }
  fileprivate struct Selection: Codable {
    let status: Answer.Status
    let sections: [Answer.Section]
    let actions: [Action]
  }
  struct Comparison {
    let evidence: GalaxySSIHealthAnalysis.Evidence
    let mean: String
    let delta: String
  }
  private struct Fact: Encodable {
    let id: String
    let metric: String
    let component: String
    let unit: String
    let observedDays: Int
    let count: Int
    let mean: String?
    let previousMean: String?
    let delta: String?
    let previousObservedDays: Int?
    let filteredTrend: GalaxySSIHealthTrendAnalysis.Fact?
  }
  private struct Packet: Encodable {
    let question: String
    let requestedDays: Int
    let facts: [Fact]
    let allowedTopics: [Topic]
    let allowedActions: [Action]
    let previousAnswer: Selection?
    enum CodingKeys: String, CodingKey {
      case question, requestedDays, facts
      case allowedTopics = "allowed_topics", allowedActions = "allowed_actions", previousAnswer = "previous_answer"
    }
  }

  let analysisID: UUID
  let comparisons: [String: Comparison]
  let payload: Data
  private let ids: Set<String>
  private let sourceIDs: Set<String>
  private let changeIDs: Set<String>
  private let allowedActions: Set<Action>

  static func question(_ raw: String) -> String? {
    let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    guard !normalized.unicodeScalars.contains(where: { scalar in
      ((0...31).contains(scalar.value) || (127...159).contains(scalar.value)) && scalar.value != 9 && scalar.value != 10
    }) else { return nil }
    let question = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    return (1...600).contains(question.utf16.count) ? question : nil
  }

  init(analysis: GalaxySSIHealthAnalysis, baseline: GalaxySSIHealthAnalysis?, question raw: String,
       previous: Answer?) throws {
    guard let question = Self.question(raw), analysis.evidence.contains(where: { $0.aggregate.count > 0 })
    else { throw GalaxySSIHealthAnalysis.Failure.invalid }
    analysisID = analysis.id
    var matched: [String: Comparison] = [:]
    let facts = analysis.evidence.map { item -> Fact in
      let value = item.aggregate
      let prior = baseline?.evidence.first {
        $0.metric == item.metric && $0.aggregate.component == value.component && $0.aggregate.unit == value.unit
      }
      var previousDays: Int?
      if let prior, let now = value.mean.flatMap({ Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }),
         let mean = prior.aggregate.mean, let before = Decimal(string: mean, locale: Locale(identifier: "en_US_POSIX")) {
        let delta = now - before
        if !delta.isNaN {
          matched[item.id] = Comparison(evidence: prior, mean: mean, delta: NSDecimalNumber(decimal: delta).stringValue)
          previousDays = prior.aggregate.observedDays
        }
      }
      return Fact(id: item.id, metric: value.metric, component: value.component, unit: value.unit,
                  observedDays: value.observedDays, count: value.count, mean: matched[item.id] == nil ? nil : value.mean,
                  previousMean: matched[item.id]?.mean, delta: matched[item.id]?.delta ?? analysis.trendFact?.delta,
                  previousObservedDays: previousDays, filteredTrend: analysis.trendFact)
    }
    comparisons = matched
    ids = Set(facts.map(\.id))
    sourceIDs = Set(analysis.evidence.filter { !$0.readings.isEmpty }.map(\.id))
    changeIDs = Set(facts.filter { $0.delta != nil }.map(\.id))
    let topics: [Topic] = changeIDs.isEmpty ? [.coverage, .sources] : [.changes, .coverage, .sources]
    let actions: [Action] = analysis.trend == nil ? Action.allCases : [.addRecord, .recordReminder]
    allowedActions = Set(actions)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    payload = try encoder.encode(Packet(question: question, requestedDays: analysis.requestedDays, facts: facts,
      allowedTopics: topics, allowedActions: actions,
      previousAnswer: previous.flatMap { $0.analysisID == analysis.id ? $0.selection : nil }))
  }

  func answer(_ output: String) throws -> Answer {
    let invalid = GalaxySSIHealthAnalysis.Failure.invalid
    guard output.utf8.count <= 4_096 else { throw invalid }
    var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("```json\n"), text.hasSuffix("```") {
      text = String(text.dropFirst(8).dropLast(3))
    }
    let bytes = Data(text.utf8)
    guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
          Set(object.keys) == ["status", "sections", "actions"],
          let entries = object["sections"] as? [[String: Any]], entries.count <= 3,
          entries.allSatisfy({ Set($0.keys) == ["topic", "fact_ids"] }),
          Self.keyTokenCount(text) == 3 + entries.count * 2
    else { throw invalid }
    let result = try JSONDecoder().decode(Selection.self, from: bytes)
    guard Set(result.sections.map(\.topic)).count == result.sections.count,
          result.actions.count <= 2, Set(result.actions).count == result.actions.count,
          Set(result.actions).isSubset(of: allowedActions),
          (result.sections.isEmpty && result.actions.isEmpty) == (result.status == .outOfScope),
          result.sections.allSatisfy({ section in
            let allowed: Set<String>
            switch section.topic {
            case .changes: allowed = changeIDs
            case .coverage: allowed = ids
            case .sources: allowed = sourceIDs
            }
            return (1...3).contains(section.factIDs.count) && Set(section.factIDs).count == section.factIDs.count
              && Set(section.factIDs).isSubset(of: allowed)
          })
    else { throw invalid }
    return Answer(analysisID: analysisID, selection: result)
  }

  private static func keyTokenCount(_ text: String) -> Int {
    // Foundation collapses duplicate keys. Count string tokens followed by a colon before decoding.
    let strings = try? NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*"(\s*:)?"#)
    return strings?.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
      .filter { $0.range(at: 1).location != NSNotFound }.count ?? 0
  }
}

enum GalaxySSIHealthFollowUpTransport {
  private static let instruction = """
    Answer only from this scoped health analysis. Return exactly one JSON object with status, sections, and actions.
    Status is ANSWERED, PARTIAL, or OUT_OF_SCOPE. Sections have distinct allowed topic values and one to three distinct
    fact_ids per topic. CHANGES requires facts with a delta; SOURCES requires facts with count greater than zero.
    Use previous_answer only to resolve references within
    the same facts. Actions are zero to two distinct allowed action IDs. OUT_OF_SCOPE has no sections or actions;
    otherwise include at least one section or action. Use PARTIAL when only part of the question is supported.
    Do not return prose, numbers, extra keys, diagnoses, treatment, invented facts, or tool calls.
    """

  static func endpoint(for model: CloudModelConfig) -> URL? {
    guard (1...120).contains(model.modelId.utf16.count), !model.modelId.isEmpty,
          model.modelId.rangeOfCharacter(from: .controlCharacters) == nil,
          let parts = URLComponents(string: model.endpoint), parts.scheme?.lowercased() == "https",
          parts.host?.isEmpty == false, parts.user == nil, parts.password == nil,
          parts.query == nil, parts.fragment == nil,
          model.apiStyle != .gemini || parts.percentEncodedPath.hasSuffix(":generateContent")
    else { return nil }
    return parts.url
  }

  static func request(model: CloudModelConfig, key: String, packet: GalaxySSIHealthFollowUp) throws -> URLRequest {
    guard let endpoint = endpoint(for: model), let input = String(data: packet.payload, encoding: .utf8)
    else { throw GalaxySSIHealthAnalysis.Failure.invalid }
    var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let user = ["role": "user", "content": input]
    let body: [String: Any]
    switch model.apiStyle {
    case .anthropic:
      request.setValue(key, forHTTPHeaderField: "x-api-key")
      request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
      body = ["model": model.modelId, "max_tokens": 768, "system": instruction, "messages": [user]]
    case .gemini:
      request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
      body = ["systemInstruction": ["parts": [["text": instruction]]],
              "contents": [["role": "user", "parts": [["text": input]]]],
              "generationConfig": ["maxOutputTokens": 1024, "responseMimeType": "application/json"]]
    case .openAICompatible:
      request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
      let host = endpoint.host?.lowercased()
      var options: [String: Any] = ["model": model.modelId, "stream": false,
        "messages": [["role": "system", "content": instruction], user]]
      options[host == "api.openai.com" ? "max_completion_tokens" : "max_tokens"] = 1024
      if host == "api.openai.com" { options["store"] = false }
      if host == "api.deepseek.com" { options["thinking"] = ["type": "disabled"] }
      body = options
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    return request
  }

  static func output(_ data: Data, style: GalaxySSICloudAPIStyle) throws -> String {
    let invalid = GalaxySSIHealthAnalysis.Failure.invalid
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw invalid }
    switch style {
    case .openAICompatible:
      guard let choices = root["choices"] as? [[String: Any]], choices.count == 1,
            let choice = choices.first, choice["finish_reason"] as? String == "stop",
            let message = choice["message"] as? [String: Any],
            message["tool_calls"] == nil || message["tool_calls"] is NSNull,
            message["function_call"] == nil || message["function_call"] is NSNull,
            message["refusal"] == nil || message["refusal"] is NSNull,
            let text = message["content"] as? String else { throw invalid }
      return text
    case .anthropic:
      guard root["stop_reason"] as? String == "end_turn",
            let blocks = root["content"] as? [[String: Any]], !blocks.isEmpty,
            blocks.allSatisfy({ $0["type"] as? String == "text" && $0["text"] is String })
      else { throw invalid }
      return blocks.compactMap { $0["text"] as? String }.joined()
    case .gemini:
      guard let candidates = root["candidates"] as? [[String: Any]], candidates.count == 1,
            let candidate = candidates.first, candidate["finishReason"] as? String == "STOP",
            let content = candidate["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]], !parts.isEmpty,
            parts.allSatisfy({ Set($0.keys).isSubset(of: ["text", "thoughtSignature"]) && $0["text"] is String })
      else { throw invalid }
      return parts.compactMap { $0["text"] as? String }.joined()
    }
  }
}
