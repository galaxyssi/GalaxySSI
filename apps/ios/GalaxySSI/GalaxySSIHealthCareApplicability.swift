import Foundation

enum GalaxySSIHealthCareApplicability {
  enum Truth: String, Codable, CaseIterable, Hashable { case unknown = "UNKNOWN", yes = "YES", no = "NO" }
  enum Specimen: String, Codable, CaseIterable, Hashable {
    case unknown = "UNKNOWN", labPlasma = "LAB_PLASMA", homeCapillary = "HOME_CAPILLARY", interstitial = "INTERSTITIAL"
  }
  enum Collection: String, Codable, CaseIterable, Hashable {
    case unknown = "UNKNOWN", fasting, afterMeal = "after_meal", resting, afterActivity = "after_activity"
  }
  struct Facts: Codable, Equatable {
    var adult = Truth.unknown
    var pregnant = Truth.unknown
    var diabetes = Truth.unknown
    var specimen = Specimen.unknown
    var fastingHours: Int?
    var illnessMedication = Truth.unknown
    var collection = Collection.unknown

    var isValid: Bool { fastingHours.map { (0...72).contains($0) } != false }
    var screeningContext: GalaxySSIHealthCare.Context.Applicability {
      if adult == .no || pregnant == .yes || diabetes == .yes ||
        (specimen != .unknown && specimen != .labPlasma) || fastingHours.map({ $0 < 8 }) == true { return .excluded }
      if adult == .yes, pregnant == .no, diabetes == .no, specimen == .labPlasma, fastingHours.map({ $0 >= 8 }) == true {
        return .applicable
      }
      return .unknown
    }

    var signature: String {
      [adult.rawValue, pregnant.rawValue, diabetes.rawValue, specimen.rawValue,
       fastingHours.map { String($0) } ?? "", illnessMedication.rawValue, collection.rawValue].joined(separator: ":")
    }
  }

  enum Mode: String, Codable { case discussionOnly = "DISCUSSION_ONLY", individualized = "INDIVIDUALIZED" }
  enum Field: String, Codable, CaseIterable, Hashable {
    case metric, unit, collectionCondition = "collection_condition", adult, pregnant, diabetes, specimen, fasting,
         illnessMedication = "illness_medication"
  }
  enum Comparison: String, Codable, CaseIterable, Hashable { case equals = "EQUALS", atLeast = "AT_LEAST", atMost = "AT_MOST" }
  enum Result: String { case match, unknown, mismatch }
  enum Status: String { case missingReview, discussionOnly, matched, needsContext, mismatch, conflict }

  struct Check: Codable, Hashable, Identifiable {
    let field: Field
    let comparison: Comparison
    let expected: String
    let sourceIndex: Int
    var id: Self { self }
  }
  struct Conflict: Codable, Equatable {
    let sourceIndices: [Int]
    let detail: String
    let nextStep: String
  }
  struct Review: Codable, Equatable {
    let mode: Mode
    let checks: [Check]
    let missingInformation: [String]
    let conflicts: [Conflict]
  }

  static var schema: [String: Any] {
    func object(_ properties: [String: Any]) -> [String: Any] {
      ["type": "object", "properties": properties, "required": properties.keys.sorted(), "additionalProperties": false]
    }
    func string(_ maximum: Int, _ description: String) -> [String: Any] {
      ["type": "string", "minLength": 1, "maxLength": maximum, "description": description]
    }
    let index: [String: Any] = ["type": "integer", "minimum": 0, "maximum": 7]
    return object([
      "mode": ["type": "string", "enum": ["DISCUSSION_ONLY", "INDIVIDUALIZED"],
        "description": "Use DISCUSSION_ONLY only for CONTEXT or CLINICIAN_DISCUSSION."],
      "checks": ["type": "array", "maxItems": 12, "items": object([
        "field": ["type": "string", "enum": Field.allCases.map(\.rawValue)],
        "operator": ["type": "string", "enum": Comparison.allCases.map(\.rawValue)],
        "expected": string(80, "Source requirement, never guessed actual facts or UNKNOWN. Use saved spellings; fasting is integer hours."),
        "source_index": index
      ])],
      "missing_information": ["type": "array", "maxItems": 8, "items": string(500, "Unresolved eligibility or contraindications.")],
      "conflicts": ["type": "array", "maxItems": 8, "items": object([
        "source_indices": ["type": "array", "minItems": 2, "maxItems": 8, "items": index],
        "detail": string(1_000, "Material conflict between original cited passages."),
        "next_step": string(1_000, "How to resolve it; do not average or hide conflicts.")
      ])]
    ])
  }

  static func parse(_ input: AgentMcpJSONObject, kind: GalaxySSIHealthCarePlan.Kind, sourceCount: Int) throws -> Review {
    let invalid = GalaxySSIHealthRecords.Failure.invalid
    func bounded(_ value: AgentMcpJSONValue?, _ limit: Int) throws -> String {
      guard let text = value?.strictStringValue, !text.isBlank, text.utf8.count <= limit else { throw invalid }
      return text
    }
    func index(_ value: AgentMcpJSONValue?) throws -> Int {
      guard case .int(let number)? = value, number >= 0, number < Int64(sourceCount) else { throw invalid }
      return Int(number)
    }
    guard Set(input.keys) == ["mode", "checks", "missing_information", "conflicts"],
          let mode = Mode(rawValue: input.string("mode")),
          let rawChecks = input["checks"]?.arrayValue, rawChecks.count <= 12,
          let rawMissing = input["missing_information"]?.arrayValue, rawMissing.count <= 8,
          let rawConflicts = input["conflicts"]?.arrayValue, rawConflicts.count <= 8,
          mode != .discussionOnly || discussionKind(kind) else { throw invalid }
    let checks = try rawChecks.map { row -> Check in
      guard let value = row.objectValue, Set(value.keys) == ["field", "operator", "expected", "source_index"],
            let field = Field(rawValue: value.string("field")), let op = Comparison(rawValue: value.string("operator")),
            op == .equals || field == .fasting else { throw invalid }
      let expected = try bounded(value["expected"], 80)
      guard validExpected(expected, field: field) else { throw invalid }
      return .init(field: field, comparison: op, expected: expected, sourceIndex: try index(value["source_index"]))
    }
    guard Set(checks).count == checks.count else { throw invalid }
    let missing = try rawMissing.map { try bounded($0, 500) }
    let conflicts = try rawConflicts.map { row -> Conflict in
      guard let value = row.objectValue, Set(value.keys) == ["source_indices", "detail", "next_step"],
            let raw = value["source_indices"]?.arrayValue, (2...8).contains(raw.count) else { throw invalid }
      let indices = try raw.map { try index($0) }
      guard Set(indices).count == indices.count else { throw invalid }
      return try .init(sourceIndices: indices, detail: bounded(value["detail"], 1_000),
        nextStep: bounded(value["next_step"], 1_000))
    }
    guard mode == .discussionOnly || !checks.isEmpty || !missing.isEmpty || !conflicts.isEmpty else { throw invalid }
    return .init(mode: mode, checks: checks, missingInformation: missing, conflicts: conflicts)
  }

  private static func validExpected(_ value: String, field: Field) -> Bool {
    switch field {
    case .metric: return GalaxySSIHealthMetric(rawValue: value) != nil
    case .unit: return value.utf8.count <= 32 && value != "UNKNOWN"
    case .collectionCondition: return Collection(rawValue: value).map { $0 != .unknown } == true
    case .adult, .pregnant, .diabetes, .illnessMedication: return value == "YES" || value == "NO"
    case .specimen: return Specimen(rawValue: value).map { $0 != .unknown } == true
    case .fasting: return Int(value).map { (0...72).contains($0) && String($0) == value } == true
    }
  }

  static func currentFacts(_ concern: GalaxySSIHealthCare.Concern) -> Facts? {
    guard let context = concern.context, context.record == concern.assessment.record else { return nil }
    return context.facts
  }

  static func result(_ check: Check, concern: GalaxySSIHealthCare.Concern) -> Result {
    let facts = currentFacts(concern)
    let actual: String?
    switch check.field {
    case .metric: actual = concern.metric.rawValue
    case .unit: actual = concern.assessment.unit
    case .collectionCondition: actual = facts?.collection.rawValue
    case .adult: actual = facts?.adult.rawValue
    case .pregnant: actual = facts?.pregnant.rawValue
    case .diabetes: actual = facts?.diabetes.rawValue
    case .specimen: actual = facts?.specimen.rawValue
    case .fasting: actual = facts?.fastingHours.map { String($0) }
    case .illnessMedication: actual = facts?.illnessMedication.rawValue
    }
    guard let actual, !actual.isBlank, actual != "UNKNOWN" else { return .unknown }
    if check.comparison == .equals { return actual == check.expected ? .match : .mismatch }
    guard check.field == .fasting, let lhs = Int(actual), let rhs = Int(check.expected) else { return .unknown }
    return (check.comparison == .atLeast ? lhs >= rhs : lhs <= rhs) ? .match : .mismatch
  }

  static func status(_ review: Review?, concern: GalaxySSIHealthCare.Concern) -> Status {
    guard let review else { return .missingReview }
    if review.mode == .discussionOnly { return .discussionOnly }
    if !review.conflicts.isEmpty { return .conflict }
    if review.checks.contains(where: { result($0, concern: concern) == .mismatch }) { return .mismatch }
    if !review.missingInformation.isEmpty || review.checks.isEmpty ||
      review.checks.contains(where: { result($0, concern: concern) == .unknown }) { return .needsContext }
    return .matched
  }

  static func canAdopt(_ action: GalaxySSIHealthCarePlan.Action, concern: GalaxySSIHealthCare.Concern) -> Bool {
    switch status(action.applicability, concern: concern) {
    case .matched: return true
    case .missingReview, .discussionOnly: return discussionKind(action.kind)
    default: return false
    }
  }

  private static func discussionKind(_ kind: GalaxySSIHealthCarePlan.Kind) -> Bool {
    kind == .context || kind == .clinicianDiscussion
  }
}
