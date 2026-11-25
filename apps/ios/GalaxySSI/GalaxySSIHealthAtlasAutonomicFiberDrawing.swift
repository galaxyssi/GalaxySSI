import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func autonomicFiber(_ fiber: GalaxySSIHealthAtlasAutonomicRoutes.Fiber, _ color: UInt32, first: Bool) {
    let width = first ? 3.5 : 2.15
    stroke(fiber.path, Self.cream, width + 2.7); stroke(fiber.path, color, width)
  }
  func autonomicSegment(_ fiber: GalaxySSIHealthAtlasAutonomicRoutes.Fiber, _ fraction: Double, _ color: UInt32) {
    guard fraction.isFinite, fraction > 0 else { return }
    stroke(fiber.path.trimmedPath(from: max(0, fraction - 0.18), to: fraction), color, 5.1)
    if fraction < 1 { at(fiber.route, fraction) { x, y in disc(x, y, 3.9, color, border: Self.cream) } }
  }
  func autonomicGanglion(_ x: Double, _ y: Double, _ color: UInt32, _ activity: Double) {
    if activity > 0 {
      let radius = 8 + 5 * activity
      stroke(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)), color, 1.25)
    }
    oval(x - 7, y - 8, x + 7, y + 8, fill: Self.cream, border: color)
    disc(x - 2.1, y - 2.2, 1.75, color)
    disc(x + 1.9, y + 2.1, 2.25 + activity, color)
  }
  func autonomicTarget(_ activity: Double) {
    let x = GalaxySSIHealthAtlasAutonomicRoutes.saX, y = GalaxySSIHealthAtlasAutonomicRoutes.saY
    disc(x, y, 4, 0x795777, border: Self.cream)
    if activity > 0 {
      let radius = 5.8 + 2.8 * activity
      stroke(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)), 0x795777, 1.15)
    }
  }
  func autonomicCompareRoute(_ first: GalaxySSIHealthAtlasAutonomicRoutes.Fiber, _ second: GalaxySSIHealthAtlasAutonomicRoutes.Fiber,
    _ x: Double, _ y: Double, _ color: UInt32, split: Double, phase: Double) {
    autonomicFiber(first, color, first: true); autonomicFiber(second, color, first: false)
    at(first.route, 0) { sx, sy in disc(sx, sy, 4.8, color, border: Self.cream) }
    let handoff = GalaxySSIHealthAtlasAutonomicMotion.Comparison(split: split, phase: phase)
    autonomicGanglion(x, y, color, handoff.handoff)
    at(handoff.onFirst ? first.route : second.route, handoff.fraction) { px, py in disc(px, py, 4.2, color, border: Self.cream) }
  }
  func autonomicBeatMarks(_ t: Double, _ spacing: Double) {
    let left = 52.0, right = 308.0, y = 299.0
    arrow(left, y, right, y, 0x596F73)
    let travel = (t * 2.4).truncatingRemainder(dividingBy: 1) * spacing
    for i in 0...8 {
      let x = left + travel + spacing * Double(i)
      if x < left + 7 || x > right - 13 { continue }
      line(x, y - 11, x, y + 5, 0x795777, 2)
      disc(x, y - 11, 2.4, 0x795777)
    }
  }
}
