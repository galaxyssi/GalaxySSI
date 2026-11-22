import SwiftUI
import UIKit

enum GalaxySSIAgentChatShortcutLayout {
  enum Action: String, CaseIterable, Identifiable {
    case feed, newSession = "new", chats, photo, files, health, scan
    var id: String { rawValue }
  }
  static let initialActionCount = 5

  static func height(fontSize: CGFloat, minimumTouch: CGFloat) -> CGFloat {
    max(48, max(minimumTouch, ceil(fontSize * 1.4) + 16))
  }
  @MainActor
  static func naturalWidth(title: String, fontSize: CGFloat, showsUnread: Bool) -> CGFloat {
    let text = (title as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: fontSize)]).width
    return ceil(text) + max(17, fontSize + 1) + 4 + 8 + (showsUnread ? 6 : 0)
  }

  static func widths(available: CGFloat, natural: [CGFloat], minimumTouch: CGFloat) -> [CGFloat] {
    let viewport = available.isFinite ? max(0, available) : 0
    let minimum = minimumTouch.isFinite ? max(48, minimumTouch) : 48
    let base = natural.map { $0.isFinite ? max(minimum, ceil($0)) : minimum }
    let count = min(initialActionCount, base.count)
    guard count > 0 else { return [] }
    let extra = max(0, viewport - base.prefix(count).reduce(0, +)) / CGFloat(count)
    return base.enumerated().map { index, value in
      index < count ? value + extra : max(value, viewport / CGFloat(initialActionCount))
    }
  }

  static func startOffset(content: CGFloat, viewport: CGFloat, left: CGFloat, right: CGFloat, rtl: Bool) -> CGFloat {
    guard [content, viewport, left, right].allSatisfy(\.isFinite) else { return 0 }
    let start = -left
    return rtl ? max(start, content - max(0, viewport) + right) : start
  }
}

@MainActor
final class GalaxySSIAgentShortcutScrollReference: ObservableObject {
  private weak var view: UIScrollView?
  private var rtl = false

  func bind(_ scroll: UIScrollView, rtl: Bool) {
    guard view !== scroll || self.rtl != rtl else { return }
    view = scroll; self.rtl = rtl
    reset()
  }
  func activate(_ action: () -> Void) {
    reset()
    action()
  }
  private func reset() {
    guard let view else { return }
    view.layoutIfNeeded()
    let inset = view.adjustedContentInset
    let x = GalaxySSIAgentChatShortcutLayout.startOffset(content: view.contentSize.width,
      viewport: view.bounds.width, left: inset.left, right: inset.right, rtl: rtl)
    view.setContentOffset(CGPoint(x: x, y: view.contentOffset.y), animated: false)
  }
}

struct GalaxySSIAgentShortcutScrollResolver: UIViewRepresentable {
  let reference: GalaxySSIAgentShortcutScrollReference
  let rtl: Bool
  func makeUIView(context: Context) -> UIView {
    let view = UIView(); view.isUserInteractionEnabled = false; return view
  }
  func updateUIView(_ view: UIView, context: Context) {
    DispatchQueue.main.async { [weak view] in
      var ancestor = view?.superview
      while let current = ancestor {
        if let scroll = current as? UIScrollView { reference.bind(scroll, rtl: rtl); return }
        ancestor = current.superview
      }
    }
  }
}
