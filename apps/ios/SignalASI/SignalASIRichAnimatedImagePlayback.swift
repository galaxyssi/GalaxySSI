import UIKit

final class SignalASIRichAnimatedImagePlaybackCoordinator {
  static let shared = SignalASIRichAnimatedImagePlaybackCoordinator()

  private weak var activeImageView: UIImageView?

  private init() {}

  func activate(_ imageView: UIImageView) {
    guard imageView.animationImages?.isEmpty == false else { return }
    if activeImageView !== imageView {
      activeImageView?.stopAnimating()
    }
    activeImageView = imageView
    imageView.startAnimating()
  }

  func deactivate(_ imageView: UIImageView) {
    imageView.stopAnimating()
    if activeImageView === imageView {
      activeImageView = nil
    }
  }
}

final class SignalASIRichAnimatedImageView: UIImageView {
  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      SignalASIRichAnimatedImagePlaybackCoordinator.shared.deactivate(self)
    } else if animationImages?.isEmpty == false {
      SignalASIRichAnimatedImagePlaybackCoordinator.shared.activate(self)
    }
  }
}
