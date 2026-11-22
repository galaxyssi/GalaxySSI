import Foundation
import UserNotifications
import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthCareModelAttentionTests: XCTestCase {
  typealias Attention = GalaxySSIHealthCareModelAttention

  func testCompletionAtomicallyAdmitsAnEncryptedReceiptAndPostingDoesNotReplay() async throws {
    let f = try fixture()
    let arguments = try attentionInput(f)
    let review = try f.records.recordLocalCareModelReview(f.approval, arguments: arguments, now: f.now)
    XCTAssertNil(try f.records.load().localCareModelAttention)
    try f.records.finishLocalCareDiscussionTurn(f.approval, answer: "Synthetic completed assessment", now: f.now)
    let notice = try current(f)
    XCTAssertEqual(notice.createdAt, review.createdAt)
    XCTAssertEqual(notice.conversation, review.authorization.thread)
    XCTAssertEqual(notice.state, .waiting)
    XCTAssertNil(try Data(contentsOf: f.file).range(of: Data(notice.conversation.uuidString.utf8)))
    var posts = 0
    _ = try await deliver(f, post: { _ in posts += 1; return true })
    _ = try await deliver(f, post: { _ in posts += 1; return true })
    XCTAssertEqual(posts, 1)
    XCTAssertEqual(try current(f).state, .posted)
    let reopened = GalaxySSIHealthRecords(owner: f.records.owner, secrets: f.secrets, isolatedFile: f.file)
    XCTAssertTrue(try reopened.pendingModelAttention().isEmpty)
    XCTAssertEqual(try reopened.load().localCareModelReviews?[review.id], review)
  }

  func testNoAttentionOrMissingAssessmentDoesNotCreateAReceipt() throws {
    let f = try fixture()
    _ = try f.records.recordLocalCareModelReview(f.approval, arguments: f.arguments(), now: f.now)
    try f.records.finishLocalCareDiscussionTurn(f.approval, answer: "No attention requested", now: f.now)
    XCTAssertTrue(try f.records.load().localCareModelAttention?.isEmpty ?? true)
    let missing = try fixture()
    try missing.records.finishLocalCareDiscussionTurn(missing.approval, answer: "No assessment retained", now: missing.now)
    XCTAssertNil(try missing.records.load().localCareModelAttention)
  }

  func testVisibleNotificationReconcilesACompletedPostWithoutPostingAgain() async throws {
    let f = try completed()
    let notice = try current(f)
    _ = try await deliver(f, visible: [notice.identifier: notice.turn], post: { _ in XCTFail("Do not duplicate a visible notice"); return false })
    XCTAssertEqual(try current(f).state, .posted)
    _ = try await deliver(f, post: { _ in XCTFail("Dismissal must not replay"); return false })
  }

  func testDeniedOSPermissionAndSeparateOptOutConsumeWithoutDiscardingTheAssessment() async throws {
    let f = try completed()
    _ = try await deliver(f, allowed: false, post: { _ in XCTFail("OS denial"); return false })
    XCTAssertEqual(try current(f).state, .inAppOnly)
    XCTAssertNotNil(try f.records.load().localCareModelReviews?[f.approval.id])
    let disabled = try completed()
    var settings = try XCTUnwrap(disabled.records.load().recordingReminders?.settings)
    settings.modelReviews = false
    try disabled.records.saveRecordingReminderSettings(settings, at: disabled.now)
    XCTAssertEqual(try current(disabled).state, .inAppOnly)
    settings = try XCTUnwrap(disabled.records.load().recordingReminders?.settings)
    settings.modelReviews = true
    try disabled.records.saveRecordingReminderSettings(settings, at: disabled.now)
    _ = try await deliver(disabled, post: { _ in XCTFail("Enabling must not replay disabled updates"); return false })
  }

  func testQuietHoursAndPausesLeaveTheReceiptWaitingForRevalidation() async throws {
    let f = try completed()
    let end = f.now.addingTimeInterval(3600)
    var settings = try XCTUnwrap(f.records.load().recordingReminders?.settings)
    settings.pausedUntil = end
    try f.records.saveRecordingReminderSettings(settings, at: f.now)
    let paused = try await deliver(f, post: { _ in XCTFail("Paused"); return false })
    XCTAssertEqual(paused, end)
    XCTAssertEqual(try current(f).state, .waiting)
    settings = try XCTUnwrap(f.records.load().recordingReminders?.settings)
    settings.pausedUntil = nil
    let hour = calendar.component(.hour, from: f.now)
    settings.quietStart = hour; settings.quietEnd = (hour + 2) % 24
    try f.records.saveRecordingReminderSettings(settings, at: f.now)
    let quiet = try await deliver(f, post: { _ in XCTFail("Quiet window"); return false })
    XCTAssertEqual(quiet, settings.nextDelivery(f.now, calendar: calendar))
    XCTAssertEqual(try current(f).state, .waiting)
  }

  func testFailurePersistsBackoffAndRetriesTheSameReceipt() async throws {
    let f = try completed()
    let value = try current(f)
    var calls = 0
    let wake = try await deliver(f, post: { _ in calls += 1; return false })
    XCTAssertEqual(wake, f.now.addingTimeInterval(60))
    XCTAssertEqual(try current(f).turn, value.turn)
    _ = try await deliver(f, at: f.now.addingTimeInterval(59), post: { _ in calls += 1; return true })
    XCTAssertEqual(calls, 1)
    _ = try await deliver(f, at: f.now.addingTimeInterval(60), post: { _ in calls += 1; return true })
    XCTAssertEqual(calls, 2)
    XCTAssertEqual(try current(f).state, .posted)
  }

  func testPostCallbackRevocationCancelsTheNoticeAndPreservesHistory() async throws {
    let f = try completed()
    let value = try current(f)
    var cancelled: [String] = []
    _ = try await deliver(f, post: { _ in
      try? f.records.revokeLocalCareResearch(f.concern.id)
      return true
    }, cancel: { cancelled.append($0) })
    XCTAssertEqual(cancelled, [value.identifier])
    XCTAssertEqual(try current(f).state, .stale)
    XCTAssertNotNil(try f.records.load().localCareModelReviews?[value.turn])
  }

  func testForegroundSuppressionRequiresTheExactProfileAndConversation() async throws {
    let f = try completed()
    let value = try current(f)
    let visibility = Attention.Visibility()
    let one = UUID(), two = UUID()
    visibility.update(one, scope: .init(owner: value.owner, concern: value.concern, conversation: UUID()))
    XCTAssertFalse(visibility.contains(owner: value.owner, conversation: value.conversation))
    visibility.update(two, scope: .init(owner: "another-profile", concern: value.concern, conversation: value.conversation))
    XCTAssertFalse(visibility.contains(owner: value.owner, conversation: value.conversation))
    visibility.update(one, scope: .init(owner: value.owner, concern: value.concern, conversation: value.conversation))
    _ = try await deliver(f, foreground: { visibility.contains(owner: $0.owner, conversation: $0.conversation) },
      post: { _ in XCTFail("Already visible"); return false })
    XCTAssertEqual(try current(f).state, .inAppOnly)
    visibility.update(one, scope: nil); visibility.update(two, scope: nil)
    XCTAssertFalse(visibility.contains(owner: value.owner, conversation: value.conversation))
  }

  func testChangedBindingOrMeasurementCancelsOldNoticeWithoutRemovingAssessments() async throws {
    let f = try completed()
    _ = try await deliver(f, binding: { _ in false }, post: { _ in XCTFail("Changed provider"); return false })
    XCTAssertEqual(try current(f).state, .stale)
    let changed = try completed()
    let notice = try current(changed)
    try changed.records.write(.init(metric: .glucose, measuredAt: changed.now, value: 115, unitOverride: "mg/dL"))
    var cancelled: [String] = []
    _ = try await deliver(changed, visible: [notice.identifier: notice.turn], cancel: { cancelled.append($0) })
    XCTAssertTrue(cancelled.contains(notice.identifier))
    XCTAssertEqual(try current(changed).state, .stale)
    XCTAssertNotNil(try changed.records.load().localCareModelReviews?[notice.turn])
  }

  func testNotificationAndTapTokenContainNoModelHealthTextAndCannotRedirectTurns() throws {
    let f = try completed()
    let value = try current(f)
    let request = GalaxySSIHealthCareModelAttentionRuntime.request(value, language: "en")
    XCTAssertEqual(request.identifier, value.identifier)
    XCTAssertNil(request.trigger)
    XCTAssertEqual(request.content.userInfo.count, 1)
    XCTAssertEqual(request.content.userInfo[Attention.turnKey] as? String, value.turn.uuidString)
    XCTAssertFalse(request.content.body.contains("Synthetic"))
    XCTAssertFalse(request.content.body.contains("110"))
    XCTAssertNil(try f.records.modelAttentionTarget(identifier: value.identifier, turn: UUID(), now: f.now))
    XCTAssertEqual(try f.records.modelAttentionTarget(identifier: value.identifier, turn: value.turn, now: f.now), value)
    XCTAssertTrue(Attention.isIdentifier(value.identifier))
    XCTAssertFalse(Attention.isIdentifier(value.identifier + "0"))
    XCTAssertNotEqual(value.identifier, Attention.identifier(owner: "another-profile", concern: value.concern))
  }

  func testLegacySettingsKeepGlobalOptInOffAndDoNotBackfillCompletedReviews() throws {
    let settings = GalaxySSIHealthRecordingReminders.Settings()
    let decoded = try JSONDecoder().decode(GalaxySSIHealthRecordingReminders.Settings.self, from: JSONEncoder().encode(settings))
    XCTAssertFalse(decoded.notifications)
    XCTAssertTrue(decoded.allowsModelReviews)
    let f = try fixture()
    _ = try f.records.recordLocalCareModelReview(f.approval, arguments: attentionInput(f), now: f.now)
    XCTAssertNil(try f.records.load().localCareModelAttention)
  }

  func testLateCompletionCannotAcknowledgeAReplacementOnTheSameStableIdentifier() throws {
    let f = try completed()
    let previous = try current(f)
    var archive = try f.records.load()
    let saved = try XCTUnwrap(archive.localCareModelReviews?[previous.turn])
    let replacement = GalaxySSIHealthCareModelReview.Review(id: UUID(), owner: saved.owner, authorization: saved.authorization,
      revision: saved.revision, trigger: saved.trigger, inputVersion: saved.inputVersion,
      createdAt: saved.createdAt.addingTimeInterval(1), input: saved.input)
    let next = Attention.Receipt(replacement)
    archive.localCareModelAttention?[next.concern] = next
    try f.records.persistModelAttention(archive)
    XCTAssertEqual(next.identifier, previous.identifier)
    XCTAssertFalse(try f.records.finishModelAttention(previous, state: .posted))
    XCTAssertEqual(try current(f), next)
  }

  func testBoundedPagesDrainStaleOutboxWithoutLosingRemainingReceipts() async throws {
    let f = try completed()
    var archive = try f.records.load()
    let review = try XCTUnwrap(archive.localCareModelReviews?[f.approval.id])
    let auth = review.authorization
    var receipts: [UUID: Attention.Receipt] = [:]
    for index in 0..<65 {
      let nextAuth = GalaxySSIHealthCareResearch.Authorization(concern: UUID(), metric: auth.metric, thread: auth.thread,
        localPermission: auth.localPermission, onlinePermission: auth.onlinePermission, profileScopeEpoch: auth.profileScopeEpoch,
        contact: auth.contact, model: auth.model, endpoint: auth.endpoint, destination: auth.destination,
        sources: auth.sources, authorizedAt: auth.authorizedAt)
      let nextReview = GalaxySSIHealthCareModelReview.Review(id: UUID(), owner: review.owner, authorization: nextAuth,
        revision: review.revision, trigger: review.trigger, inputVersion: review.inputVersion,
        createdAt: f.now.addingTimeInterval(Double(index)), input: review.input)
      receipts[nextAuth.concern] = Attention.Receipt(nextReview)
    }
    archive.localCareModelAttention = receipts
    try f.records.persistModelAttention(archive)
    var pages: [Int] = []
    while true {
      let page = try f.records.pendingModelAttention()
      if page.isEmpty { break }
      pages.append(page.count)
      _ = try await deliver(f, post: { _ in XCTFail("Unbound synthetic rows must not notify"); return false })
    }
    XCTAssertEqual(pages, [30, 30, 5])
    XCTAssertEqual(try f.records.load().localCareModelAttention?.count, 65)
  }

  func testLiveProviderBindingRechecksCredentialsAndDestinationBlocklist() throws {
    let f = try completed()
    let auth = try XCTUnwrap(f.records.load().localCareResearch?.authorizations[f.concern.id.uuidString])
    var model = try XCTUnwrap(f.approval.model)
    model.keychainAccount = "attention-fixture-key"
    try f.secrets.setString("fixture-api-key", account: model.keychainAccount)
    let contact = GalaxySSIContact(id: "provider", galaxySSIId: "provider", name: "Fixture", displayName: "Fixture",
      type: "agent", agentKind: "cloud-api", deliveryMode: .cloudAPI, trustState: .verified, desktopId: "", desktopName: "",
      identityFingerprint: "", setupStatus: "ready", setupDetail: "", cloudProvider: "Custom", cloudModels: [model],
      selectedCloudModelId: model.id, deleted: false, createdAt: f.now, updatedAt: f.now)
    typealias Context = GalaxySSIHealthCareModelAttentionRuntime.Context
    let current = Context(owner: f.records.owner, contacts: [contact], links: [], language: "en", secrets: f.secrets, blocked: [])
    XCTAssertTrue(current.permits(auth))
    let blocked = Context(owner: f.records.owner, contacts: [contact], links: [], language: "en", secrets: f.secrets, blocked: ["provider"])
    XCTAssertFalse(blocked.permits(auth))
    try f.secrets.setString("rotated-fixture-key", account: model.keychainAccount)
    XCTAssertFalse(current.permits(auth))
  }

  func testMigrationDoesNotBackfillAnAttentionReceiptForAnAlreadyCompletedReview() async throws {
    let f = try completed()
    var archive = try f.records.load()
    archive.localCareModelAttention = nil
    try f.records.persistModelAttention(archive)
    _ = try f.records.reconcileLocalCareResearch(now: f.now)
    _ = try await deliver(f, post: { _ in XCTFail("No migration alerts"); return false })
    XCTAssertNil(try f.records.load().localCareModelAttention)
    XCTAssertNotNil(try f.records.load().localCareModelReviews?[f.approval.id])
    XCTAssertEqual(try f.records.load().localCareResearch?.jobs[f.concern.id.uuidString]?.state, .completed)
  }

  func testUnavailableEncryptionKeyCannotCommitCompletionOrDiscardAssessment() throws {
    let f = try fixture()
    let review = try f.records.recordLocalCareModelReview(f.approval, arguments: attentionInput(f), now: f.now)
    let before = try Data(contentsOf: f.file)
    let account = "health.records.v1." + f.records.owner
    let key = try XCTUnwrap(f.secrets.string(account: account))
    f.secrets.delete(account: account)
    XCTAssertThrowsError(try f.records.finishLocalCareDiscussionTurn(f.approval, answer: "Not committed", now: f.now))
    XCTAssertEqual(try Data(contentsOf: f.file), before)
    try f.secrets.setString(key, account: account)
    let archive = try f.records.load()
    XCTAssertEqual(archive.localCareModelReviews?[review.id], review)
    XCTAssertEqual(archive.localCareResearch?.jobs[f.concern.id.uuidString]?.state, .dispatched)
    XCTAssertNil(archive.localCareModelAttention)
  }

  private var calendar: Calendar {
    var result = Calendar(identifier: .gregorian); result.timeZone = TimeZone(secondsFromGMT: 0)!; return result
  }
  private func fixture() throws -> HealthModelReviewFixture {
    let f = try HealthModelReviewFixture()
    var settings = try f.records.loadRecordingReminders(at: f.now, calendar: calendar).settings
    settings.notifications = true; settings.modelReviews = true; settings.quietStart = 0; settings.quietEnd = 0
    try f.records.saveRecordingReminderSettings(settings, at: f.now)
    return f
  }
  private func completed() throws -> HealthModelReviewFixture {
    let f = try fixture()
    _ = try f.records.recordLocalCareModelReview(f.approval, arguments: attentionInput(f), now: f.now)
    try f.records.finishLocalCareDiscussionTurn(f.approval, answer: "Synthetic completed assessment", now: f.now)
    return f
  }
  private func attentionInput(_ f: HealthModelReviewFixture) throws -> AgentMcpJSONObject {
    var value = try f.arguments(); value["attention_requested"] = .bool(true); return value
  }
  private func current(_ f: HealthModelReviewFixture) throws -> Attention.Receipt {
    try XCTUnwrap(f.records.load().localCareModelAttention?[f.concern.id])
  }
  private func deliver(_ f: HealthModelReviewFixture, at date: Date? = nil, allowed: Bool = true,
      visible: [String: UUID] = [:], binding: (Attention.Receipt) -> Bool = { _ in true },
      foreground: (Attention.Receipt) -> Bool = { _ in false },
      post: (Attention.Receipt) async -> Bool = { _ in true }, cancel: (String) -> Void = { _ in }) async throws -> Date? {
    try await GalaxySSIHealthCareModelAttentionDelivery.reconcile(records: f.records, systemAllowed: allowed,
      visible: visible, now: date ?? f.now, calendar: calendar, binding: binding, foreground: foreground, post: post, cancel: cancel)
  }
}
