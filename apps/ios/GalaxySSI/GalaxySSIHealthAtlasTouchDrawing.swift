import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func touchScene(step: Int, t: Double) {
    switch step {
    case 0, 1, 4: touchSkin(step: step, t: t)
    case 2: touchChannel(t)
    default: touchFiring(t)
    }
  }
  private func touchSkin(step: Int, t: Double) {
    typealias Motion = GalaxySSIHealthAtlasMotionSenseMotion
    let load = Motion.touchLoad(step: step, time: t), surface = 134.0
    func deflection(_ x: Double) -> Double { Motion.deflection(x, load: load) }
    var dermis = Path(); dermis.move(to: CGPoint(x: 29, y: surface))
    for x in stride(from: 29, through: 331, by: 2) { dermis.addLine(to: CGPoint(x: Double(x), y: surface + deflection(Double(x)))) }
    dermis.addLine(to: CGPoint(x: 331, y: 294)); dermis.addLine(to: CGPoint(x: 29, y: 294)); dermis.closeSubpath()
    motionArea(dermis, 176, 320, 0xF5E2C8, 0xE4C5A8, Self.coral)
    var skin = Path(); skin.move(to: CGPoint(x: 29, y: surface))
    for x in stride(from: 29, through: 331, by: 2) { skin.addLine(to: CGPoint(x: Double(x), y: surface + deflection(Double(x)))) }
    for x in stride(from: 331, through: 29, by: -2) { skin.addLine(to: CGPoint(x: Double(x), y: 192 + 0.47 * deflection(Double(x)))) }
    skin.closeSubpath(); motionArea(skin, 115, 234, 0xF7D7C6, 0xDEAC9F, Self.coral)
    for i in 0...10 {
      let x = Double(43 + i * 27), y = 163 + deflection(x) * 0.77
      oval(x - 10, y - 10, x + 10, y + 12, fill: Self.peach, border: Self.coral); disc(x, y + 2, 2.8, 0xA8757F)
    }
    let objectY = surface + deflection(179) - Motion.touchLift(step: step, time: t)
    oval(117, objectY - 54, 241, objectY, top: 47, bottom: 149, from: 0xFFE9CA, to: 0xDCA78C, border: Self.sienna)
    let nerve = GalaxySSIHealthAtlasSectionLessonView.path(Motion.touchNerve, width: 360, height: 360)
    stroke(nerve, 0x9BBDAC, 10); stroke(nerve, Self.teal, 3)
    let ry = 17 - 4.5 * load
    oval(165, 201 - ry, 193, 201 + ry, top: 137, bottom: 290, from: 0xD8E9DF, to: 0x8BB7AD, border: Self.teal)
    disc(182, 199, 5.5, Self.violet)
    if step != 0 || load > 0.35 {
      let count = step == 4 ? Int(load * 5) : 3
      for i in 0..<count {
        at(Motion.touchNerve, (t * 1.4 + Double(i) * 0.21).truncatingRemainder(dividingBy: 1)) { disc($0, $1, 4.2, Self.blue, border: Self.cream) }
      }
    }
    label("sense_touch_surface", 73, 103, 122); line(73, 113, 73, 134, Self.coral, 1.25)
    label("sense_touch_merkel", 102, 241, 140); line(132, 226, 169, 208, Self.teal, 1.25); label("sense_touch_nerve", 258, 323, 178)
  }
  private func touchChannel(_ t: Double) {
    let load = GalaxySSIHealthAtlasMotionSenseMotion.touchLoad(step: 2, time: t), gap = 11 + 20 * load
    rounded(42, 191, 318, 274, 20, 0xDCEADF)
    for i in 0...13 {
      let x = Double(49 + 20 * i)
      if (127...233).contains(x) { continue }
      for offset in [-6.0, 6.0] { disc(x, 178 + offset, 5.4, Self.peach, border: Self.coral) }
    }
    rounded(127, 153, 179 - gap / 2, 204, 8, 0x7AAEA0); rounded(179 + gap / 2, 153, 233, 204, 8, 0x7AAEA0)
    arrow(138, 141, 138 - 15 * t, 141, Self.coral); arrow(222, 141, 222 + 15 * t, 141, Self.coral)
    for i in 0...3 {
      let dy = GalaxySSIHealthAtlasChemicalSenseMotion.transfer(t, index: i, startsAt: 0.24)
      disc(Double(176 + i % 2 * 9), Double(113 - i * 12) + 132 * dy, 4.2, Self.blue, border: Self.cream)
    }
    label("sense_touch_ions", 284, 97, 132); line(255, 106, 195, 129, Self.blue, 1.25); motionScientificText("PIEZO2", 180, 301)
  }
  private func touchFiring(_ t: Double) {
    let x = 52.0, length = 255.0, end = Int(length * t)
    label("sense_touch_press", 179, 62, 216); label("sense_touch_signal", 179, 200, 207)
    line(x, 142, x + length, 142, 0xBCBCAF, 1.4); line(x, 289, x + length, 289, 0xBCBCAF, 1.4)
    var pressure = Path(); pressure.move(to: CGPoint(x: x, y: 142))
    for i in 0...end { pressure.addLine(to: CGPoint(x: x + Double(i), y: 142 - GalaxySSIHealthAtlasMotionSenseMotion.pressure(sample: i))) }
    stroke(pressure, Self.coral, 2.4)
    var spikes = Path(); spikes.move(to: CGPoint(x: x, y: 289))
    for i in 0...end { spikes.addLine(to: CGPoint(x: x + Double(i), y: GalaxySSIHealthAtlasMotionSenseMotion.spike(sample: i) ? 261 : 289)) }
    stroke(spikes, Self.teal, 1.8)
  }
}
