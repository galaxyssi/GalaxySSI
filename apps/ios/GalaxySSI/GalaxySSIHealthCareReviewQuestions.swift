import Foundation

extension GalaxySSIHealthRecords {
  func validateCareReviewQuestions(_ input: GalaxySSIHealthCareModelReview.Input,
      approval: GalaxySSIHealthCareDiscussion.Approval, concern: GalaxySSIHealthCare.Concern, archive: Archive) throws {
    typealias Questions = GalaxySSIHealthCareQuestions
    let refs = input.questions ?? []
    guard input.decision != .clarify || !refs.isEmpty else { throw Failure.invalid }
    guard !refs.isEmpty else { return }
    guard approval.questions != nil, approval.concernID == concern.id,
          archive.localCareResearch?.authorizations[concern.id.uuidString]?.sharesQuestionSnapshot == true,
          approval.profileScope == concern.profileScope, localCareProfileIsCurrent(concern.profileScope)
    else { throw Failure.permission }
    let scope = Questions.scope(concern), basis = try Questions.basis(concern)
    let known = try Questions.known(concern, profile: localCareProfilePayload(concern))
    let rows = archive.localCareQuestions?[concern.id.uuidString]?.revisions ?? [:]
    for ref in refs {
      guard let row = rows[ref.id.uuidString]?.last else { throw Failure.invalid }
      guard row.scope == scope, Set(approval.relatedMeasurements.keys).isSuperset(of: row.relatedMeasurements ?? [])
      else { throw Failure.permission }
      guard row.id == ref.id, row.revision == ref.revision, row.basis == basis,
            [.open, .conflict].contains(row.displayedState(basis: basis, known: known[row.proposal.key]))
      else { throw Failure.invalid }
    }
  }

  func localCareModelReviewQuestions(_ review: GalaxySSIHealthCareModelReview.Review, now: Date = Date()) throws
      -> GalaxySSIHealthCareQuestions.Page {
    typealias Questions = GalaxySSIHealthCareQuestions
    let refs = review.input.questions ?? []
    guard review.owner == owner, (1...30).contains(refs.count), Set(refs.map(\.id)).count == refs.count else {
      throw Failure.permission
    }
    try reconcileLocalCare(now: now)
    let archive = try load()
    guard archive.localCareAllowed == true, archive.localCareModelReviews?[review.id] == review,
          let concern = archive.localCare?.current[review.authorization.metric.rawValue],
          concern.id == review.authorization.concern, localCareProfileIsCurrent(concern.profileScope)
    else { throw Failure.stale }
    let scope = Questions.scope(concern)
    let rows = archive.localCareQuestions?[concern.id.uuidString]?.revisions ?? [:]
    let selected = try refs.map { ref -> Questions.Row in
      guard let row = rows[ref.id.uuidString]?.last, row.id == ref.id, row.scope == scope else { throw Failure.stale }
      return row
    }
    return try .init(rows: selected, basis: Questions.basis(concern),
      ledgerVersion: AgentModelLoopRecoveryIdentity.sha256(selected.map { "\($0.id.uuidString):\($0.revision)" }),
      known: Questions.known(concern, profile: localCareProfilePayload(concern)), next: nil)
  }
}
