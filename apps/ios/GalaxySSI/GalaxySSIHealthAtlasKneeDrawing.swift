import SwiftUI

private typealias KneeMotion = GalaxySSIHealthAtlasKneeMotion
private typealias KneeShapes = GalaxySSIHealthAtlasKneeShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func kneeScene(_ pose: GalaxySSIHealthAtlasKneeMotion.Pose, step: Int, t: Double) {
    let angle = -58 * pose.bend, shinAnchor = KneeMotion.local(-23, 32, angle: angle), flexorAnchor = KneeMotion.local(24, 24, angle: angle)
    let patellaX = 143 + pose.bend * 6, patellaY = 175 + pose.bend * 21
    let quad = kneeMuscle(behind: false, activation: pose.extensor), ham = kneeMuscle(behind: true, activation: pose.flexor)
    gradient(KneeShapes.femur, 27, 200, 0xFFF0D6, 0xD7B28B); stroke(KneeShapes.femur, KneeShapes.boneLip, 1.35)
    line(176, 42, 175, 141, 0xB68F6C, 1.3)
    kneeCurve(KneeMotion.curve(150, 185, [160,204,199,192,205,178]), Self.teal, 3.3)
    var local = context; local.translateBy(x: 178, y: 192); local.rotate(by: .degrees(angle))
    let shin = copy(local)
    for bone in [KneeShapes.fibula, KneeShapes.tibia] { shin.gradient(bone, 0, 124, 0xFFECD0, 0xDDBC96); shin.stroke(bone, KneeShapes.boneLip, 1.35) }
    // This local curve includes negative x coordinates; draw it directly rather than a bounded transport track.
    var lip = Path(); lip.move(to: CGPoint(x: -22, y: 11))
    lip.addCurve(to: CGPoint(x: 21, y: 9), control1: CGPoint(x: -16, y: 4), control2: CGPoint(x: 11, y: 3)); shin.stroke(lip, Self.teal, 3)
    shin.line(-4, 47, -1, 114, 0xB68F6C, 1.3)
    kneeCurve(KneeMotion.curve(quad.x, quad.y, [quad.x - 2,quad.y + 12,patellaX - 8,patellaY - 8,patellaX,patellaY]), KneeShapes.quad, 7)
    let quadTrack = KneeMotion.curve(patellaX, patellaY + 4, [patellaX - 2,patellaY + 19,shinAnchor.x - 6,shinAnchor.y - 5,shinAnchor.x,shinAnchor.y])
    kneeCurve(quadTrack, KneeShapes.quad, 6)
    if step == 0 || step >= 2 { kneePulse(quadTrack, (1 - t) * 0.82 + 0.08, step == 3 ? KneeShapes.quad : 0xEFA366) }
    let hamTrack = KneeMotion.curve(ham.x, ham.y, [ham.x + 1,ham.y + 22,flexorAnchor.x + 10,flexorAnchor.y - 16,flexorAnchor.x,flexorAnchor.y])
    kneeCurve(hamTrack, KneeShapes.ham, 5)
    if step == 1 { kneePulse(hamTrack, 1 - t, 0xD39CAE) }
    oval(patellaX - 9, patellaY - 13, patellaX + 9, patellaY + 12, fill: 0xFAE0BB, border: KneeShapes.boneLip)
    label("knee_quadriceps", 60, 58, 102); line(58, 64, 116, 91, KneeShapes.quad, 1.15)
    label("knee_hamstrings", 292, 58, 104); line(281, 64, 227, 90, KneeShapes.ham, 1.15)
    label("knee_patella", 58, 189, 101); line(61, 195, patellaX - 12, patellaY, KneeShapes.boneLip, 1.15)
    let mark = KneeMotion.local(0, 100, angle: angle)
    line(311, 312, mark.x + 9, mark.y, KneeShapes.boneLip, 1.15); label("knee_tibia", 309, 331, 92)
    if step == 1 || step == 3 {
      let before = KneeMotion.local(-18, 99, angle: angle + (step == 1 ? 10 : -10)), after = KneeMotion.local(-18, 99, angle: angle + (step == 1 ? -5 : 5))
      arrow(before.x, before.y, after.x, after.y, step == 1 ? KneeShapes.ham : KneeShapes.quad)
    }
  }
  private func kneeMuscle(behind: Bool, activation: Double) -> KneeMotion.Point {
    let x = behind ? 216.0 : 133, width = 12 + activation * 8, tip = (behind ? 167.0 : 159) - activation * 9, start = x + (behind ? 2 : -4)
    let shape = Path { p in
      p.move(to: CGPoint(x: start, y: 35))
      p.addCurve(to: CGPoint(x: x, y: tip), control1: CGPoint(x: x + width * 1.4, y: 59), control2: CGPoint(x: x + width, y: 120))
      p.addCurve(to: CGPoint(x: start, y: 35), control1: CGPoint(x: x - width, y: 128), control2: CGPoint(x: x - width * 1.4, y: 67)); p.closeSubpath()
    }
    gradient(shape, behind ? 40 : 38, behind ? 170 : 165, behind ? 0xE4BAC7 : 0xF4C0A9, behind ? 0xAB627E : 0xCC765F)
    stroke(shape, behind ? 0x99566F : 0xBF7359, 1.35)
    for i in -1...1 {
      let shift = Double(i) * width / 2
      kneeCurve(KneeMotion.curve(x + 1 + shift * 0.3, 55, [x + shift * 1.3,86,x + shift,tip - 27,x + shift * 0.31,tip - 11]), 0xFFDACB, 1.15)
    }
    return KneeMotion.Point(x: x, y: tip)
  }
  private func kneeCurve(_ route: KneeMotion.Route, _ color: UInt32, _ width: Double) {
    stroke(GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360), color, width)
  }
  private func kneePulse(_ route: KneeMotion.Route, _ t: Double, _ color: UInt32) {
    at(route, t) { x, y in disc(x, y, 3.6, color, border: Self.cream) }
  }
}
