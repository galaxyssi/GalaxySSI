import Foundation

@MainActor
extension GalaxySSIHealthRecords {
  typealias ModelAttention = GalaxySSIHealthCareModelAttention

  func pendingModelAttention(limit: Int = ModelAttention.pageSize) throws -> [ModelAttention.Receipt] {
    guard (1...ModelAttention.pageSize).contains(limit) else { throw Failure.invalid }
    return Array((try load().localCareModelAttention ?? [:]).values.filter { $0.state == .waiting }.sorted {
      ($0.retryAt ?? .distantPast, $0.createdAt, $0.concern.uuidString) < ($1.retryAt ?? .distantPast, $1.createdAt, $1.concern.uuidString)
    }.prefix(limit))
  }

  func modelAttentionCurrent(_ notice: ModelAttention.Receipt, now: Date = Date()) -> Bool {
    guard notice.owner == owner, let archive = try? load(),
          archive.localCareModelAttention?[notice.concern] == notice,
          let review = archive.localCareModelReviews?[notice.turn], review.input.attentionRequested,
          review.owner == owner, review.authorization.concern == notice.concern,
          review.authorization.thread == notice.conversation, review.createdAt == notice.createdAt,
          let job = archive.localCareResearch?.jobs[notice.concern.uuidString], job.id == notice.turn,
          job.state == .completed, job.reviewRequired == true, job.authorization == review.authorization.id,
          job.trigger == review.trigger, job.revision == review.revision,
          let thread = archive.localCareDiscussions?[notice.concern.uuidString], thread.id == notice.conversation,
          thread.concernID == notice.concern,
          thread.turns.contains(where: { $0.id == notice.turn && $0.automaticResearchCompleted == true &&
            $0.destination == review.authorization.destination }), localCareModelReviewIsCurrent(review, now: now) else { return false }
    return true
  }

  @discardableResult
  func finishModelAttention(_ expected: ModelAttention.Receipt, state: ModelAttention.State) throws -> Bool {
    guard state != .waiting else { throw Failure.invalid }
    var archive = try load()
    guard expected.owner == owner, expected.state == .waiting,
          archive.localCareModelAttention?[expected.concern] == expected else { return false }
    var updated = expected
    updated.state = state; updated.retryAt = nil
    archive.localCareModelAttention?[expected.concern] = updated
    try persistModelAttention(archive)
    guard try load().localCareModelAttention?[expected.concern] == updated else { throw Failure.unavailable }
    return true
  }

  @discardableResult
  func deferModelAttention(_ expected: ModelAttention.Receipt, until date: Date) throws -> Bool {
    guard date.timeIntervalSinceReferenceDate.isFinite, date >= expected.createdAt else { throw Failure.invalid }
    var archive = try load()
    guard expected.owner == owner, expected.state == .waiting,
          archive.localCareModelAttention?[expected.concern] == expected else { return false }
    archive.localCareModelAttention?[expected.concern]?.retryAt = date
    try persistModelAttention(archive)
    return true
  }

  func modelAttentionTarget(identifier: String, turn: UUID, now: Date = Date()) throws -> ModelAttention.Receipt? {
    guard ModelAttention.isIdentifier(identifier) else { throw Failure.invalid }
    let archive = try load()
    guard let value = archive.localCareModelAttention?.values.first(where: { $0.identifier == identifier && $0.turn == turn }),
          value.state == .waiting || value.state == .posted, modelAttentionCurrent(value, now: now) else { return nil }
    return value
  }
}
