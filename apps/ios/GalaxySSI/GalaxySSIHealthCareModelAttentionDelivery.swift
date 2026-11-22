import Foundation

@MainActor
enum GalaxySSIHealthCareModelAttentionDelivery {
  typealias Notice = GalaxySSIHealthCareModelAttention.Receipt
  typealias Settings = GalaxySSIHealthRecordingReminders.Settings

  static func reconcile(records: GalaxySSIHealthRecords, systemAllowed: Bool, visible: [String: UUID],
      now: Date, calendar: Calendar, clock: (() -> Date)? = nil, binding: (Notice) -> Bool, foreground: (Notice) -> Bool,
      post: (Notice) async -> Bool, cancel: (String) -> Void) async throws -> Date? {
    let settings = try records.load().recordingReminders?.settings ?? .init()
    guard settings.isValid else { throw GalaxySSIHealthRecords.Failure.invalid }
    let allowed = settings.notifications && settings.allowsModelReviews && systemAllowed
    let deferred = settings.nextDelivery(now, calendar: calendar) > now
    let stored = try records.load().localCareModelAttention ?? [:]
    func observedAt() -> Date { clock?() ?? now }
    func valid(_ value: Notice) -> Bool { records.modelAttentionCurrent(value, now: observedAt()) && binding(value) }
    for (identifier, turn) in visible {
      guard let value = stored.values.first(where: { $0.identifier == identifier && $0.turn == turn }),
            value.state == .waiting || value.state == .posted, valid(value), allowed, !deferred,
            !foreground(value) else { cancel(identifier); continue }
    }
    for value in try records.pendingModelAttention() {
      try Task.checkCancellation()
      let policy = try records.load().recordingReminders?.settings ?? .init()
      let at = observedAt()
      let allowed = policy.notifications && policy.allowsModelReviews && systemAllowed
      let deferred = policy.nextDelivery(at, calendar: calendar) > at
      if !valid(value) {
        cancel(value.identifier)
        try records.finishModelAttention(value, state: .stale)
      } else if !allowed || foreground(value) {
        cancel(value.identifier)
        try records.finishModelAttention(value, state: .inAppOnly)
      } else if deferred || (value.retryAt ?? .distantPast) > at {
        continue
      } else if visible[value.identifier] == value.turn {
        try records.finishModelAttention(value, state: .posted)
      } else {
        if visible[value.identifier] != nil { cancel(value.identifier) }
        let posted = await post(value)
        if Task.isCancelled { cancel(value.identifier); throw CancellationError() }
        let fresh = try records.load().recordingReminders?.settings ?? .init()
        let afterPost = observedAt()
        if !valid(value) {
          cancel(value.identifier)
          try records.finishModelAttention(value, state: .stale)
        } else if !fresh.notifications || !fresh.allowsModelReviews || foreground(value) {
          cancel(value.identifier)
          try records.finishModelAttention(value, state: .inAppOnly)
        } else if fresh.nextDelivery(afterPost, calendar: calendar) > afterPost {
          cancel(value.identifier)
        } else if posted {
          if try !records.finishModelAttention(value, state: .posted) { cancel(value.identifier) }
        } else {
          try records.deferModelAttention(value, until: afterPost.addingTimeInterval(60))
        }
      }
    }
    guard let next = try records.pendingModelAttention(limit: 1).first else { return nil }
    let fresh = try records.load().recordingReminders?.settings ?? .init()
    let at = observedAt()
    return max(at.addingTimeInterval(1), fresh.nextDelivery(max(at, next.retryAt ?? at), calendar: calendar))
  }
}
