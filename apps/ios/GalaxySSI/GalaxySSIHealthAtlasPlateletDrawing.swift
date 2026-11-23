import SwiftUI

private typealias PlateletMotion = GalaxySSIHealthAtlasPlateletMotion
private typealias PlateletShapes = GalaxySSIHealthAtlasPlateletShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func plateletScene(step: Int, t: Double) {
    plateletVessel(focus: step == 0 ? wave(t * 0.5) : 0)
    plateletRedCell(64, 151, -21); plateletRedCell(211, 130, 14); plateletRedCell(301, 194, -17)
    plateletCell(57, 195, 15, activation: 0, size: 0.74); plateletCell(289, 164, 24, activation: 0, size: 0.70)
    plateletArriving(PlateletMotion.anchor, fraction: PlateletMotion.attached(step: step, phase: t), activation: PlateletMotion.active(step: step, phase: t))
    if step == 2 { plateletSignals(spread: PlateletMotion.ease((t - 0.16) / 0.76), visibility: 1) }
    if step == 3 { plateletSignals(spread: 1, visibility: 1 - PlateletMotion.ease(t / 0.42)) }
    for recruit in PlateletMotion.recruits {
      let joined = PlateletMotion.joined(step: step, phase: t, delay: recruit.delay)
      plateletArriving(recruit, fraction: joined, activation: PlateletMotion.ease(joined / 0.7))
    }
    if step == 4 { plateletFibrin(t) }
    plateletAnnotations(step)
  }
  private func plateletVessel(focus: Double) {
    gradient(Path(roundedRect: CGRect(x: 24, y: 88, width: 312, height: 147), cornerRadius: 15), 94, 234, 0xFBFFFC, 0xDCEEEA)
    plateletWall(PlateletShapes.topWall); plateletLowerWall(focus)
    var mirror = context; mirror.translateBy(x: 360, y: 0); mirror.scaleBy(x: -1, y: 1)
    copy(mirror).plateletLowerWall(focus)
    for i in 0...7 { plateletLiningCell(46 + 38 * Double(i), 105) }
    line(87, 62, 87, 98, PlateletShapes.wall, 1.1); label("platelet_vessel_lining", 87, 55, 124)
    arrow(245, 66, 299, 66, PlateletShapes.fiber); label("platelet_blood_flow", 272, 55, 106)
  }
  private func plateletWall(_ shape: Path) {
    gradient(shape, 80, 270, 0xF3D7D7, 0xE8B6B9); stroke(shape, PlateletShapes.wall, 1.2)
  }
  private func plateletLowerWall(_ focus: Double) {
    plateletWall(PlateletShapes.lowerWall); line(37, 251, 149, 251, 0xDCA2A8, 1.3)
    for i in 0...2 { plateletLiningCell(50 + 39 * Double(i), 225) }
    stroke(PlateletShapes.exposedEdge, 0xF4D6AA, 4 + 3 * max(0, focus)); stroke(PlateletShapes.exposedEdge, 0xAE7C51, 1.3)
  }
  private func plateletLiningCell(_ x: Double, _ y: Double) {
    oval(x - 16, y - 4, x + 16, y + 4, fill: 0xF4C8CF, border: PlateletShapes.lining)
    oval(x - 3, y - 1.7, x + 3, y + 1.7, fill: PlateletShapes.lining, border: PlateletShapes.lining)
  }
  private func plateletRedCell(_ x: Double, _ y: Double, _ angle: Double) {
    var local = context; local.translateBy(x: x, y: y); local.rotate(by: .degrees(angle))
    let art = copy(local)
    art.oval(-18, -9, 18, 9, fill: 0xE7AAAD, border: 0xBD7E8B); art.oval(-8, -3.8, 8, 3.8, fill: 0xF6C8C7, border: 0xDC9DA5)
  }
  private func plateletArriving(_ arrival: PlateletMotion.Arrival, fraction: Double, activation: Double) {
    let pose = PlateletMotion.pose(arrival, fraction: fraction)
    plateletCell(pose.x, pose.y, pose.angle, activation: activation)
  }
  private func plateletCell(_ x: Double, _ y: Double, _ angle: Double, activation: Double, size: Double = 1) {
    var local = context; local.translateBy(x: x, y: y); local.rotate(by: .degrees(angle)); local.scaleBy(x: size, y: size)
    let art = copy(local), points = PlateletMotion.outline(activation: activation)
    var outline = Path()
    outline.move(to: CGPoint(x: (points[13].x + points[0].x) * 0.5, y: (points[13].y + points[0].y) * 0.5))
    for i in points.indices {
      let next = points[(i + 1) % points.count], p = points[i]
      outline.addQuadCurve(to: CGPoint(x: (p.x + next.x) * 0.5, y: (p.y + next.y) * 0.5), control: CGPoint(x: p.x, y: p.y))
    }
    outline.closeSubpath(); art.fill(outline, PlateletShapes.plateletFill); art.stroke(outline, PlateletShapes.platelet, 1.35)
    art.disc(-4, -1.5, 1.65, Self.cream); art.disc(3.5, 1.5, 1.3, PlateletShapes.platelet)
  }
  private func plateletSignals(spread: Double, visibility: Double) {
    guard spread > 0, visibility > 0 else { return }
    for i in 0...3 {
      let f = PlateletMotion.ease(spread * 1.28 - Double(i) * 0.09)
      if f > 0 {
        let endX = 141 + Double(i) * 14
        disc(PlateletMotion.mix(166, endX, f), 221 - Double(36 + (i % 2) * 8) * f, (2.6 + 0.6 * f) * visibility, PlateletShapes.signal)
      }
    }
  }
  private func plateletFibrin(_ t: Double) {
    for (i, strand) in PlateletMotion.strands.enumerated() {
      let f = PlateletMotion.strandFraction(t, index: i)
      guard f > 0 else { continue }
      let path = GalaxySSIHealthAtlasSectionLessonView.path(strand, width: 360, height: 360).trimmedPath(from: 0, to: CGFloat(f))
      stroke(path, 0xEDF8EE, 4); stroke(path, PlateletShapes.fiber, 1.75)
    }
  }
  private func plateletAnnotations(_ step: Int) {
    switch step {
    case 0:
      line(180, 260, 180, 296, PlateletShapes.wall, 1.1); label("platelet_exposed_gap", 180, 317, 150)
    case 1, 2:
      let x = step == 1 ? 180.0 : 108
      plateletCell(x, 295, 0, activation: step == 1 ? 0 : 1, size: 0.78); label("platelet_fragment", x, 319, 118)
      if step == 2 {
        disc(244, 296, 2.6, PlateletShapes.signal); disc(252, 290, 2.6, PlateletShapes.signal); disc(260, 296, 2.6, PlateletShapes.signal)
        label("platelet_signals", 252, 319, 118)
      }
    case 3, 4:
      plateletCell(102, 296, -18, activation: 1, size: 0.61); plateletCell(114, 292, 18, activation: 1, size: 0.61)
      label("platelet_plug", 108, 319, 118)
      if step == 4 {
        line(240, 297, 264, 291, PlateletShapes.fiber, 1.75); line(244, 289, 260, 299, PlateletShapes.fiber, 1.75)
        label("platelet_fibrin_mesh", 252, 319, 118)
      }
    default: break
    }
  }
}
