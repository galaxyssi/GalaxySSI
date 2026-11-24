import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func nailLabels() {
    nailCallout("nail_story_label_fold", 75, 99, 91, 118, 124, 145)
    nailCallout("nail_story_label_plate", 179, 76, 179, 95, 181, 154)
    nailCallout("nail_story_label_bed", 237, 116, 237, 133, 245, 170)
    nailCallout("nail_story_label_edge", 302, 99, 302, 119, 301, 168)
    nailCallout("nail_story_label_matrix", 58, 316, 43, 248, 101, 197)
  }
  private func nailCallout(_ key: String, _ x: Double, _ y: Double, _ elbowX: Double, _ elbowY: Double, _ anchorX: Double, _ anchorY: Double) {
    let start = y + (elbowY < y ? -15 : 5)
    line(x, start, elbowX, elbowY, 0x655F6B, 1.15)
    line(elbowX, elbowY, anchorX, anchorY, 0x655F6B, 1.15)
    disc(anchorX, anchorY, 2, 0x655F6B, border: Self.cream)
    label(key, x, y, 118)
  }
}
