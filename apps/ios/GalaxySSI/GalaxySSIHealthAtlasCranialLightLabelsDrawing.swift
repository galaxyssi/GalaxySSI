import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func cranialLight(_ frame: GalaxySSIHealthAtlasCranialMotion.Frame) {
    typealias Geometry = GalaxySSIHealthAtlasCranialGeometry
    stroke(Geometry.lightGuide, 0xCCAA71, 1.15)
    line(49, 52, 74, 67, 0xCCAA71, 1.2); line(66, 40, 82, 54, 0xCCAA71, 1.2)
    guard frame.step == 0 else { return }
    stroke(Geometry.lightThrough, 0xD7B789, 1.1)
    cranialSignal(Self.cranialLightIn, Geometry.lightIn, frame.t / 0.50, 0xB47C31)
    cranialSignal(Self.cranialLightThrough, Geometry.lightThrough, (frame.t - 0.48) / 0.31, 0xB47C31)
    let glow = sin(.pi * GalaxySSIHealthAtlasCranialMotion.ease(frame.t, 0.58, 1))
    if glow > 0 {
      var local = context; local.translateBy(x: 90, y: 0)
      local.opacity = Double(Int(205 * glow)) / 255
      copy(local).stroke(Geometry.retina, 0xB47C31, 2)
    }
  }
  private static let cranialLightIn = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 56, y: 44),
    commands: [.init(kind: .quad, points: [.init(x: 77, y: 54), .init(x: 90, y: 75)])])
  private static let cranialLightThrough = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 90, y: 91),
    commands: [.init(kind: .line, points: [.init(x: 90, y: 117)])])

  func cranialLabels(_ step: Int) {
    cranialCallout("cranial_reflex_story_iris", 180, 89, 94, 135, 84, 104, 81)
    cranialCallout("cranial_reflex_story_retina", 157, 118, 64, 133, 114, 106, 114)
    cranialCallout("cranial_reflex_story_optic", 180, 154, 112, 130, 150, 114, 151)
    cranialCallout("cranial_reflex_story_chiasm", 180, 172, 87, 180, 178, 180, 199)
    cranialCallout("cranial_reflex_story_ganglion", 253, 190, 107, 298, 183, 311, 153)
    cranialCallout("cranial_reflex_story_pretectum", 106, 219, 93, 121, 223, 148, 239)
    cranialCallout("cranial_reflex_story_ew", 66, 291, 118, 120, 283, 143, 277)
    cranialCallout("cranial_reflex_story_motor", 298, 274, 111, 281, 259, 284, 234)
    cranialCallout("cranial_reflex_story_midbrain", 180, 340, 105, 180, 325, 180, 307)
    if step == 4 {
      cranialCallout("cranial_reflex_story_direct", 109, 34, 124, 108, 39, 108, 53)
      cranialCallout("cranial_reflex_story_consensual", 260, 34, 144, 260, 39, 260, 53)
    }
  }
  private func cranialCallout(_ key: String, _ x: Double, _ baseline: Double, _ width: Double,
    _ startX: Double, _ startY: Double, _ targetX: Double, _ targetY: Double) {
    line(startX, startY, targetX, targetY, 0x65747E, 0.95)
    disc(targetX, targetY, 1.45, 0x65747E)
    label(key, x, baseline, width)
  }
}
