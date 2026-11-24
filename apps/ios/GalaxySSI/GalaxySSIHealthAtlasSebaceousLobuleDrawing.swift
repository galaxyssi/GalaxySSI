import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func sebaceousLobule(_ step: Int, _ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasSebaceousGeometry
    typealias Motion = GalaxySSIHealthAtlasSebaceousMotion
    sebaceousFill(Geometry.lobule, 79, 288, 0xFFEAD0, 0xE2B99E, 0x99696B)
    stroke(Geometry.duct, 0x99696B, 15); stroke(Geometry.duct, 0xEED39E, 11)
    for (index, point) in Geometry.basal.enumerated() {
      if step == 1 && index == 3 { continue }
      oval(point.x - 4.8, point.y - 3.8, point.x + 4.8, point.y + 3.8, fill: 0xD7A8B6, border: 0x99696B)
      disc(point.x, point.y, 1.65, 0x9773A0)
    }
    for (index, point) in Geometry.mature.enumerated() {
      if (2...3).contains(step) && index == 9 { continue }
      sebaceousCell(point.x, point.y, 8.1 + Double(index % 3), 0.36 + Double(index % 4) * 0.14, 1)
    }
    switch step {
    case 1:
      let spread = 1.2 + 6 * t
      sebaceousCell(266 - spread, 94, 4.3, 0, 1)
      sebaceousCell(266 + spread, 96 + 7 * t, 4.3 + t, 0.18 * t, 1)
      stroke(Path(ellipseIn: CGRect(x: 251 - t * 2, y: 84, width: 31 + t * 4, height: 24 + t * 2)), Self.teal, 1.5)
    case 2:
      let focus = Motion.eased(t)
      sebaceousCell(266 + 6 * focus, 129 + 31 * focus, 7.4 + 6 * focus, focus, 1)
    case 3:
      let open = Motion.eased(t), x = 261 - 13 * open, y = 151 + 23 * open
      sebaceousCell(x, y, 13.2, 0.92, 1 - open)
      for index in 0...3 {
        at(Geometry.ductTrack, Motion.release(t, index)) { px, py in
          disc(px, py, 2.4 + Double(index % 2) * 0.7, 0xD69742, border: 0x9B651E)
        }
      }
    case 4:
      for i in 0...3 {
        at(Geometry.ductTrack, Motion.duct(t, i)) { x, y in
          disc(x, y, 3, 0xD69742, border: 0x9B651E)
        }
      }
    default: break
    }
  }
}
