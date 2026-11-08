import Foundation

enum GalaxySSIHealthCareQuestions {
  static let pageSize = 8
  static let maximumQuestions = 120
  static let maximumRevisions = 32
  static let tool = "galaxyssi_health_questions_propose"
  static let instruction = """
    Propose only necessary unresolved clarification questions for this concern. Use stable lowercase keys such as
    context.fasting_hours or profile.height for known field categories. Respect answered, deferred and declined
    questions, and do not treat stale or conflicting replies as current facts. Never supply an answer for the user.
    Return an empty questions array if nothing material remains. This tool cannot make or adopt a treatment plan.
    """

  static func configure(_ body: inout [String: Any], style: GalaxySSICloudAPIStyle) {
    let fields: [String: Any] = ["key": ["type": "string", "maxLength": 80],
      "question": ["type": "string", "maxLength": 500], "purpose": ["type": "string", "maxLength": 1_000]]
    let item: [String: Any] = ["type": "object", "required": fields.keys.sorted(), "properties": fields,
      "additionalProperties": false]
    let schema: [String: Any] = ["type": "object", "required": ["questions"], "additionalProperties": false,
      "properties": ["questions": ["type": "array", "maxItems": 8, "items": item]]]
    switch style {
    case .openAICompatible:
      body["tools"] = [["type": "function", "function": ["name": tool, "description": instruction, "parameters": schema]]]
      body["tool_choice"] = ["type": "function", "function": ["name": tool]]
    case .anthropic:
      body["tools"] = [["name": tool, "description": instruction, "input_schema": schema]]
      body["tool_choice"] = ["type": "tool", "name": tool, "disable_parallel_tool_use": true]
    case .gemini:
      body["tools"] = [["functionDeclarations": [["name": tool, "description": instruction, "parametersJsonSchema": schema]]]]
      body["toolConfig"] = ["functionCallingConfig": ["mode": "ANY", "allowedFunctionNames": [tool]]]
    }
  }

  static func parse(_ args: AgentMcpJSONObject) throws -> [Proposal] {
    let invalid = GalaxySSIHealthRecords.Failure.invalid
    guard Set(args.keys) == ["questions"], let rows = args["questions"]?.arrayValue, rows.count <= pageSize
    else { throw invalid }
    let values: [Proposal] = try rows.map { row in
      guard let item = row.objectValue, Set(item.keys) == ["key", "question", "purpose"],
            let key = item["key"]?.strictStringValue, key.utf8.count <= 80,
            key.range(of: #"\A[a-z][a-z0-9_.]{0,79}\z"#, options: .regularExpression) != nil,
            let question = item["question"]?.strictStringValue, !question.isBlank, question.utf8.count <= 500,
            let purpose = item["purpose"]?.strictStringValue, !purpose.isBlank, purpose.utf8.count <= 1_000
      else { throw invalid }
      return .init(key: key, question: question, purpose: purpose)
    }
    guard Set(values.map(\.key)).count == values.count else { throw invalid }
    return values
  }

  enum State: String, Codable { case open, answered, deferred, declined, conflict, stale }

  struct Proposal: Codable, Equatable {
    let key: String
    let question: String
    let purpose: String
  }

  struct Row: Codable, Equatable, Identifiable {
    var id = UUID()
    let proposal: Proposal
    let scope: String
    var basis: String
    let turn: UUID
    let createdAt: Date
    var updatedAt: Date
    var revision = 1
    var state = State.open
    var answer: String?

    func displayedState(basis current: String, known: AgentMcpJSONValue?) -> State {
      if basis != current { return .stale }
      if state == .conflict { return .conflict }
      if known != nil { return .answered }
      return state
    }
  }

  struct Page {
    let rows: [Row]
    let basis: String
    let known: AgentMcpJSONObject
    let next: UUID?

    func state(_ row: Row) -> State { row.displayedState(basis: basis, known: known[row.proposal.key]) }

    var payload: AgentMcpJSONObject {
      ["items": .array(rows.map { row in
        let state = state(row)
        return .object(["key": .string(row.proposal.key), "question": state == .stale ? .null : .string(row.proposal.question),
          "purpose": state == .stale ? .null : .string(row.proposal.purpose),
          "state": .string(state.rawValue), "revision": .int(Int64(row.revision)),
          "reviewed_answer": state == .stale ? .null : row.answer.map(AgentMcpJSONValue.string) ?? .null,
          "saved_fact": known[row.proposal.key] ?? .null, "ask_again": .bool(state == .open)])
      }), "has_more": .bool(next != nil), "answers_are_self_reports": .bool(true)]
    }
  }

  struct Ledger: Codable {
    var revisions: [String: [Row]] = [:]

    func page(scope: String, basis: String, known: AgentMcpJSONObject, after: UUID?) throws -> Page {
      let current = revisions.values.compactMap(\.last).filter { $0.scope == scope }.sorted {
        ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString)
      }
      let start: Int
      if let after {
        guard let index = current.firstIndex(where: { $0.id == after }) else { throw GalaxySSIHealthRecords.Failure.stale }
        start = index + 1
      } else { start = 0 }
      let rows = Array(current.dropFirst(start).prefix(pageSize))
      return .init(rows: rows, basis: basis, known: known, next: start + rows.count < current.count ? rows.last?.id : nil)
    }

    mutating func propose(_ values: [Proposal], scope: String, basis: String, known: AgentMcpJSONObject,
                          turn: UUID, now: Date) throws {
      let existing = Set(revisions.values.compactMap(\.last).filter { $0.scope == scope }.map(\.proposal.key))
      let new = values.filter { known[$0.key] == nil && !existing.contains($0.key) }
      guard revisions.count + new.count <= maximumQuestions else { throw GalaxySSIHealthRecords.Failure.invalid }
      for value in new {
        let row = Row(proposal: value, scope: scope, basis: basis, turn: turn, createdAt: now, updatedAt: now)
        revisions[row.id.uuidString] = [row]
      }
    }

    mutating func review(_ expected: Row, scope: String, basis: String, state: State, answer: String?, now: Date) throws {
      let id = expected.id.uuidString
      let text = answer?.trimmingCharacters(in: .whitespacesAndNewlines)
      let needsAnswer = state == .answered || state == .conflict
      guard expected.scope == scope, state != .stale, now >= expected.updatedAt,
            var history = revisions[id], history.last == expected, history.count < maximumRevisions,
            state == .open || expected.basis == basis,
            state == .open || (expected.state != .deferred && expected.state != .declined),
            needsAnswer ? text.map({ !$0.isEmpty && $0.utf8.count <= 2_000 }) == true : text == nil
      else { throw GalaxySSIHealthRecords.Failure.stale }
      var next = expected
      next.revision += 1
      next.basis = basis
      next.state = state
      next.answer = text
      next.updatedAt = now
      history.append(next)
      revisions[id] = history
    }
  }

  static func scope(_ concern: GalaxySSIHealthCare.Concern) -> String {
    let selection = concern.profileScope?.selection
    return AgentModelLoopRecoveryIdentity.sha256([
      "fields": selection?.fields.map(\.rawValue).sorted().joined(separator: ",") ?? "",
      "entries": selection?.entries.map(\.uuidString).sorted().joined(separator: ",") ?? ""
    ])
  }

  static func basis(_ concern: GalaxySSIHealthCare.Concern) throws -> String {
    var context = concern.context
    context?.confirmedAt = nil
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try AgentModelLoopRecoveryIdentity.sha256([
      "record": String(decoding: encoder.encode(concern.assessment.record), as: UTF8.self),
      "context": String(decoding: encoder.encode(context), as: UTF8.self),
      "profile_versions": String(decoding: encoder.encode(concern.profileScope?.versions), as: UTF8.self)
    ])
  }

  static func known(_ concern: GalaxySSIHealthCare.Concern, profile: AgentMcpJSONObject?) throws -> AgentMcpJSONObject {
    var facts: AgentMcpJSONObject = [:]
    if let context = concern.context, context.record == concern.assessment.record, let answers = context.answers {
      let encoded = try JSONEncoder().encode(answers)
      let saved = try JSONDecoder().decode(AgentMcpJSONObject.self, from: encoded)
      for (key, value) in saved { facts["context." + key] = value }
    }
    for (key, value) in profile?["fields"]?.objectValue ?? [:] {
      if let item = value.objectValue, item["state"] == .string("known"), let known = item["value"], known != .null {
        facts["profile." + key.lowercased()] = known
      }
    }
    return facts
  }

  static func matches(_ text: String?, fact: AgentMcpJSONValue) -> Bool {
    guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
    switch fact {
    case .bool(let flag): return (flag ? ["yes", "true"] : ["no", "false"]).contains(value)
    case .int(let number): return value == String(number)
    case .string(let string): return value == string.lowercased()
    default: return value == AgentMcpJSONCodec.stringify(fact).lowercased()
    }
  }
}
