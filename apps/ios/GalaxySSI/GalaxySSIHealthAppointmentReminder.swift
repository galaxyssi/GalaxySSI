import Foundation

enum GalaxySSIHealthAppointmentReminder {
  static let notificationKind = "galaxyssi_health_reminder_kind"
  static let kind = "appointment"
  enum State: String, Codable { case scheduled, delivered, cancelled, expired }

  struct Reference: Codable, Equatable {
    let visit: UUID
    let revision: Int
    let permission: UUID
    let profileEpoch: UUID?
    let plannedAt: Date

    var actionID: String { Self.key(visit) }
    static func key(_ visit: UUID) -> String { "appointment:" + visit.uuidString }
  }

  static func available(_ visit: GalaxySSIHealthEncounter.Entry, now: Date) -> Bool {
    [.planned, .booked].contains(visit.details.state) && visit.details.plannedAt.map { $0 > now } == true
  }

  static func text(_ key: String, _ fallback: String, _ language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.appointment." + key, fallback: fallback, language: language)
  }
}

extension GalaxySSIHealthRecords {
  func saveAppointmentReminder(_ visit: GalaxySSIHealthEncounter.Entry, expected: GalaxySSIHealthEncounter.Stamp,
      previousToken: UUID?, at: Date, confirmed: Bool, now: Date = Date()) throws -> GalaxySSIHealthCareFollowUp.Reminder {
    typealias Appointment = GalaxySSIHealthAppointmentReminder
    guard confirmed, now.timeIntervalSince1970.isFinite, now.timeIntervalSince1970 > 0,
          at.timeIntervalSince1970.isFinite, at > now,
          Appointment.available(visit, now: now), let planned = visit.details.plannedAt, at < planned else { throw Failure.invalid }
    var archive = try load()
    let (concern, stamp) = try localCareEncounterScope(id: expected.concern, metric: expected.metric, archive: archive, now: now)
    let key = Appointment.Reference.key(visit.id)
    guard expected == stamp, visit.concern == concern.id, archive.localCareEncounters?.entries[visit.id] == visit,
          concern.stage != .paused, concern.stage != .closed, localCareProfileIsCurrent(concern.profileScope),
          archive.localCareFollowUps?[key]?.id == previousToken else { throw Failure.stale }
    let ref = Appointment.Reference(visit: visit.id, revision: visit.revision, permission: stamp.permission,
      profileEpoch: concern.profileScopeEpoch, plannedAt: planned)
    let value = GalaxySSIHealthCareFollowUp.Reminder(id: UUID(), actionID: key, concernID: concern.id, metric: concern.metric,
      requestedAt: at, appointment: ref)
    var reminders = archive.localCareFollowUps ?? [:]
    reminders[key] = value
    archive.localCareFollowUps = reminders
    try persistAppointmentReminder(archive)
    guard try load().localCareFollowUps?[key] == value else { throw Failure.unavailable }
    return value
  }

  func appointmentReminder(visit: UUID, now: Date = Date()) throws -> GalaxySSIHealthCareFollowUp.Reminder? {
    try reconcileAppointmentReminders(now: now)
    let archive = try load()
    guard archive.localCareAllowed == true, var value = archive.localCareFollowUps?[GalaxySSIHealthAppointmentReminder.Reference.key(visit)],
          value.appointment?.visit == visit,
          archive.localCare?.current[value.metric.rawValue]?.id == value.concernID,
          archive.localCareEncounters?.entries[visit]?.concern == value.concernID else { return nil }
    if !appointmentReminderIsCurrent(value, archive: archive, now: now),
       value.appointmentState != .cancelled, value.appointmentState != .expired {
      value.appointmentState = value.appointment.map { $0.plannedAt <= now } == true ? .expired : .cancelled
    }
    return value
  }

  func reconcileAppointmentReminders(now: Date = Date()) throws {
    var archive = try load()
    var changed = false
    for (key, value) in archive.localCareFollowUps ?? [:] {
      guard let ref = value.appointment, value.appointmentState != .cancelled, value.appointmentState != .expired,
            !appointmentReminderIsCurrent(value, archive: archive, now: now) else { continue }
      archive.localCareFollowUps?[key]?.appointmentState = ref.plannedAt <= now ? .expired : .cancelled
      changed = true
    }
    if changed { try persistAppointmentReminder(archive) }
  }

  func appointmentReminderIsCurrent(_ reminder: GalaxySSIHealthCareFollowUp.Reminder, archive: Archive, now: Date) -> Bool {
    guard let ref = reminder.appointment, reminder.journalReview == nil, reminder.actionID == ref.actionID,
          ref.revision > 0, reminder.appointmentState != .cancelled, reminder.appointmentState != .expired,
          archive.localCareAllowed == true, archive.localCarePermission == ref.permission,
          let concern = archive.localCare?.current[reminder.metric.rawValue], concern.id == reminder.concernID,
          concern.stage != .paused, concern.stage != .closed, concern.profileScopeEpoch == ref.profileEpoch,
          localCareProfileIsCurrent(concern.profileScope),
          let visit = archive.localCareEncounters?.entries[ref.visit], visit.concern == concern.id,
          visit.revision == ref.revision, visit.details.plannedAt == ref.plannedAt,
          reminder.requestedAt < ref.plannedAt, GalaxySSIHealthAppointmentReminder.available(visit, now: now)
    else { return false }
    return true
  }

  func markAppointmentDelivered(token: UUID, now: Date = Date()) throws {
    var archive = try load()
    guard let key = archive.localCareFollowUps?.first(where: { $0.value.id == token && $0.value.appointment != nil })?.key,
          var value = archive.localCareFollowUps?[key], appointmentReminderIsCurrent(value, archive: archive, now: now),
          value.submittedFor.map({ $0 <= now.addingTimeInterval(2) }) == true else { throw Failure.stale }
    guard value.appointmentState != .delivered else { return }
    value.appointmentState = .delivered
    archive.localCareFollowUps?[key] = value
    try persistAppointmentReminder(archive)
  }

  static func appointmentReminderPreferences(_ archive: Archive) -> GalaxySSIHealthReviewDelivery.Preferences? {
    guard let settings = archive.recordingReminders?.settings, settings.notifications, settings.isValid else { return nil }
    return .init(enabled: true, pausedUntil: settings.pausedUntil, quietStart: settings.quietStart, quietEnd: settings.quietEnd)
  }

  static func followUpPreferences(_ reminder: GalaxySSIHealthCareFollowUp.Reminder, archive: Archive)
      -> GalaxySSIHealthReviewDelivery.Preferences? {
    reminder.appointment == nil ? careFollowUpPreferences(archive) : appointmentReminderPreferences(archive)
  }

  func appointmentCleanupDeadline(now: Date = Date()) throws -> Date? {
    let archive = try load()
    return (archive.localCareFollowUps ?? [:]).values.compactMap { value -> Date? in
      guard appointmentReminderIsCurrent(value, archive: archive, now: now) else { return nil }
      return value.appointment?.plannedAt
    }.min()
  }
}
