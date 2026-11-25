import SwiftUI

private typealias CerebellumMotion = GalaxySSIHealthAtlasCerebellumMotion
private typealias CerebellumInk = GalaxySSIHealthAtlasCerebellumShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func cerebellumReach(step: Int, t: Double) {
    let progress = CerebellumMotion.reachProgress(chapter: step, phase: t), deviation = step == 4 ? CerebellumMotion.laterDeviation(t) : 1
    let finger = CerebellumMotion.point(progress, deviation: deviation)
    line(144, 78, 345, 78, 0xCDDCD8, 1)
    switch step {
    case 0: cerebellumKey("cerebellum_story_predicted", 246, CerebellumInk.prediction, dashed: true)
    case 4:
      cerebellumKey("cerebellum_story_earlier", 191, CerebellumInk.earlier, dashed: true); cerebellumKey("cerebellum_story_later", 296, Self.teal)
    default:
      cerebellumKey("cerebellum_story_predicted", 191, CerebellumInk.prediction, dashed: true); cerebellumKey("cerebellum_story_actual", 296, Self.teal)
    }
    line(318, 118, 318, 140, CerebellumInk.guide, 1); label("cerebellum_story_target", 318, 111, 64)
    disc(318, 162, 18, 0xF8EAC7, border: 0xC3A477); disc(318, 162, 11, 0xF2D392, border: Self.sienna); disc(318, 162, 4, Self.cream, border: Self.sienna)
    oval(145, 263, 308, 284, fill: 0xE2EAE1, border: 0xDBE5DC); cerebellumArm(finger)
    line(164, 249, 182, 284, CerebellumInk.guide, 1); disc(164, 249, 1.7, CerebellumInk.guide); label("cerebellum_story_arm", 198, 300, 111)
    cerebellumTrace(1, deviation: step == 4 ? 1 : 0, color: step == 4 ? CerebellumInk.earlier : CerebellumInk.prediction, dashed: true)
    let laterReach = step == 4 && ((t >= 0.18 && t < 0.48) || t >= 0.66)
    if (1...3).contains(step) || laterReach { cerebellumTrace(progress, deviation: deviation, color: Self.teal) }
    let predicted = CerebellumMotion.point(step == 0 ? t : progress, deviation: 0)
    if step == 2 || (step == 3 && progress < 0.85) { line(predicted.x, predicted.y, finger.x, finger.y, CerebellumInk.earlier, 1.25) }
    if step == 0 || step == 2 || (step == 3 && progress < 0.85) { disc(predicted.x, predicted.y, 3.8, Self.cream, border: CerebellumInk.prediction) }
    if step != 0 { disc(finger.x, finger.y, 3.3, Self.teal, border: Self.cream) }
    if step == 1 {
      line(145, 311, 344, 311, 0xCDDCD8, 1)
      cerebellumCue("cerebellum_story_vision", 188, time: t, delay: 0.18, color: CerebellumInk.prediction)
      cerebellumCue("cerebellum_story_position", 295, time: t, delay: 0.29, color: Self.teal)
    }
    if step == 2 { label("cerebellum_story_mismatch", 247, 338, 194) }
  }
  private func cerebellumArm(_ finger: CerebellumMotion.Point) {
    guard let arm = CerebellumMotion.arm(finger) else { return }
    var upper = context; upper.translateBy(x: 164, y: 243); upper.rotate(by: .degrees(arm.upperAngle))
    let art = copy(upper)
    art.oval(1, -13, 91, 13, top: -15, bottom: 18, from: 0xFFE1C6, to: 0xE4AC98, border: Self.coral)
    art.gradient(CerebellumInk.sleeve, -22, 28, 0xC8E4DB, 0x85B3AB); art.stroke(CerebellumInk.sleeve, Self.teal, 1.25)
    var lower = context; lower.translateBy(x: finger.x, y: finger.y); lower.rotate(by: .degrees(arm.lowerAngle))
    let forearm = copy(lower)
    forearm.gradient(CerebellumInk.forearm, -15, 18, 0xFFE1C6, 0xE4AC98); forearm.stroke(CerebellumInk.forearm, Self.coral, 1.25)
    forearm.line(-19, -2, -10, -2, 0xC4847E, 1)
  }
  private func cerebellumTrace(_ progress: Double, deviation: Double, color: UInt32, dashed: Bool = false) {
    guard progress > 0 else { return }
    var trail = Path(); trail.move(to: CGPoint(x: 212, y: 187))
    for i in 1...32 { let p = CerebellumMotion.point(progress * Double(i) / 32, deviation: deviation); trail.addLine(to: CGPoint(x: p.x, y: p.y)) }
    cerebellumLinework(trail, color, dashed: dashed)
  }
  private func cerebellumKey(_ key: String, _ x: Double, _ color: UInt32, dashed: Bool = false) {
    var trail = Path(); trail.move(to: CGPoint(x: x - 13, y: 35)); trail.addLine(to: CGPoint(x: x + 13, y: 35))
    cerebellumLinework(trail, color, dashed: dashed); label(key, x, 59, 102)
  }
  private func cerebellumLinework(_ path: Path, _ color: UInt32, dashed: Bool) {
    context.stroke(path, with: .color(Self.color(color)), style: StrokeStyle(lineWidth: dashed ? 1.7 : 2.4, lineCap: .round, lineJoin: .round, dash: dashed ? [5, 4] : [], dashPhase: 0))
  }
  private func cerebellumCue(_ key: String, _ x: Double, time: Double, delay: Double, color: UInt32) {
    label(key, x, 332, 96); line(x - 24, 343, x + 24, 343, 0xB5CCC4, 1.35)
    if let travel = CerebellumMotion.cueTravel(time, delay: delay) { disc(x - 24 + 48 * travel, 343, 3.5, color, border: Self.cream) }
  }
}
