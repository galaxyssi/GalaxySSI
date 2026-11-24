import SwiftUI
import UIKit

struct GalaxySSIHealthActivityChart: UIViewRepresentable {
  let result: GalaxySSIHealthActivityComparison
  let kind: GalaxySSIHealthActivityKind
  let locale: Locale
  let zone: TimeZone
  let language: String
  @Binding var selectedDay: String

  func makeUIView(context: Context) -> GalaxySSIHealthActivityChartView { GalaxySSIHealthActivityChartView() }
  func updateUIView(_ view: GalaxySSIHealthActivityChartView, context: Context) {
    view.configure(result: result, kind: kind, locale: locale, zone: zone, language: language,
      selectedDay: selectedDay, onSelection: { selectedDay = $0 })
  }
}

final class GalaxySSIHealthActivityChartView: UIView, UIGestureRecognizerDelegate {
  private var result: GalaxySSIHealthActivityComparison?
  private var kind = GalaxySSIHealthActivityKind.steps
  private var locale = Locale.current, zone = TimeZone.current
  private var language = "en", selectedDay = ""
  private var onSelection: (String) -> Void = { _ in }
  private var area = CGRect.zero, dates: [String] = [], values: [String] = []
  private var recorded: [Int] { result?.pairs.indices.filter { result?.pairs[$0].current != nil } ?? [] }
  private var selectedIndex: Int? { recorded.first { key($0) == selectedDay } }
  private var maximum: Double = 3, interval: Double = 1
  private var down: CGPoint?, dragged = false
  private var outsideTap: UITapGestureRecognizer?
  private var axisFont: UIFont { UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: 11)) }
  private var tipFont: UIFont { UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12)) }
  private let accent = GalaxySSIHealthTheme.accentUIColor

  override init(frame: CGRect) {
    super.init(frame: frame)
    isOpaque = false; isAccessibilityElement = true; isMultipleTouchEnabled = true; contentMode = .redraw
    accessibilityIdentifier = "health-activity-chart"
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection); setNeedsDisplay()
  }

  func configure(result: GalaxySSIHealthActivityComparison, kind: GalaxySSIHealthActivityKind,
                 locale: Locale, zone: TimeZone, language: String, selectedDay: String,
                 onSelection: @escaping (String) -> Void) {
    self.result = result; self.kind = kind; self.locale = locale; self.zone = zone
    self.language = language; self.selectedDay = selectedDay; self.onSelection = onSelection
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
    accessibilityTraits = recorded.isEmpty ? .staticText : [.button, .adjustable]
    updateDescription(); setNeedsDisplay()
  }
  private func key(_ index: Int) -> String {
    guard let result, result.pairs.indices.contains(index) else { return "" }
    return GalaxySSIHealthActivityComparison.dayKey(result.pairs[index].day, zone: zone)
  }
  private func point(_ index: Int) -> CGPoint {
    guard let pairs = result?.pairs else { return .zero }
    let x = pairs.count == 1 ? area.midX : area.minX + area.width * CGFloat(index) / CGFloat(pairs.count - 1)
    return CGPoint(x: x, y: area.maxY - area.height * CGFloat(Double(pairs[index].current ?? 0) / maximum))
  }
  private func label(_ index: Int) -> String {
    guard let value = result?.pairs[index].current else { return "" }
    let number = kind == .steps ? value.formatted(.number.locale(locale)) :
      (Double(value) / 60_000).formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    let unit = GalaxySSILocalization.string("galaxyssi.health.activity_comparison." + (kind == .steps ? "steps_unit" : "minutes"),
      fallback: kind == .steps ? "steps" : "min", language: language)
    func localizedFormat(_ locale: String, fallback: String) -> String {
      guard let path = Bundle.main.path(forResource: locale, ofType: "lproj"), let bundle = Bundle(path: path) else { return fallback }
      return bundle.localizedString(forKey: "health_activity_point_value", value: fallback, table: "HealthActivitySelection")
    }
    let english = localizedFormat("en", fallback: "%1$@ \u{00b7} %2$@")
    let template = localizedFormat(LanguagePolicySettings.resolveInterface(language) == LanguagePolicySettings.zhCN ? "zh-Hans" : "en", fallback: english)
    return String(format: template, dates[index], number + " " + unit)
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
      context.setFillColor(accent.cgColor); context.fillEllipse(in: CGRect(x: p.x - 5.5, y: p.y - 5.5, width: 11, height: 11))
      context.setFillColor(UIColor.systemBackground.cgColor); context.fillEllipse(in: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9))
      context.setFillColor(accent.cgColor); context.fillEllipse(in: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5))
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
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    if touches.count == 1 { down = touches.first?.location(in: self); dragged = false } else { dragged = true }
  }
  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let down, let p = touches.first?.location(in: self) else { return }
    if hypot(p.x - down.x, p.y - down.y) > 10 { dragged = true }
  }
  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    defer { down = nil }
    guard !dragged, let down, let p = touches.first?.location(in: self), hypot(p.x - down.x, p.y - down.y) <= 10 else { return }
    func distance(_ index: Int) -> CGFloat { let q = point(index); return hypot(q.x - p.x, q.y - p.y) }
    let hit = recorded.min { distance($0) < distance($1) }.flatMap { !area.isEmpty && distance($0) <= 22 ? $0 : nil }
    select(hit)
    if hit != nil { becomeFirstResponder() }
  }
  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { down = nil; dragged = true }
  override func accessibilityActivate() -> Bool { guard let last = recorded.last else { return false }; if selectedIndex == nil { select(last) }; return true }
  override func accessibilityIncrement() { moveSelection(forward: true) }
  override func accessibilityDecrement() { moveSelection(forward: false) }
  private func moveSelection(forward: Bool) {
    let current = selectedIndex
    let next = forward ? recorded.first { current == nil || $0 > current! } : recorded.last { current == nil || $0 < current! }
    if let next { select(next); UIAccessibility.post(notification: .announcement, argument: label(next)) }
  }
  override var canBecomeFirstResponder: Bool { !recorded.isEmpty }
  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if presses.contains(where: { $0.key?.keyCode == .keyboardRightArrow }) { moveSelection(forward: true); return }
    if presses.contains(where: { $0.key?.keyCode == .keyboardLeftArrow }) { moveSelection(forward: false); return }
    super.pressesBegan(presses, with: event)
  }
  // Observe outside taps without swallowing List controls or vertical scrolling.
  override func willMove(toWindow newWindow: UIWindow?) {
    if let outsideTap { outsideTap.view?.removeGestureRecognizer(outsideTap) }
    outsideTap = nil
    super.willMove(toWindow: newWindow)
    if let newWindow {
      let tap = UITapGestureRecognizer(target: self, action: #selector(clearFromOutside))
      tap.cancelsTouchesInView = false; tap.delegate = self; newWindow.addGestureRecognizer(tap); outsideTap = tap
    }
  }
  @objc private func clearFromOutside() { select(nil) }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    !isHidden && !bounds.contains(touch.location(in: self)) && selectedIndex != nil
  }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
