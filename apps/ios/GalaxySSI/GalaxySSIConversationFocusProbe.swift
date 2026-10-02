import SwiftUI
import UIKit

struct GalaxySSIConversationFocusProbe: UIViewRepresentable {
  @Binding var focused: Bool

  func makeUIView(context: Context) -> FocusView { FocusView() }

  func updateUIView(_ view: FocusView, context: Context) {
    view.changed = { value in
      if focused != value { focused = value }
    }
    view.refresh()
  }

  final class FocusView: UIView {
    var changed: ((Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []

    override init(frame: CGRect) {
      super.init(frame: frame)
      for name in [UIWindow.didBecomeKeyNotification, UIWindow.didResignKeyNotification,
                   UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification] {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          self?.refresh()
        })
      }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() { super.didMoveToWindow(); refresh() }
    override func layoutSubviews() { super.layoutSubviews(); refresh() }

    func refresh() {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        var responder: UIResponder? = self
        var covered = false
        while let current = responder {
          if let controller = current as? UIViewController, controller.presentedViewController != nil {
            covered = true
          }
          responder = current.next
        }
        self.changed?(self.window?.isKeyWindow == true &&
          self.window?.windowScene?.activationState == .foregroundActive && !covered)
      }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
  }
}
