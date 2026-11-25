import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func uterocervicalVagina(_ t: Double) {
    let g = GalaxySSIHealthAtlasUterocervicalVaginalGeometry.self
    uterocervicalSurface(g.facingVaginalWall, 104, 270, 0xF5DAE0, 0xD8A5BD, 0x765870)
    uterocervicalSurface(g.deepVaginalWall, 148, 280, 0xEAD4DF, 0xB489A4, 0x765870)
    uterocervicalSurface(g.muscleVaginalWall, 111, 273, 0xE7A598, 0xC4808E, 0xA5636D)
    stroke(g.vaginalMuscleFibers, 0xAA6878, 1.2)
    let depth = GalaxySSIHealthAtlasUterocervicalMotion.foldDepth(t)
    let lining = Path { p in
      p.move(to: CGPoint(x: 233, y: 106))
      for i in 0...4 {
        let index = Double(i), y = 108 + 22 * index, x = 232 - 4.4 * index + 1.12 * index * index
        p.addCurve(to: CGPoint(x: x + 15 * depth, y: y + 11), control1: CGPoint(x: x - 5, y: y + 4), control2: CGPoint(x: x - 3 + 15 * depth, y: y + 7))
        p.addCurve(to: CGPoint(x: x - 2, y: y + 22), control1: CGPoint(x: x + 17 * depth, y: y + 15), control2: CGPoint(x: x - 3, y: y + 17))
      }
      p.addCurve(to: CGPoint(x: 260, y: 267), control1: CGPoint(x: 244, y: 237), control2: CGPoint(x: 252, y: 253))
      p.addQuadCurve(to: CGPoint(x: 250, y: 272), control: CGPoint(x: 256, y: 273))
      p.addCurve(to: CGPoint(x: 223, y: 103), control1: CGPoint(x: 211, y: 221), control2: CGPoint(x: 203, y: 144)); p.closeSubpath()
    }
    uterocervicalSurface(lining, 104, 270, 0xF5DAE0, 0xD8A5BD, 0x9C6881)
    line(259, 269, 273, 271, 0x24776D, 1.35)
    uterocervicalCallout("folds", 244, 81, 117, 246, 90, 229 + 15 * depth, 141)
    uterocervicalCallout("muscle", 204, 316, 84, 205, 300, 219, 232)
    uterocervicalCallout("opening", 295, 316, 94, 294, 300, 266, 270)
  }
}
