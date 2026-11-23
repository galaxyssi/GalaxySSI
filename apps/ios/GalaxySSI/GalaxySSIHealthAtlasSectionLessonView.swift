import SwiftUI

struct GalaxySSIHealthAtlasSectionLessonView: View {
  let lesson: GalaxySSIHealthAtlasSectionLesson
  let phase: Double
  let stages: [String]
  let language: String
  private static let rim = Color(red: 249/255, green: 252/255, blue: 249/255)
  private static let highlight = Color(red: 23/255, green: 106/255, blue: 90/255)
  private static let flowColor = Color(red: 40/255, green: 95/255, blue: 130/255)
  var body: some View {
    if let selected = GalaxySSIHealthAtlasSectionLesson.Phase(phase), let feature = lesson.feature(stage: selected.stage), stages.count == 4 {
      Canvas { context, size in
        var drawing = context
        let scale = min(size.width / 360, size.height / 280)
        drawing.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 280 * scale) / 2)
        drawing.scaleBy(x: scale, y: scale)
        let picture = drawing.resolve(Image(lesson.plate.asset))
        drawing.draw(picture, in: CGRect(x: 0, y: 0, width: 360, height: 280))
        let radius = selected.radius(hasRoute: !lesson.routes.isEmpty)
        let x = feature.marker.x * 360, y = feature.marker.y * 280
        let ring = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        drawing.stroke(ring, with: .color(Self.rim), lineWidth: 5)
        drawing.stroke(ring, with: .color(Self.highlight), lineWidth: 2.6)
        if let route = lesson.route(stage: selected.stage), let flow = Self.flow(route, fraction: selected.fraction) {
          drawing.stroke(flow.trail, with: .color(Color(red: 249/255, green: 252/255, blue: 1).opacity(234.0/255)),
            style: StrokeStyle(lineWidth: 5.6, lineCap: .round))
          drawing.stroke(flow.trail, with: .color(Self.flowColor), style: StrokeStyle(lineWidth: 2.7, lineCap: .round))
          let edge = Color(red: 249/255, green: 252/255, blue: 1)
          drawing.fill(flow.tip, with: .color(edge))
          drawing.stroke(flow.tip, with: .color(edge), style: StrokeStyle(lineWidth: 2.6, lineJoin: .round))
          drawing.fill(flow.tip, with: .color(Self.flowColor))
        }
      }.aspectRatio(360.0 / 280, contentMode: .fit).frame(maxHeight: 226)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GalaxySSIHealthAtlasText.get(feature.title, language) + ". " +
          GalaxySSIHealthAtlasText.get(stages[selected.stage], language))
        .accessibilityIdentifier("atlas-section-diagram")
    }
  }
  struct Flow {
    let trail: Path
    let point: CGPoint
    let direction: CGVector
    let tip: Path
  }
  static func flow(_ route: GalaxySSIHealthAtlasSectionLesson.Route, fraction: Double) -> Flow? {
    guard route.valid, fraction.isFinite, (0...1).contains(fraction), let first = route.commands.first else { return nil }
    let start = CGPoint(x: route.start.x, y: route.start.y)
    func tangent(to end: CGPoint, from candidates: [CGPoint]) -> CGVector {
      for candidate in candidates {
        let delta = CGVector(dx: end.x - candidate.x, dy: end.y - candidate.y)
        if hypot(delta.dx, delta.dy) > 1e-12 { return delta }
      }
      return .zero
    }
    // The endpoint control polygon gives the analytic Bezier tangent, including at rewind.
    var delta = CGVector.zero
    for control in first.points {
      delta = tangent(to: CGPoint(x: control.x, y: control.y), from: [start])
      if hypot(delta.dx, delta.dy) > 1e-12 { break }
    }
    let trail = fraction == 0 ? Path() : path(route).trimmedPath(from: 0, to: CGFloat(fraction))
    var point = start
    trail.cgPath.applyWithBlock { pointer in
      let element = pointer.pointee
      switch element.type {
      case .moveToPoint: point = element.points[0]
      case .addLineToPoint:
        delta = tangent(to: element.points[0], from: [point]); point = element.points[0]
      case .addQuadCurveToPoint:
        delta = tangent(to: element.points[1], from: [element.points[0], point]); point = element.points[1]
      case .addCurveToPoint:
        delta = tangent(to: element.points[2], from: [element.points[1], element.points[0], point]); point = element.points[2]
      case .closeSubpath: break
      @unknown default: break
      }
    }
    let length = hypot(delta.dx, delta.dy)
    guard length > 1e-12 else { return nil }
    let dx = delta.dx / length, dy = delta.dy / length, x = point.x, y = point.y
    var tip = Path()
    tip.move(to: CGPoint(x: x + dx * 6.5, y: y + dy * 6.5))
    tip.addLine(to: CGPoint(x: x - dx * 5.5 - dy * 4.3, y: y - dy * 5.5 + dx * 4.3))
    tip.addLine(to: CGPoint(x: x - dx * 5.5 + dy * 4.3, y: y - dy * 5.5 - dx * 4.3))
    tip.closeSubpath()
    return Flow(trail: trail, point: point, direction: CGVector(dx: dx, dy: dy), tip: tip)
  }
  static func path(_ route: GalaxySSIHealthAtlasSectionLesson.Route) -> Path {
    var path = Path(); path.move(to: CGPoint(x: route.start.x, y: route.start.y))
    for command in route.commands {
      guard command.valid else { continue }
      let points = command.points.map { CGPoint(x: $0.x, y: $0.y) }
      switch command.kind {
      case .line: path.addLine(to: points[0])
      case .quad: path.addQuadCurve(to: points[1], control: points[0])
      case .cubic: path.addCurve(to: points[2], control1: points[0], control2: points[1])
      }
    }
    return path
  }
}

typealias GalaxySSIHealthAtlasLymphLessonView = GalaxySSIHealthAtlasSectionLessonView
