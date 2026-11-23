import SwiftUI

extension GalaxySSIHealthAtlasLymphImmuneDrawing {
  func antibodyScene(_ motion: Motion) {
    switch motion.chapter {
    case 0: recognize(motion.fraction)
    case 1: helperSignal(motion.fraction)
    case 2: expand(motion)
    case 3: specialize(motion.fraction)
    default: release(motion.fraction)
    }
  }
  private func recognize(_ t: Double) {
    cell("HealthAtlasImmuneBCell", 112, 181, 220)
    let x = 294 - 101 * t
    antigen(x, 182, 9); label(106, 288, "antibody_story_b_cell")
    leader(265, 123, x, 173, "antibody_story_antigen", Self.gold)
  }
  private func helperSignal(_ t: Double) {
    let right = 264 - 15 * t
    cell("HealthAtlasImmuneBCell", 98, 177, 176)
    var mirrored = context; mirrored.translateBy(x: right, y: 177); mirrored.scaleBy(x: -1, y: 1); mirrored.translateBy(x: -right, y: -177)
    copy(mirrored).cell("HealthAtlasImmuneTCell", right, 177, 176)
    line(149, 174, right - 61, 174, Self.teal, 2.3); antigen(153, 174, 4)
    for i in 0...2 {
      let f = Motion.loop(t * 1.4 + Double(i) / 3)
      tracer(right - 62 - f * (right - 221), Double(185 + i * 5), Self.gold, 2.9)
    }
    label(95, 270, "antibody_story_b_cell"); label(263, 270, "antibody_story_helper")
    leader(179, 78, 173, 176, "antibody_story_signal", Self.teal)
  }
  private func expand(_ motion: Motion) {
    let clones = motion.clones
    for center in clones.centers { cell("HealthAtlasImmuneBCell", center.x, center.y, clones.diameter) }
    label(180, 287, "antibody_story_clone")
  }
  private func specialize(_ t: Double) {
    cell("HealthAtlasImmuneBCell", 180, 86, 93)
    var left = Path(); left.move(to: CGPoint(x: 180, y: 125))
    left.addQuadCurve(to: CGPoint(x: 113, y: 185), control: CGPoint(x: 157, y: 150)); stroke(left, Self.teal, 2.6)
    var right = Path(); right.move(to: CGPoint(x: 180, y: 125))
    right.addQuadCurve(to: CGPoint(x: 247, y: 185), control: CGPoint(x: 203, y: 150)); stroke(right, Self.teal, 2.6)
    let f = Motion.loop(t * 1.35)
    for d in [-1.0, 1.0] { tracer(180 + d * 67 * f, 125 + 60 * f, Self.gold, 3.5) }
    cell("HealthAtlasImmunePlasma", 107, 234, 102 + 17 * t); cell("HealthAtlasImmuneBCell", 253, 234, 98 + 13 * t)
    label(101, 320, "antibody_story_plasma"); label(257, 320, "antibody_story_memory")
  }
  private func release(_ t: Double) {
    cell("HealthAtlasImmunePlasma", 101, 180, 156)
    oval(290, 180, 37, 51, 0xECD6A3); oval(303, 182, 13, 27, 0xF3E6BF)
    for i in 0...2 {
      let y = Double(158 + i * 22), x = 158 + Double(74 - i * 5) * Motion.loop(t * 1.5 + Double(i) / 3)
      antibody(x, y, Self.teal); antigen(i == 1 ? 253 : 257, y, 5)
      if t > 0.23 + Double(i) * 0.19 { antibody(240, y, Self.teal) }
    }
    label(99, 286, "antibody_story_plasma"); leader(216, 100, 235, 148, "antibody_story_antibody", Self.teal)
    label(291, 265, "antibody_story_antigen")
  }
  private func antigen(_ x: Double, _ y: Double, _ r: Double) {
    var path = Path(); path.move(to: CGPoint(x: x - r, y: y)); path.addLine(to: CGPoint(x: x, y: y - r))
    path.addLine(to: CGPoint(x: x + r, y: y)); path.addLine(to: CGPoint(x: x, y: y + r)); path.closeSubpath()
    fill(path, 0xE8B66E); stroke(path, Self.gold, 1.2)
  }
  private func antibody(_ x: Double, _ y: Double, _ value: UInt32) {
    var path = Path(); path.move(to: CGPoint(x: x - 8, y: y)); path.addLine(to: CGPoint(x: x + 1, y: y))
    path.addLine(to: CGPoint(x: x + 9, y: y - 6)); path.move(to: CGPoint(x: x + 1, y: y)); path.addLine(to: CGPoint(x: x + 9, y: y + 6))
    stroke(path, Self.cream, 5); stroke(path, value, 2.8)
  }
}
