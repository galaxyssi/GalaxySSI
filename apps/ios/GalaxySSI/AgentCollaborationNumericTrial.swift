import Foundation

enum AgentCollaborationNumericFeedback {
  static let mode = "numeric_cases"
  static let trust = "host_numeric_replay_projection_not_independent_reference_truth_or_generalization"
  static let changes = ["improved", "regressed", "error_reduced", "error_increased", "domain_recovered", "domain_failed"]
  static let filters = ["failed", "all", "domain_error"] + changes
  static let instructions = "Use numeric_cases with exact object_id, revision, sha256 and case_filter (default failed). " +
    "Follow next_cursor with the same filter and join content pages before decoding. Use workspace for the full immutable trial."

  struct Request {
    let reference: AgentCollaborationResearchReference
    let filter: String
    let offset: Int64
    private let binding: String

    init?(_ input: AgentMcpJSONObject) {
      guard Set(input.keys).isSubset(of: ["mode", "object_id", "revision", "sha256", "case_filter", "cursor"]),
            input["mode"] == .string(AgentCollaborationNumericFeedback.mode),
            let reference = AgentCollaborationCandidateRecall.reference(input),
            case .string(let filter) = input["case_filter"] ?? .string("failed"), filters.contains(filter),
            case .string(let cursor) = input["cursor"] ?? .string(""), cursor.utf8.count <= 512
      else { return nil }
      var fields = AgentCollaborationCandidateRecall.reference(reference)
      fields["case_filter"] = .string(filter)
      let binding = AgentMcpJSONCodec.sha256(fields)
      if cursor.isEmpty {
        offset = 0
      } else {
        guard let fields = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(cursor.utf8)),
              Set(fields.keys) == ["binding", "offset"], fields["binding"] == .string(binding),
              case .int(let position)? = fields["offset"], position > 0 else { return nil }
        offset = position
      }
      self.reference = reference
      self.filter = filter
      self.binding = binding
    }

    func cursor(at offset: Int64) -> AgentMcpJSONValue {
      .string(AgentMcpJSONCodec.stringify(["binding": .string(binding), "offset": .int(offset)]))
    }
  }

  static func summary(_ revision: AgentCollaborationResearchRevision) -> AgentMcpJSONObject? {
    guard revision.draft.kind == .numericModelTrial, var replay = revision.numericReplay else { return nil }
    replay.removeValue(forKey: "checks")
    replay["case_details_omitted"] = .bool(true)
    if var worst = replay["worst_case"]?.objectValue, case .double(let value)? = worst["actual"],
       let integer = Int64(exactly: value) {
      // Match the numeric representation used when the encrypted receipt is decoded again.
      worst["actual"] = .int(integer)
      replay["worst_case"] = .object(worst)
    }
    if var comparison = replay["comparison"]?.objectValue {
      for change in changes {
        if let ids = comparison.removeValue(forKey: change + "_case_ids")?.arrayValue {
          comparison[change + "_case_count"] = .int(Int64(ids.count))
        }
      }
      comparison["case_ids_omitted"] = .bool(true)
      replay["comparison"] = .object(comparison)
    }
    let source = AgentCollaborationCandidateRecall.reference(revision.reference)
    var selector = source
    selector["mode"] = .string(mode)
    selector["case_filter"] = .string("failed")
    replay["source_reference"] = .object(source)
    replay["case_feedback"] = .object(selector)
    return replay
  }

  static func page(_ request: Request, revision: AgentCollaborationResearchRevision) throws -> AgentMcpJSONObject {
    guard revision.reference == request.reference, revision.draft.kind == .numericModelTrial,
          let replay = revision.numericReplay, let checks = replay["checks"]?.arrayValue,
          let cases = revision.draft.body["numeric_model_trial"]?.objectValue?["validator"]?.objectValue?["cases"]?.arrayValue,
          (1...4_096).contains(cases.count), checks.count == cases.count,
          replay["case_count"] == .int(Int64(cases.count)),
          let spec = replay["spec_sha256"], let model = replay["model_sha256"]
    else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    let comparison = replay["comparison"]?.objectValue
    var changed: [String: Set<String>] = [:]
    if let comparison {
      for change in changes {
        guard let list = comparison[change + "_case_ids"]?.arrayValue else { throw AgentTeamHistoryDatabase.Failure.corrupt }
        let ids = Set(list.compactMap(\.strictStringValue))
        guard ids.count == list.count else { throw AgentTeamHistoryDatabase.Failure.corrupt }
        changed[change] = ids
      }
    }
    var selected: [AgentMcpJSONValue] = []
    var registered = Set<String>()
    for (item, observed) in zip(cases, checks) {
      guard var row = item.objectValue, let id = row["id"]?.strictStringValue, registered.insert(id).inserted,
            let check = observed.objectValue, check["id"] == .string(id), case .bool(let passed)? = check["passed"]
      else { throw AgentTeamHistoryDatabase.Failure.corrupt }
      let labels = changes.filter { changed[$0]?.contains(id) == true }
      let include: Bool
      switch request.filter {
      case "all": include = true
      case "failed": include = !passed
      case "domain_error": include = check["error"] != nil
      default: include = labels.contains(request.filter)
      }
      if include {
        row["observed"] = observed
        row["changes"] = .array(labels.map(AgentMcpJSONValue.string))
        selected.append(.object(row))
      }
    }
    guard changed.values.allSatisfy({ $0.isSubset(of: registered) }) else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    let content = AgentMcpJSONCodec.stringify(["cases": .array(selected)])
    let page = try AgentCollaborationEvidenceContent.page(Data(content.utf8), offset: request.offset, evidence: true)
    guard page.end > request.offset else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    return [
      "status": .string("returned"), "content": .string(page.content), "offset": .int(request.offset),
      "end_offset": .int(page.end), "total_characters": .int(page.wireTotal),
      "offset_unit": .string(AgentCollaborationEvidenceContent.offsetUnit),
      "next_cursor": page.end < page.wireTotal ? request.cursor(at: page.end) : .null,
      "case_filter": .string(request.filter), "matched_case_count": .int(Int64(selected.count)),
      "case_count": .int(Int64(cases.count)), "source_reference": .object(AgentCollaborationCandidateRecall.reference(revision.reference)),
      "spec_sha256": spec, "model_sha256": model, "has_comparison": .bool(comparison != nil),
      "trust": .string(trust), "read_guidance": .string(instructions)
    ]
  }

  static func advances(_ request: Request, output: AgentMcpJSONObject) -> Bool {
    guard output["status"] == .string("returned"), output["trust"] == .string(trust),
          output["case_filter"] == .string(request.filter), output["offset"] == .int(request.offset),
          output["source_reference"] == .object(AgentCollaborationCandidateRecall.reference(request.reference)),
          case .int(let end)? = output["end_offset"], case .int(let total)? = output["total_characters"],
          end > request.offset, end <= total, let content = output["content"]?.strictStringValue,
          Int64(content.utf16.count) == end - request.offset else { return false }
    return output["next_cursor"] == (end < total ? request.cursor(at: end) : .null)
  }
}

enum AgentCollaborationNumericTrial {
  static let validatorId = "numeric_model_cases.v1"
  static let requirement = "Verify the saved numeric model on exactly the registered test cases; this does not establish generalization or physical validity."

  static func passes(spec: AgentMcpJSONObject, computation: AgentMcpJSONObject) -> Bool {
    evaluate(["purpose": .string("Verify the registered cases"), "reference_basis": .string("Pinned criterion"),
      "limitations": .string("Finite cases only"), "validator": .object(spec),
      "computation": .object(computation)])?["passed"] == .bool(true)
  }
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

  struct ValidatorIssue: Error {
    let path: String
    let expected: String
    let actual: String
  }

  private struct RegisteredCase {
    let id: String
    let inputs: [String: Double]
    let expected: ReplayDecimal
    let tolerance: ReplayDecimal
  }

  static func validatorIssue(_ spec: AgentMcpJSONObject) -> ValidatorIssue? {
    if case .failure(let issue) = parseValidator(spec) { return issue }
    return nil
  }

  private static func parseValidator(_ spec: AgentMcpJSONObject)
    -> Result<(variables: Set<String>, cases: [RegisteredCase]), ValidatorIssue> {
    func fail(_ path: String, _ expected: String, _ actual: String)
      -> Result<(variables: Set<String>, cases: [RegisteredCase]), ValidatorIssue> {
      .failure(.init(path: path, expected: expected, actual: actual))
    }
    guard spec["id"] == .string(validatorId) else {
      return fail(".id", validatorId, "missing or unsupported validator ID")
    }
    guard Set(spec.keys).isSubset(of: ["id", "variables", "cases"]) else {
      return fail("", "only id, variables and cases", "unexpected fields")
    }
    guard let names = spec["variables"]?.arrayValue, (1...64).contains(names.count) else {
      return fail(".variables", "array with 1 to 64 variable names", "missing, wrong type or out of range")
    }
    let variables = Set(names.compactMap(\.strictStringValue))
    guard variables.count == names.count, variables.allSatisfy({
      $0.range(of: "^[A-Za-z][A-Za-z0-9_]{0,63}$", options: .regularExpression) != nil
    }) else { return fail(".variables", "unique ASCII variable identifiers", "duplicate or invalid variable name") }
    guard let cases = spec["cases"]?.arrayValue, (1...4_096).contains(cases.count) else {
      return fail(".cases", "array with 1 to 4096 registered cases", "missing, wrong type or out of range")
    }
    var ids = Set<String>()
    var parsed: [RegisteredCase] = []
    for (index, item) in cases.enumerated() {
      let path = ".cases[\(index)]"
      guard let row = item.objectValue, Set(row.keys).isSubset(of: ["id", "input", "expected", "absolute_tolerance"]) else {
        return fail(path, "case object with id, input, expected and absolute_tolerance", "wrong type or unexpected fields")
      }
      guard let id = row["id"]?.strictStringValue, !id.isBlank, id.utf8.count <= 128, ids.insert(id).inserted else {
        return fail(path + ".id", "unique nonblank case ID of at most 128 UTF-8 bytes", "missing, duplicate or invalid case ID")
      }
      guard let inputs = row["input"]?.objectValue, Set(inputs.keys) == variables else {
        return fail(path + ".input", "object with exactly the registered variables", "missing or different input fields")
      }
      let values = inputs.compactMapValues { number($0) }
      guard values.count == inputs.count else {
        return fail(path + ".input", "finite JSON numbers", "non-numeric or nonfinite value")
      }
      guard let expected = decimal(row["expected"], reference: true) else {
        return fail(path + ".expected", "supported finite decimal", "missing or invalid expected value")
      }
      guard let tolerance = decimal(row["absolute_tolerance"], reference: true), !tolerance.negative else {
        return fail(path + ".absolute_tolerance", "supported nonnegative finite decimal", "missing or invalid tolerance")
      }
      parsed.append(.init(id: id, inputs: values, expected: expected, tolerance: tolerance))
    }
    return .success((variables, parsed))
  }

  static func evaluate(_ trial: AgentMcpJSONObject) -> AgentMcpJSONObject? {
    guard Set(trial.keys).subtracting(["previous_trial"]) == ["purpose", "reference_basis", "limitations", "validator", "computation"],
          AgentCollaborationForecastIntake.hasText(trial, ["purpose", "reference_basis", "limitations"]),
          let spec = trial["validator"]?.objectValue, case .success(let registered) = parseValidator(spec),
          let computation = trial["computation"]?.objectValue, Set(computation.keys) == ["validator_id", "model"],
          computation["validator_id"] == .string(validatorId), let model = computation["model"]?.objectValue
    else { return nil }
    let cases = registered.cases
    var nodes = 0
    guard let expression = compile(model, variables: registered.variables, depth: 1, nodes: &nodes),
          nodes * cases.count <= 2_000_000 else { return nil }
    var checks: [AgentMcpJSONValue] = []
    var failures = 0
    var domainErrors = 0
    var greatestError: ReplayDecimal?
    var worst: AgentMcpJSONObject?
    var worstError: ReplayDecimal?
    var firstDomainError: AgentMcpJSONObject?
    for item in cases {
      var check: AgentMcpJSONObject = ["id": .string(item.id), "passed": .bool(false)]
      if let actual = expression(item.inputs), let actualDecimal = ReplayDecimal(String(actual)) {
        let error = ReplayDecimal.distance(actualDecimal, item.expected)
        let passed = !item.tolerance.isLess(than: error)
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
