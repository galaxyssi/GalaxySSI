import Foundation

enum GalaxySSIHealthCareTarget {
  enum Component: String, Codable, CaseIterable { case value, systolic, diastolic }
  enum Comparison: String { case reviewRequired, notComparable, below, within, above }

  struct Bounds: Codable, Equatable {
    let low: Decimal?
    let high: Decimal?
    let lowInclusive: Bool
    let highInclusive: Bool

    init(low: String, high: String, lowInclusive: Bool, highInclusive: Bool) throws {
      func parse(_ input: String) throws -> Decimal? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        guard text.utf8.count <= 20,
              text.range(of: #"\A[0-9]+(?:\.[0-9]+)?\z"#, options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN
        else { throw GalaxySSIHealthRecords.Failure.invalid }
        return value
      }
      let parsedLow = try parse(low), parsedHigh = try parse(high)
      self.low = parsedLow
      self.high = parsedHigh
      self.lowInclusive = parsedLow != nil && lowInclusive
      self.highInclusive = parsedHigh != nil && highInclusive
      guard self.low != nil || self.high != nil else { throw GalaxySSIHealthRecords.Failure.invalid }
      if let low = self.low, let high = self.high,
         !(low < high || low == high && self.lowInclusive && self.highInclusive) {
        throw GalaxySSIHealthRecords.Failure.invalid
      }
    }

    var description: String {
      let left = low.map { (lowInclusive ? ">= " : "> ") + NSDecimalNumber(decimal: $0).stringValue }
      let right = high.map { (highInclusive ? "<= " : "< ") + NSDecimalNumber(decimal: $0).stringValue }
      return [left, right].compactMap { $0 }.joined(separator: ", ")
    }
  }

  struct Confirmed: Codable, Equatable {
    let component: Component
    let bounds: Bounds
    let unit: String
    let basis: String
  }

  static func components(for metric: GalaxySSIHealthMetric) -> [Component] {
    if metric == .bloodPressure { return [.systolic, .diastolic] }
    return metric.form == .qualitative ? [] : [.value]
  }

  static func basis(_ concern: GalaxySSIHealthCare.Concern) throws -> String {
    var context = concern.context?.applicability.rawValue ?? ""
    if let answers = concern.context?.answers {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      context += ":" + AgentModelLoopRecoveryIdentity.sha256([
        "answers": String(decoding: try encoder.encode(answers), as: UTF8.self)
      ])
    }
    return AgentModelLoopRecoveryIdentity.sha256([
      "assessment": try GalaxySSIHealthCare.inputDigest(concern.assessment),
      "context": context
    ])
  }

  static func canConfirm(_ bounds: Bounds, component: Component, concern: GalaxySSIHealthCare.Concern) -> Bool {
    let form = concern.metric.form
    guard concern.assessment.record != nil, components(for: concern.metric).contains(component),
          concern.metric.units.contains(concern.assessment.unit) else { return false }
    let numbers = [bounds.low, bounds.high].compactMap { $0 }
    guard !numbers.isEmpty else { return false }
    if let low = bounds.low, let high = bounds.high,
       !(low < high || low == high && bounds.lowInclusive && bounds.highInclusive) { return false }
    return numbers.allSatisfy { number in
      guard !number.isNaN, number >= 0, form != .positive || number > 0 else { return false }
      if form != .count { return true }
      var value = number, rounded = Decimal.zero
      NSDecimalRound(&rounded, &value, 0, .down)
      return rounded == number
    }
  }

  static func compare(_ target: Confirmed, concern: GalaxySSIHealthCare.Concern,
                      reading: GalaxySSIHealthReading?) -> Comparison {
    guard (try? basis(concern)) == target.basis,
          let reading, GalaxySSIHealthCare.Record(reading) == concern.assessment.record else { return .reviewRequired }
    guard reading.isValid, reading.metric == concern.metric, reading.unit == target.unit,
          canConfirm(target.bounds, component: target.component, concern: concern),
          let value = target.component == .diastolic ? reading.diastolic : reading.value else { return .notComparable }
    let bounds = target.bounds
    if let low = bounds.low, value < low || value == low && !bounds.lowInclusive { return .below }
    if let high = bounds.high, value > high || value == high && !bounds.highInclusive { return .above }
    return .within
  }
}
