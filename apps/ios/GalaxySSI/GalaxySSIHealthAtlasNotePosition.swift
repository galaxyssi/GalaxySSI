import Foundation

// UIKit layout/zoom callbacks coalesce into one post-layout SwiftUI update.
final class GalaxySSIHealthAtlasNotePosition {
  private var next: CGPoint?
  private var sent: CGPoint?
  private var scheduled = false
  private var identity: String?
  func report(_ point: CGPoint, identity: String, deliver: @escaping (CGPoint) -> Void) {
    guard point.x.isFinite, point.y.isFinite else { return }
    if self.identity != identity { self.identity = identity; sent = nil }
    next = point
    guard !scheduled else { return }
    scheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.scheduled = false
      guard let point = self.next else { return }
      if let sent = self.sent, abs(sent.x - point.x) < 0.5, abs(sent.y - point.y) < 0.5 { return }
      self.sent = point
      deliver(point)
    }
  }
}
