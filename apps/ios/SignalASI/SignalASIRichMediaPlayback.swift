import Foundation

final class SignalASIRichMediaPlaybackCoordinator {
  static let shared = SignalASIRichMediaPlaybackCoordinator()

  private weak var activeOwner: AnyObject?
  private var activePause: (() -> Void)?

  private init() {}

  func activate(owner: AnyObject, pause: @escaping () -> Void) {
    if let activeOwner, activeOwner !== owner {
      activePause?()
    }
    self.activeOwner = owner
    activePause = pause
  }

  func deactivate(owner: AnyObject) {
    guard activeOwner === owner else { return }
    activeOwner = nil
    activePause = nil
  }

  func pauseForRuntimeBoundary() {
    let pause = activePause
    activeOwner = nil
    activePause = nil
    pause?()
  }
}
