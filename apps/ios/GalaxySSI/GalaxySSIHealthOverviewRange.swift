import Foundation

struct GalaxySSIHealthOverviewRange: Equatable {
  enum Source: String { case report, record, confirmedTarget }
  enum Position: String { case below, within, above, notComparable }
  let component: GalaxySSIHealthCareTarget.Component
  let source: Source
  let bounds: String
  let unit: String
  let position: Position
  var outside: Bool { position == .below || position == .above }

  static func report(_ reading: GalaxySSIHealthReading) -> Self? {
    guard reading.isValid, reading.metric != .bloodPressure, !reading.unit.isEmpty, reading.metric.units.contains(reading.unit),
          let raw = reading.referenceInterval,
          let range = GalaxySSIHealthReportedResult.parse(raw, metric: .glucose, allowFreeformQualitative: false),
          [.range, .comparison].contains(range.kind), let low = range.lower else { return nil }
    let position: Position
    if let number = reading.value, reading.reported == nil, !number.isNaN {
      if range.kind == .range, number < low { position = .below }
      else if range.kind == .range, let high = range.upper, number > high { position = .above }
      else if range.comparator == "<" && number >= low || range.comparator == "<=" && number > low { position = .above }
      else if range.comparator == ">" && number <= low || range.comparator == ">=" && number < low { position = .below }
      else { position = .within }
    } else { position = .notComparable }
    return .init(component: .value, source: reading.reportSource == nil ? .record : .report,
      bounds: range.raw, unit: reading.unit, position: position)
  }

  static func target(_ reading: GalaxySSIHealthReading, concern: GalaxySSIHealthCare.Concern) -> Self? {
    guard reading.isValid, ![.paused, .closed].contains(concern.stage), let target = concern.target?.numeric,
          concern.metric == reading.metric, concern.assessment.record == GalaxySSIHealthCare.Record(reading),
          GalaxySSIHealthCareTarget.components(for: reading.metric).contains(target.component),
          target.unit == reading.unit else { return nil }
    let position: Position
    switch GalaxySSIHealthCareTarget.compare(target, concern: concern, reading: reading) {
    case .reviewRequired: return nil
    case .notComparable: position = .notComparable
    case .below: position = .below
    case .within: position = .within
    case .above: position = .above
    }
    let bounds = target.bounds
    let text: String
    if let low = bounds.low, let high = bounds.high, bounds.lowInclusive, bounds.highInclusive {
      text = NSDecimalNumber(decimal: low).stringValue + "\u{2013}" + NSDecimalNumber(decimal: high).stringValue
    } else {
      let low = bounds.low.map { (bounds.lowInclusive ? "\u{2265} " : "> ") + NSDecimalNumber(decimal: $0).stringValue }
      let high = bounds.high.map { (bounds.highInclusive ? "\u{2264} " : "< ") + NSDecimalNumber(decimal: $0).stringValue }
      text = [low, high].compactMap { $0 }.joined(separator: " / ")
    }
    return .init(component: target.component, source: .confirmedTarget, bounds: text, unit: target.unit, position: position)
  }
}

extension GalaxySSIHealthRecords {
  // A read-only projection, bound to the same archive used to render the readings.
  func overviewRanges(expected: Archive, now: Date) throws -> [GalaxySSIHealthMetric: [GalaxySSIHealthOverviewRange]] {
    let archive = try load()
    guard archive.derivesOverview == true, expected.derivesOverview == true, archive.current == expected.current,
          archive.localCareAllowed == expected.localCareAllowed, archive.localCarePermission == expected.localCarePermission,
          archive.profileAnalysisPermission == expected.profileAnalysisPermission,
          archive.localCare?.current == expected.localCare?.current else { return [:] }
    let grouped = Dictionary(grouping: archive.current.filter { $0.isValid && $0.measuredAt <= now }) { $0.metric }
    var result: [GalaxySSIHealthMetric: [GalaxySSIHealthOverviewRange]] = [:]
    for (metric, readings) in grouped where metric != .temperature && metric != .oxygenSaturation {
      guard let reading = readings.first else { continue }
      var ranges = [GalaxySSIHealthOverviewRange.report(reading)].compactMap { $0 }
      if archive.localCareAllowed == true, archive.profileAnalysisPermission != nil,
         let concern = archive.localCare?.current[metric.rawValue],
         (GalaxySSIHealthCare.assess(readings, context: concern.context) ?? .removed) == concern.assessment,
         localCareProfileIsCurrent(concern.profileScope),
         let target = GalaxySSIHealthOverviewRange.target(reading, concern: concern) { ranges.append(target) }
      if !ranges.isEmpty { result[metric] = ranges }
    }
    return result
  }
}
