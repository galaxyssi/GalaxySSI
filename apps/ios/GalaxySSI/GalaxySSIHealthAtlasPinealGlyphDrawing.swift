import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func pinealBrain(_ x: Double, _ y: Double, _ size: Double) {
    var c = context; c.translateBy(x: x, y: y); c.scaleBy(x: size, y: size)
    c.draw(Image("HealthAtlasFunctionPineal"), in: CGRect(x: 0, y: 0, width: 360, height: 280))
  }
  func pinealSun(_ x: Double, _ y: Double, _ r: Double) {
    disc(x, y, r, 0xF0D499, border: 0xA6783D)
    for i in 0...7 {
      var c = context; c.translateBy(x: x, y: y); c.rotate(by: .degrees(45*Double(i)))
      copy(c).line(0, -r-3.3, 0, -r-6.7, 0xA6783D, 1.3)
    }
  }
  func pinealCrescent(_ x: Double, _ y: Double, _ r: Double, _ sky: UInt32) {
    disc(x, y, r, 0x8293B5); disc(x+r*0.51, y-r*0.39, r*0.86, sky)
  }
  func pinealMolecule(_ x: Double, _ y: Double, _ form: Int, _ active: Bool) {
    let color: UInt32 = form == 0 ? 0xA56A35 : form == 1 ? 0x317C79 : 0x73518E
    let tone: UInt32 = active ? color : 0xE1ECEB
    switch form {
    case 0: disc(x, y, 5.4, tone, border: color)
    case 1: oval(x-6.1, y-4.5, x+6.1, y+4.5, fill: tone, border: color)
    default:
      var c = context; c.translateBy(x: x, y: y); c.rotate(by: .degrees(45))
      let art = copy(c), p = Path(roundedRect: CGRect(x: -4.1, y: -4.1, width: 8.2, height: 8.2), cornerRadius: 1.5)
      art.fill(p, tone); art.stroke(p, color, 1.05)
    }
  }
  func pinealSegment(_ track: GalaxySSIHealthAtlasPinealRoutes.Track, _ fraction: Double, _ color: UInt32, _ width: Double) {
    if fraction > 0 { stroke(track.path.trimmedPath(from: 0, to: fraction), color, width) }
  }
  func pinealDirection(_ track: GalaxySSIHealthAtlasPinealRoutes.Track, _ color: UInt32) {
    guard track.length > 0 else { return }
    at(track.route, 0.63) { x, y in
      at(track.route, min(0.94, 0.63+8/track.length)) { nx, ny in arrow(x, y, nx, ny, color) }
    }
  }
}
