import UIKit

final class GalaxySSIRichAnimatedImagePlaybackCoordinator {
  static let shared = GalaxySSIRichAnimatedImagePlaybackCoordinator()

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

final class GalaxySSIRichAnimatedImageView: UIImageView {
  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      GalaxySSIRichAnimatedImagePlaybackCoordinator.shared.deactivate(self)
    } else if animationImages?.isEmpty == false {
      GalaxySSIRichAnimatedImagePlaybackCoordinator.shared.activate(self)
    }
  }
}
