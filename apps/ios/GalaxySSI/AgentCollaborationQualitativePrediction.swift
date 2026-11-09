import Foundation

struct AgentCollaborationQualitativePrediction {
  enum Mode: String {
    case probabilistic, qualitative

    init?(_ forecast: AgentMcpJSONObject) {
      guard let field = forecast["prediction_mode"] else { self = .probabilistic; return }
      guard let value = field.strictStringValue, let mode = Self(rawValue: value) else { return nil }
      self = mode
    }
  }

  enum Expectation: String { case expected, notExpected = "not_expected", unknown }

  struct Event {
    let id: String
    let pointer: String
    let expected: AgentMcpJSONValue
  }

  private struct Test {
    let hypotheses: [String]
    let events: [String]
    let matrix: [String: [String: [String: Expectation]]]
  }

  private let events: [Event]
  private let selectedAction: String
  private let choices: [String: [String: Expectation]]
  private let test: Test?

  init?(_ forecast: AgentMcpJSONObject, actions: Set<String>) {
    let hasText = AgentCollaborationForecastIntake.hasText
    guard Mode(forecast) == .qualitative, forecast["utility_unit"] == nil,
          hasText(forecast, ["work_id", "executor", "horizon", "decision_rationale", "risk_tradeoff",
            "information_value", "revalidate_before_action"]),
          actions.contains(forecast.string("selected_action")),
          let rawEvents = forecast["events"]?.arrayValue, (1...32).contains(rawEvents.count),
          let rawChoices = forecast["choices"]?.arrayValue, rawChoices.count == actions.count else { return nil }
    var parsedEvents: [Event] = []
    var eventIDs: Set<String> = []
    for item in rawEvents {
      guard let event = item.objectValue, hasText(event, ["id", "meaning", "unit"]),
            event["utility_if_true"] == nil, event["utility_if_false"] == nil,
            let pointer = event["pointer"]?.strictStringValue, pointer.hasPrefix("/"),
            pointer.range(of: "~(?![01])", options: .regularExpression) == nil,
            let expected = event["expected"], Self.isScalar(expected),
            eventIDs.insert(event.string("id")).inserted else { return nil }
      parsedEvents.append(.init(id: event.string("id"), pointer: pointer, expected: expected))
    }
    var parsedChoices: [String: [String: Expectation]] = [:]
    for item in rawChoices {
      guard let choice = item.objectValue, hasText(choice, ["reasoning", "uncertainty", "resources", "risk"]),
            choice["probabilities"] == nil, actions.contains(choice.string("action_id")),
            let labels = Self.labels(choice["expectations"], ids: eventIDs),
            parsedChoices.updateValue(labels, forKey: choice.string("action_id")) == nil else { return nil }
    }
    if let field = forecast["hypothesis_test"] {
      guard let spec = field.objectValue,
            let parsed = Self.parseTest(spec, actions: actions, events: eventIDs) else { return nil }
      test = parsed
    } else { test = nil }
    events = parsedEvents
    choices = parsedChoices
    selectedAction = forecast.string("selected_action")
  }

  private static func labels(_ value: AgentMcpJSONValue?, ids: Set<String>) -> [String: Expectation]? {
    guard let raw = value?.objectValue, Set(raw.keys) == ids else { return nil }
    let parsed = raw.compactMapValues { $0.strictStringValue.flatMap(Expectation.init(rawValue:)) }
    return parsed.count == ids.count ? parsed : nil
  }

  private static func parseTest(_ spec: AgentMcpJSONObject, actions: Set<String>, events: Set<String>) -> Test? {
    guard AgentCollaborationForecastIntake.hasText(spec,
            ["question", "assumptions", "prediction_basis", "misspecification_check"]),
          ["likelihoods", "likelihood_basis", "prior_outcome", "conditional_history"].allSatisfy({ spec[$0] == nil }),
          let rows = spec["hypotheses"]?.arrayValue, (2...32).contains(rows.count),
          let rawIDs = spec["event_ids"]?.arrayValue, (1...32).contains(rawIDs.count),
          let matrix = spec["predictions"]?.objectValue, Set(matrix.keys) == actions else { return nil }
    let ids = rawIDs.compactMap(\.strictStringValue)
    let selected = Set(ids)
    guard ids.count == rawIDs.count, selected.count == ids.count, selected.isSubset(of: events) else { return nil }
    var hypotheses: [String] = []
    for entry in rows {
      guard let item = entry.objectValue, AgentCollaborationForecastIntake.hasText(item, ["id", "claim"]),
            item["prior"] == nil, !hypotheses.contains(item.string("id")) else { return nil }
      hypotheses.append(item.string("id"))
    }
    var result: [String: [String: [String: Expectation]]] = [:]
    for (action, value) in matrix {
      guard let entries = value.objectValue, Set(entries.keys) == Set(hypotheses) else { return nil }
      let parsed = entries.compactMapValues { labels($0, ids: selected) }
      guard parsed.count == hypotheses.count else { return nil }
      result[action] = parsed
    }
    return Test(hypotheses: hypotheses, events: ids, matrix: result)
  }

  var declaration: AgentMcpJSONObject {
    let actions: [AgentMcpJSONValue] = choices.keys.sorted().map { action in
      let distinguishing = test?.events.filter { event in
        let values = test?.matrix[action]?.values.compactMap { $0[event] } ?? []
        return values.contains(.expected) && values.contains(.notExpected)
      } ?? []
      return .object(["action_id": .string(action), "distinguishing_event_ids": .array(distinguishing.map(AgentMcpJSONValue.string)),
        "expected_information_gain_bits": .null, "expected_utility": .null])
    }
    return ["prediction_mode": .string("qualitative"), "state": .string("declared_qualitative_comparison"),
      "selected_action": .string(selectedAction), "action_information": .array(actions),
      "hypotheses_exhaustive_verified": .bool(false), "causality_proven": .bool(false)]
  }

  func feedback(withinValidity: Bool, measurement: (String) -> AgentMcpJSONValue?) -> AgentMcpJSONObject {
    var observed: [String: Bool] = [:]
    if withinValidity {
      for event in events {
        guard let value = measurement(event.pointer), Self.isScalar(value) else { continue }
        observed[event.id] = Self.equal(event.expected, value)
      }
    }
    func compare(_ labels: [String: Expectation], ids: [String]) -> AgentMcpJSONObject {
      var matched: [String] = [], contradicted: [String] = [], unresolved: [String] = []
      for id in ids {
        guard let expectation = labels[id], expectation != .unknown, let value = observed[id] else {
          unresolved.append(id); continue
        }
        if value == (expectation == .expected) { matched.append(id) } else { contradicted.append(id) }
      }
      return ["state": .string(!contradicted.isEmpty ? "contradicted" : unresolved.isEmpty
        ? "consistent_with_observation" : "unresolved"), "matched_event_ids": .array(matched.map(AgentMcpJSONValue.string)),
        "contradicted_event_ids": .array(contradicted.map(AgentMcpJSONValue.string)),
        "unresolved_event_ids": .array(unresolved.map(AgentMcpJSONValue.string))]
    }
    let hypotheses: [AgentMcpJSONObject] = test.map { spec in
      spec.hypotheses.map { id in
        var row = compare(spec.matrix[selectedAction]?[id] ?? [:], ids: spec.events)
        row["hypothesis_id"] = .string(id)
        return row
      }
    } ?? []
    let ids = test?.events ?? events.map(\.id)
    let count = ids.filter { observed[$0] != nil }.count
    let allContradicted = !hypotheses.isEmpty && hypotheses.allSatisfy { $0["state"] == .string("contradicted") }
    let state = allContradicted ? "contradicted_hypothesis_space"
      : count < ids.count ? "incomplete_observation" : "compared_with_observation"
    return ["prediction_mode": .string("qualitative"), "state": .string(state),
      "action": .object(compare(choices[selectedAction] ?? [:], ids: events.map(\.id))),
      "hypotheses": .array(hypotheses.map(AgentMcpJSONValue.object)),
      "observed_events": .int(Int64(count)), "registered_events": .int(Int64(ids.count)), "scored_events": .int(0),
      "posterior": .null, "information_gain_bits": .null, "brier_scores": .null, "expected_utility": .null,
      "causality_proven": .bool(false), "hypothesis_proven": .bool(false)]
  }

  private static func isScalar(_ value: AgentMcpJSONValue) -> Bool {
    switch value {
    case .object, .array: return false
    case .double(let number): return number.isFinite
    default: return true
    }
  }

  private static func equal(_ lhs: AgentMcpJSONValue, _ rhs: AgentMcpJSONValue) -> Bool {
    switch (lhs, rhs) {
    case (.int(let integer), .double(let number)), (.double(let number), .int(let integer)):
      return Int64(exactly: number) == integer
    default: return lhs == rhs
    }
  }
}
