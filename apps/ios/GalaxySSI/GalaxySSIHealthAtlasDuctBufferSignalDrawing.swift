import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ductBufferSignal(_ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasDuctBufferGeometry
    typealias Motion = GalaxySSIHealthAtlasDuctBufferMotion
    typealias Routes = GalaxySSIHealthAtlasDuctBufferRoutes
    ductBufferFilled(Geometry.mucosa, 0xF2C8BB, 0x975E64)
    for i in 0...13 {
      let x = 36 + Double(i) * 20
      if i != 9 {
        rounded(x, 148, x + 18, 174, 5, 0xF9DCC8)
        oval(x + 5, 162, x + 13, 171, fill: 0xC18D9D, border: 0x975E64)
      }
    }
    ductBufferFilled(Geometry.sCell, 0xDCBBD8, 0x694B82)
    disc(219, 171, 3.8, 0x694B82)
    stroke(Geometry.bloodCourse, 0x975E64, 16); stroke(Geometry.bloodCourse, 0xF1C4BF, 12)
    rounded(49, 300, 175, 320, 7, 0xD8EEE8)
    for i in 0...3 { ductBufferCell(49 + Double(i) * 32, 271, 32, 31, active: i == 2) }
    line(51, 302, 174, 302, 0x547C7B, 1.5)
    let arrival = Motion.acidArrival(t)
    for i in 0...3 {
      at(Routes.acidTrack.route, 0.27 + arrival * 0.73 - 0.085 * Double(i)) { x, y in ductBufferAcidMark(x, y - Double(i % 2) * 6, 1) }
    }
    let signal = Motion.secretin(t)
    for i in 0...3 {
      let f = signal - Double(i) * 0.12
      if f > 0 { at(Routes.signalTrack.route, f) { x, y in disc(x, y, 3.3, 0x694B82, border: Self.cream) } }
    }
  }
}
