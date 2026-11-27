import SwiftUI
import UIKit

@MainActor
final class GalaxySSIHealthMetricReadingAnchor {
  private struct WeakMarker { weak var view: MarkerView? }
  private struct Pending {
    let keys: [String]
    let offset: CGFloat
    let oldY: CGFloat
    let ticket: UUID
  }
  private var markers: [String: WeakMarker] = [:]
  private var pending: Pending?
  private var expected: Set<String>?
  private var ticket = UUID()
  var allowed: (() -> Bool)?

  func clear() { ticket = UUID(); pending = nil; expected = nil }
  func capture() {
    clear()
    guard allowed?() == true, let first = markers.values.compactMap(\.view).first(where: { $0.window != nil }),
          let scroll = first.scroll(), !scroll.isTracking, !scroll.isDragging, !scroll.isDecelerating else { return }
    let rows = markers.filter { $0.key != "filter" }.compactMap { key, value -> (String, CGRect)? in
      guard let view = value.view, view.window != nil, view.scroll() === scroll else { return nil }
      return (key, view.convert(view.bounds, to: scroll))
    }.sorted { $0.1.minY < $1.1.minY }
    let y = scroll.contentOffset.y
    let top = y + scroll.adjustedContentInset.top
    guard let min = rows.first?.1.minY, let max = rows.last?.1.maxY, top >= min, top < max,
      let index = rows.firstIndex(where: { $0.1.maxY > top }) else { return }
    pending = Pending(keys: GalaxySSIReadingPosition.nearestKeys(rows.map(\.0), index: index),
      offset: rows[index].1.minY - y, oldY: y, ticket: ticket)
  }
  func restore(keys: [String]) {
    expected = Set(keys)
    let current = ticket
    DispatchQueue.main.async { [weak self] in
      guard let self, self.ticket == current else { return }
      self.restoreIfReady()
    }
  }
  fileprivate func attach(_ view: MarkerView, key: String) {
    markers[key] = WeakMarker(view: view)
  }
  fileprivate func detach(_ view: MarkerView, key: String) {
    if markers[key]?.view === view { markers.removeValue(forKey: key) }
  }
  fileprivate func restoreIfReady() {
    guard let pending, pending.ticket == ticket, let expected, allowed?() == true,
          let filter = markers["filter"]?.view, let scroll = filter.scroll(), scroll.window != nil else { return }
    guard !scroll.isTracking, !scroll.isDragging, !scroll.isDecelerating else { clear(); return }
    let minY = -scroll.adjustedContentInset.top
    let maxY = max(minY, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
    guard abs(scroll.contentOffset.y - min(maxY, max(minY, pending.oldY))) < 1 else { clear(); return }
    let key = pending.keys.first { expected.contains($0) } ?? pending.keys.compactMap { old in
      let metric = old.split(separator: ":", maxSplits: 1).first ?? ""
      return expected.sorted().first { $0.hasPrefix(String(metric) + ":") }
    }.first
    guard let view = key.flatMap({ markers[$0]?.view }) ?? (key == nil ? filter : nil), view.window != nil,
      view.scroll() === scroll, view.bounds.height > 0 else { return }
    let y = view.convert(.zero, to: scroll).y - (key == nil ? scroll.adjustedContentInset.top : pending.offset)
    clear()
    scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: min(maxY, max(minY, y))), animated: false)
  }

  struct Marker: UIViewRepresentable {
    let anchor: GalaxySSIHealthMetricReadingAnchor
    let key: String
    func makeUIView(context: Context) -> MarkerView { MarkerView() }
    func updateUIView(_ view: MarkerView, context: Context) {
      if view.key != key { view.anchor?.detach(view, key: view.key) }
      view.anchor = anchor; view.key = key
      anchor.attach(view, key: key)
    }
    static func dismantleUIView(_ view: MarkerView, coordinator: ()) {
      view.anchor?.detach(view, key: view.key); view.anchor = nil
    }
  }
  final class MarkerView: UIView {
    weak var anchor: GalaxySSIHealthMetricReadingAnchor?
    var key = ""
    override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false }
    required init?(coder: NSCoder) { return nil }
    override func layoutSubviews() {
      super.layoutSubviews()
      // Wait until the whole SwiftUI layout pass has installed the surviving markers.
      DispatchQueue.main.async { [weak self] in self?.anchor?.restoreIfReady() }
    }
    func scroll() -> UIScrollView? {
      var ancestor = superview
      while let view = ancestor {
        if let scroll = view as? UIScrollView { return scroll }
        ancestor = view.superview
      }
      return nil
    }
  }
}
