import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  private static let prolactin: UInt32 = 0x9E4873, mammaryEdge: UInt32 = 0xA05B73
  private static let milkLumen: UInt32 = 0xFFF7EA, milkFill: UInt32 = 0xF0D392, milkEdge: UInt32 = 0xAB7840
  private static let lactoEpithelium: [CGPoint] = (0..<16).map { CGPoint(x: cos(Double($0) * .pi / 8), y: sin(Double($0) * .pi / 8)) }
  func lactotrophSignal(_ step: Int, _ t: Double) {
    typealias G = GalaxySSIHealthAtlasLactotrophGeometry
    switch step {
    case 0:
      pituitaryVessel(G.topPortal, 14); pituitaryVessel(G.releaseBlood, 18)
      fill(G.cell, 0xEDBEC7); stroke(G.cell, Self.mammaryEdge, 2.2)
      oval(118, 159, 164, 196, fill: 0xC891AA, border: 0x966487)
      for i in 0...4 {
        let x = 143 + Double(i) * 18, relief = Self.pituitarySmooth((t - 0.09 - Double(i) * 0.035) / 0.43)
        line(x - 4, 122, x + 4, 122, 0x477C8B, 2.2)
        var local = context; local.opacity = Double(Int(255 * (1 - relief))) / 255
        local.translateBy(x: x, y: 113 - 23 * relief); local.rotate(by: .degrees(45))
        copy(local).fill(Path(CGRect(x: -4.3, y: -4.3, width: 8.6, height: 8.6)), 0x477C8B)
      }
      for i in 0...3 {
        let p = (t - 0.41 - Double(i) * 0.085) / 0.46, x = 173 + Double(i) * 13
        if p < 0.57 {
          let start = 185 + Double(i) * 3
          disc(x, start + (258 - start) * Self.pituitarySmooth(p / 0.57), 4, Self.prolactin, border: 0xFFFCF3)
        } else { pituitaryMarker(G.releaseBloodRoute, 0.51 + Double(i) * 0.045 + (p - 0.57) * 0.53, Self.prolactin) }
      }
      label("antlacto_art_dopamine", 180, 60, 255); label("antlacto_art_cell", 187, 156, 125); label("antlacto_art_prl_blood", 180, 309, 271)
    case 1:
      pituitaryVessel(G.mammaryBlood, 15); anteriorPituitary(18, 105, 0.88, Self.prolactin)
      stroke(G.ducts, Self.mammaryEdge, 9); stroke(G.ducts, 0xEDBCC4, 6)
      for (x, y, r) in [(245.0, 111.0, 18.0), (286, 98, 17), (254, 181, 21), (305, 190, 17), (258, 144, 15)] {
        disc(x, y, r, 0xEDB9C1, border: Self.mammaryEdge); disc(x, y, r * 0.56, Self.milkLumen, border: Self.mammaryEdge)
      }
      for i in 0...5 { pituitaryMarker(G.mammaryBloodRoute, t * 1.6 - Double(i) * 0.16, Self.prolactin) }
      let arrival = Self.pituitarySmooth((t - 0.57) / 0.3)
      if arrival > 0 { pituitaryRing(254, 181, 22 + arrival * 7, Self.prolactin, opacity: 1 - arrival, width: 2.8) }
      label("antpit_art_anterior", 54, 181, 100); label("antlacto_art_alveoli", 269, 65, 150); label("antlacto_art_prl_blood", 173, 298, 260)
    case 2:
      pituitaryVessel(G.nearAlveolus, 17); lactoAlveolus()
      for i in 0...3 {
        let f = (t - Double(i) * 0.105) / 0.56, approach = (t - 0.33 - 0.09 * Double(i)) / 0.32
        pituitaryMarker(G.nearAlveolusRoute, (f + 0.23 * Double(i)) * 0.59, Self.prolactin)
        let x = 127 + Double(i) * 27, y = i == 0 || i == 3 ? 234.0 : 242.0
        if (0...1).contains(approach) { disc(x, 262 + (y - 262) * Self.pituitarySmooth(approach), 4.2, Self.prolactin) }
        let bound = Self.pituitarySmooth((approach - 0.68) * 2.5)
        if bound > 0 { pituitaryRing(x, y, 5.8 + 3 * bound, Self.prolactin, opacity: 0.85 * bound, width: 2) }
      }
      label("antlacto_art_wall", 166, 67, 252); label("antlacto_art_lumen", 169, 175, 82); label("antlacto_art_prl_blood", 177, 307, 260)
    default:
      lactoAlveolus()
      var local = context; local.clip(to: G.lumenClip); let inside = copy(local)
      let pool = Self.pituitarySmooth((t - 0.30) / 0.59)
      if pool > 0 {
        let surface = 218 - 26 * pool
        inside.rounded(120, surface, 220, 226, 8, Self.milkFill); inside.line(128, surface + 1, 213, surface + 1, Self.milkEdge, 1.35)
      }
      for i in 0...5 {
        let f = (t - 0.11 - 0.093 * Double(i)) / 0.38
        if (0...1).contains(f) {
          let k = (i * 2 + 9) % 16, radius = 50 - 37 * Self.pituitarySmooth(f), unit = Self.lactoEpithelium[k]
          inside.disc(170 + unit.x * radius, 171 + unit.y * radius, 3 + 2.5 * f, Self.milkFill, border: Self.milkEdge)
        }
      }
      label("antlacto_art_wall", 166, 67, 250); label("antlacto_art_milk_lumen", 178, 280, 275); line(170, 262, 170, 215, Self.milkEdge, 1.4)
    }
  }
  private func lactoAlveolus() {
    line(225, 145, 300, 110, Self.mammaryEdge, 23); line(225, 145, 300, 110, 0xE9AEBD, 20)
    disc(170, 171, 71, 0xECBDC5, border: Self.mammaryEdge)
    for i in 0..<16 {
      let unit = Self.lactoEpithelium[i], next = Self.lactoEpithelium[(i + 1) % 16]
      line(170 + unit.x * 49, 171 + unit.y * 49, 170 + unit.x * 69, 171 + unit.y * 69, Self.mammaryEdge, 1.25)
      disc(170 + 31 * (unit.x + next.x), 171 + 31 * (unit.y + next.y), 3, Self.mammaryEdge)
    }
    disc(170, 171, 47, Self.milkLumen, border: Self.mammaryEdge); line(204, 155, 300, 110, Self.milkLumen, 9)
  }
}
