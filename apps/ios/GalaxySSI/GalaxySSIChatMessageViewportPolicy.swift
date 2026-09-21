import SwiftUI

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
}

struct GalaxySSIChatMessageContentHeightKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}
