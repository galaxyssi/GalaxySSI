import Foundation

enum AgentTranscriptScrollPolicy {
  static func nextAutoFollow(
    current: Bool,
    userScrollActive: Bool,
    itemCount: Int,
    lastVisiblePosition: Int,
    remainingPx: Int,
    thresholdPx: Int
  ) -> Bool {
    if !userScrollActive {
      return current
    }
    return itemCount == 0 ||
      (lastVisiblePosition == itemCount - 1 && remainingPx <= thresholdPx)
  }

  static func shouldLoadOlderFromScroll(
    dy: Int,
    firstVisiblePosition: Int,
    hydrationPending: Bool
  ) -> Bool {
    dy < 0 &&
      !hydrationPending &&
      firstVisiblePosition <= 1
  }

  static func shouldLoadOlderFromPull(
    downY: Double,
    currentY: Double,
    canScrollUp: Bool,
    hydrationPending: Bool,
    thresholdPx: Int
  ) -> Bool {
    !hydrationPending &&
      !canScrollUp &&
      currentY - downY >= Double(thresholdPx)
  }
}
