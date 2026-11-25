import Foundation
import CoreGraphics

struct GalaxySSIHealthAtlasVertebralMotion {
  let bend: Double
  let angle: Double
  let glide: Double
  init(step: Int, phase: Double) {
    let t = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(phase)
    let eased = t * t * (3 - 2 * t)
    bend = step == 1 ? eased : step == 2 ? 1 - 2 * eased : 0
    angle = bend >= 0 ? -6.5 * bend : -3 * bend
    glide = bend >= 0 ? -4 * bend : -2.2 * bend
  }
  func point(_ x: Double, _ y: Double) -> CGPoint {
    let radians = angle * .pi / 180, dx = x - 119, dy = y - 151
    return CGPoint(x: 119 + cos(radians) * dx - sin(radians) * dy + glide,
      y: 151 + sin(radians) * dx + cos(radians) * dy)
  }
  var left: CGPoint { point(73, 139) }
  var right: CGPoint { point(166, 139) }
  var facet: CGPoint {
    let p = point(232, 152)
    return CGPoint(x: (p.x + 232) / 2, y: (p.y + 161) / 2)
  }
}
