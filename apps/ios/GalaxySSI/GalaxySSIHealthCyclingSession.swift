import Foundation

extension GalaxySSIHealthMotion {
  struct Cycling: Codable, Equatable {
    struct Day: Codable, Equatable { let start: Date; let zone: String; var seconds: TimeInterval }
    enum Kind: String, Codable { case enter, pedalling, exit, still, foot, motor, uncertain, cycling, inactive }
    struct Event { let at: Date; let kind: Kind }
    struct Departure: Codable, Equatable { let kind: Kind; let from: Date; var last: Date }
    var epoch = UUID()
    var cursor: Date?
    var lastEvent: Date?
    var started: Date?
    var zone = ""
    var days: [Day] = []
    // Optional additions keep previously encrypted ledgers decodable without inventing evidence.
    var evidence: Date?
    var gap: Date?
    var stillSince: Date?
    var departure: Departure?
    var candidate: Date?
    var confirmedThrough: Date? { started.map { gap ?? evidence ?? $0 } }

    mutating func observe(_ event: Event, now: Date, calendar: Calendar) {
      guard event.kind != .uncertain, event.at.timeIntervalSinceReferenceDate.isFinite, event.at <= now,
            lastEvent.map({ event.at > $0 }) != false else { return }
      let kind: Kind = event.kind == .cycling ? .enter : (event.kind == .inactive ? .exit : event.kind)
      let time = event.at, bike = kind == .enter || kind == .pedalling
      if started != nil && !riding(time) { settle(now: now, calendar: calendar) }
      if started == nil {
        let possible = candidate.flatMap { time > $0 && time.timeIntervalSince($0) <= 90 ? $0 : nil }
        guard bike || candidate != nil else { return }
        if !bike { candidate = nil; record(time); return }
        if kind == .enter || possible.map({ time.timeIntervalSince($0) >= 15 }) == true {
          started = possible ?? time; evidence = time; gap = nil; stillSince = nil; departure = nil; candidate = nil
        } else { candidate = possible ?? time }
        record(time); return
      }
      switch kind {
      case .enter, .pedalling:
        evidence = time; gap = nil; stillSince = nil; departure = nil
      case .exit: gap = gap ?? time
      case .still: gap = gap ?? time; stillSince = stillSince ?? time; departure = nil
      case .foot, .motor:
        var next = departure.flatMap { $0.kind == kind && time.timeIntervalSince($0.last) <= 90 ? $0 : nil } ??
          Departure(kind: kind, from: time, last: time)
        next.last = time
        if time.timeIntervalSince(next.from) >= (kind == .motor ? 25 : 50) {
          finish(until: min(confirmedThrough ?? time, next.from), now: now, calendar: calendar)
          record(time); return
        }
        gap = gap ?? time; stillSince = nil; departure = next
      default: return
      }
      record(time)
    }
    mutating func settle(now: Date, calendar: Calendar) {
      if let until = confirmedThrough { finish(until: until, now: now, calendar: calendar) }
      else { clearRide() }
    }
    // Only replay an interval supplied by history boundaries or an explicit current-state snapshot.
    mutating func replay(_ kind: Kind, from: Date, through: Date, now: Date, calendar: Calendar, includeEnd: Bool) {
      guard kind != .uncertain, from.timeIntervalSinceReferenceDate.isFinite, through.timeIntervalSinceReferenceDate.isFinite,
            from <= through, through <= now, through.timeIntervalSince(from) <= 7 * 86_400 else { return }
      observe(.init(at: from, kind: kind), now: now, calendar: calendar)
      let sampled: Kind = kind == .enter || kind == .cycling ? .pedalling : kind
      var date = max(from, lastEvent ?? from).addingTimeInterval(20)
      while date < through {
        observe(.init(at: date, kind: sampled), now: now, calendar: calendar)
        date = date.addingTimeInterval(20)
      }
      if includeEnd { observe(.init(at: through, kind: sampled), now: now, calendar: calendar) }
    }
    mutating func expire(now: Date, calendar: Calendar) {
      if started != nil && !riding(now) { settle(now: now, calendar: calendar) }
      if candidate.map({ now.timeIntervalSince($0) > 90 }) == true { candidate = nil }
    }
    func riding(_ now: Date) -> Bool {
      guard let started, let confirmedThrough, now >= confirmedThrough,
            (0...43_200).contains(now.timeIntervalSince(started)), now.timeIntervalSince(confirmedThrough) < 480,
            stillSince.map({ now.timeIntervalSince($0) < 180 }) != false else { return false }
      return true
    }
    func today(_ now: Date, calendar: Calendar) -> TimeInterval {
      let date = calendar.startOfDay(for: now)
      guard let interval = calendar.dateInterval(of: .day, for: date) else { return 0 }
      let saved = days.first { $0.start == date && $0.zone == calendar.timeZone.identifier }?.seconds ?? 0
      let active = started.flatMap { begin in confirmedThrough.map { intersection(interval, from: begin, to: min(now, $0)) } } ?? 0
      return min(interval.duration, saved + active)
    }
    private mutating func record(_ date: Date) { lastEvent = date; cursor = max(cursor ?? date, date) }
    private mutating func clearRide() { started = nil; evidence = nil; gap = nil; stillSince = nil; departure = nil; candidate = nil }
    private mutating func finish(until: Date, now: Date, calendar: Calendar) {
      guard let begin = started else { clearRide(); return }
      let end = begin.addingTimeInterval(min(43_200, max(0, min(now, until).timeIntervalSince(begin))))
      let today = calendar.startOfDay(for: now), floor = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now
      days = days.filter { $0.start >= floor && $0.start <= now }
      for offset in 0..<8 {
        guard let date = calendar.date(byAdding: .day, value: -offset, to: today),
              let interval = calendar.dateInterval(of: .day, for: date) else { continue }
        let part = intersection(interval, from: begin, to: end)
        guard part > 0 else { continue }
        if let index = days.firstIndex(where: { $0.start == date && $0.zone == calendar.timeZone.identifier }) {
          days[index].seconds = min(interval.duration, days[index].seconds + part)
        } else { days.append(.init(start: date, zone: calendar.timeZone.identifier, seconds: part)) }
      }
      days = Array(days.sorted { $0.start == $1.start ? $0.zone < $1.zone : $0.start > $1.start }.prefix(8))
      clearRide()
    }
    private func intersection(_ interval: DateInterval, from: Date, to: Date) -> TimeInterval {
      max(0, min(to, interval.end).timeIntervalSince(max(from, interval.start)))
    }
    func validate() throws {
      let invalid = GalaxySSIHealthRecords.Failure.invalid
      guard [cursor, lastEvent, started, evidence, gap, stillSince, candidate].compactMap({ $0 })
        .allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }) else { throw invalid }
      if let started {
        guard candidate == nil, let lastEvent, lastEvent >= started,
              [evidence, gap, stillSince].compactMap({ $0 }).allSatisfy({ $0 >= started && $0 <= lastEvent }),
              stillSince == nil || gap != nil else { throw invalid }
        if let evidence, let gap, gap < evidence { throw invalid }
      } else if evidence != nil || gap != nil || stillSince != nil || departure != nil { throw invalid }
      if let candidate, lastEvent.map({ candidate > $0 }) != false { throw invalid }
      if let departure {
        guard [.foot, .motor].contains(departure.kind), departure.from.timeIntervalSinceReferenceDate.isFinite,
              departure.last.timeIntervalSinceReferenceDate.isFinite, let started, departure.from >= started,
              departure.last >= departure.from, lastEvent.map({ departure.last <= $0 }) == true else { throw invalid }
      }
    }
  }
}
