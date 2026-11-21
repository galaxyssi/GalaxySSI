import Foundation

enum GalaxySSIHealthMotion {
  static let maximumSteps = Int(Int32.max)
  static let maximumGoal = 1_000_000
  struct Steps: Codable, Equatable {
    var segment = UUID()
    var day: Date
    var zone: String
    var total = 0
    var base = 0
    var start: Date?
    var sampledThrough: Date?

    mutating func resume(now: Date, calendar: Calendar) {
      if day != calendar.startOfDay(for: now) || zone != calendar.timeZone.identifier {
        day = calendar.startOfDay(for: now); zone = calendar.timeZone.identifier; total = 0
      }
      base = total; start = now; sampledThrough = nil; segment = UUID()
    }
    mutating func observe(_ count: Int, from: Date, through: Date, now: Date, calendar: Calendar) {
      guard count >= 0, let start, from == start, through >= start, through <= now,
            day == calendar.startOfDay(for: now), zone == calendar.timeZone.identifier,
            sampledThrough.map({ through >= $0 }) != false else { return }
      total = max(total, base + min(count, GalaxySSIHealthMotion.maximumSteps - base))
      sampledThrough = through
    }
    func today(_ now: Date, calendar: Calendar) -> Int? {
      day == calendar.startOfDay(for: now) && zone == calendar.timeZone.identifier ? total : nil
    }
  }
  struct State: Codable, Equatable {
    var revision = UUID()
    var goal: Int?
    var stepsEnabled: Date?
    var cyclingEnabled: Date?
    var steps: Steps?
    var cycling = Cycling()
    var clockWall: Date?
    var clockUptime: TimeInterval?

    mutating func prepare(now: Date, uptime: TimeInterval, calendar: Calendar) {
      let rebooted = clockUptime.map { uptime < $0 } ?? false
      let recoveryFloor = rebooted ? max(calendar.startOfDay(for: now), now.addingTimeInterval(-uptime)) : now
      let changedClock: Bool
      if let wall = clockWall, let previous = clockUptime {
        changedClock = uptime < previous || abs(now.timeIntervalSince(wall) - (uptime - previous)) > 120
      } else { changedClock = false }
      if let enabled = stepsEnabled {
        if steps == nil { steps = .init(day: calendar.startOfDay(for: now), zone: calendar.timeZone.identifier) }
        if changedClock { stepsEnabled = min(enabled, now); steps?.resume(now: max(min(enabled, now), recoveryFloor), calendar: calendar) }
        else if steps?.day != calendar.startOfDay(for: now) || steps?.zone != calendar.timeZone.identifier {
          steps?.resume(now: max(enabled, calendar.startOfDay(for: now)), calendar: calendar)
        } else if steps?.start == nil { steps?.resume(now: now, calendar: calendar) }
      }
      if changedClock || cycling.zone != calendar.timeZone.identifier || cycling.cursor.map({ $0 > now }) == true {
        var previous = calendar
        previous.timeZone = TimeZone(identifier: cycling.zone) ?? calendar.timeZone
        cycling.settle(now: now, calendar: previous); cycling.lastEvent = nil
        cycling.cursor = rebooted ? min(now, max(cycling.cursor ?? recoveryFloor, now.addingTimeInterval(-uptime))) : now
        cycling.epoch = UUID()
        if let enabled = cyclingEnabled { cyclingEnabled = min(enabled, now) }
      }
      cycling.zone = calendar.timeZone.identifier
      clockWall = now; clockUptime = uptime
    }
    mutating func enableSteps(_ enabled: Bool, now: Date, calendar: Calendar) {
      stepsEnabled = enabled ? now : nil
      if enabled {
        if steps == nil { steps = .init(day: calendar.startOfDay(for: now), zone: calendar.timeZone.identifier) }
        steps?.resume(now: now, calendar: calendar)
      } else { steps?.start = nil; steps?.segment = UUID() }
    }
    mutating func enableCycling(_ enabled: Bool, now: Date, calendar: Calendar) {
      cycling.settle(now: now, calendar: calendar)
      cyclingEnabled = enabled ? now : nil
      cycling.lastEvent = nil; cycling.cursor = now
      cycling.zone = calendar.timeZone.identifier; cycling.epoch = UUID()
    }
    func validate() throws {
      let invalid = GalaxySSIHealthRecords.Failure.invalid
      guard goal.map({ (1...GalaxySSIHealthMotion.maximumGoal).contains($0) }) != false,
            [stepsEnabled, cyclingEnabled, clockWall, cycling.cursor, cycling.lastEvent, cycling.started, cycling.evidence,
             cycling.gap, cycling.stillSince, cycling.candidate].compactMap({ $0 })
              .allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }),
            clockUptime.map({ $0.isFinite && $0 >= 0 }) != false, cycling.days.count <= 8 else { throw invalid }
      guard stepsEnabled != nil || steps?.start == nil, cyclingEnabled != nil || (cycling.started == nil && cycling.candidate == nil),
            cyclingEnabled == nil || (cycling.cursor != nil && TimeZone(identifier: cycling.zone) != nil),
            stepsEnabled == nil || (steps != nil && steps?.start != nil) else { throw invalid }
      try cycling.validate()
      if let steps {
        guard steps.day.timeIntervalSinceReferenceDate.isFinite, let zone = TimeZone(identifier: steps.zone),
              (0...GalaxySSIHealthMotion.maximumSteps).contains(steps.total), (0...steps.total).contains(steps.base),
              [steps.start, steps.sampledThrough].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }) else { throw invalid }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        guard calendar.startOfDay(for: steps.day) == steps.day,
              steps.start.map({ calendar.startOfDay(for: $0) == steps.day }) != false,
              steps.sampledThrough.map({ calendar.startOfDay(for: $0) == steps.day && $0 >= (steps.start ?? .distantPast) }) != false else { throw invalid }
      }
      var keys = Set<String>()
      for day in cycling.days {
        guard let zone = TimeZone(identifier: day.zone), day.start.timeIntervalSinceReferenceDate.isFinite,
              day.seconds.isFinite, day.seconds >= 0, keys.insert(day.zone + ":" + String(day.start.timeIntervalSinceReferenceDate)).inserted else { throw invalid }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        guard calendar.startOfDay(for: day.start) == day.start,
              day.seconds <= (calendar.dateInterval(of: .day, for: day.start)?.duration ?? 0) else { throw invalid }
      }
    }
  }
  static func progress(goal: Int?, steps: Int?, fresh: Bool, permitted: Bool) -> Double? {
    guard permitted, fresh, let goal, (1...maximumGoal).contains(goal), let steps, steps >= 0 else { return nil }
    return Double(steps) / Double(goal)
  }
}
