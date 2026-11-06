import SwiftUI
import UIKit

enum GalaxySSIChatMessageInitialPosition: Equatable {
  case first
  case last
}

enum GalaxySSIChatMessageViewportPolicy {
  static func initialPosition(
    systemNotifications: Bool,
    contentHeight: CGFloat,
    viewportHeight: CGFloat
  ) -> GalaxySSIChatMessageInitialPosition {
    systemNotifications || (contentHeight > 0 && contentHeight <= viewportHeight) ? .first : .last
  }

  static func followsLatest(systemNotifications: Bool, nearLatest: Bool) -> Bool {
    !systemNotifications && nearLatest
  }

  static func firstVisible(_ frames: [UUID: CGRect], height: CGFloat) -> (UUID, CGFloat)? {
    frames.filter { $0.value.maxY > 0 && $0.value.minY < height }
      .min { $0.value.minY < $1.value.minY }.map { ($0.key, $0.value.minY) }
  }
}

struct GalaxySSIChatViewportEpoch {
  private(set) var revision = UUID()

  mutating func invalidate() { revision = UUID() }
  func accepts(_ ticket: UUID) -> Bool { revision == ticket }
}

struct GalaxySSIChatViewportAnchor {
  let cursor: GalaxySSIChatHistoryCursor
  let top: CGFloat
}

struct GalaxySSIChatMessageFramesKey: PreferenceKey {
  static var defaultValue: [UUID: CGRect] = [:]
  static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
    value.merge(nextValue()) { _, new in new }
  }
}

final class GalaxySSIChatScrollReference {
  weak var view: UIScrollView?

  @MainActor
  func adjustTop(by distance: CGFloat) {
    guard let view, distance.isFinite else { return }
    view.layoutIfNeeded()
    let minY = -view.adjustedContentInset.top
    let maxY = max(minY, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
    let offset = min(max(view.contentOffset.y + distance, minY), maxY)
    view.setContentOffset(CGPoint(x: view.contentOffset.x, y: offset), animated: false)
  }
}

struct GalaxySSIChatScrollResolver: UIViewRepresentable {
  let reference: GalaxySSIChatScrollReference

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.isUserInteractionEnabled = false
    return view
  }

  func updateUIView(_ view: UIView, context: Context) {
    DispatchQueue.main.async { [weak view] in
      var ancestor = view?.superview
      while let current = ancestor {
        if let scroll = current as? UIScrollView { reference.view = scroll; return }
        ancestor = current.superview
      }
    }
  }
}

struct GalaxySSIChatMessageContentHeightKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}
