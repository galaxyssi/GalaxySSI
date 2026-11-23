import SwiftUI

enum GalaxySSIHealthAtlasFunctionPath {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  struct Sample { let point: CGPoint; let direction: CGVector }
  static func sample(_ route: Route, position: Double, width: Double, height: Double) -> Sample? {
    guard position.isFinite, (0...1).contains(position), route.start.fits(width: width, height: height),
      !route.commands.isEmpty, route.commands.count <= 16,
      route.commands.allSatisfy({ $0.fits(width: width, height: height) }) else { return nil }
    let start = CGPoint(x: route.start.x, y: route.start.y)
    var point = start, delta = CGVector.zero
    for control in route.commands[0].points {
      delta = CGVector(dx: control.x - start.x, dy: control.y - start.y)
      if hypot(delta.dx, delta.dy) > 1e-12 { break }
    }
    // Path trimming uses arc length, while each endpoint control polygon gives its tangent.
    let path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: width, height: height)
    let partial = position == 0 ? Path() : path.trimmedPath(from: 0, to: CGFloat(position))
    partial.cgPath.applyWithBlock { element in
      let value = element.pointee
      let end: CGPoint
      let controls: [CGPoint]
      switch value.type {
      case .moveToPoint: point = value.points[0]; return
      case .addLineToPoint: end = value.points[0]; controls = [point]
      case .addQuadCurveToPoint: end = value.points[1]; controls = [value.points[0], point]
      case .addCurveToPoint: end = value.points[2]; controls = [value.points[1], value.points[0], point]
      default: return
      }
      for control in controls {
        delta = CGVector(dx: end.x - control.x, dy: end.y - control.y)
        if hypot(delta.dx, delta.dy) > 1e-12 { break }
      }
      point = end
    }
    let length = hypot(delta.dx, delta.dy)
    guard length > 1e-12 else { return nil }
    return Sample(point: point, direction: CGVector(dx: delta.dx / length, dy: delta.dy / length))
  }
}
