import Foundation

struct GalaxySSIHealthMeasurementSelection {
  struct Request: Equatable { let id = UUID(); let period: GalaxySSIHealthMeasurementPeriod? }
  private(set) var displayed: GalaxySSIHealthMeasurementPeriod?
  private(set) var pending: Request?
  var selected: GalaxySSIHealthMeasurementPeriod? { if let pending { return pending.period }; return displayed }
  mutating func choose(_ period: GalaxySSIHealthMeasurementPeriod?) -> Request? {
    if let pending, pending.period == period { return nil }
    pending = nil
    guard displayed != period else { return nil }
    let request = Request(period: period); pending = request; return request
  }
  mutating func commit(_ request: Request) -> Bool {
    guard pending == request else { return false }
    displayed = request.period; pending = nil; return true
  }
  mutating func cancel() { pending = nil }
}

enum GalaxySSIHealthMeasurementList {
  enum ItemID: Hashable {
    case series(GalaxySSIHealthMeasurementPeriods.Key), missing(GalaxySSIHealthMetric)
  }
  struct Item: Identifiable {
    let metric: GalaxySSIHealthOverview.Metric
    let series: GalaxySSIHealthMeasurementPeriods.Series?
    var id: ItemID { series.map { .series($0.key) } ?? .missing(metric.metric) }
  }

  // Prior outliers belong in the caption, not the current-result abnormal filter.
  static func rows(_ items: [Item], abnormal: Bool) -> [Item] {
    items.enumerated().filter { $0.element.metric.metric != .steps && (!abnormal || $0.element.metric.outsideRange) }
      .sorted {
        let a = $0.element.metric, b = $1.element.metric
        return (a.outsideRange ? 0 : 1, a.reading == nil ? 1 : 0, $0.offset) <
          (b.outsideRange ? 0 : 1, b.reading == nil ? 1 : 0, $1.offset)
      }.map(\.element)
  }
  static func previewSize(_ items: [Item]) -> Int {
    min(items.count, max(5, items.filter { $0.metric.outsideRange }.count))
  }
}
