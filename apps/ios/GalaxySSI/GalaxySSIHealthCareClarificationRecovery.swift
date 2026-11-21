import Foundation

extension GalaxySSIHealthRecords {
  func allowsReviewedCareQuestionFollowUp(_ concern: GalaxySSIHealthCare.Concern,
      row: GalaxySSIHealthCareQuestions.Row, archive: Archive) -> Bool {
    guard let auth = archive.localCareResearch?.authorizations[concern.id.uuidString],
          auth.metric == concern.metric,
          auth.reviewedAnswerFollowUp == true, auth.sharesQuestionSnapshot == true,
          auth.localPermission == archive.localCarePermission, auth.onlinePermission == archive.healthOnlinePermission,
          auth.profileScopeEpoch == concern.profileScopeEpoch, localCareProfileIsCurrent(concern.profileScope),
          archive.localCareDiscussions?[concern.id.uuidString]?.id == auth.thread,
          row.scope == GalaxySSIHealthCareQuestions.scope(concern),
          Set((auth.relatedMeasurements ?? [:]).keys).isSuperset(of: row.relatedMeasurements ?? [])
    else { return false }
    return true
  }

  func retainAutomaticCareQuestions(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      arguments: AgentMcpJSONObject, now: Date = Date()) throws
      -> (approval: GalaxySSIHealthCareDiscussion.Approval, receipt: AgentMcpJSONObject) {
    typealias Questions = GalaxySSIHealthCareQuestions
    guard approval.canProposeAutomaticQuestions, let approved = approval.questions else { throw Failure.permission }
    let values = try Questions.parse(arguments)
    try validateLocalCareDiscussionTurn(approval, now: now)
    var archive = try load()
    let key = approval.concernID.uuidString
    let digest = AgentMcpJSONCodec.sha256(arguments)
    guard var thread = archive.localCareDiscussions?[key], let index = thread.turns.indices.last,
          thread.id == approval.threadID, thread.turns[index].id == approval.id,
          archive.localCareModelReviews?[approval.id] == nil,
          let concern = archive.localCare?.current[approval.metric.rawValue],
          let auth = archive.localCareResearch?.authorizations[key], auth.reviewedAnswerFollowUp == true,
          auth.sharesQuestionSnapshot == true else { throw Failure.stale }
    if let previous = thread.turns[index].automaticQuestionRequestDigest, previous != digest { throw Failure.stale }
    var ledger = archive.localCareQuestions?[key] ?? .init()
    try ledger.propose(values, scope: Questions.scope(concern), basis: approved.basis, known: approved.known,
      turn: approval.id, now: now, relatedMeasurements: Set(approval.relatedMeasurements.keys))
    var ledgers = archive.localCareQuestions ?? [:]
    ledgers[key] = ledger
    archive.localCareQuestions = ledgers
    let page = approved
    thread.turns[index].questionsRetained = values.isEmpty ? nil : true
    thread.turns[index].automaticQuestionRequestDigest = digest
    thread.turns[index].questionSnapshotVersion = page.ledgerVersion
    archive.localCareDiscussions?[key] = thread
    try persistCareClarification(archive)
    let keys = Set(values.map(\.key))
    let rows = ledger.revisions.values.compactMap(\.last).filter {
      $0.scope == Questions.scope(concern) && $0.basis == approved.basis && keys.contains($0.proposal.key) &&
        Set(approval.relatedMeasurements.keys).isSuperset(of: $0.relatedMeasurements ?? [])
    }.sorted { $0.id.uuidString < $1.id.uuidString }
    let stored = try load()
    guard stored.localCareDiscussions?[key]?.turns.last?.automaticQuestionRequestDigest == digest,
          rows.allSatisfy({ stored.localCareQuestions?[key]?.revisions[$0.id.uuidString]?.last == $0 }) else {
      throw Failure.unavailable
    }
    let receipt: AgentMcpJSONObject = ["stored": .bool(true), "questions": .array(rows.map {
      .object(["question_id": .string($0.id.uuidString), "revision": .int(Int64($0.revision)),
        "key": .string($0.proposal.key), "state": .string(page.state($0).rawValue)])
    }), "answers_invented": .bool(false), "plan_adopted": .bool(false), "notification_sent": .bool(false)]
    return (approval, receipt)
  }
}
