import Foundation

enum AgentCollaborationNumericTrial {
  static let validatorId = "numeric_model_cases.v1"
  private typealias Expression = ([String: Double]) -> Double?
  private static let unary: [String: (Double) -> Double] = [
    "neg": { -$0 }, "abs": { abs($0) }, "exp": { exp($0) }, "expm1": { expm1($0) },
    "log": { log($0) }, "log1p": { log1p($0) }, "sqrt": { sqrt($0) },
    "sin": { sin($0) }, "cos": { cos($0) }
  ]
  private static let binary: [String: (Double, Double) -> Double] = [
    "add": { $0 + $1 }, "sub": { $0 - $1 }, "mul": { $0 * $1 }, "div": { $0 / $1 },
    "pow": { pow($0, $1) }, "min": { min($0, $1) }, "max": { max($0, $1) }
  ]

  static func evaluate(_ trial: AgentMcpJSONObject) -> AgentMcpJSONObject? {
    guard Set(trial.keys).subtracting(["previous_trial"]) == ["purpose", "reference_basis", "limitations", "validator", "computation"],
          AgentCollaborationForecastIntake.hasText(trial, ["purpose", "reference_basis", "limitations"]),
          let spec = trial["validator"]?.objectValue, Set(spec.keys) == ["id", "variables", "cases"],
          spec["id"] == .string(validatorId), let names = spec["variables"]?.arrayValue,
          (1...64).contains(names.count), let cases = spec["cases"]?.arrayValue, (1...4_096).contains(cases.count),
          let computation = trial["computation"]?.objectValue, Set(computation.keys) == ["validator_id", "model"],
          computation["validator_id"] == .string(validatorId), let model = computation["model"]?.objectValue
    else { return nil }
    let variables = Set(names.compactMap(\.strictStringValue))
    guard variables.count == names.count, variables.allSatisfy({
      $0.range(of: "^[A-Za-z][A-Za-z0-9_]{0,63}$", options: .regularExpression) != nil
    }) else { return nil }
    var nodes = 0
    guard let expression = compile(model, variables: variables, depth: 1, nodes: &nodes),
          nodes * cases.count <= 2_000_000 else { return nil }
    var ids = Set<String>()
    var checks: [AgentMcpJSONValue] = []
    var failures = 0
    var domainErrors = 0
    for item in cases {
      guard let row = item.objectValue, Set(row.keys) == ["id", "input", "expected", "absolute_tolerance"],
            let id = row["id"]?.strictStringValue, !id.isBlank, id.utf8.count <= 128, ids.insert(id).inserted,
            let inputs = row["input"]?.objectValue, Set(inputs.keys) == variables,
            let expected = number(row["expected"]), let tolerance = number(row["absolute_tolerance"]), tolerance >= 0
      else { return nil }
      let values = inputs.compactMapValues { number($0) }
      guard values.count == inputs.count else { return nil }
      var check: AgentMcpJSONObject = ["id": .string(id), "passed": .bool(false)]
      if let actual = expression(values) {
        let error = abs(actual - expected)
        let passed = error.isFinite && error <= tolerance
        check["actual"] = .double(actual)
        check["absolute_error"] = error.isFinite ? .double(error) : .null
        check["passed"] = .bool(passed)
        if !passed { failures += 1 }
      } else {
        check["error"] = .string("nonfinite_expression_result")
        failures += 1
        domainErrors += 1
      }
      checks.append(.object(check))
    }
    return [
      "validator_id": .string(validatorId), "passed": .bool(failures == 0),
      "case_count": .int(Int64(cases.count)), "failed_cases": .int(Int64(failures)),
      "domain_error_cases": .int(Int64(domainErrors)), "checks": .array(checks),
      "spec_sha256": .string(fingerprint(spec)), "model_sha256": .string(fingerprint(model)),
      "meaning": .string("host_float64_replay_not_reference_truth_or_generalization")
    ]
  }

  static func comparison(previous: AgentMcpJSONObject, current: AgentMcpJSONObject) -> AgentMcpJSONObject? {
    guard previous["spec_sha256"] == current["spec_sha256"],
          let before = previous["checks"]?.arrayValue?.compactMap(\.objectValue),
          let after = current["checks"]?.arrayValue?.compactMap(\.objectValue),
          before.count == after.count else { return nil }
    var transitions: [String: [AgentMcpJSONValue]] = [:]
    for (old, new) in zip(before, after) {
      guard let id = old["id"], id == new["id"] else { return nil }
      let oldPass = old["passed"] == .bool(true)
      let newPass = new["passed"] == .bool(true)
      if !oldPass && newPass { transitions["improved", default: []].append(id) }
      if oldPass && !newPass { transitions["regressed", default: []].append(id) }
      if old["error"] != nil && new["error"] == nil { transitions["domain_recovered", default: []].append(id) }
      if old["error"] == nil && new["error"] != nil { transitions["domain_failed", default: []].append(id) }
      if let a = number(old["absolute_error"]), let b = number(new["absolute_error"]) {
        if b < a { transitions["error_reduced", default: []].append(id) }
        if b > a { transitions["error_increased", default: []].append(id) }
      }
    }
    var result: AgentMcpJSONObject = ["same_registered_cases": .bool(true),
      "model_changed": .bool(previous["model_sha256"] != current["model_sha256"])]
    for key in ["improved", "regressed", "domain_recovered", "domain_failed", "error_reduced", "error_increased"] {
      result[key + "_case_ids"] = .array(transitions[key] ?? [])
    }
    return result
  }

  private static func compile(_ node: AgentMcpJSONObject, variables: Set<String>, depth: Int,
                              nodes: inout Int) -> Expression? {
    nodes += 1
    guard depth <= 48, nodes <= 2_048 else { return nil }
    if Set(node.keys) == ["constant"], let value = number(node["constant"]) { return { _ in value } }
    if Set(node.keys) == ["variable"], let name = node["variable"]?.strictStringValue, variables.contains(name) {
      return { $0[name] }
    }
    guard Set(node.keys) == ["op", "args"], let operation = node["op"]?.strictStringValue,
          let args = node["args"]?.arrayValue else { return nil }
    if let op = unary[operation], args.count == 1, let child = args[0].objectValue,
       let first = compile(child, variables: variables, depth: depth + 1, nodes: &nodes) {
      return { input in first(input).flatMap { finite(op($0)) } }
    }
    if let op = binary[operation], args.count == 2, let left = args[0].objectValue, let right = args[1].objectValue,
       let first = compile(left, variables: variables, depth: depth + 1, nodes: &nodes),
       let second = compile(right, variables: variables, depth: depth + 1, nodes: &nodes) {
      return { input in
        guard let a = first(input), let b = second(input) else { return nil }
        return finite(op(a, b))
      }
    }
    return nil
  }

  private static func finite(_ value: Double) -> Double? { value.isFinite ? value : nil }

  private static func number(_ value: AgentMcpJSONValue?) -> Double? {
    switch value {
    case .some(.int(let n)): return Double(n)
    case .some(.double(let n)): return finite(n)
    default: return nil
    }
  }

  private static func fingerprint(_ object: AgentMcpJSONObject) -> String {
    func normalized(_ value: AgentMcpJSONValue) -> AgentMcpJSONValue {
      switch value {
      case .double(let n): return Int64(exactly: n).map(AgentMcpJSONValue.int) ?? value
      case .array(let children): return .array(children.map(normalized))
      case .object(let children): return .object(children.mapValues(normalized))
      default: return value
      }
    }
    return AgentMcpJSONCodec.sha256(object.mapValues(normalized))
  }
}
