import Foundation

enum GalaxySSIHealthCarePlan {
  static let tool = "galaxyssi_health_plan_propose"
  static let description = """
    Retain one draft for explicit user review. Use only lifestyle, clinician discussion, measurement recheck,
    or context clarification. Do not prescribe, invent numeric targets, suggest delaying urgent care or claim to
    have scheduled anything. Use no review window unless justified. Citations are unverified source claims.
    """

  enum Kind: String, Codable, CaseIterable {
    case lifestyle = "LIFESTYLE"
    case clinicianDiscussion = "CLINICIAN_DISCUSSION"
    case recheck = "RECHECK"
    case context = "CONTEXT"
  }
  enum State: String, Codable { case pending, accepted, dismissed }
  struct Source: Codable, Equatable {
    let title: String
    let url: URL
    let version: String
    let applicability: String
    var provenance: GalaxySSIHealthCareEvidence.Provenance?
  }
  struct Action: Codable, Equatable, Identifiable {
    let id: Int
    let kind: Kind
    let description: String
    let rationale: String
    let sourceIndex: Int
    let dueFrom: Date?
    let dueUntil: Date?
    var applicability: GalaxySSIHealthCareApplicability.Review?
  }
  struct Draft: Codable, Equatable {
    let uncertainty: String
    let sources: [Source]
    let actions: [Action]
    var target: GalaxySSIHealthCareTarget.Proposal?
  }
  struct Proposal: Codable, Equatable, Identifiable {
    let id: UUID
    let concernID: UUID
    let metric: GalaxySSIHealthMetric
    let concernRevision: Int
    let assessmentDigest: String
    var sourceContext: GalaxySSIHealthCare.Context? = nil
    let carePermission: UUID
    let onlinePermission: UUID
    let contactID: String
    let modelID: String
    let endpoint: URL
    let destinationDigest: String
    let createdAt: Date
    let requestDigest: String
    let draft: Draft
    var state = State.pending
    var selected: Set<Int> = []
    var resolvedAt: Date?
    var targetAccepted: Bool?
  }
  struct AdoptedAction: Codable, Equatable, Identifiable {
    let proposalID: UUID
    let action: Action
    let source: Source
    let confirmedAt: Date
    var outcome: GalaxySSIHealthCareFollowUp.Outcome?
    var targetRevision: Int?
    var id: String { "\(proposalID.uuidString):\(action.id)" }
  }

  static var schema: [String: Any] {
    func string(_ maximum: Int, description: String = "") -> [String: Any] {
      ["type": "string", "maxLength": maximum, "description": description]
    }
    func object(_ properties: [String: Any]) -> [String: Any] {
      ["type": "object", "properties": properties, "required": properties.keys.sorted(), "additionalProperties": false]
    }
    func array(_ items: [String: Any]) -> [String: Any] {
      ["type": "array", "items": items, "minItems": 1, "maxItems": 8]
    }
    let date = string(40, description: "ISO 8601 with an explicit offset, or empty if no review window applies.")
    var envelope = object([
      "uncertainty": string(2_000, description: "Missing context, limitations and remaining uncertainty."),
      "sources": array(object(["title": string(300), "url": string(1_000, description: "Exact supplied HTTPS source URL."),
        "version": string(80), "applicability": string(2_000, description: "Population, applicability and limitations."),
        "evidence_id": string(36, description: "Exact ID from native_sources; reuse only with a different passage."),
        "quote": string(600, description: "Short original-language passage copied from the provided excerpt.")])),
      "actions": ["type": "array", "minItems": 0, "maxItems": 8, "items": object([
        "kind": ["type": "string", "enum": Kind.allCases.map(\.rawValue)],
        "description": string(1_000), "rationale": string(2_000, description: "Justify the step and any review window."),
        "source_index": ["type": "integer", "minimum": 0, "maximum": 7], "due_from": date, "due_until": date,
        "applicability": GalaxySSIHealthCareApplicability.schema])]
    ])
    var properties = envelope["properties"] as? [String: Any] ?? [:]
    properties["target"] = GalaxySSIHealthCareTarget.schema
    envelope["properties"] = properties
    return envelope
  }

  static func parse(_ args: AgentMcpJSONObject, evidence: [GalaxySSIHealthCareEvidence.Receipt], now: Date) throws -> Draft {
    let invalid = GalaxySSIHealthRecords.Failure.invalid
    func text(_ object: AgentMcpJSONObject, _ key: String, max: Int) throws -> String {
      guard let value = object[key]?.strictStringValue, !value.isBlank, value.utf8.count <= max else { throw invalid }
      return value
    }
    func date(_ object: AgentMcpJSONObject, _ key: String) throws -> Date? {
      guard let value = object[key]?.strictStringValue, value.utf8.count <= 40 else { throw invalid }
      if value.isEmpty { return nil }
      let formatter = ISO8601DateFormatter()
      guard value.range(of: #"(?:Z|[+-][0-9]{2}:[0-9]{2})$"#, options: .regularExpression) != nil
      else { throw invalid }
      if let parsed = formatter.date(from: value) { return parsed }
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      guard let parsed = formatter.date(from: value) else { throw invalid }
      return parsed
    }
    guard Set(args.keys).subtracting(["target"]) == ["uncertainty", "sources", "actions"],
          let rawSources = args["sources"]?.arrayValue, (1...8).contains(rawSources.count),
          let rawActions = args["actions"]?.arrayValue, rawActions.count <= 8
    else { throw invalid }
    let sources = try rawSources.map { row -> Source in
      guard let item = row.objectValue, Set(item.keys) == ["title", "url", "version", "applicability", "evidence_id", "quote"],
            let parts = URLComponents(string: try text(item, "url", max: 1_000)), parts.scheme == "https",
            parts.host?.isEmpty == false, parts.user == nil, parts.password == nil, let url = parts.url,
            let id = UUID(uuidString: try text(item, "evidence_id", max: 36)),
            let receipt = evidence.first(where: { $0.id == id }),
            let provenance = receipt.match(url: url, quote: try text(item, "quote", max: 2_400), fromModelExcerpt: true)
      else { throw invalid }
      _ = try text(item, "title", max: 300)
      return try .init(title: receipt.title, url: url, version: text(item, "version", max: 80),
        applicability: text(item, "applicability", max: 2_000), provenance: provenance)
    }
    var cited: [UUID: Set<String>] = [:]
    for source in sources {
      guard let provenance = source.provenance,
            cited[provenance.receiptID, default: []].insert(provenance.quote).inserted else { throw invalid }
    }
    let actions = try rawActions.enumerated().map { index, row -> Action in
      guard let item = row.objectValue,
            Set(item.keys) == ["kind", "description", "rationale", "source_index", "due_from", "due_until", "applicability"],
            let kind = item["kind"]?.strictStringValue.flatMap(Kind.init(rawValue:)),
            let review = item["applicability"]?.objectValue,
            case .int(let source)? = item["source_index"], source >= 0, source < Int64(sources.count)
      else { throw invalid }
      let from = try date(item, "due_from"), until = try date(item, "due_until")
      if let from, let until {
        guard from <= until, until >= now else { throw invalid }
      } else if from != nil || until != nil { throw invalid }
      return try .init(id: index, kind: kind, description: text(item, "description", max: 1_000),
        rationale: text(item, "rationale", max: 2_000), sourceIndex: Int(source), dueFrom: from, dueUntil: until,
        applicability: GalaxySSIHealthCareApplicability.parse(review, kind: kind, sourceCount: sources.count))
    }
    let target: GalaxySSIHealthCareTarget.Proposal?
    if let value = args["target"], value != .null {
      guard let body = value.objectValue else { throw invalid }
      target = try GalaxySSIHealthCareTarget.parse(body, sourceCount: sources.count)
    } else { target = nil }
    guard !actions.isEmpty || target != nil else { throw invalid }
    return try .init(uncertainty: text(args, "uncertainty", max: 2_000), sources: sources, actions: actions, target: target)
  }

  static func arguments(_ data: Data, style: GalaxySSICloudAPIStyle) throws -> AgentMcpJSONObject {
    let invalid = GalaxySSIHealthRecords.Failure.invalid
    let root = try JSONDecoder().decode(AgentMcpJSONObject.self, from: data)
    switch style {
    case .openAICompatible:
      guard let choices = root["choices"]?.arrayValue, choices.count == 1, let choice = choices.first?.objectValue,
            choice.string("finish_reason") == "tool_calls",
            let calls = choice["message"]?.objectValue?["tool_calls"]?.arrayValue, calls.count == 1,
            let call = calls.first?.objectValue, call.string("type") == "function",
            let function = call["function"]?.objectValue, function.string("name") == tool,
            let raw = function["arguments"]?.strictStringValue else { throw invalid }
      return try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(raw.utf8))
    case .anthropic:
      guard root.string("stop_reason") == "tool_use",
            let content = root["content"]?.arrayValue, (1...8).contains(content.count) else { throw invalid }
      let calls = content.compactMap(\.objectValue).filter { $0.string("type") == "tool_use" }
      guard content.allSatisfy({ ["text", "tool_use"].contains($0.objectValue?.string("type") ?? "") }),
            calls.count == 1, let call = calls.first, call.string("name") == tool,
            let input = call["input"]?.objectValue else { throw invalid }
      return input
    case .gemini:
      guard let candidates = root["candidates"]?.arrayValue, candidates.count == 1,
            let candidate = candidates.first?.objectValue, candidate.string("finishReason") == "STOP",
            let parts = candidate["content"]?.objectValue?["parts"]?.arrayValue, (1...8).contains(parts.count)
      else { throw invalid }
      let calls = parts.compactMap { $0.objectValue?["functionCall"]?.objectValue }
      guard parts.allSatisfy({ part in
        guard let object = part.objectValue else { return false }
        return object["functionCall"]?.objectValue != nil || object["text"]?.strictStringValue != nil
      }), calls.count == 1, let function = calls.first,
            function.string("name") == tool, let input = function["args"]?.objectValue else { throw invalid }
      return input
    }
  }
}
