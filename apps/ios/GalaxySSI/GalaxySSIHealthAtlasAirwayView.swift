import SwiftUI

struct GalaxySSIHealthAtlasAirwayView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height) / 360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 360 * scale) / 2); local.scaleBy(x: scale, y: scale)
      let art = GalaxySSIHealthAtlasIllustratedDrawing(context: local, language: language)
      art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), 0, 360, 0xE8F4F3, 0xFBF0DF)
      let step = story.chapter(phase), t = story.fraction(phase)
      art.airwayOverview(step: step, t: t); art.airwayCrossSection(step: step, t: t)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-airway-clearance-art")
  }
}

private enum AirwayInk {
  static let bend: UInt32 = 0x446B7D, film: UInt32 = 0xA4C9C8, dust: UInt32 = 0xAE784D
  static let left = Path { p in
    p.move(to: CGPoint(x: 85, y: 66))
    p.addCurve(to: CGPoint(x: 57, y: 69), control1: CGPoint(x: 80, y: 54), control2: CGPoint(x: 69, y: 57))
    p.addCurve(to: CGPoint(x: 40, y: 125), control1: CGPoint(x: 43, y: 84), control2: CGPoint(x: 39, y: 106))
    p.addCurve(to: CGPoint(x: 76, y: 131), control1: CGPoint(x: 42, y: 140), control2: CGPoint(x: 59, y: 139))
    p.addCurve(to: CGPoint(x: 87, y: 103), control1: CGPoint(x: 85, y: 127), control2: CGPoint(x: 88, y: 120)); p.closeSubpath()
  }
  static let right = Path { p in
    p.move(to: CGPoint(x: 106, y: 66))
    p.addCurve(to: CGPoint(x: 137, y: 74), control1: CGPoint(x: 113, y: 55), control2: CGPoint(x: 125, y: 59))
    p.addCurve(to: CGPoint(x: 151, y: 127), control1: CGPoint(x: 150, y: 92), control2: CGPoint(x: 154, y: 113))
    p.addCurve(to: CGPoint(x: 120, y: 134), control1: CGPoint(x: 147, y: 141), control2: CGPoint(x: 132, y: 139))
    p.addCurve(to: CGPoint(x: 106, y: 112), control1: CGPoint(x: 111, y: 131), control2: CGPoint(x: 105, y: 124))
    p.addCurve(to: CGPoint(x: 106, y: 89), control1: CGPoint(x: 114, y: 103), control2: CGPoint(x: 114, y: 95)); p.closeSubpath()
  }
  static let airway = Path { p in
    p.move(to: CGPoint(x: 95, y: 34))
    p.addCurve(to: CGPoint(x: 96, y: 65), control1: CGPoint(x: 92, y: 42), control2: CGPoint(x: 96, y: 50))
    p.addLine(to: CGPoint(x: 96, y: 87))
    p.addCurve(to: CGPoint(x: 62, y: 108), control1: CGPoint(x: 91, y: 95), control2: CGPoint(x: 78, y: 98))
    p.move(to: CGPoint(x: 96, y: 87))
    p.addCurve(to: CGPoint(x: 131, y: 110), control1: CGPoint(x: 102, y: 93), control2: CGPoint(x: 117, y: 99))
  }
}

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func airwayOverview(step: Int, t: Double) {
    for lung in [AirwayInk.left, AirwayInk.right] {
      gradient(lung, 34, 138, 0xFFE5DE, 0xDF9A9D); stroke(lung, Self.coral, 1.25)
    }
    if step == 4 {
      let esophagus = Path { p in
        p.move(to: CGPoint(x: 96, y: 34))
        p.addCurve(to: CGPoint(x: 108, y: 48), control1: CGPoint(x: 107, y: 22), control2: CGPoint(x: 111, y: 33))
        p.addCurve(to: CGPoint(x: 123, y: 79), control1: CGPoint(x: 109, y: 61), control2: CGPoint(x: 118, y: 69))
      }
      stroke(esophagus, 0xCF9683, 7.5); stroke(esophagus, 0xFFE3CF, 4)
    }
    stroke(AirwayInk.airway, AirwayInk.bend, 12); stroke(AirwayInk.airway, 0xA9D0DA, 8); stroke(AirwayInk.airway, 0xE9F4ED, 4)
    for i in 0...3 { let y = 49 + 9 * Double(i); line(91, y, 101, y, 0x6F9DAA, 1.1) }
    line(113, 43, 205, 43, AirwayInk.film, 1.05); label("airway_throat", 259, 47, 103)
    disc(82, 97, 12, 0xD8EFEA, border: Self.teal); disc(82, 97, 4, Self.teal, border: Self.cream)
    line(95, 108, 206, 117, Self.teal, 1.1); label("airway_airway_wall", 270, 121, 116)
    if step == 3 {
      let f = GalaxySSIHealthAtlasAirwayMotion.surfaceTravel(step: step, fraction: t)
      at(GalaxySSIHealthAtlasAirwayMotion.clearance, 0.27 + 0.71 * f) { x, y in disc(x, y, 4.3, Self.teal, border: Self.cream) }
    } else if step == 4 {
      let f = min(1, max(0, t * 1.38))
      if f < 0.3 {
        at(GalaxySSIHealthAtlasAirwayMotion.clearance, 0.866 + f * (0.134 / 0.3)) { x, y in disc(x, y, 4.3, Self.teal, border: Self.cream) }
      } else {
        at(GalaxySSIHealthAtlasAirwayMotion.toEsophagus, (f - 0.3) / 0.7) { x, y in disc(x, y, 4.3, Self.teal, border: Self.cream) }
      }
      line(133, 73, 181, 74, Self.coral, 1.1); label("airway_esophagus", 245, 78, 122)
    }
  }
  func airwayCrossSection(step: Int, t: Double) {
    rounded(18, 147, 342, 330, 8, 0xF5F4E9)
    if step >= 3 {
      arrow(99, 177, 222, 177, Self.teal); label("airway_toward_throat", 278, 181, 100)
    } else { label(step == 0 ? "airway_particles" : "airway_mucus", 266, 174, 121) }
    rounded(25, 199, 335, 223, 8, 0xC6E2D6); rounded(25, 217, 335, 253, 4, 0xDCECEF)
    line(34, 218, 327, 218, AirwayInk.film, 1.1)
    for index in 0...6 {
      let x = 48 + Double(index) * 44
      if index == 3 { airwayGoblet(x, step: step, t: t) } else {
        oval(x - 20, 244, x + 20, 305, top: 230, bottom: 302, from: 0xC4E5E7, to: 0x79AAB8, border: AirwayInk.bend)
        oval(x - 8, 277, x + 8, 290, fill: 0xA9B5DB, border: Self.violet)
        for fiber in -2...2 { airwayCilium(x + Double(fiber) * 6, 246, column: index, fiber: fiber, step: step, t: t) }
      }
    }
    var clipped = context
    clipped.clip(to: Path(CGRect(x: 25, y: 181, width: 310, height: 40)))
    let dust = copy(clipped), drift = GalaxySSIHealthAtlasAirwayMotion.surfaceTravel(step: step, fraction: t) * 288
    for i in 0...2 {
      let descent = GalaxySSIHealthAtlasAirwayMotion.fall(step: step, fraction: t, index: i)
      let x = 50 + Double(i) * 32 + drift + 4 * wave(descent * 0.5), y = 184 + 25 * descent + Double(i) * 3
      dust.disc(x, y, 4 - Double(i) * 0.4, AirwayInk.dust, border: Self.cream)
    }
    if step == 1 { label("airway_goblet", 181, 319, 140) } else {
      label("airway_cilia", 45, 319, 50); line(34, 304, 29, 239, Self.teal, 1)
      label("airway_mucus", 268, 319, 114); line(324, 310, 331, 215, Self.teal, 1)
    }
  }
  private func airwayGoblet(_ x: Double, step: Int, t: Double) {
    let shape = Path { p in
      p.move(to: CGPoint(x: x - 17, y: 246))
      p.addCurve(to: CGPoint(x: x - 5, y: 290), control1: CGPoint(x: x - 21, y: 263), control2: CGPoint(x: x - 3, y: 271))
      p.addQuadCurve(to: CGPoint(x: x + 7, y: 301), control: CGPoint(x: x - 4, y: 304))
      p.addCurve(to: CGPoint(x: x + 17, y: 248), control1: CGPoint(x: x + 11, y: 285), control2: CGPoint(x: x + 4, y: 274))
      p.addQuadCurve(to: CGPoint(x: x - 17, y: 246), control: CGPoint(x: x + 2, y: 241)); p.closeSubpath()
    }
    fill(shape, 0xB0D6BB); stroke(shape, Self.teal, 1.2); disc(x + 2, 288, 5, Self.violet, border: Self.cream)
    for i in -1...1 {
      let upward = step == 1 ? GalaxySSIHealthAtlasAirwayMotion.secretion(t, index: i) : 0
      disc(x + 7 * Double(i) + 7 * upward, 257 - 51 * upward + 2 * Double(i), 4, 0x69A68F, border: Self.cream)
    }
  }
  private func airwayCilium(_ x: Double, _ y: Double, column: Int, fiber: Int, step: Int, t: Double) {
    let beat = GalaxySSIHealthAtlasAirwayMotion.ciliaryBeat(step: step, fraction: t, column: column, fiber: fiber)
    let shape = Path { p in
      p.move(to: CGPoint(x: x, y: y))
      p.addCurve(to: CGPoint(x: x + beat, y: y - 25 + abs(beat) * 0.20), control1: CGPoint(x: x + beat * 0.2, y: y - 9), control2: CGPoint(x: x + beat, y: y - 14))
    }
    stroke(shape, Self.teal, 1.6)
  }
}
