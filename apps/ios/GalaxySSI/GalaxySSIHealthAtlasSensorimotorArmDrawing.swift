import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func sensorimotorArm(_ frame: GalaxySSIHealthAtlasSensorimotorMotion.Frame) {
    typealias Geometry = GalaxySSIHealthAtlasSensorimotorGeometry
    var upper = context
    upper.translateBy(x: 41, y: 266)
    upper.rotate(by: .radians(frame.upperAngle))
    let proximal = copy(upper)
    proximal.sensorimotorArea(Geometry.upperArm, -13, 15, 0xFFDECA, 0xE3AB94, Self.coral)
    proximal.sensorimotorArea(Geometry.sleeve, -17, 18, 0xB9D6D1, 0x80A8A2, 0x4D796A)
    proximal.line(23, -12, 25, 12, 0x4D796A, 1)
    var lower = context
    lower.translateBy(x: frame.finger.x, y: frame.finger.y)
    lower.rotate(by: .radians(frame.lowerAngle))
    let distal = copy(lower)
    distal.sensorimotorArea(Geometry.forearm, -13, 15, 0xFFDECA, 0xE3AB94, Self.coral)
    distal.line(-29, 1, -22, 2, 0xC18476, 1)
  }
  func sensorimotorReach(_ progress: Double, dashed: Bool) {
    typealias Motion = GalaxySSIHealthAtlasSensorimotorMotion
    var trace = Path()
    let start = Motion.finger(0)
    trace.move(to: CGPoint(x: start.x, y: start.y))
    for i in 1...20 {
      let p = progress * Double(i) / 20, point = Motion.finger(p)
      trace.addLine(to: CGPoint(x: point.x, y: point.y))
    }
    context.stroke(trace, with: .color(Self.color(0x4D796A)),
      style: StrokeStyle(lineWidth: dashed ? 1.7 : 1.25, lineCap: .round, lineJoin: .round, dash: dashed ? [3.5, 3.5] : [], dashPhase: 0))
    if dashed && progress > 0 {
      let end = Motion.finger(progress)
      disc(end.x, end.y, 3.5, 0x4D796A, border: Self.cream)
    }
  }
}
