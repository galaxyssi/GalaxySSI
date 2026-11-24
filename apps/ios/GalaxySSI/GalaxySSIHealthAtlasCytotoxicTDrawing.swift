import SwiftUI

extension GalaxySSIHealthAtlasImmuneDrawing {
  func cytotoxicScene(_ step: Int, _ t: Double) {
    switch step {
    case 0: cytotoxicPair(83 + 44 * Self.ease(t), 0)
    case 1:
      cytotoxicPair(127 + 22 * Self.ease(t, 0.02, 0.44), 0); cytotoxicContact(Self.ease(t, 0.44, 0.93))
    case 2:
      cytotoxicPair(149, Self.ease(t, 0.10, 0.95)); cytotoxicContact(1 - Self.ease(t, 0, 0.24), showLabel: false)
      art.label("cytotoxic_t_story_label_apoptosis", 254, 83, 164)
    default:
      let f = Self.ease(t), x = 149 - 75 * f, y = 170 - 38 * f
      cytotoxicTarget(1, fragments: f); lymphocyte(x, y, 1.08, 0xB8DCEC, 0x6399BD, 0x366581)
      var local = art.context; local.translateBy(x: 280, y: 262); local.scaleBy(x: 0.61, y: 0.61)
      let neighbor = art.copy(local), rim = GalaxySSIHealthAtlasImmuneGeometry.bodyRim
      neighbor.gradient(rim, -60, 60, 0xE5E7D4, 0xBEC8A8); neighbor.stroke(rim, 0x748064, 1.6)
      neighbor.oval(-24, -22, 20, 20, fill: 0xA69AB2, border: 0x766B84)
      art.label("cytotoxic_t_story_label_cell", max(75, x - 3), y + 72, 128)
      art.label("cytotoxic_t_story_label_apoptosis", 234, 112, 151); art.label("cytotoxic_t_story_label_neighbor", 252, 323, 185)
    }
  }
  private func cytotoxicPair(_ x: Double, _ change: Double) {
    cytotoxicTarget(change); lymphocyte(x, 170, 1.08, 0xB8DCEC, 0x6399BD, 0x366581)
    art.label("cytotoxic_t_story_label_cell", 113, 263, 132); art.label("cytotoxic_t_story_label_target", 254, 263, 174)
  }
  private func cytotoxicContact(_ activity: Double, showLabel: Bool = true) {
    guard activity > 0 else { return }
    let spread = 3 + 14 * activity
    var path = Path(); path.move(to: CGPoint(x: 195, y: 170 - spread))
    path.addQuadCurve(to: CGPoint(x: 193, y: 170 + spread), control: CGPoint(x: 198, y: 170))
    art.stroke(path, 0xF8EEE1, 6.1); art.stroke(path, 0x385C78, 2.25)
    if showLabel { art.label("cytotoxic_t_story_label_contact", 172, 73, 170); art.line(176, 83, 192, 145, 0x385C78, 1.1) }
  }
  private func cytotoxicTarget(_ change: Double, fragments: Double = 0) {
    let size = 1 - 0.36 * change
    var local = art.context; local.translateBy(x: 255 - (1 - size) * 59, y: 170 + 5 * change); local.scaleBy(x: size, y: size)
    let target = art.copy(local), rim = GalaxySSIHealthAtlasImmuneGeometry.bodyRim
    target.gradient(rim, -60, 60, 0xF6CFC5, 0xD58E92); target.stroke(rim, 0x9C5C61, 1.6)
    target.oval(-23 + 10 * change, -26 + 9 * change, 31 - 8 * change, 24 - 6 * change, fill: 0xA97491, border: 0x80516E)
    target.disc(10, -6, 7 - 3 * change, 0x79506B); target.disc(2, 7, 4 - change, 0x79506B)
    for i in 0...2 {
      let f = Self.ease(change, 0.13 + Double(i) * 0.13, 0.66 + Double(i) * 0.10)
      if f <= 0 { continue }
      let x = 40 + Double(i % 2) * 11 + 14 * f + fragments * (18 + Double(i) * 6)
      let y = -40 + Double(i) * 35 + Double(i - 1) * (11 * f + 12 * fragments)
      target.disc(x, y, 3 + f * (7 - Double(i)) - 2.4 * fragments, 0xDF9C9D, border: 0x9C5C61)
    }
  }
}
