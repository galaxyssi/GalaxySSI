import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  private static let fshSignal: UInt32 = 0x2D7D78, lhSignal: UInt32 = 0x8B4876, gnrhSignal: UInt32 = 0x536F92
  func gonadotrophSignal(_ step: Int, _ t: Double) {
    typealias G = GalaxySSIHealthAtlasGonadotrophGeometry
    switch step {
    case 0:
      pituitaryVessel(G.input, 15)
      for i in 0...3 {
        line(35 + Double(i) * 9, 114 - Double(i) * 5, 65 + Double(i) * 5, 152, 0xA299AF, 3)
        disc(65 + Double(i) * 5, 152, 5, 0x9E8DA9, border: 0x786B85)
      }
      anteriorPituitary(187, 143, 1.23, Self.gnrhSignal)
      for i in 0...1 {
        let f = (t - 0.37 * Double(i)) / 0.61
        pituitaryTrace(G.inputRoute, f - 0.17, f, Self.gnrhSignal, 5); pituitaryMarker(G.inputRoute, f, Self.gnrhSignal, radius: 4.5)
      }
      let arrival = Self.pituitarySmooth((t - 0.59) / 0.40)
      if arrival > 0 { pituitaryRing(241, 181, 8 + arrival * 14, Self.gnrhSignal, opacity: 1 - arrival, width: 2.4) }
      label("antgonad_art_terminal", 96, 76, 176); label("antgonad_art_gnrh", 144, 218, 218); label("antgonad_art_cell", 238, 263, 173)
    case 1:
      pituitaryVessel(G.trunk, 18); pituitaryVessel(G.ovarianBranch, 15); pituitaryVessel(G.testisBranch, 15)
      anteriorPituitary(18, 147, 0.97, Self.gnrhSignal); fill(G.ovary, 0xEDC1B2); stroke(G.ovary, 0xA2677A, 1.6)
      disc(284, 102, 10, 0xF9DBCA, border: 0xA2677A); disc(307, 109, 7, 0xF9DBCA, border: 0xA2677A)
      oval(265, 205, 320, 274, fill: 0xC5D9D7, border: 0x788E90); oval(275, 215, 310, 262, fill: 0xEAF2E7, border: 0x788E90)
      for i in 0...2 { oval(281, 221 + 12 * Double(i), 303, 229 + 12 * Double(i), fill: 0xD2E4DD, border: 0x788E90) }
      for i in 0...2 {
        let f = (t - Double(i) * 0.14) / 0.66
        gonadotrophPair(G.trunkRoute, f / 0.41); gonadotrophPair(G.ovarianBranchRoute, (f - 0.41) / 0.59); gonadotrophPair(G.testisBranchRoute, (f - 0.41) / 0.59)
      }
      disc(92, 286, 4.5, Self.fshSignal)
      var legend = context; legend.translateBy(x: 181, y: 286); legend.rotate(by: .degrees(45))
      copy(legend).fill(Path(CGRect(x: -3.6, y: -3.6, width: 7.2, height: 7.2)), Self.lhSignal)
      label("antgonad_art_fsh", 119, 290, 45); label("antgonad_art_lh", 205, 290, 33)
      label("antpit_art_anterior", 65, 229, 115); label("antgonad_art_ovary", 289, 65, 115); label("antgonad_art_testis", 294, 303, 110)
    case 2: gonadotrophFollicle(t)
    default: gonadotrophTubule(t)
    }
  }
  private func gonadotrophFollicle(_ t: Double) {
    typealias G = GalaxySSIHealthAtlasGonadotrophGeometry
    gonadotrophApproach(G.ovarianFshRoute, 0.62); gonadotrophApproach(G.ovarianLhRoute, 0.70)
    disc(190, 181, 84, 0xE5AFB7, border: 0xA2677A); disc(190, 181, 68, 0xD38DA4, border: 0xA2677A)
    disc(190, 181, 49, 0xF9E4DD, border: 0xA2677A); disc(215, 210, 20, 0xD99CB2, border: 0xA2677A)
    disc(216, 210, 12, 0xFFFCF3, border: 0xA2677A); disc(214, 209, 4, 0xA5688B)
    for i in 0...19 { let f = Double(i) / 20; disc(190 + 59 * wave(f + 0.25), 181 + 59 * wave(f), 3.3, 0xAA6B86) }
    for i in 0...2 {
      pituitaryMarker(G.ovarianFshRoute, (t - 0.09 * Double(i)) / 0.56, Self.fshSignal, radius: 4.5)
      pituitaryMarker(G.ovarianLhRoute, (t - 0.08 - 0.09 * Double(i)) / 0.54, Self.lhSignal, radius: 4.5, angular: true)
    }
    let inner = Self.pituitarySmooth((t - 0.52) / 0.43), outer = Self.pituitarySmooth((t - 0.59) / 0.35)
    endocrineArc(190, 181, 59, 59, 201, 122 * inner, Self.fshSignal, 4.2)
    endocrineArc(190, 181, 77, 77, -27, 121 * outer, Self.lhSignal, 4.2)
    label("antgonad_art_fsh_granulosa", 94, 72, 164); label("antgonad_art_lh_theca", 270, 72, 150); label("antgonad_art_follicle", 190, 308, 212)
  }
  private func gonadotrophTubule(_ t: Double) {
    typealias G = GalaxySSIHealthAtlasGonadotrophGeometry
    gonadotrophApproach(G.testisFshRoute, 0.66); gonadotrophApproach(G.testisLhRoute, 0.82)
    disc(139, 197, 73, 0xC2D3CC, border: 0x788E90); disc(139, 197, 40, 0xEBF1E8, border: 0x788E90)
    disc(317, 168, 24, 0xC2D3CC, border: 0x788E90); disc(317, 168, 13, 0xEBF1E8, border: 0x788E90)
    fill(G.sertoliCell, 0x93BBB2); stroke(G.sertoliCell, Self.fshSignal, 1.6); disc(124, 145, 4.6, Self.fshSignal)
    for i in 0...12 {
      let a = Double(i) / 13
      if i != 9 && i != 10 { disc(139 + 57 * wave(a + 0.25), 197 + 57 * wave(a), 5.5, 0xE9EBDF, border: 0x788E90) }
    }
    for (x1, y1, x2, y2) in [(236.0, 165.0, 257.0, 185.0), (252, 178, 275, 199), (235, 196, 260, 219)] { oval(x1, y1, x2, y2, fill: 0xE6B4B8, border: 0xA2677A) }
    disc(247, 174, 3.6, Self.lhSignal); disc(264, 189, 3.6, Self.lhSignal); disc(248, 208, 3.6, Self.lhSignal)
    for i in 0...2 {
      pituitaryMarker(G.testisFshRoute, (t - 0.11 * Double(i)) / 0.49, Self.fshSignal, radius: 4.5)
      pituitaryMarker(G.testisLhRoute, (t - 0.10 - 0.09 * Double(i)) / 0.53, Self.lhSignal, radius: 4.5, angular: true)
    }
    let response = Self.pituitarySmooth((t - 0.52) / 0.43)
    if response > 0 {
      var local = context; local.opacity = Double(Int(255 * (1 - response))) / 255
      copy(local).stroke(G.sertoliCell, Self.fshSignal, 2 + response * 5)
    }
    for i in 0...3 {
      let f = (t - 0.59 - 0.085 * Double(i)) / 0.38
      if (0...1).contains(f) {
        var local = context; local.opacity = Double(Int(255 * (1 - 0.7 * f))) / 255
        copy(local).disc(263 + (297 + 4 * Double(i) - 263) * f, 188 + (230 - Double(i) * 11 - 188) * f, 3.2, 0xAE792E)
      }
    }
    label("antgonad_art_fsh_sertoli", 92, 73, 156); label("antgonad_art_lh_leydig", 264, 73, 159)
    label("antgonad_art_tubule", 121, 306, 198); label("antgonad_art_testosterone", 274, 269, 151)
  }
  private func gonadotrophApproach(_ route: GalaxySSIHealthAtlasSectionLesson.Route, _ end: Double) {
    pituitaryTrace(route, 0, end, 0xB17A86, 12); pituitaryTrace(route, 0, end, 0xF6D9DC, 9)
  }
  private func gonadotrophPair(_ route: GalaxySSIHealthAtlasSectionLesson.Route, _ f: Double) {
    pituitaryMarker(route, f + 0.04, Self.fshSignal, radius: 4)
    pituitaryMarker(route, f - 0.04, Self.lhSignal, radius: 4.6, angular: true)
  }
}
