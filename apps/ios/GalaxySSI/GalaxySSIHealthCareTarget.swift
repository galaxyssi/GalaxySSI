import Foundation

enum GalaxySSIHealthCareTarget {
  enum Component: String, Codable, CaseIterable { case value, systolic, diastolic }
  enum Comparison: String, Encodable { case reviewRequired, notComparable, below, within, above }

  struct Bounds: Codable, Equatable {
    let low: Decimal?
    let high: Decimal?
    let lowInclusive: Bool
    let highInclusive: Bool

    var description: String {
      var parts: [String] = []
      if let low { parts.append((lowInclusive ? ">= " : "> ") + GalaxySSIHealthCareComparison.Sample.number(low)) }
      if let high { parts.append((highInclusive ? "<= " : "< ") + GalaxySSIHealthCareComparison.Sample.number(high)) }
      return parts.joined(separator: ", ")
    }
  }
  struct Proposal: Codable, Equatable {
    let component: Component
    let bounds: Bounds
    let unit: String
    let rationale: String
    let sourceIndex: Int
    let applicability: GalaxySSIHealthCareApplicability.Review
  }
  struct Confirmed: Codable, Equatable {
    let proposalID: UUID
    let component: Component
    let bounds: Bounds
    let unit: String
    let source: GalaxySSIHealthCarePlan.Source
    let basis: String
  }
  struct ModelValue: Encodable {
    let component: Component
    let bounds: Bounds
    let unit: String
    let comparison: Comparison
    let approval = "user_confirmed_not_clinician_verified"
  }

  static var schema: [String: Any] {
    let decimal: [String: Any] = ["type": "string", "maxLength": 20,
      "description": "Exact nonnegative decimal or empty when this bound is absent. Do not use a report midpoint."]
    let properties: [String: Any] = [
      "field": ["type": "string", "enum": Component.allCases.map(\.rawValue)],
      "low": decimal, "high": decimal, "low_inclusive": ["type": "boolean"], "high_inclusive": ["type": "boolean"],
      "unit": ["type": "string", "maxLength": 32], "rationale": ["type": "string", "maxLength": 2_000],
      "source_index": ["type": "integer", "minimum": 0, "maximum": 7],
      "applicability": GalaxySSIHealthCareApplicability.schema
    ]
    return ["type": "object", "properties": properties, "required": properties.keys.sorted(), "additionalProperties": false]
  }

  static func parse(_ input: AgentMcpJSONObject, sourceCount: Int) throws -> Proposal {
    let invalid = GalaxySSIHealthRecords.Failure.invalid
    func bound(_ key: String) throws -> Decimal? {
      guard let text = input[key]?.strictStringValue, text.utf8.count <= 20 else { throw invalid }
      if text.isEmpty { return nil }
      guard text.range(of: #"\A[0-9]+(?:\.[0-9]+)?\z"#, options: .regularExpression) != nil,
            let parsed = GalaxySSIHealthReportedResult.number(text), !parsed.isNaN else { throw invalid }
      return parsed
    }
    guard Set(input.keys) == ["field", "low", "high", "unit", "low_inclusive", "high_inclusive",
      "rationale", "source_index", "applicability"],
      let field = Component(rawValue: input.string("field")), let unit = input["unit"]?.strictStringValue,
      !unit.isBlank, unit.utf8.count <= 32,
      let rationale = input["rationale"]?.strictStringValue, !rationale.isBlank, rationale.utf8.count <= 2_000,
      case .int(let index)? = input["source_index"], index >= 0, index < Int64(sourceCount),
      case .bool(let lowInclusive)? = input["low_inclusive"], case .bool(let highInclusive)? = input["high_inclusive"],
      let review = input["applicability"]?.objectValue else { throw invalid }
    let low = try bound("low"), high = try bound("high")
    guard low != nil || high != nil else { throw invalid }
    if let low, let high, !(low < high || low == high && lowInclusive && highInclusive) { throw invalid }
    let applicability = try GalaxySSIHealthCareApplicability.parse(review, kind: .recheck, sourceCount: sourceCount)
    guard applicability.mode == .individualized else { throw invalid }
    return .init(component: field, bounds: .init(low: low, high: high,
      lowInclusive: low != nil && lowInclusive, highInclusive: high != nil && highInclusive), unit: unit,
      rationale: rationale, sourceIndex: Int(index), applicability: applicability)
  }

  static func canConfirm(_ proposal: Proposal, concern: GalaxySSIHealthCare.Concern) -> Bool {
    let form = concern.metric.form
    let componentMatches = concern.metric == .bloodPressure ? proposal.component != .value : proposal.component == .value
    let bounds = [proposal.bounds.low, proposal.bounds.high].compactMap { $0 }
    if let low = proposal.bounds.low, let high = proposal.bounds.high,
       !(low < high || low == high && proposal.bounds.lowInclusive && proposal.bounds.highInclusive) { return false }
    guard concern.assessment.record != nil, componentMatches, form != .qualitative,
          concern.metric.units.contains(proposal.unit), concern.assessment.unit == proposal.unit,
          !bounds.isEmpty, bounds.allSatisfy({ valid($0, form: form) }),
          GalaxySSIHealthCareApplicability.status(proposal.applicability, concern: concern) == .matched
    else { return false }
    return true
  }

  private static func valid(_ number: Decimal, form: GalaxySSIHealthMetric.Form) -> Bool {
    if number.isNaN || number < 0 || (form == .positive && number <= 0) { return false }
    if form == .count {
      var value = number, rounded = Decimal()
      NSDecimalRound(&rounded, &value, 0, .down)
      return rounded == number
    }
    return true
  }

  static func basis(_ concern: GalaxySSIHealthCare.Concern) throws -> String {
    let record = concern.assessment.record
    return AgentModelLoopRecoveryIdentity.sha256([
      "record": record.map { $0.id.uuidString + ":" + String($0.revision) } ?? "",
      "assessment": try GalaxySSIHealthCare.inputDigest(concern.assessment),
      "context": concern.context?.applicability.rawValue ?? "",
      "facts": concern.context?.facts?.signature ?? ""
    ])
  }

  static func comparison(_ concern: GalaxySSIHealthCare.Concern) -> Comparison {
    guard let target = concern.target?.numeric, (try? basis(concern)) == target.basis else { return .reviewRequired }
    guard let sample = concern.measurement, sample.record == concern.assessment.record, sample.unit == target.unit,
          sample.metric == concern.metric else { return .notComparable }
    let value = target.component == .diastolic ? sample.diastolic : sample.value
    guard let value else { return .notComparable }
    if let low = target.bounds.low, value < low || value == low && !target.bounds.lowInclusive { return .below }
    if let high = target.bounds.high, value > high || value == high && !target.bounds.highInclusive { return .above }
    return .within
  }

  static func modelValue(_ concern: GalaxySSIHealthCare.Concern) -> ModelValue? {
    guard let target = concern.target?.numeric else { return nil }
    return .init(component: target.component, bounds: target.bounds, unit: target.unit, comparison: comparison(concern))
  }
}
