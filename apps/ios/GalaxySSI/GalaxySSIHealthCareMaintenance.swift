import Foundation

enum GalaxySSIHealthCareMaintenance {
  enum Basis: String, Codable, CaseIterable { case currentTarget = "CURRENT_TARGET", riskReview = "RISK_REVIEW" }
  enum Gap: String, CaseIterable, Hashable { case target, history, comparability, applicability, openActions, recheck, priority }

  struct Draft: Codable, Equatable {
    let rationale: String
    let records: [GalaxySSIHealthCare.Record]
    let historyVersion: String
    let sourceIndex: Int
    let recheckIndex: Int
    let applicability: GalaxySSIHealthCareApplicability.Review
    let basis: Basis
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
    let index: [String: Any] = ["type": "integer", "minimum": 0, "maximum": 7]
    let fields: [String: Any] = [
      "rationale": ["type": "string", "maxLength": 2_000],
      "recent_sample_count": ["type": "integer", "minimum": 2, "maximum": GalaxySSIHealthCareSeries.pageSize],
      "source_index": index, "recheck_index": index, "applicability": GalaxySSIHealthCareApplicability.schema,
      "goal_basis": ["type": "string", "enum": Basis.allCases.map(\.rawValue)]
    ]
    return ["type": "object", "required": fields.keys.sorted(), "properties": fields, "additionalProperties": false]
  }

  static func parse(_ input: AgentMcpJSONObject, actions: [GalaxySSIHealthCarePlan.Action], sourceCount: Int,
                    records: [GalaxySSIHealthCare.Record], version: String) throws -> Draft {
    let invalid = GalaxySSIHealthRecords.Failure.invalid
    guard Set(input.keys) == ["rationale", "recent_sample_count", "source_index", "recheck_index", "applicability", "goal_basis"],
          let rationale = input["rationale"]?.strictStringValue, !rationale.isBlank, rationale.utf8.count <= 2_000,
          let basis = Basis(rawValue: input.string("goal_basis")),
          case .int(let count)? = input["recent_sample_count"], count >= 2, count <= Int64(records.count),
          case .int(let source)? = input["source_index"], (0..<Int64(sourceCount)).contains(source),
          case .int(let index)? = input["recheck_index"], (0..<Int64(actions.count)).contains(index),
          actions[Int(index)].kind == .recheck, let review = input["applicability"]?.objectValue else { throw invalid }
    let applicability = try GalaxySSIHealthCareApplicability.parse(review, kind: .recheck, sourceCount: sourceCount)
    guard applicability.mode == .individualized, applicability.checks.contains(where: { $0.sourceIndex == Int(source) })
    else { throw invalid }
    return .init(rationale: rationale, records: Array(records.prefix(Int(count))), historyVersion: version,
      sourceIndex: Int(source), recheckIndex: Int(index), applicability: applicability, basis: basis)
  }

  struct Evaluation {
    let gaps: Set<Gap>
    let samples: [GalaxySSIHealthCareComparison.Sample]
  }

  static func evaluate(_ plan: GalaxySSIHealthCarePlan.Draft, draft: Draft, concern: GalaxySSIHealthCare.Concern,
                       readings: [GalaxySSIHealthReading], page: GalaxySSIHealthCareSeries.Page, now: Date) -> Evaluation {
    guard plan.sources.indices.contains(draft.sourceIndex),
          let recheck = plan.actions.first(where: { $0.id == draft.recheckIndex }) else {
      return .init(gaps: [.recheck], samples: [])
    }
    var gaps: Set<Gap> = []
    let rows = Array(page.rows.prefix(draft.records.count))
    let window = readings.prefix(draft.records.count)
    let samples = window.map(GalaxySSIHealthCareComparison.Sample.init)
    if draft.historyVersion != page.binding.historyVersion || rows.map(\.record) != draft.records ||
      samples.map(\.record) != draft.records || Set(samples.map(\.measuredAt)).count < 2 ||
      (rows.count < page.rows.count && rows.last?.measuredAt == page.rows[rows.count].measuredAt) ||
      (rows.count == page.rows.count && page.next != nil) {
      gaps.insert(.history)
    }
    if let current = samples.first, concern.assessment.record == current.record {
      for sample in samples {
        let previous = concern.context?.record == sample.record ? concern.context :
          (concern.comparison?.previousContext).flatMap { $0.record == sample.record ? $0 : nil }
        let comparison = GalaxySSIHealthCareComparison.Pair(before: sample, after: current, kind: .historyChanged,
          previousContext: previous, nearestAtCapture: nil)
        if comparison.gaps(currentContext: concern.context).contains(where: { $0 != .methodUnverified }) {
          gaps.insert(.comparability)
        }
      }
    } else {
      gaps.insert(.comparability)
    }
    switch draft.basis {
    case .riskReview:
      if concern.target != nil { gaps.insert(.target) }
    case .currentTarget:
      if let target = concern.target?.numeric, !window.isEmpty {
        // The saved target is bound to the current record; older rows must match its numeric bounds and unit separately.
        if GalaxySSIHealthCareTarget.compare(target, concern: concern, reading: window.first) != .within {
          gaps.insert(.target)
        }
        for sample in samples {
          let value = target.component == .diastolic ? sample.diastolic : sample.value
          guard sample.unit == target.unit, let value else { gaps.insert(.target); continue }
          let bounds = target.bounds
          if bounds.low.map({ value < $0 || (value == $0 && !bounds.lowInclusive) }) == true ||
            bounds.high.map({ value > $0 || (value == $0 && !bounds.highInclusive) }) == true { gaps.insert(.target) }
        }
      } else { gaps.insert(.target) }
    }
    if GalaxySSIHealthCareApplicability.status(draft.applicability, concern: concern) != .matched {
      gaps.insert(.applicability)
    }
    if (concern.adoptedActions ?? []).contains(where: { $0.outcome == nil }) { gaps.insert(.openActions) }
    if recheck.kind != .recheck || recheck.dueFrom.map({ $0 > now }) != true ||
      !GalaxySSIHealthCareApplicability.canAdopt(recheck, concern: concern) { gaps.insert(.recheck) }
    if concern.bloodPressureWarning != nil { gaps.insert(.priority) }
    return .init(gaps: gaps, samples: samples)
  }

  static func nextDue(_ concern: GalaxySSIHealthCare.Concern, permission: UUID) -> Date? {
    guard concern.stage == .maintenance, let review = concern.maintenanceReview,
          review.carePermission == permission, concern.maintenanceHistoryVersion == review.historyVersion,
          concern.targetRevision == review.targetRevision, concern.bloodPressureWarning == nil,
          (try? GalaxySSIHealthCareTarget.basis(concern)) == review.contextBasis,
          let recheck = concern.adoptedActions?.first(where: { $0.id == review.actionID }),
          recheck.action.kind == .recheck, recheck.outcome == nil, recheck.action.dueFrom == review.due else { return nil }
    let actions = concern.adoptedActions?.filter { $0.proposalID == review.proposalID && $0.outcome == nil } ?? []
    return min(review.due, actions.compactMap(\.action.dueFrom).min() ?? review.due)
  }
}
