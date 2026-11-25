import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  private static let ghSignal: UInt32 = 0x307A71, igfSignal: UInt32 = 0x765291
  func somatotrophSignal(_ step: Int, _ t: Double) {
    typealias G = GalaxySSIHealthAtlasSomatotrophGeometry
    switch step {
    case 0:
      pituitaryVessel(G.capillary, 21); gradient(G.cell, 95, 222, 0xFFEDDB, 0xE6B0A6); stroke(G.cell, 0xA36570, 2)
      oval(96, 130, 158, 176, fill: 0xC58FA9, border: 0x916983); disc(123, 154, 5, 0x9A6687)
      for i in 0...6 {
        let f = (t - 0.065 * Double(i)) / 0.56, x = 149 + 15 * Double(i), y = 180 + 10 * wave(Double(i) * 0.15)
        if f < 0.69 {
          let p = Self.pituitarySmooth(f / 0.69)
          disc(x + (172 + 4 * Double(i) - x) * p, y + (216 - y) * p, 5, 0xFFFCF3, border: Self.ghSignal)
        } else if f < 1 { disc(172 + 4 * Double(i), 216 + 27 * (f - 0.69) / 0.31, 3.4, Self.ghSignal) }
        let released = t - 0.56 - 0.065 * Double(i)
        if released >= 0 { pituitaryMarker(G.capillaryRoute, 0.47 + 0.014 * Double(i) + released * 1.35, Self.ghSignal) }
      }
      label("antsoma_art_cell", 180, 68, 260); label("antsoma_art_gh_blood", 180, 293, 270)
    case 1:
      pituitaryVessel(G.trunk, 13); pituitaryVessel(G.upperBranch, 10); pituitaryVessel(G.lowerBranch, 10)
      anteriorPituitary(20, 145, 1.06, Self.ghSignal); somatotrophLiver(238, 69, 0.68); somatotrophFibers(234, 222, 0.77)
      for i in 0...3 {
        let f = (t - Double(i) * 0.11) * 2.1
        pituitaryMarker(G.trunkRoute, f * 3, Self.ghSignal)
        pituitaryMarker(G.upperBranchRoute, (f - 0.33) * 1.32, Self.ghSignal)
        pituitaryMarker(G.lowerBranchRoute, (f - 0.33) * 1.18, Self.ghSignal)
      }
      label("antpit_art_anterior", 61, 234, 104); label("antsoma_art_gh_blood", 135, 146, 145)
      label("antsoma_art_liver", 288, 60, 120); label("antsoma_art_muscle", 284, 305, 135)
    case 2:
      pituitaryVessel(G.hepaticOut, 16); somatotrophLiver(50, 106, 1.26)
      stroke(G.input, 0xB17A86, 9); stroke(G.input, 0xF6D9DC, 6)
      for i in 0...2 {
        let delay = 0.09 * Double(i), response = (t - 0.26 - delay) / 0.29
        pituitaryMarker(G.inputRoute, (t - delay) / 0.41, Self.ghSignal)
        if (0...1).contains(response) { pituitaryRing(141 + Double(i) * 12, 158 + Double(i) * 9, 6 + response * 12, Self.igfSignal, opacity: 1 - response, width: 2.4) }
        pituitaryMarker(G.hepaticOutRoute, (t - 0.46 - delay) / 0.39, Self.igfSignal, radius: 4.6, angular: true)
      }
      label("antsoma_art_gh", 64, 59, 85); label("antsoma_art_liver", 204, 116, 100); label("antsoma_art_igf_blood", 244, 297, 196)
    default:
      pituitaryVessel(G.muscleGh, 12); pituitaryVessel(G.muscleIgf, 12); somatotrophFibers(87, 159, 1.43)
      for i in 0...2 {
        pituitaryMarker(G.muscleGhRoute, (t - 0.13 * Double(i)) / 0.53, Self.ghSignal)
        pituitaryMarker(G.muscleIgfRoute, (t - 0.07 - 0.13 * Double(i)) / 0.53, Self.igfSignal, radius: 4.5, angular: true)
      }
      for i in 0...5 {
        let f = Self.pituitarySmooth((t - 0.34 - 0.06 * Double(i)) / 0.31), x = 125 + 22 * Double(i), y = 186 + 31 * Double(i % 3)
        if f > 0 { line(x, y, x + 27 * f, y, 0x8A464E, 3.6) }
      }
      label("antsoma_art_gh", 70, 71, 91); label("antsoma_art_igf", 288, 71, 108); label("antsoma_art_muscle", 180, 291, 220)
    }
  }
  private func somatotrophLiver(_ x: Double, _ y: Double, _ scale: Double) {
    var local = context; local.translateBy(x: x, y: y); local.scaleBy(x: scale, y: scale)
    let art = copy(local)
    art.gradient(GalaxySSIHealthAtlasSomatotrophGeometry.liverShape, 10, 94, 0xE5A18A, 0xBC7266)
    art.stroke(GalaxySSIHealthAtlasSomatotrophGeometry.liverShape, 0x854D4D, 1.9)
    art.stroke(GalaxySSIHealthAtlasSomatotrophGeometry.liverDivision, 0xA75F59, 1.7)
  }
  private func somatotrophFibers(_ x: Double, _ y: Double, _ scale: Double) {
    var local = context; local.translateBy(x: x, y: y); local.scaleBy(x: scale, y: scale)
    for row in 0...2 {
      var next = local; next.translateBy(x: 0, y: 22 * Double(row)); let art = copy(next)
      art.fill(GalaxySSIHealthAtlasSomatotrophGeometry.fiber, row == 1 ? 0xD79B9A : 0xE5AAA0)
      art.stroke(GalaxySSIHealthAtlasSomatotrophGeometry.fiber, 0xA35D65, 1.6)
      for i in 0...7 { let xx = 21 + 12 * Double(i); art.line(xx, 7, xx - 2, 19, 0xBC7880, 1.3) }
    }
  }
}
