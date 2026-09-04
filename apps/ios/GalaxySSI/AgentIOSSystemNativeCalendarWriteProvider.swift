import Foundation
#if canImport(EventKit)
import EventKit
#endif

protocol AgentIOSCalendarWriteProviding {
  func upsertEvent(
    eventId: Int64,
    calendarId: Int64,
    title: String,
    description: String,
    location: String,
    startEpochMillis: Int64,
    endEpochMillis: Int64,
    timezone: String,
    nowMillis: Int64
  ) -> AgentNativeToolExecutionResult
  func deleteEvent(eventId: Int64, nowMillis: Int64) -> AgentNativeToolExecutionResult
}

struct AgentIOSDefaultCalendarWriteProvider: AgentIOSCalendarWriteProviding {
  func upsertEvent(
    eventId: Int64,
    calendarId: Int64,
    title: String,
    description: String,
    location: String,
    startEpochMillis: Int64,
    endEpochMillis: Int64,
    timezone: String,
    nowMillis: Int64
  ) -> AgentNativeToolExecutionResult {
    guard startEpochMillis > 0, endEpochMillis > startEpochMillis else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_time_range",
        message: "Calendar event time range is invalid"
      )
    }
    let boundedTitle = bounded(title, 240)
    guard !boundedTitle.isEmpty else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_calendar_event",
        message: "Calendar event title is empty"
      )
    }

    #if canImport(EventKit)
    let authorization = EKEventStore.authorizationStatus(for: .event)
    guard isCalendarWritable(authorization) else {
      return AgentNativeToolExecutionResult.failure(
        code: "calendar_permission_required",
        message: "iOS Calendar write permission is required before events can be changed."
      )
    }

    let store = EKEventStore()
    guard let calendar = calendar(store: store, matching: calendarId) else {
      return AgentNativeToolExecutionResult.failure(
        code: "calendar_not_found",
        message: "Writable iOS calendar was not found."
      )
    }

    do {
      if eventId > 0 {
        return try updateEvent(
          store: store,
          eventId: eventId,
          calendar: calendar,
          title: boundedTitle,
          description: bounded(description, 2_000),
          location: bounded(location, 240),
          startEpochMillis: startEpochMillis,
          endEpochMillis: endEpochMillis,
          timezone: bounded(timezone, 80),
          authorization: authorization,
          nowMillis: nowMillis
        )
      }
      return try createEvent(
        store: store,
        calendar: calendar,
        title: boundedTitle,
        description: bounded(description, 2_000),
        location: bounded(location, 240),
        startEpochMillis: startEpochMillis,
        endEpochMillis: endEpochMillis,
        timezone: bounded(timezone, 80),
        authorization: authorization,
        nowMillis: nowMillis
      )
    } catch {
      return AgentNativeToolExecutionResult.failure(
        code: "calendar_write_failed",
        message: "iOS Calendar write failed."
      )
    }
    #else
    return AgentNativeToolExecutionResult.failure(
      code: "eventkit_unavailable",
      message: "EventKit is unavailable on this platform."
    )
    #endif
  }

  func deleteEvent(eventId: Int64, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    guard eventId > 0 else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_event_id",
        message: "Calendar event id must be positive."
      )
    }

    #if canImport(EventKit)
    let authorization = EKEventStore.authorizationStatus(for: .event)
    guard isCalendarWritable(authorization) else {
      return AgentNativeToolExecutionResult.failure(
        code: "calendar_permission_required",
        message: "iOS Calendar write permission is required before events can be deleted."
      )
    }

    let store = EKEventStore()
    do {
      guard let event = findEventForDelete(store: store, eventId: eventId, nowMillis: nowMillis) else {
        return AgentNativeToolExecutionResult.success(
          output: commonOutput(
            [
              "event_id": .int(eventId),
              "deleted_rows": .int(0),
              "event_found": .bool(false)
            ],
            authorization: authorization,
            nowMillis: nowMillis
          ),
          message: "Calendar event delete completed"
        )
      }
      try store.remove(event, span: .thisEvent, commit: true)
      return AgentNativeToolExecutionResult.success(
        output: commonOutput(
          [
            "event_id": .int(eventId),
            "deleted_rows": .int(1),
            "event_found": .bool(true)
          ],
          authorization: authorization,
          nowMillis: nowMillis
        ),
        message: "Calendar event delete completed"
      )
    } catch {
      return AgentNativeToolExecutionResult.failure(
        code: "calendar_delete_failed",
        message: "iOS Calendar event delete failed."
      )
    }
    #else
    return AgentNativeToolExecutionResult.failure(
      code: "eventkit_unavailable",
      message: "EventKit is unavailable on this platform."
    )
    #endif
  }

  #if canImport(EventKit)
  private func createEvent(
    store: EKEventStore,
    calendar: EKCalendar,
    title: String,
    description: String,
    location: String,
    startEpochMillis: Int64,
    endEpochMillis: Int64,
    timezone: String,
    authorization: EKAuthorizationStatus,
    nowMillis: Int64
  ) throws -> AgentNativeToolExecutionResult {
    let event = EKEvent(eventStore: store)
    apply(
      event: event,
      calendar: calendar,
      title: title,
      description: description,
      location: location,
      startEpochMillis: startEpochMillis,
      endEpochMillis: endEpochMillis,
      timezone: timezone
    )
    try store.save(event, span: .thisEvent, commit: true)
    let eventId = syntheticEventId(event)
    return AgentNativeToolExecutionResult.success(
      output: commonOutput(
        [
          "event_id": .int(eventId),
          "calendar_id": .int(syntheticCalendarId(calendar.calendarIdentifier)),
          "title": .string(title),
          "start_epoch_ms": .int(startEpochMillis),
          "end_epoch_ms": .int(endEpochMillis),
          "location": .string(location),
          "created": .bool(true)
        ],
        authorization: authorization,
        nowMillis: nowMillis
      ),
      message: "Calendar event created"
    )
  }

  private func updateEvent(
    store: EKEventStore,
    eventId: Int64,
    calendar: EKCalendar,
    title: String,
    description: String,
    location: String,
    startEpochMillis: Int64,
    endEpochMillis: Int64,
    timezone: String,
    authorization: EKAuthorizationStatus,
    nowMillis: Int64
  ) throws -> AgentNativeToolExecutionResult {
    guard let event = findEventForUpdate(
      store: store,
      eventId: eventId,
      startEpochMillis: startEpochMillis,
      endEpochMillis: endEpochMillis
    ) else {
      return AgentNativeToolExecutionResult.success(
        output: commonOutput(
          [
            "event_id": .int(eventId),
            "updated_rows": .int(0),
            "event_found": .bool(false)
          ],
          authorization: authorization,
          nowMillis: nowMillis
        ),
        message: "Calendar event updated"
      )
    }
    apply(
      event: event,
      calendar: calendar,
      title: title,
      description: description,
      location: location,
      startEpochMillis: startEpochMillis,
      endEpochMillis: endEpochMillis,
      timezone: timezone
    )
    try store.save(event, span: .thisEvent, commit: true)
    return AgentNativeToolExecutionResult.success(
      output: commonOutput(
        [
          "event_id": .int(eventId),
          "calendar_id": .int(syntheticCalendarId(calendar.calendarIdentifier)),
          "title": .string(title),
          "start_epoch_ms": .int(startEpochMillis),
          "end_epoch_ms": .int(endEpochMillis),
          "location": .string(location),
          "updated_rows": .int(1),
          "event_found": .bool(true)
        ],
        authorization: authorization,
        nowMillis: nowMillis
      ),
      message: "Calendar event updated"
    )
  }

  private func apply(
    event: EKEvent,
    calendar: EKCalendar,
    title: String,
    description: String,
    location: String,
    startEpochMillis: Int64,
    endEpochMillis: Int64,
    timezone: String
  ) {
    event.calendar = calendar
    event.title = title
    event.notes = description
    event.location = location
    event.startDate = date(startEpochMillis)
    event.endDate = date(endEpochMillis)
    event.timeZone = TimeZone(identifier: timezone) ?? .current
  }

  private func calendar(store: EKEventStore, matching calendarId: Int64) -> EKCalendar? {
    store.calendars(for: .event).first {
      syntheticCalendarId($0.calendarIdentifier) == calendarId
    }
  }

  private func findEventForUpdate(
    store: EKEventStore,
    eventId: Int64,
    startEpochMillis: Int64,
    endEpochMillis: Int64
  ) -> EKEvent? {
    let start = date(startEpochMillis).addingTimeInterval(-366 * 24 * 60 * 60)
    let end = date(endEpochMillis).addingTimeInterval(366 * 24 * 60 * 60)
    return firstEvent(store: store, eventId: eventId, start: start, end: end)
  }

  private func findEventForDelete(
    store: EKEventStore,
    eventId: Int64,
    nowMillis: Int64
  ) -> EKEvent? {
    let now = date(nowMillis)
    let start = Calendar.current.date(byAdding: .year, value: -1, to: now)
      ?? now.addingTimeInterval(-366 * 24 * 60 * 60)
    let end = Calendar.current.date(byAdding: .year, value: 5, to: now)
      ?? now.addingTimeInterval(5 * 366 * 24 * 60 * 60)
    return firstEvent(store: store, eventId: eventId, start: start, end: end)
  }

  private func firstEvent(
    store: EKEventStore,
    eventId: Int64,
    start: Date,
    end: Date
  ) -> EKEvent? {
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
    return store.events(matching: predicate).first {
      syntheticEventId($0) == eventId
    }
  }

  private func commonOutput(
    _ values: AgentMcpJSONObject,
    authorization: EKAuthorizationStatus,
    nowMillis: Int64
  ) -> AgentMcpJSONObject {
    var output = values
    output["authorization_status"] = .string(authorizationStatus(authorization))
    output["scope"] = .string("ios_calendar_write")
    output["platform"] = .string("ios")
    output["observed_at_epoch_ms"] = .int(nowMillis)
    return output
  }

  private func isCalendarWritable(_ status: EKAuthorizationStatus) -> Bool {
    status == .authorized || String(describing: status).lowercased().contains("full")
  }

  private func authorizationStatus(_ status: EKAuthorizationStatus) -> String {
    switch status {
    case .notDetermined:
      return "not_determined"
    case .restricted:
      return "restricted"
    case .denied:
      return "denied"
    case .authorized:
      return "authorized"
    @unknown default:
      return String(describing: status)
        .replacingOccurrences(of: " ", with: "_")
        .lowercased()
    }
  }

  private func syntheticEventId(_ event: EKEvent) -> Int64 {
    syntheticCalendarId(event.eventIdentifier ?? "\(event.startDate.timeIntervalSince1970)|\(event.title ?? "")")
  }

  private func syntheticCalendarId(_ identifier: String) -> Int64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in identifier.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return Int64(hash & 0x7fff_ffff_ffff_ffff)
  }
  #endif

  private func date(_ epochMillis: Int64) -> Date {
    Date(timeIntervalSince1970: TimeInterval(epochMillis) / 1_000)
  }

  private func bounded(_ value: String, _ limit: Int) -> String {
    String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }
}
