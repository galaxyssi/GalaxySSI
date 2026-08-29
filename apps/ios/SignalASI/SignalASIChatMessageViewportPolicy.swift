import Foundation

enum SignalASIChatMessageInitialPosition: Equatable {
  case first
  case last
}

enum SignalASIChatMessageViewportPolicy {
  static func initialPosition(systemNotifications: Bool) -> SignalASIChatMessageInitialPosition {
    systemNotifications ? .first : .last
  }

  static func followsLatest(systemNotifications: Bool) -> Bool {
    !systemNotifications
  }
}
