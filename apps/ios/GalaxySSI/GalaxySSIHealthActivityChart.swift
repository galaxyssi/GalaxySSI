import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

struct GalaxySSIHealthActivityChart: UIViewRepresentable {
  let result: GalaxySSIHealthActivityComparison
  let kind: GalaxySSIHealthActivityKind
  let locale: Locale
  let zone: TimeZone
  let language: String
  @Binding var selectedDay: String
  var onTracking: (Bool) -> Void = { _ in }

  func makeUIView(context: Context) -> GalaxySSIHealthActivityChartView { GalaxySSIHealthActivityChartView() }
  func updateUIView(_ view: GalaxySSIHealthActivityChartView, context: Context) {
    view.configure(result: result, kind: kind, locale: locale, zone: zone, language: language,
      selectedDay: selectedDay, onSelection: { selectedDay = $0 }, onTracking: onTracking)
  }
}

final class GalaxySSIHealthActivityChartView: UIView, UIGestureRecognizerDelegate {
  private var result: GalaxySSIHealthActivityComparison?
  private var kind = GalaxySSIHealthActivityKind.steps
  private var locale = Locale.current, zone = TimeZone.current
  private var language = "en", selectedDay = ""
  private var onSelection: (String) -> Void = { _ in }
  private var area = CGRect.zero, dates: [String] = [], values: [String] = []
  private var days: [Int] { result.map { Array($0.pairs.indices) } ?? [] }
  private var selectedIndex: Int? { days.first { key($0) == selectedDay } }
  private var maximum: Double = 3, interval: Double = 1
  private var outsideTap: UITapGestureRecognizer?
  private var timeline: GalaxySSIHealthActivityTimelineGesture!
  private var onTracking: (Bool) -> Void = { _ in }
  private var axisFont: UIFont { UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: 11)) }
  private var tipFont: UIFont { UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12)) }
  private let accent = GalaxySSIHealthTheme.accentUIColor

  override init(frame: CGRect) {
    super.init(frame: frame)
    isOpaque = false; isAccessibilityElement = true; isMultipleTouchEnabled = true; contentMode = .redraw
    accessibilityIdentifier = "health-activity-chart"
    timeline = GalaxySSIHealthActivityTimelineGesture(target: self, action: #selector(timelineChanged))
    timeline.cancelsTouchesInView = false
    timeline.onTimeline = { [weak self] in self?.onTimeline($0) == true }
    timeline.onTracking = { [weak self] active in self?.onTracking(active) }
    addGestureRecognizer(timeline)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection); setNeedsDisplay()
  }

  func configure(result: GalaxySSIHealthActivityComparison, kind: GalaxySSIHealthActivityKind,
                 locale: Locale, zone: TimeZone, language: String, selectedDay: String,
                 onSelection: @escaping (String) -> Void, onTracking: @escaping (Bool) -> Void = { _ in }) {
    self.result = result; self.kind = kind; self.locale = locale; self.zone = zone
    self.language = language; self.selectedDay = selectedDay; self.onSelection = onSelection; self.onTracking = onTracking
    let divisor: Double = kind == .cycling ? 60_000 : 1
    interval = max(1, ceil(Double(result.pairs.compactMap(\.current).max() ?? 0) / divisor / 3))
    maximum = interval * 3 * divisor
    values = (0...3).map { (interval * Double($0)).formatted(.number.precision(.fractionLength(0)).locale(locale)) }
    let formatter = DateFormatter(); formatter.locale = locale; formatter.timeZone = zone
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    formatter.calendar = calendar
    formatter.dateFormat = result.pairs.first.map { first in
      calendar.component(.year, from: first.day) == calendar.component(.year, from: result.pairs.last?.day ?? first.day)
    } == true ? "M/d" : "yy/M/d"
    dates = result.pairs.map { formatter.string(from: $0.day) }
    accessibilityTraits = days.isEmpty ? .staticText : [.button, .adjustable]
    updateDescription(); setNeedsDisplay()
  }
  private func key(_ index: Int) -> String {
    guard let result, result.pairs.indices.contains(index) else { return "" }
    return GalaxySSIHealthActivityComparison.dayKey(result.pairs[index].day, zone: zone)
  }
  private func point(_ index: Int) -> CGPoint {
    guard let pairs = result?.pairs else { return .zero }
    let x = pairs.count == 1 ? area.midX : area.minX + area.width * CGFloat(index) / CGFloat(pairs.count - 1)
    let y = pairs[index].current.map { area.maxY - area.height * CGFloat(Double($0) / maximum) } ?? area.midY
    return CGPoint(x: x, y: y)
  }
  private func label(_ index: Int) -> String {
    guard let result else { return "" }
    let unit = GalaxySSILocalization.string("galaxyssi.health.activity_comparison." + (kind == .steps ? "steps_unit" : "minutes"),
      fallback: kind == .steps ? "steps" : "min", language: language)
    func localized(_ key: String, _ locale: String, fallback: String) -> String {
      guard let path = Bundle.main.path(forResource: locale, ofType: "lproj"), let bundle = Bundle(path: path) else { return fallback }
      return bundle.localizedString(forKey: key, value: fallback,
        table: key == "health_activity_day_unrecorded" ? "HealthActivityScrubbing" : "HealthActivitySelection")
    }
    let resolved = LanguagePolicySettings.resolveInterface(language) == LanguagePolicySettings.zhCN ? "zh-Hans" : "en"
    let english = localized("health_activity_point_value", "en", fallback: "%1$@ \u{00b7} %2$@")
    let template = localized("health_activity_point_value", resolved, fallback: english)
    let amount: String
    if let value = result.pairs[index].current {
      let number = kind == .steps ? value.formatted(.number.locale(locale)) :
        (Double(value) / 60_000).formatted(.number.precision(.fractionLength(0...1)).locale(locale))
      amount = number + " " + unit
    } else {
      let english = localized("health_activity_day_unrecorded", "en", fallback: "No record")
      amount = localized("health_activity_day_unrecorded", resolved, fallback: english)
    }
    return String(format: template, dates[index], amount)
  }
  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext(), let result, !result.pairs.isEmpty else { return }
    let attributes: [NSAttributedString.Key: Any] = [.font: axisFont, .foregroundColor: UIColor.secondaryLabel]
    func width(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: attributes).width }
    let dateWidth = dates.map(width).max() ?? 0
    let left = max((values.map(width).max() ?? 0) + 9, dateWidth / 2 + 1)
    let right = bounds.width - max(10, dateWidth / 2 + 1)
    let top = max(14, axisFont.lineHeight / 2 + 1), bottom = bounds.height - axisFont.lineHeight - 12
    area = CGRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top))
    guard !area.isEmpty else { return }
    for tick in 0...3 {
      let y = bottom - area.height * CGFloat(tick) / 3
      context.setStrokeColor(UIColor.separator.cgColor); context.setLineWidth(0.5)
      context.move(to: CGPoint(x: left, y: y)); context.addLine(to: CGPoint(x: right, y: y)); context.strokePath()
      (values[tick] as NSString).draw(at: CGPoint(x: left - 8 - width(values[tick]), y: y - axisFont.lineHeight / 2), withAttributes: attributes)
    }
    let preferred = result.pairs.count <= 7 ? 7 : 5
    let ticks = result.dateTickIndices(limit: min(preferred, Int(area.width / (dateWidth + 8)) + 1))
    for index in ticks {
      (dates[index] as NSString).draw(at: CGPoint(x: point(index).x - width(dates[index]) / 2, y: bottom + 6), withAttributes: attributes)
    }
    if let index = selectedIndex {
      context.setStrokeColor(accent.withAlphaComponent(0.5).cgColor); context.setLineWidth(1)
      context.move(to: CGPoint(x: point(index).x, y: top)); context.addLine(to: CGPoint(x: point(index).x, y: bottom)); context.strokePath()
    }
    context.setStrokeColor(accent.cgColor); context.setFillColor(accent.cgColor); context.setLineWidth(2)
    var previous: CGPoint?
    for pair in result.pairs {
      guard pair.current != nil else { previous = nil; continue }
      let current = point(pair.id)
      if let previous { context.move(to: previous); context.addLine(to: current); context.strokePath() }
      context.fillEllipse(in: CGRect(x: current.x - 2.5, y: current.y - 2.5, width: 5, height: 5))
      previous = current
    }
    if let index = selectedIndex {
      let p = point(index)
      if result.pairs[index].current != nil {
        context.setFillColor(accent.cgColor); context.fillEllipse(in: CGRect(x: p.x - 5.5, y: p.y - 5.5, width: 11, height: 11))
        context.setFillColor(UIColor.systemBackground.cgColor); context.fillEllipse(in: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9))
        context.setFillColor(accent.cgColor); context.fillEllipse(in: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5))
      }
      drawTooltip(label(index), at: p)
    }
  }
  private func drawTooltip(_ label: String, at point: CGPoint) {
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [.font: tipFont, .foregroundColor: UIColor.label, .paragraphStyle: paragraph]
    let ideal = ceil((label as NSString).size(withAttributes: attributes).width)
    let rightRoom = bounds.width - point.x - 11, leftRoom = point.x - area.minX - 9
    let onRight = rightRoom >= ideal + 16 || rightRoom >= leftRoom
    let room = (onRight ? rightRoom : leftRoom) - 16
    guard room >= 1 else { return }
    let width = min(ideal, room)
    let height = ceil((label as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height)
    let boxHeight = height + 10, boxWidth = width + 16
    let box = CGRect(x: onRight ? point.x + 9 : point.x - 9 - boxWidth,
      y: min(max(area.minY, point.y - boxHeight / 2), max(area.minY, area.maxY - boxHeight)), width: boxWidth, height: boxHeight)
    UIColor.secondarySystemBackground.setFill(); UIBezierPath(roundedRect: box, cornerRadius: 6).fill()
    (label as NSString).draw(with: box.insetBy(dx: 8, dy: 5), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
  }
  private func select(_ index: Int?) {
    let day = index.map(key) ?? ""
    guard day != selectedDay else { return }
    selectedDay = day; onSelection(day); updateDescription(); setNeedsDisplay()
  }
  private func updateDescription() {
    accessibilityLabel = selectedIndex.map(label) ?? GalaxySSILocalization.string("galaxyssi.health.activity_comparison.data",
      fallback: "Chart data", language: language)
  }
  private func onTimeline(_ p: CGPoint) -> Bool {
    !area.isEmpty && p.x >= area.minX - 10 && p.x <= area.maxX + 10 && p.y >= area.minY - 10 && p.y <= bounds.height
  }
  @objc private func timelineChanged() {
    guard timeline.state == .began || timeline.state == .changed || timeline.state == .ended else { return }
    let p = timeline.position
    if timeline.scrubbing || onTimeline(p), let result, !area.isEmpty {
      select(result.nearestDayIndex(fraction: Double((p.x - area.minX) / area.width))); becomeFirstResponder()
    } else if timeline.state == .ended { select(nil) }
  }
  override func accessibilityActivate() -> Bool { guard let last = days.last else { return false }; if selectedIndex == nil { select(last) }; return true }
  override func accessibilityIncrement() { moveSelection(forward: true) }
  override func accessibilityDecrement() { moveSelection(forward: false) }
  private func moveSelection(forward: Bool) {
    let current = selectedIndex
    let next = forward ? days.first { current == nil || $0 > current! } : days.last { current == nil || $0 < current! }
    if let next { select(next); UIAccessibility.post(notification: .announcement, argument: label(next)) }
  }
  override var canBecomeFirstResponder: Bool { !days.isEmpty }
  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if presses.contains(where: { $0.key?.keyCode == .keyboardRightArrow }) { moveSelection(forward: true); return }
    if presses.contains(where: { $0.key?.keyCode == .keyboardLeftArrow }) { moveSelection(forward: false); return }
    super.pressesBegan(presses, with: event)
  }
  // Observe outside taps without swallowing List controls or vertical scrolling.
  override func willMove(toWindow newWindow: UIWindow?) {
    if newWindow == nil { timeline.isEnabled = false; timeline.isEnabled = true }
    if let outsideTap { outsideTap.view?.removeGestureRecognizer(outsideTap) }
    outsideTap = nil
    super.willMove(toWindow: newWindow)
    if let newWindow {
      let tap = UITapGestureRecognizer(target: self, action: #selector(clearFromOutside))
      tap.cancelsTouchesInView = false; tap.delegate = self; newWindow.addGestureRecognizer(tap); outsideTap = tap
    }
  }
  override func didMoveToWindow() {
    super.didMoveToWindow()
    var ancestor = superview
    while let view = ancestor {
      if let scroll = view as? UIScrollView { scroll.panGestureRecognizer.require(toFail: timeline); break }
      ancestor = view.superview
    }
  }
  @objc private func clearFromOutside() { select(nil) }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    !isHidden && !bounds.contains(touch.location(in: self)) && selectedIndex != nil
  }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    gestureRecognizer === outsideTap || other === outsideTap
  }
}

// A directional recognizer fails early for vertical scrolls, before claiming a horizontal scrub.
final class GalaxySSIHealthActivityTimelineGesture: UIGestureRecognizer {
  var onTimeline: (CGPoint) -> Bool = { _ in false }
  var onTracking: (Bool) -> Void = { _ in }
  private(set) var position = CGPoint.zero
  private(set) var scrubbing = false
  private var origin = CGPoint.zero, tracking = false
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    guard !tracking, touches.count == 1, let touch = touches.first else { abort(); return }
    origin = touch.location(in: view); position = origin; tracking = true; onTracking(true)
  }
  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    guard tracking, let touch = touches.first else { return }
    position = touch.location(in: view)
    if state == .possible {
      let dx = abs(position.x - origin.x), dy = abs(position.y - origin.y)
      if max(dx, dy) > 10 {
        guard dx > dy, onTimeline(origin) else { state = .failed; finish(); return }
        scrubbing = true; state = .began
      }
    } else if scrubbing { state = .changed }
  }
  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    guard tracking, let touch = touches.first else { return }
    position = touch.location(in: view)
    if state == .possible && max(abs(position.x - origin.x), abs(position.y - origin.y)) > 10 { state = .failed }
    else { state = .ended }
    finish()
  }
  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { abort() }
  private func abort() { state = state == .possible ? .failed : .cancelled; finish() }
  private func finish() {
    guard tracking else { return }
    tracking = false
    let callback = onTracking
    DispatchQueue.main.async { callback(false) }
  }
  override func reset() { finish(); scrubbing = false; super.reset() }
}
