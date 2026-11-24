import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  private static let muralFill: UInt32 = 0x80BBB0, muralEdge: UInt32 = 0x286B66
  private static let pericyteLining: UInt32 = 0xE2A7A6, pericyteLiningEdge: UInt32 = 0x905765
  private static let pericyteMatrix: UInt32 = 0xEDDBAD, pericyteMatrixEdge: UInt32 = 0xAD8650
  private static let pericyteLumen: UInt32 = 0xFFE8DF, pericyteFocus: UInt32 = 0xFFF3A1
  func pericyteCoverage(_ step: Int, _ t: Double) {
    rounded(16, 20, 344, 340, 10, 0xFBF6E9)
    if step == 1 { pericyteCrossSection(t) }
    else if step == 2 { pericyteWallDetail(t) }
    else { pericyteLengthwise(t, cooperation: step == 3) }
  }
  private func pericyteLengthwise(_ t: Double, cooperation: Bool) {
    typealias G = GalaxySSIHealthAtlasPericyteGeometry
    label("pericyte_coverage_art_lengthwise", 180, 46, 280); fill(G.sleeve, Self.pericyteMatrix)
    rounded(28, 138, 332, 237, 13, Self.pericyteLining)
    for i in 0...4 {
      let x = 54 + 62 * Double(i)
      oval(x - 12, 144, x + 12, 152, fill: Self.pericyteLiningEdge, border: Self.pericyteLiningEdge)
      oval(x - 12, 221, x + 12, 230, fill: Self.pericyteLiningEdge, border: Self.pericyteLiningEdge)
      if i < 4 { line(x + 32, 139, x + 34, 157, Self.pericyteLiningEdge, 1.2); line(x + 29, 216, x + 35, 236, Self.pericyteLiningEdge, 1.2) }
    }
    var clipped = context; clipped.clip(to: G.window); let lumen = copy(clipped)
    lumen.fill(G.window, Self.pericyteLumen)
    for i in 0...3 {
      let x = 28 + 304 * (t + 0.25 * Double(i)).truncatingRemainder(dividingBy: 1), y = i % 2 == 0 ? 172.0 : 203.0
      lumen.oval(x - 13, y - 6, x + 13, y + 6, fill: 0xD98983, border: Self.pericyteLiningEdge)
      lumen.oval(x - 6, y - 2, x + 6, y + 2, fill: Self.pericyteLining, border: Self.pericyteLining)
    }
    stroke(G.window, Self.pericyteLiningEdge, 1.2); stroke(G.sleeve, Self.pericyteMatrixEdge, 1.3)
    fill(G.profile, Self.muralFill); stroke(G.profile, Self.muralEdge, 1.35)
    oval(148, 101, 173, 118, fill: Self.muralEdge, border: Self.muralEdge)
    label("pericyte_coverage_art_lumen", 180, 192, 110)
    pericyteCallout("cell", 158, 77, 155, 157, 97); pericyteCallout("lining", 87, 282, 123, 105, 226)
    if cooperation {
      line(91, 241, 269, 241, Self.pericyteFocus, 2.5 + 1.1 * (1 + wave(t)))
      pericyteCallout("matrix", 234, 319, 190, 244, 242)
    }
  }
  private func pericyteCrossSection(_ t: Double) {
    typealias G = GalaxySSIHealthAtlasPericyteGeometry
    label("pericyte_coverage_art_cross_section", 180, 46, 280)
    disc(170, 173, 81, Self.pericyteMatrix, border: Self.pericyteMatrixEdge)
    disc(170, 173, 70, Self.pericyteLining, border: Self.pericyteLiningEdge)
    for i in 0...3 {
      var local = context; local.translateBy(x: 170, y: 173); local.rotate(by: .degrees(16 + Double(i) * 90)); local.translateBy(x: -170, y: -173)
      copy(local).oval(156, 107, 184, 118, fill: Self.pericyteLiningEdge, border: Self.pericyteLiningEdge)
      local.translateBy(x: 170, y: 173); local.rotate(by: .degrees(43)); local.translateBy(x: -170, y: -173)
      copy(local).line(170, 103, 170, 120, Self.pericyteLiningEdge, 1.2)
    }
    disc(170, 173, 55, Self.pericyteLumen, border: Self.pericyteLiningEdge)
    fill(G.wrap, Self.muralFill); stroke(G.wrap, Self.muralEdge, 1.45)
    oval(178, 78, 226, 109, fill: Self.muralFill, border: Self.muralEdge); oval(188, 84, 211, 101, fill: Self.muralEdge, border: Self.muralEdge)
    at(G.wrapTraceRoute, 0.08 + 0.83 * t) { disc($0, $1, 4.1, Self.pericyteFocus, border: Self.muralEdge) }
    label("pericyte_coverage_art_lumen", 170, 177, 97)
    pericyteCallout("cell", 257, 73, 140, 215, 88); pericyteCallout("extension", 269, 285, 130, 244, 228)
    pericyteCallout("matrix", 104, 313, 160, 127, 239)
  }
  private func pericyteWallDetail(_ t: Double) {
    typealias G = GalaxySSIHealthAtlasPericyteGeometry
    label("pericyte_coverage_art_detail", 180, 46, 280); rounded(29, 214, 331, 279, 8, Self.pericyteLumen)
    fill(G.matrix, Self.pericyteMatrix); stroke(G.matrix, Self.pericyteMatrixEdge, 1.2)
    fill(G.liningDetail, Self.pericyteLining); stroke(G.liningDetail, Self.pericyteLiningEdge, 1.4)
    fill(G.muralDetail, Self.muralFill); stroke(G.muralDetail, Self.muralEdge, 1.4)
    oval(151, 122, 194, 141, fill: Self.muralEdge, border: Self.muralEdge)
    oval(83, 199, 130, 219, fill: Self.pericyteLiningEdge, border: Self.pericyteLiningEdge)
    let r = 13 + 5 * (1 + wave(t - 0.25))
    stroke(Path(ellipseIn: CGRect(x: 191 - r, y: 192 - r, width: 2 * r, height: 2 * r)), Self.pericyteFocus, 2.3)
    label("pericyte_coverage_art_lumen", 167, 259, 110)
    pericyteCallout("cell", 100, 83, 145, 155, 124); pericyteCallout("matrix", 258, 104, 152, 273, 146)
    pericyteCallout("contact", 262, 312, 142, 191, 198); pericyteCallout("lining", 75, 296, 109, 61, 229)
  }
  private func pericyteCallout(_ key: String, _ x: Double, _ y: Double, _ width: Double, _ tipX: Double, _ tipY: Double) {
    line(x, y > tipY ? y - 15 : y + 5, tipX, tipY, 0x50686A, 1.1)
    disc(tipX, tipY, 2.3, Self.cream, border: 0x50686A); label("pericyte_coverage_art_" + key, x, y, width)
  }
}
