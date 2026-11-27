import SwiftUI
import UIKit

@MainActor
struct GalaxySSIReadingParagraphAnchor: UIViewRepresentable {
  let scope: String
  let holding: () -> Bool
  func makeUIView(context: Context) -> Probe { Probe() }
  func updateUIView(_ view: Probe, context: Context) {
    if view.scope != scope { view.reset(); view.scope = scope }
    view.holding = holding
    view.start()
  }
  static func dismantleUIView(_ view: Probe, coordinator: ()) { view.stop(); view.holding = nil }

  struct RowMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
      let view = UIView(); view.isUserInteractionEnabled = false
      view.accessibilityIdentifier = "ios.reading.row-marker"
      return view
    }
    func updateUIView(_ view: UIView, context: Context) {}
  }

  final class Probe: UIView {
    var scope = ""
    var holding: (() -> Bool)?
    private var link: CADisplayLink?
    private weak var target: UIView?
    private weak var previousScroll: UIScrollView?
    private var top: CGFloat = 0
    private var previousOffset: CGFloat = 0
    override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false }
    required init?(coder: NSCoder) { return nil }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { stop() } else { start() } }
    func reset() { target = nil; previousScroll = nil }
    func start() {
      guard window != nil, holding?() == true, link == nil else { return }
      let value = CADisplayLink(target: self, selector: #selector(sample))
      value.preferredFramesPerSecond = 30
      value.add(to: .main, forMode: .common)
      link = value
    }
    func stop() { link?.invalidate(); link = nil; reset() }
    private func scrollView() -> UIScrollView? {
      var current = superview
      while let view = current {
        if let scroll = view as? UIScrollView { return scroll }
        current = view.superview
      }
      return nil
    }
    private func belongs(_ view: UIView, scroll: UIScrollView) -> Bool {
      guard view.window === window, !view.isHidden, view.alpha > 0.01, view.bounds.height > 0 else { return false }
      var parent: UIView? = view
      while let current = parent, current !== scroll {
        guard !current.isHidden, current.alpha > 0.01 else { return false }
        parent = current.superview
      }
      return parent === scroll
    }
    private func visible(_ view: UIView, scroll: UIScrollView) -> Bool {
      belongs(view, scroll: scroll) && view.convert(view.bounds, to: scroll).intersects(scroll.bounds)
    }
    @objc private func sample() {
      guard holding?() == true else { stop(); return }
      guard let window, window.isKeyWindow, window.windowScene?.activationState == .foregroundActive,
            let scroll = scrollView(), !scroll.isTracking, !scroll.isDragging, !scroll.isDecelerating else { reset(); return }
      if let target, previousScroll === scroll, belongs(target, scroll: scroll) {
        // A user/programmatic scroll wins over a retained layout anchor.
        guard abs(scroll.contentOffset.y - previousOffset) < 1 else { reset(); return }
        let next = target.convert(.zero, to: scroll).y - scroll.bounds.minY
        let delta = next - top
        if delta.isFinite, abs(delta) >= 0.5 {
          let minY = -scroll.adjustedContentInset.top
          let maxY = max(minY, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
          let y = min(maxY, max(minY, scroll.contentOffset.y + delta))
          scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: false)
        }
        if visible(target, scroll: scroll) {
          top = target.convert(.zero, to: scroll).y - scroll.bounds.minY
          previousOffset = scroll.contentOffset.y
          return
        }
      }
      reset()
      var queue = scroll.subviews
      var checked = 0
      var paragraphs: [UIView] = []
      var rows: [UIView] = []
      while !queue.isEmpty && checked < 2_048 {
        let view = queue.removeFirst(); checked += 1
        guard !view.isHidden, view.alpha > 0.01 else { continue }
        if view is AgentReplyParagraphTextView, visible(view, scroll: scroll) {
          paragraphs.append(view)
        } else if view.accessibilityIdentifier == "ios.reading.row-marker", visible(view, scroll: scroll) {
          rows.append(view)
        }
        // Do not descend into web views, editable controls or nested scroll containers.
        if view is UIScrollView { continue }
        queue.append(contentsOf: view.subviews)
      }
      if let view = (paragraphs.isEmpty ? rows : paragraphs).min(by: {
        $0.convert(.zero, to: scroll).y < $1.convert(.zero, to: scroll).y
      }) {
        target = view; previousScroll = scroll
        top = view.convert(.zero, to: scroll).y - scroll.bounds.minY
        previousOffset = scroll.contentOffset.y
      }
    }
  }
}
