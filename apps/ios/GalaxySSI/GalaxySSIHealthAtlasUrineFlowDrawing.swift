import SwiftUI

private typealias UrineMotion = GalaxySSIHealthAtlasUrineMotion
private typealias UrineShapes = GalaxySSIHealthAtlasUrineShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func urinePeristalsis(_ t: Double) {
    guard let channel = UrineShapes.ureterChannel else { return }
    let front = UrineMotion.front(t), pinch = front - 0.16
    urinePassage(channel) { UrineMotion.ureterRadius($0, time: t) }
    urinePulse(channel.route, front: front + 0.05, length: 0.10, width: 13)
    let i = min(64, max(0, Int((pinch * 64).rounded()))), sample = channel.samples[i]
    let x = Double(sample.point.x), y = Double(sample.point.y), nx = -Double(sample.direction.dy), ny = Double(sample.direction.dx)
    for side in [-1.0, 1.0] { arrow(x + side * nx * 34, y + side * ny * 34, x + side * nx * 16, y + side * ny * 16, Self.violet) }
    urineCallout("urine_route_story_ureter", 56, 42, 96, 43, 94)
    label("urine_route_story_contraction", 239, 55, 168); line(151, 50, 164, 50, Self.violet, 2.4)
    arrow(126, 299, 233, 299, Self.teal); label("urine_route_story_to_bladder", 180, 322, 180)
  }
  func urineJunction(_ t: Double) {
    guard let channel = UrineShapes.tunnelChannel else { return }
    rounded(20, 189, 340, 280, 9, 0xDFECE8)
    fill(UrineShapes.junctionWall, Self.peach); stroke(UrineShapes.junctionWall, Self.coral, 1.4)
    for y in stride(from: 122, through: 181, by: 12) {
      var trace = Path(); trace.move(to: CGPoint(x: 24, y: Double(y)))
      trace.addCurve(to: CGPoint(x: 336, y: Double(y + 47)), control1: CGPoint(x: 131, y: Double(y + 4)), control2: CGPoint(x: 223, y: Double(y + 33)))
      stroke(trace, 0xD99897, 1.2)
    }
    let front = UrineMotion.junctionFront(t)
    urinePassage(channel) { UrineMotion.tunnelRadius($0, time: t) }
    urinePulse(channel.route, front: front, length: 0.11, width: 7)
    urinePulse(UrineMotion.junctionExit, front: (front - 1) * 5.4, length: 0.35, width: 5)
    urineCallout("urine_route_story_oblique_tunnel", 154, 51, 150, 158, 151)
    urineCallout("urine_route_story_bladder_wall", 279, 101, 139, 300, 182)
    label("urine_route_story_bladder_interior", 180, 306, 195)
  }
  func urineReservoir(_ t: Double, emptying: Bool) {
    guard let channel = UrineShapes.outletChannel else { return }
    let frame = UrineMotion.Reservoir(time: t, emptying: emptying)
    urinePassage(channel) { frame.outletRadius($0) }
    let shape = UrineShapes.bladder(half: frame.half, top: frame.dome, base: 260, neck: 13)
    gradient(shape, 70, 265, 0xF8DDD4, 0xDEA1A9); stroke(shape, Self.coral, 1.6)
    let lumen = UrineShapes.bladder(half: frame.half - 11, top: frame.dome + 11, base: 258, neck: 5 + 2 * frame.open)
    fill(lumen, Self.cream)
    var liquid = context; liquid.clip(to: lumen)
    let art = copy(liquid)
    art.gradient(Path(CGRect(x: 45, y: frame.level, width: 270, height: 262 - frame.level)), 105, 262, 0xFFE7A7, 0xE7B568)
    art.line(45, frame.level, 315, frame.level, 0xCA974B, 1.5); stroke(lumen, 0xBD8186, 1.35)
    let inlet = GalaxySSIHealthAtlasSectionLessonView.path(UrineMotion.inlet, width: 360, height: 360)
    for side in 0...1 {
      var local = context
      if side == 1 { local.translateBy(x: 360, y: 0); local.scaleBy(x: -1, y: 1) }
      let entry = copy(local)
      entry.stroke(inlet, Self.coral, 13); entry.stroke(inlet, 0xF7D9C4, 10); entry.stroke(inlet, Self.cream, 4)
      if !emptying { entry.urinePulse(UrineMotion.inlet, front: (t * 2.1 + Double(side) * 0.48).truncatingRemainder(dividingBy: 1.2), length: 0.2, width: 4.2) }
    }
    if emptying && frame.open > 0.8 && frame.drain < 1 {
      urinePulse(channel.route, front: ((t - 0.14) * 4).truncatingRemainder(dividingBy: 1.23), length: 0.28, width: 6 * frame.open, from: 0.13)
    }
    urineCallout("urine_route_story_bladder", 180, 43, 120, 180, frame.dome + 5)
    urineCallout("urine_route_story_ureters", 37, 144, 60, 50, 169)
    urineCallout("urine_route_story_urethra", 271, 306, 99, 187, 320)
    urineCallout("urine_route_story_outlet", 75, 269, 136, 169, 283)
  }
}
