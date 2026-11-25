import SwiftUI
import UIKit

@MainActor
final class GalaxySSIHealthAtlasScrollMemory: ObservableObject {
  private(set) var offset: Double = 0
  private(set) var requestedOffset: Double?
  @Published private(set) var revision = UUID()
  func capture(_ value: Double) { offset = GalaxySSIHealthAtlasState.safeScroll(value) }
  func restore(_ value: Double) {
    requestedOffset = GalaxySSIHealthAtlasState.safeScroll(value)
    revision = UUID()
  }
}

// Observe the containing SwiftUI scroll view without replacing its delegate or
// entering a diagram's nested zoom view. Restore after content layout, in iOS 15.
@MainActor
struct GalaxySSIHealthAtlasScrollAnchor: UIViewRepresentable {
  let memory: GalaxySSIHealthAtlasScrollMemory
  let revision: UUID
  func makeCoordinator() -> Coordinator { Coordinator(memory: memory) }
  func makeUIView(context: Context) -> Anchor {
    let view = Anchor()
    view.isUserInteractionEnabled = false
    view.accessibilityElementsHidden = true
    view.updated = { [weak coordinator = context.coordinator, weak view] in
      if let view { coordinator?.attach(view) }
    }
    return view
  }
  func updateUIView(_ view: Anchor, context: Context) {
    context.coordinator.request(revision)
    context.coordinator.attach(view)
  }
  static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) {
    view.updated = nil; coordinator.detach()
  }
  final class Anchor: UIView {
    var updated: (() -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); updated?() }
    override func didMoveToSuperview() { super.didMoveToSuperview(); updated?() }
    override func layoutSubviews() { super.layoutSubviews(); updated?() }
  }
  @MainActor final class Coordinator {
    let memory: GalaxySSIHealthAtlasScrollMemory
    private weak var scroll: UIScrollView?
    private var observations: [NSKeyValueObservation] = []
    private var revision: UUID?
    private var pending: Double?
    private var applying = false
    init(memory: GalaxySSIHealthAtlasScrollMemory) { self.memory = memory }
    func request(_ revision: UUID) {
      guard self.revision != revision else { return }
      self.revision = revision
      pending = memory.requestedOffset
    }
    func attach(_ view: UIView) {
      var ancestor = view.superview
      while let current = ancestor, !(current is UIScrollView) { ancestor = current.superview }
      guard let containing = ancestor as? UIScrollView else { return }
      if scroll !== containing {
        detach(); scroll = containing
        observations = [
          containing.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.changed() }
          },
          containing.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.changed() }
          }
        ]
      }
      // SwiftUI may still be laying out the parent when this background attaches.
      DispatchQueue.main.async { [weak self] in self?.changed() }
    }
    func changed() {
      guard !applying, let scroll, scroll.window != nil else { return }
      if scroll.isDragging || scroll.isDecelerating { pending = nil }
      let top = scroll.adjustedContentInset.top
      if let pending, scroll.bounds.height > 0 {
        let maximum = max(0, scroll.contentSize.height + top + scroll.adjustedContentInset.bottom - scroll.bounds.height)
        let target = min(CGFloat(pending), maximum) - top
        if abs(scroll.contentOffset.y - target) > 0.5 {
          applying = true
          scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: target), animated: false)
          applying = false
        }
        // Keep the request until asynchronous diagrams have enough height. A new
        // user drag always cancels it, including an unreachable old orientation.
        if maximum >= CGFloat(pending) { self.pending = nil }
      }
      memory.capture(Double(scroll.contentOffset.y + top))
    }
    func detach() { observations.forEach { $0.invalidate() }; observations = []; scroll = nil }
  }
}
