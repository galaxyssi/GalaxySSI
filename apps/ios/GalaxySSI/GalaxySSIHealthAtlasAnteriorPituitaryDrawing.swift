import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func anteriorPituitary(_ x: Double, _ y: Double, _ scale: Double, _ highlight: UInt32) {
    var local = context; local.translateBy(x: x, y: y); local.scaleBy(x: scale, y: scale)
    let art = copy(local)
    art.fill(GalaxySSIHealthAtlasAnteriorPituitaryGeometry.neuralLobe, 0xCBBECD)
    art.stroke(GalaxySSIHealthAtlasAnteriorPituitaryGeometry.neuralLobe, 0x887989, 1.6)
    art.fill(GalaxySSIHealthAtlasAnteriorPituitaryGeometry.adenohypophysis, 0xEFBDAD)
    art.stroke(GalaxySSIHealthAtlasAnteriorPituitaryGeometry.adenohypophysis, 0x9A626A, 1.6)
    for i in 0...2 {
      art.oval(11 + Double(i) * 11, 35 - 2 * Double(i), 18 + Double(i) * 11, 43 - 2 * Double(i), fill: 0xD88E8F, border: 0xB3767E)
      art.disc(21 + Double(i) * 10, 49 - 2 * Double(i), 2.3, 0xB3767E)
    }
    art.disc(44, 31, 6, highlight, border: 0xFFFCF3)
  }
  func pituitaryVessel(_ path: Path, _ width: Double = 18) { stroke(path, 0xB17A86, width + 3); stroke(path, 0xF6D9DC, width) }
  func pituitaryMarker(_ route: GalaxySSIHealthAtlasSectionLesson.Route, _ fraction: Double, _ tint: UInt32,
    radius: Double = 3.6, angular: Bool = false) {
    guard fraction.isFinite, (0...1).contains(fraction) else { return }
    at(route, fraction) { x, y in
      if angular {
        var local = context; local.translateBy(x: x, y: y); local.rotate(by: .degrees(45))
        let r = radius * 0.8; copy(local).fill(Path(CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)), tint)
      } else { disc(x, y, radius, tint) }
    }
  }
  func pituitaryRing(_ x: Double, _ y: Double, _ r: Double, _ tint: UInt32, opacity: Double, width: Double) {
    var local = context; local.opacity = Double(Int(255 * min(1, max(0, opacity)))) / 255
    copy(local).stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), tint, width)
  }
  static func pituitarySmooth(_ t: Double) -> Double { let p = min(1, max(0, t)); return p * p * (3 - 2 * p) }
}
