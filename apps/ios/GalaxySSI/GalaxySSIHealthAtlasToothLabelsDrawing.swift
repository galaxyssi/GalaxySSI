import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func toothCallout(_ key: String, _ x: Double, _ y: Double, _ width: Double,
    _ elbowX: Double, _ elbowY: Double, _ targetX: Double, _ targetY: Double) {
    line(elbowX, elbowY, targetX, targetY, 0x52676A, 1)
    disc(targetX, targetY, 1.6, 0x52676A)
    label(key, x, y, width)
  }
}
