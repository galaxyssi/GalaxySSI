import Foundation

enum GalaxySSIHealthCareRelatedContext {
  typealias Scope = [String: String]

  struct Measurement: Encodable {
    let metric: GalaxySSIHealthMetric
    let inputVersion: String
    let record: GalaxySSIHealthCare.Record?
    let measuredAt: Date?
    let result: String?
    let unit: String?
    let reference: String?
    let conditions: String?
    let context: GalaxySSIHealthCare.Context?

    var basis: String {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      // All fields are finite, validated archive values.
      return AgentModelLoopRecoveryIdentity.sha256(["selected_measurement":
        String(decoding: (try? encoder.encode(self)) ?? Data(), as: UTF8.self)])
    }

    var payload: AgentMcpJSONObject {
      var sample: AgentMcpJSONObject = ["metric": .string(metric.rawValue), "basis": .string(basis),
        "input_version": .string(inputVersion), "available": .bool(record != nil)]
      sample["record"] = record.map { .object(["record_id": .string($0.id.uuidString),
        "revision": .int(Int64($0.revision))]) } ?? .null
      sample["measured_at"] = measuredAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null
      sample["result"] = result.map(AgentMcpJSONValue.string) ?? .null
      sample["unit"] = unit.map(AgentMcpJSONValue.string) ?? .null
      sample["reference"] = reference.map(AgentMcpJSONValue.string) ?? .null
      sample["measurement_conditions"] = conditions.map(AgentMcpJSONValue.string) ?? .null
      if let context, let bytes = try? JSONEncoder().encode(context),
         let value = try? JSONDecoder().decode(AgentMcpJSONValue.self, from: bytes) {
        sample["confirmed_context"] = value
      } else { sample["confirmed_context"] = .null }
      return sample
    }
  }

  static func measurement(_ metric: GalaxySSIHealthMetric, archive: GalaxySSIHealthRecords.Archive,
                          now: Date) -> Measurement {
    let readings = archive.current.filter { $0.metric == metric && $0.isValid && $0.measuredAt <= now }
    let latest = readings.first
    let record = latest.map(GalaxySSIHealthCare.Record.init)
    let savedContext = archive.localCare?.current[metric.rawValue]?.context
    let context = savedContext.flatMap { $0.record == record ? $0 : nil }
    let numbers = [latest?.value, latest?.diastolic].compactMap { $0 }
      .map { NSDecimalNumber(decimal: $0).stringValue }
    return .init(metric: metric, inputVersion: GalaxySSIHealthCareSeries.version(readings), record: record,
      measuredAt: latest?.measuredAt, result: latest.map { $0.reported?.raw ?? numbers.joined(separator: " / ") },
      unit: latest?.unit, reference: latest?.referenceInterval, conditions: latest?.conditions, context: context)
  }

  static func capture(_ selected: Set<GalaxySSIHealthMetric>, archive: GalaxySSIHealthRecords.Archive,
                      now: Date) -> Scope {
    Dictionary(uniqueKeysWithValues: selected.map { ($0.rawValue, measurement($0, archive: archive, now: now).basis) })
  }

  static func metrics(_ scope: Scope) throws -> Set<GalaxySSIHealthMetric> {
    guard scope.count <= GalaxySSIHealthMetric.allCases.count,
          scope.values.allSatisfy({ $0.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } })
    else { throw GalaxySSIHealthRecords.Failure.invalid }
    let values = scope.keys.compactMap(GalaxySSIHealthMetric.init(rawValue:))
    guard values.count == scope.count else { throw GalaxySSIHealthRecords.Failure.invalid }
    return Set(values)
  }

  static func current(_ scope: Scope, primary: GalaxySSIHealthMetric,
                      archive: GalaxySSIHealthRecords.Archive, now: Date) -> Bool {
    guard let selected = try? metrics(scope), !selected.contains(primary) else { return false }
    return capture(selected, archive: archive, now: now) == scope
  }

  static func permits(_ previous: Scope?, selected: Scope?) -> Bool {
    Set((previous ?? [:]).keys).isSubset(of: Set((selected ?? [:]).keys))
  }
}

extension GalaxySSIHealthRecords {
  func relatedLocalCareOptions(primary: GalaxySSIHealthMetric, now: Date = Date()) throws
      -> [GalaxySSIHealthCareRelatedContext.Measurement] {
    let archive = try load()
    guard archive.localCareAllowed == true else { throw Failure.permission }
    return GalaxySSIHealthMetric.allCases.filter { $0 != primary }.map {
      GalaxySSIHealthCareRelatedContext.measurement($0, archive: archive, now: now)
    }.filter { $0.record != nil }
  }

  func approveRelatedLocalCareMeasurements(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      selected: Set<GalaxySSIHealthMetric>, now: Date = Date()) throws -> GalaxySSIHealthCareDiscussion.Approval {
    try validateLocalCareDiscussionApproval(approval)
    guard approval.research == nil, !selected.contains(approval.metric) else { throw Failure.invalid }
    return try bindRelatedLocalCareMeasurements(approval, selected: selected, archive: load(), now: now)
  }

  func bindRelatedLocalCareMeasurements(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      selected: Set<GalaxySSIHealthMetric>, archive: Archive, now: Date) throws -> GalaxySSIHealthCareDiscussion.Approval {
    typealias Related = GalaxySSIHealthCareRelatedContext
    guard !selected.contains(approval.metric) else { throw Failure.invalid }
    var result = approval
    result.relatedMeasurements = Related.capture(selected, archive: archive, now: now)
    guard let concern = archive.localCare?.current[approval.metric.rawValue],
          let thread = archive.localCareDiscussions?[approval.concernID.uuidString] else { throw Failure.stale }
    var prior = thread
    prior.turns.removeAll { $0.id == approval.id }
    result.payload = try GalaxySSIHealthCareDiscussion.payload(concern: concern, question: approval.question,
      thread: prior, destination: approval.destinationDigest, savedProfile: localCareProfilePayload(concern),
      actionFeedback: approval.includesActionFeedback ? localCareModelFeedback(concern, thread: prior,
        destination: approval.destinationDigest, archive: archive, includesHistory: approval.feedbackHistoryAllowed,
        relatedMeasurements: result.relatedMeasurements) : nil, relatedMeasurements: result.relatedMeasurements)
    result.relatedPayload = selected.isEmpty ? [:] : ["selected": .array(selected.sorted { $0.rawValue < $1.rawValue }.map {
      .object(Related.measurement($0, archive: archive, now: now).payload)
    }), "complete_health_archive": .bool(false), "other_conversations_included": .bool(false),
      "clinical_verification": .bool(false)]
    result.relatedHistory = [:]
    for metric in selected {
      let page = try relatedLocalCareMeasurementPage(result, metric: metric, archive: archive, now: now)
      result.relatedHistory[metric.rawValue] = .init(binding: page.binding,
        recent: try GalaxySSIHealthCareHistoryTool.output(page, metric: metric, turn: approval.id,
          remaining: GalaxySSIHealthCareHistoryTool.maximumPages), entryToken: UUID().uuidString)
    }
    if approval.questions != nil {
      let page = try modelLocalCareQuestionPage(concern, archive: archive,
        selected: result.relatedMeasurements, after: nil)
      result.questions = page
      if approval.questionCursor != nil {
        result.questionCursor = .init(page, remaining: GalaxySSIHealthCareQuestions.maximumContinuations)
      }
    }
    return result
  }

  func validateRelatedLocalCareMeasurements(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      archive: Archive, now: Date) throws {
    typealias Related = GalaxySSIHealthCareRelatedContext
    guard Related.current(approval.relatedMeasurements, primary: approval.metric, archive: archive, now: now),
          Set(approval.relatedHistory.keys) == Set(approval.relatedMeasurements.keys) else { throw Failure.stale }
    if approval.relatedMeasurements.isEmpty {
      guard approval.relatedPayload.isEmpty else { throw Failure.permission }
      return
    }
    let selected = try Related.metrics(approval.relatedMeasurements)
    let expected: AgentMcpJSONObject = ["selected": .array(selected.sorted { $0.rawValue < $1.rawValue }.map {
      .object(Related.measurement($0, archive: archive, now: now).payload)
    }), "complete_health_archive": .bool(false), "other_conversations_included": .bool(false), "clinical_verification": .bool(false)]
    guard approval.relatedPayload == expected else { throw Failure.stale }
    for metric in selected {
      guard let history = approval.relatedHistory[metric.rawValue] else { throw Failure.stale }
      let page = try relatedLocalCareMeasurementPage(approval, metric: metric, archive: archive, now: now)
      let output = try GalaxySSIHealthCareHistoryTool.output(page, metric: metric, turn: approval.id,
        remaining: GalaxySSIHealthCareHistoryTool.maximumPages)
      var expected = output.payload, actual = history.recent.payload
      expected.removeValue(forKey: "next"); actual.removeValue(forKey: "next")
      guard history.binding == page.binding, history.recent.cursor == page.next, actual == expected,
            history.entryToken.flatMap(UUID.init(uuidString:)) != nil else { throw Failure.stale }
    }
  }

  func localCareReviewReferences(_ concern: GalaxySSIHealthCare.Concern,
      related: GalaxySSIHealthCareRelatedContext.Scope, archive: Archive, now: Date)
      -> [GalaxySSIHealthCareModelReview.Reference] {
    var refs = GalaxySSIHealthCareModelReview.references(concern)
    for key in related.keys.sorted() {
      guard let metric = GalaxySSIHealthMetric(rawValue: key),
            let record = GalaxySSIHealthCareRelatedContext.measurement(metric, archive: archive, now: now).record else { continue }
      let ref = GalaxySSIHealthCareModelReview.Reference(record)
      if !refs.contains(ref) { refs.append(ref) }
    }
    return Array(refs.prefix(30))
  }

  func relatedLocalCarePlanIsCurrent(_ plan: GalaxySSIHealthCarePlan.Proposal, archive: Archive, now: Date) -> Bool {
    let scope = plan.relatedMeasurements ?? [:]
    guard GalaxySSIHealthCareRelatedContext.current(scope, primary: plan.metric, archive: archive, now: now) else { return false }
    if scope.isEmpty { return true }
    guard let authorization = archive.localCareResearch?.authorizations[plan.concernID.uuidString],
          authorization.destination == plan.destinationDigest, authorization.localPermission == plan.carePermission,
          authorization.onlinePermission == plan.onlinePermission,
          archive.localCareDiscussions?[plan.concernID.uuidString]?.id == authorization.thread else { return false }
    return GalaxySSIHealthCareRelatedContext.permits(scope, selected: authorization.relatedMeasurements)
  }

  func modelLocalCareQuestionPage(_ concern: GalaxySSIHealthCare.Concern, archive: Archive,
      selected: GalaxySSIHealthCareRelatedContext.Scope, after: UUID?) throws -> GalaxySSIHealthCareQuestions.Page {
    typealias Questions = GalaxySSIHealthCareQuestions
    return try (archive.localCareQuestions?[concern.id.uuidString] ?? .init()).page(
      scope: Questions.scope(concern), basis: Questions.basis(concern),
      known: Questions.known(concern, profile: localCareProfilePayload(concern)), after: after,
      allowedRelatedMeasurements: Set(selected.keys))
  }

  func relatedLocalCareMeasurementPage(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      metric: GalaxySSIHealthMetric, archive: Archive, after: GalaxySSIHealthCareSeries.Cursor? = nil,
      now: Date) throws -> GalaxySSIHealthCareSeries.Page {
    typealias Related = GalaxySSIHealthCareRelatedContext
    guard approval.relatedMeasurements[metric.rawValue] != nil,
          Related.current(approval.relatedMeasurements, primary: approval.metric, archive: archive, now: now)
    else { throw Failure.stale }
    let readings = archive.current.filter { $0.metric == metric && $0.isValid && $0.measuredAt <= now }
    let binding = GalaxySSIHealthCareSeries.Binding(concern: approval.concernID, revision: approval.concernRevision,
      historyVersion: GalaxySSIHealthCareSeries.version(readings), permission: archive.localCarePermission)
    return try GalaxySSIHealthCareSeries.page(readings, binding: binding, after: after)
  }

  func readRelatedLocalCareHistory(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      metric: GalaxySSIHealthMetric, after: GalaxySSIHealthCareSeries.Cursor? = nil, now: Date = Date()) throws
      -> GalaxySSIHealthCareSeries.Page {
    try validateLocalCareDiscussionTurn(approval, now: now)
    return try relatedLocalCareMeasurementPage(approval, metric: metric, archive: load(), after: after, now: now)
  }
}
