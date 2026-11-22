import XCTest
import UserNotifications
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthAppointmentReminderTests: XCTestCase {
  typealias FollowUp = GalaxySSIHealthCareFollowUp

  func testRequiresExplicitConfirmationAndStrictFutureBounds() throws {
    let f = try Fixture()
    let visit = try f.visit()
    for at in [f.now, f.now.addingTimeInterval(-1), try XCTUnwrap(visit.details.plannedAt)] {
      XCTAssertThrowsError(try f.save(visit, at: at))
    }
    XCTAssertThrowsError(try f.save(visit, confirmed: false))
    XCTAssertNil(try f.records.appointmentReminder(visit: visit.id))
    let saved = try f.save(visit)
    XCTAssertEqual(saved, try f.records.appointmentReminder(visit: visit.id))
    XCTAssertNil(try f.records.load().localCarePlans)
    XCTAssertNil(try f.records.load().localCareResearch)
    XCTAssertFalse(String(decoding: try Data(contentsOf: f.file), as: UTF8.self).contains("Private facility"))
  }

  func testReschedulingRotatesTokenAndRejectsStaleCancelAndSubmission() throws {
    let f = try Fixture()
    let visit = try f.visit()
    let old = try f.save(visit)
    let delivery = FollowUp.Delivery(reminder: old, due: old.requestedAt)
    let new = try f.save(visit, previous: old.id, at: old.requestedAt.addingTimeInterval(60))
    XCTAssertNotEqual(old.id, new.id)
    XCTAssertEqual(old.actionID, new.actionID)
    XCTAssertThrowsError(try f.save(visit, previous: old.id))
    XCTAssertThrowsError(try f.records.cancelLocalCareFollowUp(old))
    XCTAssertThrowsError(try f.records.markLocalCareFollowUpSubmitted(delivery, calendar: f.calendar, now: f.now))
    XCTAssertNil(try f.records.localCareFollowUpTarget(token: old.id, now: old.requestedAt))
    try f.records.cancelLocalCareFollowUp(new)
    XCTAssertEqual(try f.records.appointmentReminder(visit: visit.id)?.appointmentState, .cancelled)
  }

  func testEditingOneVisitDoesNotInvalidateAnotherVisit() throws {
    let f = try Fixture()
    let first = try f.visit()
    let second = try f.visit()
    _ = try f.save(first)
    let other = try f.save(second)
    var draft = first.details
    draft.plannedAt = draft.plannedAt?.addingTimeInterval(3600)
    _ = try f.records.saveLocalCareEncounter(draft, id: first.id, operation: UUID(), expected: f.stamp(),
      expectedEntry: first.revision, now: f.now)
    XCTAssertEqual(try f.records.appointmentReminder(visit: first.id)?.appointmentState, .cancelled)
    XCTAssertEqual(try f.records.appointmentReminder(visit: second.id)?.id, other.id)
    XCTAssertEqual(try f.plan().pending.map(\.reminder.id), [other.id])
  }

  func testAttendanceCancellationAndDeletionInvalidateTokens() throws {
    for state in [GalaxySSIHealthEncounter.State.attended, .cancelled] {
      let f = try Fixture()
      let visit = try f.visit()
      let saved = try f.save(visit)
      var draft = visit.details
      draft.state = state
      draft.attendedAt = state == .attended ? f.now : nil
      _ = try f.records.saveLocalCareEncounter(draft, id: visit.id, operation: UUID(), expected: f.stamp(),
        expectedEntry: visit.revision, now: f.now)
      XCTAssertTrue(try f.plan().pending.isEmpty)
      XCTAssertNil(try f.records.localCareFollowUpTarget(token: saved.id, now: saved.requestedAt))
    }
    let f = try Fixture()
    let visit = try f.visit()
    let saved = try f.save(visit)
    try f.records.deleteLocalCareEncounter(visit, expected: f.stamp(), now: f.now)
    XCTAssertTrue(try f.plan().pending.isEmpty)
    XCTAssertNil(try f.records.localCareFollowUpTarget(token: saved.id, now: saved.requestedAt))
  }

  func testRevocationAndRenewalCannotReviveOldReminder() throws {
    let f = try Fixture()
    let visit = try f.visit()
    _ = try f.save(visit)
    try f.records.setPrivacy(.localCare, enabled: false)
    XCTAssertTrue(try f.plan().pending.isEmpty)
    try f.records.setPrivacy(.localCare, enabled: true)
    XCTAssertTrue(try f.plan().pending.isEmpty)
  }

  func testNotificationOptOutRetainsInAppReminderWithoutModelReviewPermission() throws {
    let f = try Fixture()
    let visit = try f.visit()
    let reminder = try f.save(visit)
    XCTAssertFalse(try f.plan().pending.isEmpty)
    var settings = GalaxySSIHealthRecordingReminders.Settings()
    settings.notifications = false
    try f.records.saveRecordingReminderSettings(settings, at: f.now)
    XCTAssertTrue(try f.plan().pending.isEmpty)
    XCTAssertEqual(try f.records.appointmentReminder(visit: visit.id)?.id, reminder.id)
    XCTAssertNil(try f.records.load().reviewReminderState)
    XCTAssertTrue(try f.plan(permitted: false).pending.isEmpty)
  }

  func testPauseBeyondAppointmentDoesNotScheduleLateNotification() throws {
    let f = try Fixture()
    let visit = try f.visit()
    _ = try f.save(visit)
    var settings = GalaxySSIHealthRecordingReminders.Settings()
    settings.notifications = true
    settings.pausedUntil = try XCTUnwrap(visit.details.plannedAt).addingTimeInterval(1)
    try f.records.saveRecordingReminderSettings(settings, at: f.now)
    XCTAssertTrue(try f.plan().pending.isEmpty)
  }

  func testQuietHoursBeyondAppointmentDoNotScheduleLateNotification() throws {
    let f = try Fixture()
    let visit = try f.visit()
    let original = try f.save(visit)
    let at = try XCTUnwrap(ISO8601DateFormatter().date(from: "2040-01-01T22:30:00Z"))
    let reminder = FollowUp.Reminder(id: original.id, actionID: original.actionID, concernID: original.concernID,
      metric: original.metric, requestedAt: at, appointment: .init(visit: visit.id, revision: visit.revision,
        permission: try f.stamp().permission, profileEpoch: nil, plannedAt: at.addingTimeInterval(3600)))
    let prefs = GalaxySSIHealthReviewDelivery.Preferences(enabled: true, pausedUntil: nil, quietStart: 22, quietEnd: 8)
    let plan = FollowUp.deliveryPlan(reminders: [reminder], preferences: prefs, permitted: true,
      pending: [:], delivered: [], calendar: f.calendar, now: at.addingTimeInterval(-60))
    XCTAssertTrue(plan.pending.isEmpty)
  }

  func testPausingOrClosingConcernInvalidatesItsAppointment() throws {
    for stage in [GalaxySSIHealthCare.Stage.paused, .closed] {
      let f = try Fixture()
      let visit = try f.visit()
      _ = try f.save(visit)
      let concern = try XCTUnwrap(f.records.load().localCare?.current["glucose"])
      try f.records.reviewLocalCare(concern, stage: stage, reason: "User decision", now: f.now)
      XCTAssertTrue(try f.plan().pending.isEmpty)
    }
  }

  func testRecordedZoneRejectsDSTGapAndExposesBothFoldOffsets() throws {
    let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let parser = ISO8601DateFormatter()
    let spring = try XCTUnwrap(parser.date(from: "2040-03-11T12:00:00Z"))
    let autumn = try XCTUnwrap(parser.date(from: "2040-11-04T12:00:00Z"))
    XCTAssertTrue(GalaxySSIHealthEncounter.possibleTimes(day: spring, hour: 2, minute: 30, zone: zone).isEmpty)
    let dates = GalaxySSIHealthEncounter.possibleTimes(day: autumn, hour: 1, minute: 30, zone: zone)
    XCTAssertEqual(dates.count, 2)
    XCTAssertEqual(Set(dates.map { zone.secondsFromGMT(for: $0) }).count, 2)
  }

  func testExpiryIsPersistedAndClockRollbackDoesNotReviveIt() throws {
    let f = try Fixture()
    let visit = try f.visit()
    let saved = try f.save(visit)
    let expiry = try XCTUnwrap(visit.details.plannedAt)
    XCTAssertTrue(try f.plan(now: expiry).pending.isEmpty)
    XCTAssertEqual(try f.records.load().localCareFollowUps?[saved.actionID]?.appointmentState, .expired)
    XCTAssertNil(try f.records.localCareFollowUpTarget(token: saved.id, now: expiry))
    XCTAssertTrue(try f.plan(now: f.now).pending.isEmpty)
  }

  func testDeliveredReminderDoesNotRepostAfterDismissalAndOpensExactVisit() throws {
    let f = try Fixture()
    let visit = try f.visit()
    let saved = try f.save(visit)
    let delivery = try XCTUnwrap(f.plan().pending.first)
    try f.records.markLocalCareFollowUpSubmitted(delivery, calendar: f.calendar, now: f.now)
    let target = try XCTUnwrap(f.records.localCareFollowUpTarget(token: saved.id, now: delivery.due))
    XCTAssertEqual(target.appointment?.visit, visit.id)
    try f.records.markAppointmentDelivered(token: saved.id, now: delivery.due)
    XCTAssertEqual(try f.records.load().localCareFollowUps?[saved.actionID]?.appointmentState, .delivered)
    XCTAssertTrue(try f.plan(now: delivery.due.addingTimeInterval(1)).pending.isEmpty)
    let request = GalaxySSIHealthAppointmentNotifications.request(delivery, language: "en")
    XCTAssertTrue(GalaxySSIHealthAppointmentNotifications.isAppointment(request))
    XCTAssertEqual(request.identifier, saved.identifier)
    XCTAssertEqual(request.content.userInfo.count, 1)
    XCTAssertFalse(request.content.body.contains(visit.details.facility))
    XCTAssertFalse(request.content.body.contains(visit.details.purpose))
    XCTAssertFalse(request.content.body.contains(visit.details.note))
  }

  @MainActor
  private final class Fixture {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let records: GalaxySSIHealthRecords
    let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    let concern: UUID
    var calendar: Calendar {
      var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!
      return value
    }
    init() throws {
      records = GalaxySSIHealthRecords(owner: "appointment-fixture", secrets: InMemorySecretStore(), isolatedFile: file)
      try records.write(.init(metric: .glucose, measuredAt: now.addingTimeInterval(-120), value: 110, unitOverride: "mg/dL"))
      try records.setPrivacy(.localCare, enabled: true)
      try records.reconcileLocalCare(now: now)
      concern = try XCTUnwrap(records.load().localCare?.current["glucose"]?.id)
      var settings = GalaxySSIHealthRecordingReminders.Settings()
      settings.notifications = true
      settings.quietStart = 0; settings.quietEnd = 0
      try records.saveRecordingReminderSettings(settings, at: now)
    }
    deinit { try? FileManager.default.removeItem(at: file) }
    func stamp() throws -> GalaxySSIHealthEncounter.Stamp {
      try records.localCareEncounterPage(id: concern, metric: .glucose, now: now).stamp
    }
    func visit() throws -> GalaxySSIHealthEncounter.Entry {
      var draft = GalaxySSIHealthEncounter.Draft()
      draft.purpose = "Private purpose"; draft.facility = "Private facility"; draft.note = "Private note"
      draft.state = .booked; draft.zone = "Asia/Shanghai"; draft.plannedAt = now.addingTimeInterval(86400)
      return try records.saveLocalCareEncounter(draft, id: UUID(), operation: UUID(), expected: stamp(), expectedEntry: nil, now: now).entry
    }
    func save(_ visit: GalaxySSIHealthEncounter.Entry, previous: UUID? = nil, at: Date? = nil,
              confirmed: Bool = true) throws -> FollowUp.Reminder {
      try records.saveAppointmentReminder(visit, expected: stamp(), previousToken: previous,
        at: at ?? now.addingTimeInterval(3600), confirmed: confirmed, now: now)
    }
    func plan(permitted: Bool = true, now: Date? = nil) throws -> FollowUp.DeliveryPlan {
      try records.localCareFollowUpDelivery(pending: [:], delivered: [], permitted: permitted, calendar: calendar, now: now ?? self.now)
    }
  }
}
