import Foundation

enum GalaxySSIHealthCareMaintenance {
  enum Basis: String, Codable, CaseIterable { case currentTarget = "CURRENT_TARGET", riskReview = "RISK_REVIEW" }
  enum Gap: String, CaseIterable, Hashable { case target, history, comparability, applicability, openActions, recheck, priority }

  struct Draft: Codable, Equatable {
    let rationale: String
    let records: [GalaxySSIHealthCare.Record]
    let sourceIndex: Int
    let recheckIndex: Int
    let applicability: GalaxySSIHealthCareApplicability.Review
    let goalBasis: Basis
  }

  struct Review: Codable, Equatable {
    let proposalID: UUID
    let actionID: String
    let historyVersion: String
    let contextBasis: String
    let targetRevision: Int?
    let carePermission: UUID
    let confirmedAt: Date
    let due: Date
    let basis: Basis
    let rationale: String
    let source: GalaxySSIHealthCarePlan.Source
    let samples: [GalaxySSIHealthCareComparison.Sample]
  }

  static var schema: [String: Any] {
    let index = ["type": "integer", "minimum": 0, "maximum": 7] as [String: Any]
    let record: [String: Any] = ["type": "object", "required": ["id", "revision"], "additionalProperties": false,
      "properties": ["id": ["type": "string", "maxLength": 36] as [String: Any],
                     "revision": ["type": "integer", "minimum": 1] as [String: Any]]]
    let fields: [String: Any] = ["rationale": ["type": "string", "maxLength": 2_000] as [String: Any],
      "records": ["type": "array", "minItems": 2, "maxItems": GalaxySSIHealthCareSeries.pageSize, "items": record] as [String: Any],
      "source_index": index, "recheck_index": index, "applicability": GalaxySSIHealthCareApplicability.schema,
      "goal_basis": ["type": "string", "enum": Basis.allCases.map(\.rawValue)] as [String: Any]]
    return ["type": "object", "required": fields.keys.sorted(), "properties": fields, "additionalProperties": false]
  }

  static func parse(_ input: AgentMcpJSONObject, actions: [GalaxySSIHealthCarePlan.Action], sourceCount: Int) throws -> Draft {
    let invalid = GalaxySSIHealthRecords.Failure.invalid
    guard Set(input.keys) == ["rationale", "records", "source_index", "recheck_index", "applicability", "goal_basis"],
          let rationale = input["rationale"]?.strictStringValue, !rationale.isBlank, rationale.utf8.count <= 2_000,
          let basis = Basis(rawValue: input.string("goal_basis")),
          case .int(let source)? = input["source_index"], (0..<Int64(sourceCount)).contains(source),
          case .int(let index)? = input["recheck_index"], (0..<Int64(actions.count)).contains(index),
          actions[Int(index)].kind == .recheck,
          let raw = input["records"]?.arrayValue, (2...GalaxySSIHealthCareSeries.pageSize).contains(raw.count),
          let review = input["applicability"]?.objectValue else { throw invalid }
    let records = try raw.map { value -> GalaxySSIHealthCare.Record in
      guard let ref = value.objectValue, Set(ref.keys) == ["id", "revision"],
            let id = ref["id"]?.strictStringValue.flatMap(UUID.init(uuidString:)),
            case .int(let revision)? = ref["revision"], revision > 0, let exact = Int(exactly: revision)
      else { throw invalid }
      return .init(id: id, revision: exact)
    }
    let applicability = try GalaxySSIHealthCareApplicability.parse(review, kind: .recheck, sourceCount: sourceCount)
    guard Set(records.map(\.id)).count == records.count, applicability.mode == .individualized else { throw invalid }
    return .init(rationale: rationale, records: records, sourceIndex: Int(source), recheckIndex: Int(index),
      applicability: applicability, goalBasis: basis)
  }

  static func containsApprovedPrefix(_ draft: Draft, history: GalaxySSIHealthCareHistoryTool.Output?) -> Bool {
    guard let rows = history?.payload["history"]?.objectValue?["samples"]?.arrayValue,
          rows.count >= draft.records.count else { return false }
    return zip(rows, draft.records).allSatisfy { pair in
      let ref = pair.0.objectValue?["record"]?.objectValue
      return ref?["id"]?.strictStringValue.flatMap(UUID.init(uuidString:)) == pair.1.id &&
        ref?["revision"] == .int(Int64(pair.1.revision))
    }
  }

  static func evaluate(_ plan: GalaxySSIHealthCarePlan.Draft, concern: GalaxySSIHealthCare.Concern,
                       page: GalaxySSIHealthCareSeries.Page, now: Date)
    -> (gaps: Set<Gap>, samples: [GalaxySSIHealthCareComparison.Sample]) {
    guard let draft = plan.maintenance, plan.target == nil, plan.sources.indices.contains(draft.sourceIndex),
          plan.actions.indices.contains(draft.recheckIndex) else { return ([.recheck], []) }
    var gaps: Set<Gap> = []
    let rows = Array(page.rows.prefix(draft.records.count))
    let samples = rows.map(\.sample)
    if samples.map(\.record) != draft.records || Set(samples.map(\.measuredAt)).count < 2 ||
      (samples.count < page.rows.count && samples.last?.measuredAt == page.rows[samples.count].sample.measuredAt) ||
      (samples.count == page.rows.count && page.next != nil) {
      gaps.insert(.history)
    }
    if concern.measurement?.record != samples.first?.record ||
      rows.contains(where: { $0.gaps.contains { $0 != .methodUnverified } || $0.sample.value == nil }) {
      gaps.insert(.comparability)
    }
    switch draft.goalBasis {
    case .riskReview:
      if concern.target != nil { gaps.insert(.target) }
    case .currentTarget:
      guard let target = concern.target?.numeric, GalaxySSIHealthCareTarget.comparison(concern) == .within else {
        gaps.insert(.target)
        break
      }
      for sample in samples {
        let value = target.component == .diastolic ? sample.diastolic : sample.value
        guard sample.unit == target.unit, let value else { gaps.insert(.target); continue }
        let bounds = target.bounds
        if bounds.low.map({ value < $0 || (value == $0 && !bounds.lowInclusive) }) == true ||
          bounds.high.map({ value > $0 || (value == $0 && !bounds.highInclusive) }) == true { gaps.insert(.target) }
      }
    }
    if GalaxySSIHealthCareApplicability.status(draft.applicability, concern: concern) != .matched {
      gaps.insert(.applicability)
    }
    if (concern.adoptedActions ?? []).contains(where: { $0.outcome == nil }) { gaps.insert(.openActions) }
    let recheck = plan.actions[draft.recheckIndex]
    if recheck.kind != .recheck || recheck.dueFrom.map({ $0 > now }) != true ||
      !GalaxySSIHealthCareApplicability.canAdopt(recheck, concern: concern) { gaps.insert(.recheck) }
    if concern.bloodPressureWarning != nil { gaps.insert(.priority) }
    return (gaps, samples)
  }

  static func nextDue(_ concern: GalaxySSIHealthCare.Concern, permission: UUID) -> Date? {
    guard concern.stage == .maintenance, let review = concern.maintenance,
          review.carePermission == permission, concern.historyVersion == review.historyVersion,
          concern.targetRevision == review.targetRevision, concern.bloodPressureWarning == nil,
          (try? GalaxySSIHealthCareTarget.basis(concern)) == review.contextBasis,
          let recheck = concern.adoptedActions?.first(where: { $0.id == review.actionID }),
          recheck.action.kind == .recheck, recheck.outcome == nil, recheck.action.dueFrom == review.due
    else { return nil }
    let accepted = concern.adoptedActions?.filter { $0.proposalID == review.proposalID && $0.outcome == nil } ?? []
    return min(review.due, accepted.compactMap(\.action.dueFrom).min() ?? review.due)
  }
}
