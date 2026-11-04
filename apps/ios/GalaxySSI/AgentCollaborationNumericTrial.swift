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
    var greatestError: ReplayDecimal?
    var worst: AgentMcpJSONObject?
    var worstError: ReplayDecimal?
    var firstDomainError: AgentMcpJSONObject?
    for item in cases {
      guard let row = item.objectValue, Set(row.keys) == ["id", "input", "expected", "absolute_tolerance"],
            let id = row["id"]?.strictStringValue, !id.isBlank, id.utf8.count <= 128, ids.insert(id).inserted,
            let inputs = row["input"]?.objectValue, Set(inputs.keys) == variables,
            let expected = decimal(row["expected"], reference: true),
            let tolerance = decimal(row["absolute_tolerance"], reference: true), !tolerance.negative
      else { return nil }
      let values = inputs.compactMapValues { number($0) }
      guard values.count == inputs.count else { return nil }
      var check: AgentMcpJSONObject = ["id": .string(id), "passed": .bool(false)]
      if let actual = expression(values), let actualDecimal = ReplayDecimal(String(actual)) {
        let error = ReplayDecimal.distance(actualDecimal, expected)
        let passed = !tolerance.isLess(than: error)
        check["actual"] = .double(actual)
        check["absolute_error"] = .string(error.text)
        check["passed"] = .bool(passed)
        if greatestError?.isLess(than: error) ?? true {
          greatestError = error
        }
        let worstPassed = worst?["passed"] == .bool(true)
        if worst == nil || (worstPassed && !passed) ||
           (worstPassed == passed && (worstError?.isLess(than: error) ?? true)) {
          worst = check
          worstError = error
        }
        if !passed { failures += 1 }
      } else {
        check["error"] = .string("nonfinite_expression_result")
        if firstDomainError == nil { firstDomainError = check }
        failures += 1
        domainErrors += 1
      }
      checks.append(.object(check))
    }
    return [
      "validator_id": .string(validatorId), "passed": .bool(failures == 0),
      "case_count": .int(Int64(cases.count)), "failed_cases": .int(Int64(failures)),
      "domain_error_cases": .int(Int64(domainErrors)), "finite_cases": .int(Int64(cases.count - domainErrors)),
      "checks": .array(checks),
      "max_absolute_error_on_finite_cases": greatestError.map { .string($0.text) } ?? .null,
      "worst_case": (firstDomainError ?? worst).map(AgentMcpJSONValue.object) ?? .null,
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
      if let a = decimal(old["absolute_error"]), let b = decimal(new["absolute_error"]) {
        if b.isLess(than: a) { transitions["error_reduced", default: []].append(id) }
        if a.isLess(than: b) { transitions["error_increased", default: []].append(id) }
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

  private static func decimal(_ value: AgentMcpJSONValue?, reference: Bool = false) -> ReplayDecimal? {
    let text: String
    switch value {
    case .some(.int(let n)): text = String(n)
    case .some(.double(let n)) where n.isFinite: text = String(n)
    case .some(.string(let raw)): text = raw
    default: return nil
    }
    guard (!reference || text.utf8.count <= 256), let result = ReplayDecimal(text),
          !reference || (result.digits.count <= 128 && abs(result.exponent) <= 128) else { return nil }
    return result
  }

  private struct ReplayDecimal {
    let digits: [Int]
    let exponent: Int
    let negative: Bool

    init?(_ text: String) {
      guard text.utf8.count <= 2_500 else { return nil }
      let parts = text.lowercased().split(separator: "e", omittingEmptySubsequences: false)
      guard (1...2).contains(parts.count),
            let power = parts.count == 2 ? Int(parts[1]) : 0, (-1_000...1_000).contains(power) else { return nil }
      let negative = parts[0].first == "-"
      let unsigned = negative ? parts[0].dropFirst() : parts[0]
      let mantissa = unsigned.split(separator: ".", omittingEmptySubsequences: false)
      let bytes = mantissa.joined().utf8
      guard (1...2).contains(mantissa.count), !bytes.isEmpty,
            bytes.allSatisfy({ (48...57).contains($0) }) else { return nil }
      let fraction = mantissa.count == 2 ? mantissa[1].utf8.count : 0
      self.init(Array(bytes.map { Int($0) - 48 }.reversed()), exponent: power - fraction, negative: negative)
    }

    private init(_ raw: [Int], exponent: Int, negative: Bool) {
      var digits = raw
      while digits.last == 0 { digits.removeLast() }
      let trailing = digits.prefix(while: { $0 == 0 }).count
      self.digits = Array(digits.dropFirst(trailing))
      self.exponent = digits.isEmpty ? 0 : exponent + trailing
      self.negative = !digits.isEmpty && negative
    }

    var text: String {
      digits.isEmpty ? "0" : digits.reversed().map(String.init).joined() + "e" + String(exponent)
    }

    private func aligned(to exponent: Int) -> [Int] {
      guard !digits.isEmpty else { return [] }
      return Array(repeating: 0, count: self.exponent - exponent) + digits
    }

    func isLess(than other: Self) -> Bool {
      let scale = min(exponent, other.exponent)
      let lhs = aligned(to: scale), rhs = other.aligned(to: scale)
      return Self.magnitudeLess(lhs, rhs)
    }

    static func distance(_ lhs: Self, _ rhs: Self) -> Self {
      let scale = min(lhs.exponent, rhs.exponent)
      var a = lhs.aligned(to: scale), b = rhs.aligned(to: scale)
      if magnitudeLess(a, b) { swap(&a, &b) }
      let add = lhs.negative != rhs.negative
      var carry = 0
      for index in a.indices {
        let right = index < b.count ? b[index] : 0
        let value = a[index] + (add ? right : -right) + carry
        carry = value < 0 ? -1 : value / 10
        a[index] = value - 10 * carry
      }
      if carry > 0 { a.append(carry) }
      return Self(a, exponent: scale, negative: false)
    }

    private static func magnitudeLess(_ lhs: [Int], _ rhs: [Int]) -> Bool {
      lhs.count == rhs.count ? lhs.reversed().lexicographicallyPrecedes(rhs.reversed()) : lhs.count < rhs.count
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
