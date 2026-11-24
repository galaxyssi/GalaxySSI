import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  private static let zoneFill: [UInt32] = [0xEBCA8B, 0xE9AA8C, 0xD6A0AE]
  private static let zoneInk: [UInt32] = [0x856121, 0xA5553F, 0x834A6F]
  private static let zoneMuted: [UInt32] = [0xEFDFBE, 0xEAD1C1, 0xE5CDD6]
  private static let zoneTop = [102.0, 145.0, 216.0], zoneBottom = [145.0, 216.0, 261.0]
  private static let zoneTitle = ["glomerulosa", "fasciculata", "reticularis"], zoneHormone = ["aldosterone", "cortisol", "androgen"]
  func cortexOutput(_ step: Int, _ t: Double) {
    typealias G = GalaxySSIHealthAtlasAdrenalCortexGeometry
    if step == 0 {
      for (s, fill, border) in [(1.0, UInt32(0xF3DFB9), UInt32(0x986B42)), (0.94, Self.zoneFill[0], Self.zoneInk[0]),
        (0.83, Self.zoneFill[1], Self.zoneInk[1]), (0.60, Self.zoneFill[2], Self.zoneInk[2]), (0.45, 0xD4B6BB, 0x926B77)] {
        var local = context; local.translateBy(x: 180, y: 226); local.scaleBy(x: s, y: s); local.translateBy(x: -180, y: -226)
        let art = copy(local); art.fill(G.section, fill); art.stroke(G.section, border, 1.5)
      }
      at(G.sectionRoute, 0.03 + 0.36 * t) { x, y in
        let circle = Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10))
        stroke(circle, Self.cream, 4.5); stroke(circle, 0x986B42, 1.8)
      }
      label("cortex_output_art_capsule", 78, 102, 123); line(82, 112, 104, 155, 0x986B42, 1.3)
      label("cortex_output_art_cortex", 272, 111, 140); line(266, 123, 232, 173, Self.zoneInk[1], 1.4)
      label("cortex_output_art_medulla", 180, 222, 105); label("cortex_output_art_section", 180, 315, 285)
    } else if step == 4 {
      label("cortex_output_art_sinusoid", 180, 62, 265); endocrineVessel(G.sinusoid, 22)
      for i in 0...2 {
        let y = 118 + 60 * Double(i)
        rounded(29, y - 19, 162, y + 19, 6, Self.zoneFill[i]); label("cortex_output_art_" + Self.zoneHormone[i], 95, y + 4, 119)
        line(172, y, 218, y, 0xA4B7B4, 1.45)
        cortexGlyph(i, 175 + 40 * (t + 0.15 * Double(i)).truncatingRemainder(dividingBy: 1), y)
        at(G.sinusoidRoute, (0.51 + 0.08 * Double(i) + 0.63 * t).truncatingRemainder(dividingBy: 1)) { cortexGlyph(i, $0, $1) }
      }
      label("cortex_output_art_circulation", 235, 317, 200)
    } else {
      let index = step - 1
      guard (0...2).contains(index) else { return }
      label("cortex_output_art_" + Self.zoneTitle[index], 180, 64, 275); rounded(29, 91, 191, 282, 6, 0xF1DDBA)
      for i in 0...2 {
        rounded(29, Self.zoneTop[i], 191, Self.zoneBottom[i], 0, i == index ? Self.zoneFill[i] : Self.zoneMuted[i])
        line(29, Self.zoneTop[i], 191, Self.zoneTop[i], Self.zoneInk[i], 1)
      }
      rounded(29, 261, 191, 282, 0, 0xDAC9C8); line(29, 261, 191, 261, 0xA4B7B4, 1)
      cortexTexture(index)
      let scanX = 40 + 140 * t, center = (Self.zoneTop[index] + Self.zoneBottom[index]) / 2
      rounded(scanX - 7, Self.zoneTop[index] + 3, scanX + 7, Self.zoneBottom[index] - 3, 4, 0x55FFF8EB)
      line(scanX, Self.zoneTop[index] + 3, scanX, Self.zoneBottom[index] - 3, Self.cream, 1.6)
      line(196, center, 317, center, 0xA4B7B4, 1.4); cortexGlyph(index, 203 + 110 * t, center)
      label("cortex_output_art_" + Self.zoneHormone[index], 267, center + 27, 126); label("cortex_output_art_depth", 109, 309, 189)
    }
  }
  private func cortexTexture(_ index: Int) {
    let tint = Self.zoneInk[index]
    switch index {
    case 0:
      for i in 0...4 {
        let x = 48 + 28 * Double(i)
        disc(x - 6, 124, 4.2, tint); disc(x, 117, 4.2, tint); disc(x + 6, 124, 4.2, tint); disc(x + 1, 132, 4.2, tint)
      }
    case 1:
      for i in 0...6 { for j in 0...3 {
        let x = 43 + 22 * Double(i), y = 156 + 15 * Double(j)
        oval(x - 6, y - 7, x + 6, y + 7, fill: 0xF6D2AF, border: tint); disc(x, y, 2, tint)
      } }
    default:
      for i in 0...6 {
        let x = 43 + 21 * Double(i)
        line(x, 227, x + 9, 238, tint, 2.1); line(x + 9, 238, x, 250, tint, 2.1)
        if i < 6 { line(x + 9, 238, x + 21, 227, tint, 2.1) }; disc(x + 9, 238, 3.4, tint)
      }
    }
  }
  private func cortexGlyph(_ index: Int, _ x: Double, _ y: Double) {
    if index == 0 { disc(x, y, 5, Self.zoneInk[index], border: Self.cream) }
    else if index == 1 { rounded(x - 4.5, y - 4.5, x + 4.5, y + 4.5, 1, Self.zoneInk[index]) }
    else { endocrineDiamond(x, y, 6, Self.zoneInk[index]) }
  }
}
