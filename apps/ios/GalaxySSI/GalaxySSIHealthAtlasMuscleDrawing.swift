import SwiftUI

extension GalaxySSIHealthAtlasMovementDrawing {
  func muscleScene(chapter: Int, t: Double) {
    switch chapter {
    case 0: signal(t)
    case 1: calcium(t)
    case 2: sliding(t)
    default: elbow(extending: chapter == 4, t: t)
    }
  }
  private func muscleFiber() {
    let body = Path(roundedRect: CGRect(x: 21, y: 139, width: 298, height: 145), cornerRadius: 33)
    gradient(body, top: 142, bottom: 282, from: 0xF8CFC1, to: 0xD99589); stroke(body, 0xAC6A67, 1.5)
    for i in 0...15 {
      let x = 38 + 17.5 * Double(i)
      oval(x, 158, 4, 9, 0xF9DFD4); oval(x, 263, 4, 10, 0xEDBCAD)
      line(x, 183, x, 239, 0xC6857C, 0.85)
    }
    for y in stride(from: 178, through: 246, by: 17) { line(30, Double(y), 309, Double(y), 0xC6857C, 1) }
  }
  private func signal(_ t: Double) {
    muscleFiber(); track(Motion.nerve, 0xB8D5DF, 22); track(Motion.nerve, Self.nerveColor, 3)
    oval(177, 132, 19, 10, Self.nerveColor)
    for i in 0...2 { pulse(Motion.nerve, Motion.cycle(t * 1.3 + Double(i) * 0.14), Self.white, 2.9) }
    for i in 0...8 {
      let f = Motion.cycle(t * 1.8 + Double(i) / 9)
      oval(159 + Double(i % 5) * 8.5, 134 + 18 * f, 2.5, 2.5, Self.amber)
    }
    for sign in [-1.0, 1.0] {
      let x = 177 + sign * (15 + 109 * Motion.cycle(t * 1.25))
      line(x - 7, 150, x + 7, 150, Self.teal, 3.2)
    }
    leader(103, 56, 117, 83, "motion_axon", Self.nerveColor)
    leader(265, 112, 193, 148, "motion_ach", Self.amber); label(170, 316, "motion_fiber")
  }
  private func calcium(_ t: Double) {
    muscleFiber(); track(Motion.tubule, Self.white, 16); track(Motion.tubule, Self.nerveColor, 1.8)
    pulse(Motion.tubule, Motion.cycle(t * 1.45), Self.teal, 5)
    for side in [-1.0, 1.0] {
      let x = 177 + side * 35
      oval(x, 201, 11, 35, 0xB6CFCA); oval(x, 201, 5, 26, Self.teal)
      for i in 0...7 {
        let f = Motion.cycle(t * 1.3 + Double(i) / 8)
        oval(x + side * (10 + 43 * f), 176 + Double(i) * 6.6 + Double(i % 2) * f * 16, 3.2, 3.2, Self.amber)
      }
    }
    leader(94, 106, 166, 163, "motion_tubule", Self.nerveColor)
    leader(249, 92, 212, 175, "motion_store", Self.teal); label(170, 316, "motion_ca")
  }
  private func sliding(_ t: Double) {
    let left = 170 - Motion.sarcomereHalfWidth(t), right = 340 - left
    for y in stride(from: 104, through: 168, by: 28) {
      let h = Double(y), start = 170 - Motion.myosinLength / 2
      line(left, h, left + Motion.actinLength, h, Self.teal, 4.2)
      line(right, h, right - Motion.actinLength, h, Self.teal, 4.2)
      line(start, h + 14, 340 - start, h + 14, Self.scarlet, 7)
      for i in 0...8 {
        let x = start + 8 + Double(i) * 13
        line(x, h + 14, x + (i < 4 ? 1 : -1) * (4 + 2 * sin(t * 18 + Double(i))), h + 5, Self.scarlet, 2.5)
      }
    }
    for x in [left, right] { line(x, 89, x, 185, Self.edge, 5); line(x, 194, x, 204, Self.edge, 1.3) }
    line(left, 199, right, 199, Self.edge, 1.3)
    leader(73, 59, left + 32, 104, "motion_actin", Self.teal)
    leader(258, 59, 205, 118, "motion_myosin", Self.scarlet); label(170, 220, "motion_sarcomere")
    crossBridge(t)
  }
  private func elbow(extending: Bool, t: Double) {
    let angle = Motion.elbowAngle(extending: extending, fraction: t), rad = angle * .pi / 180
    let pivotX = 131.0, pivotY = 189.0
    let radiusX = pivotX + 33 * sin(rad) + 7 * cos(rad), radiusY = pivotY + 33 * cos(rad) - 7 * sin(rad)
    let ulnaX = pivotX + 10 * sin(rad) - 10 * cos(rad), ulnaY = pivotY + 10 * cos(rad) + 10 * sin(rad)
    boneBar(132, 62, pivotX, pivotY, 14)
    var forearm = context; forearm.translateBy(x: pivotX, y: pivotY); forearm.rotate(by: .degrees(-angle)); forearm.translateBy(x: -pivotX, y: -pivotY)
    copy(forearm).boneBar(121, 195, 125, 284, 9); copy(forearm).boneBar(139, 213, 144, 286, 10)
    muscle(149, 64, radiusX, radiusY, 15 + 6 * angle / 96, Self.scarlet)
    muscle(112, 71, ulnaX, ulnaY, 18 - 5 * angle / 96, Self.purple)
    leader(251, 75, 157, 110, "motion_biceps", Self.scarlet); leader(56, 113, 106, 120, "motion_triceps", Self.purple)
    leader(54, 212, pivotX - 3, pivotY + 3, "motion_joint", Self.nerveColor)
    leader(260, 238, radiusX, radiusY, "motion_tendon", Self.edge)
    if extending { label(170, 319, "motion_reuptake") }
  }
  private func boneBar(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ width: Double) {
    let dx = x2 - x1, dy = y2 - y1, length = hypot(dx, dy)
    var local = context; local.translateBy(x: x1, y: y1); local.rotate(by: .radians(-atan2(dx, dy))); local.scaleBy(x: width / 12, y: 1)
    let drawing = copy(local)
    var path = Path(); path.move(to: CGPoint(x: -7, y: -7))
    path.addCurve(to: CGPoint(x: 10, y: -5), control1: CGPoint(x: -3, y: -15), control2: CGPoint(x: 9, y: -14))
    path.addCurve(to: CGPoint(x: 5, y: 22), control1: CGPoint(x: 11, y: 3), control2: CGPoint(x: 6, y: 10))
    path.addCurve(to: CGPoint(x: 7, y: length - 12), control1: CGPoint(x: 3, y: length * 0.47), control2: CGPoint(x: 4, y: length - 28))
    path.addCurve(to: CGPoint(x: 7, y: length + 7), control1: CGPoint(x: 10, y: length - 4), control2: CGPoint(x: 13, y: length + 2))
    path.addCurve(to: CGPoint(x: -11, y: length + 1), control1: CGPoint(x: 1, y: length + 12), control2: CGPoint(x: -10, y: length + 10))
    path.addCurve(to: CGPoint(x: -5, y: length - 32), control1: CGPoint(x: -10, y: length - 7), control2: CGPoint(x: -5, y: length - 20))
    path.addCurve(to: CGPoint(x: -7, y: 7), control1: CGPoint(x: -4, y: length * 0.46), control2: CGPoint(x: -4, y: 19))
    path.addQuadCurve(to: CGPoint(x: -7, y: -7), control: CGPoint(x: -10, y: 0)); path.closeSubpath()
    drawing.horizontalShade(path, 0xBD9675, 0xFDF3DC, 0xD7B898); drawing.stroke(path, Self.edge, 1.3)
    var highlight = Path(); highlight.move(to: CGPoint(x: 0, y: 13))
    highlight.addQuadCurve(to: CGPoint(x: 1, y: length - 11), control: CGPoint(x: -1.5, y: length * 0.58))
    drawing.stroke(highlight, Self.white, 1.2)
  }
  private func muscle(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ width: Double, _ fill: UInt32) {
    let dx = x2 - x1, dy = y2 - y1, length = hypot(dx, dy)
    var local = context; local.translateBy(x: x1, y: y1); local.rotate(by: .radians(-atan2(dx, dy)))
    copy(local).line(0, 0, 0, length, Self.edge, 5.6); copy(local).line(0, 0, 0, length, 0xE8DAC4, 3.8)
    local.scaleBy(x: width / 17, y: 1); let drawing = copy(local)
    var path = Path(); path.move(to: CGPoint(x: 0, y: length * 0.10))
    path.addCurve(to: CGPoint(x: 10, y: length * 0.65), control1: CGPoint(x: 8, y: length * 0.23), control2: CGPoint(x: 18, y: length * 0.46))
    path.addQuadCurve(to: CGPoint(x: 0, y: length * 0.84), control: CGPoint(x: 5, y: length * 0.76))
    path.addCurve(to: CGPoint(x: -10, y: length * 0.30), control1: CGPoint(x: -9, y: length * 0.71), control2: CGPoint(x: -19, y: length * 0.48))
    path.addQuadCurve(to: CGPoint(x: 0, y: length * 0.10), control: CGPoint(x: -5, y: length * 0.21)); path.closeSubpath()
    if fill == Self.scarlet { drawing.horizontalShade(path, 0x923F50, 0xDC9290, 0xA14E5D) }
    else { drawing.horizontalShade(path, 0x66527F, 0xB7A2CB, 0x83628D) }
    drawing.stroke(path, fill, 1.15)
    for i in -3...3 {
      let index = Double(i)
      var fiber = Path(); fiber.move(to: CGPoint(x: index * 0.6, y: length * (0.17 + 0.012 * abs(index))))
      fiber.addCurve(to: CGPoint(x: index * 0.4, y: length * 0.77), control1: CGPoint(x: index * 4.1, y: length * 0.36), control2: CGPoint(x: index * 3.5, y: length * 0.57))
      drawing.stroke(fiber, 0x9FF7D6CF, 0.85)
    }
  }
}
