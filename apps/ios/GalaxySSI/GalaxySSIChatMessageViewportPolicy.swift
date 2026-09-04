import Foundation

enum GalaxySSIChatMessageInitialPosition: Equatable {
  case first
  case last
}

enum GalaxySSIChatMessageViewportPolicy {
  static func initialPosition(systemNotifications: Bool) -> GalaxySSIChatMessageInitialPosition {
    systemNotifications ? .first : .last
  }

  static func followsLatest(systemNotifications: Bool) -> Bool {
    !systemNotifications
  }
}
