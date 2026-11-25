import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasHeartbeatView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  private typealias Motion = GalaxySSIHealthAtlasBeatMotion
  private static let blue = color(0x286CA0), rose = color(0xAB304C)
  var body: some View {
    let motion = Motion(chapter: story.chapter(phase), fraction: story.fraction(phase))
    GeometryReader { geometry in
      let edge = min(geometry.size.width, geometry.size.height), scale = edge / 344
      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [Self.color(0xE8F2F6), Self.color(0xF8EEEE)], startPoint: .top, endPoint: .bottom))
        GalaxySSIHealthAtlasMeshImage(asset: "HealthAtlasHeartSection", logicalSize: CGSize(width: 1254, height: 1254),
          vertices: motion.mesh, columns: 24, rows: 24)
          .frame(width: 256 * scale, height: 256 * scale).offset(x: 44 * scale, y: 0)
        Canvas { context, _ in
          var drawing = context; drawing.scaleBy(x: scale, y: scale)
          var art = drawing; art.translateBy(x: 44, y: 0); art.scaleBy(x: 256.0 / 1254, y: 256.0 / 1254)
          switch motion.stage {
          case .filling:
            stream(in: art, route: Self.rightFill, color: Self.blue, time: motion.fraction, motion: motion)
            stream(in: art, route: Self.leftFill, color: Self.rose, time: motion.fraction, motion: motion)
          case .atrialSqueeze:
            stream(in: art, route: Self.shortToRight, color: Self.blue, time: motion.fraction, motion: motion)
            stream(in: art, route: Self.shortToLeft, color: Self.rose, time: motion.fraction, motion: motion)
          case .ejection:
            stream(in: art, route: Self.rightOut, color: Self.blue, time: motion.fraction, motion: motion)
            stream(in: art, route: Self.leftOutFront, color: Self.rose, time: motion.fraction, motion: motion)
            stream(in: art, route: Self.leftOutArch, color: Self.rose, time: (motion.fraction - 0.45) / 0.55, motion: motion)
          case .pressureRise, .relaxation: break
          }
          for valve in GalaxySSIHealthAtlasHeartSection.Valve.allCases { gate(in: art, valve: valve, motion: motion) }
          legend(in: drawing, center: 86, baseline: 239, text: t("low"), color: Self.blue)
          legend(in: drawing, center: 258, baseline: 239, text: t("high"), color: Self.rose)
          pressures(in: drawing, stage: motion.stage, fraction: motion.fraction)
        }
      }.frame(width: edge, height: edge).position(x: geometry.size.width / 2, y: geometry.size.height / 2)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-heartbeat-art")
  }
  private func stream(in context: GraphicsContext, route: GalaxySSIHealthAtlasSectionLesson.Route, color: Color, time: Double, motion: Motion) {
    for distance in Motion.streamPositions(time) {
      guard let flow = GalaxySSIHealthAtlasSectionLessonView.flow(route, fraction: distance, width: 1254, height: 1254) else { continue }
      let x = motion.warpedX(flow.point.x, y: flow.point.y), y = motion.warpedY(flow.point.y)
      let dx = flow.direction.dx, dy = flow.direction.dy
      var glyph = Path()
      glyph.move(to: CGPoint(x: x - 14 * dx + 11 * dy, y: y - 14 * dy - 11 * dx))
      glyph.addLine(to: CGPoint(x: x + 7 * dx, y: y + 7 * dy))
      glyph.addLine(to: CGPoint(x: x - 14 * dx - 11 * dy, y: y - 14 * dy + 11 * dx))
      context.stroke(glyph, with: .color(Self.color(0xF8FCFF)), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
      context.stroke(glyph, with: .color(color), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
    }
  }
  private func gate(in context: GraphicsContext, valve: GalaxySSIHealthAtlasHeartSection.Valve, motion: Motion) {
    let open = motion.stage.valveOpenness(valve, fraction: motion.fraction)
    let x = valve.marker.x * 1254, y = valve.marker.y * 1254
    var drawing = context; drawing.translateBy(x: motion.warpedX(x, y: y), y: motion.warpedY(y))
    if valve.openAt(0) != true { drawing.rotate(by: .degrees(180)) }
    drawing.fill(circle(42), with: .color(Self.color(0x263D49).opacity(156.0 / 255)))
    drawing.stroke(circle(43 + motion.emphasis(valve)), with: .color(Self.color(open > 0.1 ? 0x17826B : 0x394D59)), lineWidth: 5)
    let spread = 27 * open, tilt = open * 25
    var glyph = Path(); glyph.move(to: CGPoint(x: -28, y: -10)); glyph.addLine(to: CGPoint(x: -spread, y: 10 + tilt))
    glyph.move(to: CGPoint(x: 28, y: -10)); glyph.addLine(to: CGPoint(x: spread, y: 10 + tilt))
    drawing.stroke(glyph, with: .color(Self.color(0xFFF9E7)), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
  }
  func legend(in context: GraphicsContext, center: Double, baseline: Double, text: String, color: Color) {
    let font = UIFont.systemFont(ofSize: 11.5), width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 11.5)]).width
    let start = center - (width + 13) / 2
    context.draw(Text(verbatim: text).font(.system(size: 11.5)).foregroundColor(Self.color(0x213D4D)),
      at: CGPoint(x: start + 13, y: baseline - font.ascender), anchor: .topLeading)
    context.fill(Path(ellipseIn: CGRect(x: start, y: baseline - 7.5, width: 7, height: 7)), with: .color(color))
  }
  private func circle(_ radius: Double) -> Path { Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)) }
  private static func route(_ x: Double, _ y: Double, _ controls: [Double]...) -> GalaxySSIHealthAtlasSectionLesson.Route {
    .init(start: .init(x: x, y: y), commands: controls.map { c in
      .init(kind: .cubic, points: [.init(x: c[0], y: c[1]), .init(x: c[2], y: c[3]), .init(x: c[4], y: c[5])])
    })
  }
  static let rightFill = route(368, 200, [361,310,352,355,375,441], [387,477,444,506,458,568], [477,635,407,654,451,707], [477,740,523,813,564,913])
  static let leftFill = route(1083, 512, [1024,507,966,488,906,495], [828,507,811,583,837,628], [844,651,874,660,859,690], [841,726,768,819,747,918])
  static let rightOut = route(555, 895, [526,765,567,719,593,611], [608,531,583,465,618,404], [643,359,708,339,782,337])
  static let leftOutFront = route(739, 911, [705,832,700,741,713,661], [719,617,701,571,705,466])
  static let leftOutArch = route(695, 293, [700,235,747,176,793,171], [826,165,816,116,823,69])
  static let shortToRight = route(454, 565, [472,623,415,650,451,707], [469,738,529,817,563,903])
  static let shortToLeft = route(855, 544, [814,590,875,652,860,693], [834,748,765,823,752,908])
  static func color(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
  }
  func t(_ key: String) -> String { GalaxySSIHealthAtlasFunctionText.get("health_atlas_beat_" + key, language) }
}
