import SwiftUI

struct GalaxySSIHealthAtlasSectionLessonView: View {
  let lesson: GalaxySSIHealthAtlasSectionLesson
  let phase: Double
  let stages: [String]
  let language: String
  private static let rim = Color(red: 249/255, green: 252/255, blue: 249/255)
  private static let highlight = Color(red: 23/255, green: 106/255, blue: 90/255)
  private static let flow = Color(red: 33/255, green: 86/255, blue: 117/255)
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
        if let route = lesson.route(stage: selected.stage) {
          let point = selected.fraction == 0 ? CGPoint(x: route.start.x, y: route.start.y) :
            Self.path(route).trimmedPath(from: 0, to: CGFloat(selected.fraction)).cgPath.currentPoint
          drawing.fill(Path(ellipseIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)), with: .color(Self.rim))
          drawing.fill(Path(ellipseIn: CGRect(x: point.x - 4.8, y: point.y - 4.8, width: 9.6, height: 9.6)), with: .color(Self.flow))
        }
      }.aspectRatio(360.0 / 280, contentMode: .fit).frame(maxHeight: 226)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GalaxySSIHealthAtlasText.get(feature.title, language) + ". " +
          GalaxySSIHealthAtlasText.get(stages[selected.stage], language))
        .accessibilityIdentifier("atlas-section-diagram")
    }
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
