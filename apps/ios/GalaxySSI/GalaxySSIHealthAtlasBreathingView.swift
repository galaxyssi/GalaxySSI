import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasBreathingView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  private typealias Motion = GalaxySSIHealthAtlasBreathingMotion
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  private static let teal = color(0x087A78), gold = color(0x92531D), textInk = color(0x234450)
  var body: some View {
    let motion = Motion(chapter: story.chapter(phase), fraction: story.fraction(phase), phase: phase)
    Canvas { context, size in
      let scale = min(size.width, size.height) / 344
      guard scale > 0 else { return }
      var drawing = context
      drawing.translateBy(x: (size.width - 344 * scale) / 2, y: (size.height - 344 * scale) / 2)
      drawing.scaleBy(x: scale, y: scale)
      drawing.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 344, height: 344), cornerRadius: 8),
        with: .linearGradient(Gradient(colors: [Self.color(0xEAF4F6), Self.color(0xFAF1EE)]),
          startPoint: .zero, endPoint: CGPoint(x: 0, y: 344)))
      if motion.zoom < 1 {
        var layer = drawing; layer.opacity = 1 - motion.zoom
        layer.drawLayer { whole(in: $0, motion: motion) }
      }
      if motion.zoom > 0 {
        var layer = drawing; layer.opacity = motion.zoom
        layer.drawLayer { detail(in: $0, motion: motion) }
      }
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-breathing-art")
  }
  private func whole(in context: GraphicsContext, motion: Motion) {
    var lung = context
    lung.translateBy(x: 172, y: 38)
    lung.scaleBy(x: 1 + 0.077 * motion.expansion, y: 1 + 0.045 * motion.expansion)
    lung.translateBy(x: -172, y: -38)
    lung.draw(lung.resolve(Image("HealthAtlasLungs")), in: CGRect(x: 49, y: 38, width: 246, height: 246))
    for position in motion.airPositions {
      arrow(in: lung, route: Self.toRightLung, position: position, color: Self.teal, reverse: motion.exhales, size: 3)
      // The shared trachea is drawn once; the left branch starts only beyond the split.
      if position > 0.78 {
        arrow(in: lung, route: Self.toLeftLung, position: position, color: Self.teal, reverse: motion.exhales, size: 3)
      }
    }
    let down = motion.expansion * 10
    var diaphragm = Path(); diaphragm.move(to: CGPoint(x: 42, y: 310 + down))
    diaphragm.addCurve(to: CGPoint(x: 302, y: 310 + down),
      control1: CGPoint(x: 109, y: 262 + down * 2.4), control2: CGPoint(x: 235, y: 262 + down * 2.4))
    context.stroke(diaphragm, with: .color(Self.color(0x85445A)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    label(in: context, text: t("muscle"), center: 172, baseline: 331, size: 12)
    label(in: context, text: t(motion.exhales ? "air_out" : "air_in"), center: 172, baseline: 23, size: 13)
  }
  private func detail(in context: GraphicsContext, motion: Motion) {
    var art = context; art.translateBy(x: motion.detailX, y: motion.detailY)
    art.scaleBy(x: motion.detailSpan / 1254, y: motion.detailSpan / 1254)
    art.draw(art.resolve(Image("HealthAtlasAlveolus")), in: CGRect(x: 0, y: 0, width: 1254, height: 1254))
    for t in motion.bloodPositions {
      guard let sample = Self.sample(Self.blood, position: t) else { continue }
      var cell = art; cell.translateBy(x: sample.point.x, y: sample.point.y)
      cell.rotate(by: .radians(atan2(sample.direction.dy, sample.direction.dx)))
      let oval = Path(ellipseIn: CGRect(x: -35, y: -17, width: 70, height: 34))
      cell.fill(oval, with: .color(Self.color(t < 0.42 ? 0xA64455 : 0xC55455)))
      cell.stroke(oval, with: .color(Self.color(0xF5A795)), lineWidth: 4)
      var line = Path(); line.move(to: CGPoint(x: -13, y: 0)); line.addLine(to: CGPoint(x: 13, y: 0))
      cell.stroke(line, with: .color(Self.color(0xF5A795)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
    }
    for t in motion.diffusionPositions {
      arrow(in: art, route: Self.oxygen, position: GalaxySSIHealthAtlasGasExchange.position(.oxygen, phase: t),
        color: Self.teal, reverse: false, size: 17)
      arrow(in: art, route: Self.carbon, position: GalaxySSIHealthAtlasGasExchange.position(.carbon, phase: t),
        color: Self.gold, reverse: true, size: 17)
    }
    if motion.zoom > 0.8 {
      label(in: context, text: t("alveolar_air"), center: 162, baseline: 158, size: 13)
      legend(in: context, center: 87, text: t("oxygen"), color: Self.teal)
      legend(in: context, center: 252, text: t("carbon"), color: Self.gold)
    }
  }
  private func arrow(in context: GraphicsContext, route: Route, position: Double, color: Color, reverse: Bool, size: Double) {
    guard let sample = Self.sample(route, position: position) else { return }
    let x = sample.point.x, y = sample.point.y
    let dx = sample.direction.dx * (reverse ? -1 : 1), dy = sample.direction.dy * (reverse ? -1 : 1)
    var glyph = Path()
    glyph.move(to: CGPoint(x: x - (dx - dy) * size, y: y - (dy + dx) * size))
    glyph.addLine(to: CGPoint(x: x + dx * size, y: y + dy * size))
    glyph.addLine(to: CGPoint(x: x - (dx + dy) * size, y: y - (dy - dx) * size))
    context.stroke(glyph, with: .color(.white), style: StrokeStyle(lineWidth: size * 1.25, lineCap: .round, lineJoin: .round))
    context.stroke(glyph, with: .color(color), style: StrokeStyle(lineWidth: size * 0.66, lineCap: .round, lineJoin: .round))
  }
  struct Sample { let point: CGPoint; let direction: CGVector }
  static func sample(_ route: Route, position: Double) -> Sample? {
    // This source blood path has nine curves, unlike the four-command structure annotations.
    guard position.isFinite, (0...1).contains(position), route.start.fits(width: 1254, height: 1254),
      !route.commands.isEmpty, route.commands.count <= 16,
      route.commands.allSatisfy({ $0.fits(width: 1254, height: 1254) }) else { return nil }
    let start = CGPoint(x: route.start.x, y: route.start.y)
    var point = start, delta = CGVector.zero
    for control in route.commands[0].points {
      delta = CGVector(dx: control.x - start.x, dy: control.y - start.y)
      if hypot(delta.dx, delta.dy) > 1e-12 { break }
    }
    let path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 1254, height: 1254)
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
  private func legend(in context: GraphicsContext, center: Double, text: String, color: Color) {
    let width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 11.5)]).width
    let x = center - (width + 13) / 2 + 4
    context.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: 320.5, width: 7, height: 7)), with: .color(color))
    label(in: context, text: text, center: center + 6, baseline: 328, size: 11.5)
  }
  private func label(in context: GraphicsContext, text: String, center: Double, baseline: Double, size: Double) {
    let font = UIFont.systemFont(ofSize: size), width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size)]).width
    context.draw(Text(verbatim: text).font(.system(size: size)).foregroundColor(Self.textInk),
      at: CGPoint(x: center - width / 2, y: baseline - font.ascender), anchor: .topLeading)
  }
  private static func route(_ x: Double, _ y: Double, _ controls: [Double]...) -> Route {
    .init(start: .init(x: x, y: y), commands: controls.map { c in
      .init(kind: c.count == 2 ? .line : .cubic, points: stride(from: 0, to: c.count, by: 2).map { .init(x: c[$0], y: c[$0 + 1]) })
    })
  }
  static let toRightLung = route(172, 43, [172,133], [172,143,159,148,151,158])
  static let toLeftLung = route(172, 43, [172,133], [172,143,185,148,193,158])
  static let blood = route(115, 103, [183,206,212,261,171,351], [147,415,134,484,126,548], [98,593,79,638,113,701], [155,768,122,812,157,871], [183,931,253,944,293,958], [365,971,390,1037,476,1081], [547,1122,610,1096,678,1053], [750,1012,804,982,866,1026], [945,1093,1059,1072,1160,1172])
  static let oxygen = route(482, 817, [445,866,422,941,411,1003], [395,1064])
  static let carbon = route(625, 819, [642,891,671,967,702,1011], [724,1052])
  private static func color(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasFunctionText.get("health_atlas_breathe_" + key, language) }
}
