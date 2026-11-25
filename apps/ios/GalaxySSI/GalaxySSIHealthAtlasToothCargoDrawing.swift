import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func toothArea(_ path: Path, _ fill: UInt32, _ edge: UInt32, _ weight: Double) {
    self.fill(path, fill); stroke(path, edge, weight)
  }
  func toothFoodCrumb(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ angle: Double) {
    var local = context
    local.translateBy(x: x, y: y); local.rotate(by: .degrees(angle)); local.scaleBy(x: w, y: h)
    let art = copy(local)
    art.toothArea(GalaxySSIHealthAtlasToothGeometry.crumb, 0xC98547, 0x854C2E, 0.13)
    art.line(-0.4, -0.27, 0.38, -0.28, 0xF2BF78, 0.15)
  }
  func toothBitePiece(_ piece: Path, _ dx: Double, _ dy: Double, _ from: Double, _ to: Double) {
    var local = context; local.translateBy(x: dx, y: dy)
    let art = copy(local)
    art.toothArea(piece, 0xC98547, 0x854C2E, 1.3)
    art.line(from, -2, to, -2, 0xF2BF78, 1.2)
  }
}
