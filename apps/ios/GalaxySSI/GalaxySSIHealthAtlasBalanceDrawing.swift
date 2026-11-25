import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func balanceScene(step: Int, t: Double) {
    switch step {
    case 0: labyrinth(t)
    case 1: headTurn(t)
    case 2, 3: balanceHair(otolith: step == 3, t: t)
    default: gaze(t)
    }
  }
  private func labyrinth(_ t: Double) {
    typealias Motion = GalaxySSIHealthAtlasMotionSenseMotion
    let curves = [Motion.posteriorCanal, Motion.canal, Motion.lateralCanal], colors: [UInt32] = [0xAE7892, 0x5A979D, 0x86A883]
    for (i, route) in curves.enumerated() {
      let path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
      stroke(path, Self.blue, 17); stroke(path, colors[i], 13); stroke(path, 0xCCE4D8, 5)
    }
    oval(142, 229, 210, 268, top: 112, bottom: 269, from: 0xD8E8DD, to: 0x88B9B0, border: Self.blue)
    oval(173, 254, 213, 289, top: 115, bottom: 234, from: 0xF7D7C6, to: 0xDEAC9F, border: Self.coral)
    let r = 5 + 3 * wave(t)
    disc(186, 249, r, Self.teal, border: Self.cream); disc(192, 270, r * 0.8, Self.sienna, border: Self.cream)
    label("sense_balance_canals", 230, 63, 165); line(220, 74, 216, 106, Self.blue, 1.25)
    label("sense_balance_otolith", 268, 306, 159); line(241, 288, 209, 272, Self.coral, 1.25)
  }
  private func headTurn(_ t: Double) {
    let turn = GalaxySSIHealthAtlasMotionSenseMotion.headHeading(t), lag = GalaxySSIHealthAtlasMotionSenseMotion.relativeFluid(t)
    var rotated = context; rotated.translateBy(x: 181, y: 175); rotated.rotate(by: .degrees(turn)); rotated.translateBy(x: -181, y: -175)
    let head = copy(rotated)
    head.oval(83, 82, 279, 269, top: 137, bottom: 290, from: 0xD8E9DF, to: 0x8BB7AD, border: Self.teal)
    head.oval(112, 112, 250, 239, fill: Self.cream, border: Self.blue); head.disc(260, 176, 14, Self.sand, border: Self.sienna)
    var fluid = rotated; fluid.translateBy(x: 181, y: 175); fluid.rotate(by: .degrees(lag)); fluid.translateBy(x: -181, y: -175)
    for i in 0...4 {
      let angle = Double(i * 21 + 111) * .pi / 180
      copy(fluid).disc(181 + 82 * cos(angle), 175 + 79 * sin(angle), 4.4, Self.blue, border: Self.cream)
    }
    arrow(113, 65, 203 + 54 * t, 65, Self.coral); arrow(179, 293, 94, 293, Self.blue)
    label("sense_balance_head", 181, 43, 180); label("sense_balance_fluid", 159, 320, 230)
  }
  private func balanceHair(otolith: Bool, t: Double) {
    let deflect = 21 * t
    rounded(37, 116, 323, 274, 22, 0xE0EEE8)
    if otolith {
      rounded(65 + deflect, 132, 265 + deflect, 152, 8, Self.sand)
      for i in 0...7 { disc(75 + deflect + Double(i) * 25, Double(125 - 3 * (i % 2)), 5, Self.sienna, border: Self.cream) }
    } else {
      var cup = Path(); cup.move(to: CGPoint(x: 119, y: 224))
      cup.addCurve(to: CGPoint(x: 165 + deflect, y: 122), control1: CGPoint(x: 113 + deflect, y: 194), control2: CGPoint(x: 116 + deflect, y: 143))
      cup.addCurve(to: CGPoint(x: 224 + deflect, y: 189), control1: CGPoint(x: 196 + deflect, y: 118), control2: CGPoint(x: 226 + deflect, y: 160))
      cup.addLine(to: CGPoint(x: 218, y: 224)); cup.closeSubpath()
      motionArea(cup, 112, 269, 0xD8E8DD, 0x88B9B0, Self.teal)
    }
    let count = otolith ? 7 : 5, span = otolith ? 27.0 : 23, start = otolith ? 83.0 : 124
    for i in 0..<count {
      let x = start + Double(i) * span
      oval(x - 8.5, 225, x + 8.5, 257, fill: Self.peach, border: Self.coral); disc(x, 244, 3, Self.violet)
      for j in -1...1 {
        let offset = Double(j)
        var hair = Path(); hair.move(to: CGPoint(x: x + offset * 3, y: 225))
        hair.addQuadCurve(to: CGPoint(x: x + offset * 4 + deflect, y: otolith ? 152 : 187 + offset * 5),
          control: CGPoint(x: x + offset * 3, y: 204)); stroke(hair, Self.teal, 1.6)
      }
    }
    arrow(101, 88, 155 + 53 * t, 88, Self.blue)
    label(otolith ? "sense_balance_membrane" : "sense_balance_cupula_label", 168, 60, 175); label("sense_balance_hair", 180, 311, 210)
  }
  private func gaze(_ t: Double) {
    let heading = GalaxySSIHealthAtlasMotionSenseMotion.headHeading(t), look = GalaxySSIHealthAtlasMotionSenseMotion.gazeCounterRotation(t)
    var rotated = context; rotated.translateBy(x: 180, y: 199); rotated.rotate(by: .degrees(heading)); rotated.translateBy(x: -180, y: -199)
    let head = copy(rotated)
    head.oval(104, 131, 256, 284, top: 115, bottom: 234, from: 0xF7D7C6, to: 0xDEAC9F, border: Self.coral)
    head.oval(91, 192, 108, 226, fill: Self.peach, border: Self.coral); head.oval(252, 192, 269, 226, fill: Self.peach, border: Self.coral)
    head.arrow(180, 190, 180, 116, Self.coral)
    for x in [151.0, 209] {
      head.oval(x - 16, 147, x + 16, 172, fill: Self.cream, border: Self.teal)
      var eye = rotated; eye.translateBy(x: x, y: 162); eye.rotate(by: .degrees(look)); eye.translateBy(x: -x, y: -162)
      copy(eye).disc(x, 153, 6, Self.teal); copy(eye).line(x, 147, x, 117, Self.teal, 1.3)
    }
    disc(180, 55, 10, Self.sienna, border: Self.cream); disc(180, 55, 3, Self.cream); label("sense_balance_eye", 181, 324, 232)
  }
}
