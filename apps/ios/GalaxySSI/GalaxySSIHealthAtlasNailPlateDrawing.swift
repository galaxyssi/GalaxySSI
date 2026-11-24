import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func nailPlate(_ plate: Path, tip: Double) {
    typealias Motion = GalaxySSIHealthAtlasNailMotion
    gradient(plate, 151, 189, 0xFDF5E5, 0xD9BEC8)
    var clipped = context; clipped.clip(to: plate)
    let art = copy(clipped)
    art.nailBand(Motion.bedEnd, tip, Motion.thickness / 2, Motion.thickness + 2, 0xF5E9DA)
    art.nailBand(Motion.rootX, tip, 3, 1.2, 0xFFFBF0)
    art.nailBand(Motion.rootX, tip, 7, 1, 0xCBB2B3)
    stroke(plate, 0x725D70, 1.7)
  }
  func nailOrientation(_ t: Double, plate: Path) {
    let x = 142 + 143 * GalaxySSIHealthAtlasNailMotion.ease(t)
    var clipped = context; clipped.clip(to: plate)
    copy(clipped).nailBand(x - 13, x + 13, 2, 6, 0xA4C6BB)
  }
  func nailLandmarks(_ slide: Double, step: Int, t: Double, plate: Path) {
    typealias Motion = GalaxySSIHealthAtlasNailMotion
    var clipped = context; clipped.clip(to: plate)
    let art = copy(clipped)
    for i in 0...2 {
      let x = 168 + 45 * Double(i) + slide
      let color: UInt32 = step == 4 && i < 2 ? 0xB4A1A1 : Self.teal
      art.line(x - 1.6, Motion.y(x) + 2.5, x + 1.6, Motion.y(x) + 8.5, color, 2.3)
    }
    if step == 3 {
      let offset = 11 * Motion.ease(t)
      arrow(251 + offset, 140, 271 + offset, 140, Self.teal)
    }
  }
  private func nailBand(_ from: Double, _ to: Double, _ offset: Double, _ width: Double, _ color: UInt32) {
    stroke(GalaxySSIHealthAtlasNailGeometry.band(from, to, offset), color, width)
  }
}
