import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func tasteScene(step: Int, t: Double) {
    if step == 0 { tasteTongue(t) } else { tasteBud(step: step, t: t) }
  }
  private func tasteTongue(_ t: Double) {
    var tongue = Path(); tongue.move(to: CGPoint(x: 41, y: 202))
    tongue.addCurve(to: CGPoint(x: 149, y: 135), control1: CGPoint(x: 31, y: 133), control2: CGPoint(x: 112, y: 145))
    tongue.addCurve(to: CGPoint(x: 323, y: 160), control1: CGPoint(x: 213, y: 122), control2: CGPoint(x: 307, y: 110))
    tongue.addCurve(to: CGPoint(x: 109, y: 254), control1: CGPoint(x: 348, y: 227), control2: CGPoint(x: 203, y: 254))
    tongue.addQuadCurve(to: CGPoint(x: 41, y: 202), control: CGPoint(x: 48, y: 253)); tongue.closeSubpath()
    chemicalFigure(tongue, 42, 304, 0xFFE6D3, 0xE0A4A5, Self.coral)
    for i in 0...3 {
      for j in 0...2 {
        let x = Double(89 + 54 * i + j * 6), y = Double(184 + 17 * j - 5 * i)
        oval(x - 9, y - 5, x + 9, y + 5, fill: Self.peach, border: Self.coral); disc(x, y, 2, Self.cream)
      }
    }
    var saliva = Path(); saliva.move(to: CGPoint(x: 56, y: 154))
    saliva.addCurve(to: CGPoint(x: 300, y: 126), control1: CGPoint(x: 131, y: 115), control2: CGPoint(x: 231, y: 119)); stroke(saliva, 0x82ACAE, 6)
    for i in 0...7 { disc(Double(69 + 31 * i), 98 + 27 * t + 8 * wave(t + Double(i) * 0.31), 3.8, Self.sienna, border: Self.cream) }
    chemicalLeader("sense_taste_saliva", 91, 72, 89, 138, Self.blue); chemicalLeader("sense_taste_papilla", 267, 284, 265, 192, Self.coral)
  }
  private func tasteBud(step: Int, t: Double) {
    typealias Motion = GalaxySSIHealthAtlasChemicalSenseMotion
    oval(74, 80, 284, 267, top: 98, bottom: 300, from: 0xF6DCD7, to: 0xD897A1, border: Self.coral)
    rounded(28, 72, 156, 108, 11, Self.peach); rounded(204, 72, 332, 108, 11, Self.peach)
    for i in 0...4 {
      let a = Double(i - 2)
      var cell = Path(); cell.move(to: CGPoint(x: 179 + a * 7, y: 104))
      cell.addCurve(to: CGPoint(x: 183 + a * 12, y: 255), control1: CGPoint(x: 183 + a * 35, y: 129), control2: CGPoint(x: 184 + a * 39, y: 195))
      cell.addCurve(to: CGPoint(x: 179 + a * 7, y: 104), control1: CGPoint(x: 162 + a * 11, y: 217), control2: CGPoint(x: 157 + a * 37, y: 140)); cell.closeSubpath()
      if a == 0 && step >= 2 { chemicalFigure(cell, 110, 275, 0xDBEFE9, 0x8EB7AA, Self.teal) }
      else { chemicalFigure(cell, 42, 304, 0xFFE6D3, 0xE0A4A5, a == 0 ? Self.teal : Self.coral) }
      disc(170 + a * 26, 189, 5.5, a == 0 ? Self.violet : Self.coral); line(179 + a * 7, 104, 179 + a * 8, 90, Self.teal, 1.45)
    }
    let nerve = GalaxySSIHealthAtlasSectionLessonView.path(Motion.tasteNerve, width: 360, height: 360)
    stroke(nerve, 0x99BAB6, 13); stroke(nerve, Self.blue, 2.7)
    if step <= 2 {
      for i in 0...4 {
        let f = Motion.transfer(t, index: i)
        disc(181 + Double(i - 2) * (9 - f * 6), 48 + 38 * f - Double(i) * 3, 3.5, Self.sienna, border: Self.cream)
      }
    }
    if step == 2 { disc(179, 111 + 115 * t, 5.5, Self.violet, border: Self.cream) }
    if step >= 3 {
      for i in 0...2 {
        let f = Motion.transfer(t, index: i, startsAt: 0.12)
        disc(176 + Double(i) * 4 + 2 * wave(t + Double(i)), 248 + 24 * f, 3.5, Self.violet, border: Self.cream)
      }
    }
    if step == 4 { chemicalParticles(Motion.tasteNerve, t, Self.blue, 4) }
    if step <= 2 { chemicalLeader("sense_taste_pore_label", 280, 45, 180, 85, Self.sienna) }
    if step == 2 { chemicalLeader("sense_taste_cell", 273, 273, 187, 174, Self.teal) }
    if step >= 3 {
      label("sense_taste_nerve", 275, 343, 153); chemicalLeader("sense_taste_atp_label", 98, 294, 171, 260, Self.violet)
    }
  }
}
