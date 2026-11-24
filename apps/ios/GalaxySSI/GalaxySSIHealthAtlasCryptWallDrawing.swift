import SwiftUI

struct GalaxySSIHealthAtlasCryptWallDrawing {
  let context: GraphicsContext
  let language: String
  var art: GalaxySSIHealthAtlasIllustratedDrawing { .init(context: context, language: language) }
  struct Pose {
    let point: CGPoint
    let direction: CGVector
    func at(_ along: Double, _ outward: Double) -> CGPoint {
      CGPoint(x: point.x + direction.dx * along - direction.dy * outward,
        y: point.y + direction.dy * along + direction.dx * outward)
    }
  }
  static let route = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 35, y: 74), commands: [
    .init(kind: .cubic, points: [.init(x: 67, y: 73), .init(x: 95, y: 84), .init(x: 102, y: 121)]),
    .init(kind: .cubic, points: [.init(x: 110, y: 162), .init(x: 101, y: 211), .init(x: 112, y: 248)]),
    .init(kind: .cubic, points: [.init(x: 121, y: 279), .init(x: 147, y: 291), .init(x: 175, y: 289)]),
    .init(kind: .cubic, points: [.init(x: 202, y: 287), .init(x: 227, y: 270), .init(x: 233, y: 239)]),
    .init(kind: .cubic, points: [.init(x: 239, y: 210), .init(x: 224, y: 174), .init(x: 232, y: 142)]),
    .init(kind: .cubic, points: [.init(x: 240, y: 110), .init(x: 269, y: 104), .init(x: 278, y: 75)]),
    .init(kind: .cubic, points: [.init(x: 286, y: 51), .init(x: 298, y: 42), .init(x: 318, y: 44)])])
  static let apical = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
  static let cellSpan = (GalaxySSIHealthAtlasCurveLength.route(route, width: 360, height: 360) ?? 0) / 29
  static func sample(_ slot: Double) -> Pose? {
    guard let value = GalaxySSIHealthAtlasFunctionPath.sample(route, position: min(29, max(0, slot)) / 29, width: 360, height: 360) else { return nil }
    return Pose(point: value.point, direction: value.direction)
  }
  static let boundaries: [Pose] = (0...29).compactMap { sample(Double($0)) }
  static let centers: [Pose] = (0..<29).compactMap { sample(Double($0) + 0.5) }
  static let cells: [Path] = (0..<29).compactMap { index in
    guard boundaries.count == 30, centers.count == 29 else { return nil }
    let a = boundaries[index], b = boundaries[index + 1], middle = centers[index]
    var path = Path(); path.move(to: a.point); path.addLine(to: middle.point); path.addLine(to: b.point)
    path.addLine(to: b.at(0, 20)); path.addLine(to: a.at(0, 20)); path.closeSubpath(); return path
  }
  func atPose(_ pose: Pose) -> Self {
    var local = context; local.translateBy(x: pose.point.x, y: pose.point.y)
    local.rotate(by: .radians(atan2(pose.direction.dy, pose.direction.dx)))
    return Self(context: local, language: language)
  }
  func wall(feature: Int) {
    guard Self.boundaries.count == 30, Self.centers.count == 29, Self.cells.count == 29 else { return }
    art.rounded(21, 24, 339, 326, 16, 0xE8F4F0)
    var lamina = Self.apical
    lamina.addLine(to: CGPoint(x: 332, y: 53)); lamina.addQuadCurve(to: CGPoint(x: 339, y: 73), control: CGPoint(x: 339, y: 57))
    lamina.addLine(to: CGPoint(x: 339, y: 303)); lamina.addQuadCurve(to: CGPoint(x: 318, y: 326), control: CGPoint(x: 339, y: 326))
    lamina.addLine(to: CGPoint(x: 48, y: 326)); lamina.addQuadCurve(to: CGPoint(x: 21, y: 306), control: CGPoint(x: 21, y: 326))
    lamina.addLine(to: CGPoint(x: 21, y: 93)); lamina.addQuadCurve(to: CGPoint(x: 35, y: 74), control: CGPoint(x: 21, y: 78)); lamina.closeSubpath()
    art.fill(lamina, 0xF1DBD5)
    for i in 0...8 { let x = 47 + Double(i % 2) * 11, y = 115 + Double(i) * 21; art.line(x, y, x + 18, y + 7, 0xE1BBB8, 1) }
    for i in 0..<29 {
      let tint: UInt32 = i == feature ? 0xF5D7C4 : i % 4 == 1 ? 0xF2C4B6 : i % 4 == 3 ? 0xF7D7C4 : 0xEFBBAE
      art.fill(Self.cells[i], tint); art.stroke(Self.cells[i], 0xB58489, 0.75)
      if i != feature {
        let local = atPose(Self.centers[i]); local.flatOval(-2.7, 9, 2.7, 16.2, 0xA77792)
        local.art.line(-Self.cellSpan * 0.39, 2, Self.cellSpan * 0.39, 2, 0xFAE6CF, 1.25)
      }
    }
    var basement = Path()
    for (index, pose) in Self.boundaries.enumerated() {
      if index == 0 { basement.move(to: pose.at(0, 20)) } else { basement.addLine(to: pose.at(0, 20)) }
    }
    art.stroke(Self.apical, 0xB38387, 1.05); art.stroke(basement, 0x906272, 1.45)
  }
  func panethBody(active: Bool) {
    var shape = Path(); shape.move(to: CGPoint(x: -5.9, y: 0.6))
    shape.addQuadCurve(to: CGPoint(x: -8.4, y: 13), control: CGPoint(x: -6.2, y: 6))
    shape.addQuadCurve(to: CGPoint(x: 0, y: 19.5), control: CGPoint(x: -10, y: 20))
    shape.addQuadCurve(to: CGPoint(x: 8.4, y: 13), control: CGPoint(x: 10, y: 20))
    shape.addQuadCurve(to: CGPoint(x: 5.9, y: 0.6), control: CGPoint(x: 6.2, y: 6)); shape.closeSubpath()
    art.fill(shape, active ? 0xEFA77C : 0xE6AB95); art.stroke(shape, active ? 0x9F514B : 0xAA7270, 1.2)
    flatOval(-4.4, 12.2, 4.4, 17.8, 0x805675)
  }
  func flatOval(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ tint: UInt32) {
    art.fill(Path(ellipseIn: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)), tint)
  }
  func leader(_ key: String, _ point: CGPoint, _ x2: Double, _ y2: Double, _ labelX: Double, _ width: Double, _ tint: UInt32) {
    art.line(point.x, point.y, x2, y2, tint, 1.15); art.disc(point.x, point.y, 2, tint)
    art.label(key, labelX, y2 - 4, width)
  }
  func ring(_ x: Double, _ y: Double, _ radius: Double, opacity: Double, width: Double, tint: UInt32) {
    var local = context; local.opacity = Double(Int(255 * min(1, max(0, opacity)))) / 255
    GalaxySSIHealthAtlasIllustratedDrawing(context: local, language: language)
      .stroke(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)), tint, width)
  }
  static func ease(_ t: Double, _ start: Double = 0, _ end: Double = 1) -> Double {
    let p = min(1, max(0, (t - start) / (end - start))); return p * p * (3 - 2 * p)
  }
}
