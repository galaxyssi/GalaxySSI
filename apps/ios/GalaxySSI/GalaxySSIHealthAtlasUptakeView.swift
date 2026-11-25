import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasUptakeView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  private static let routes: [Path] = [
    route(87, 40, 119, 14, 151, 21, 169, 45), route(171, 98, 170, 114, 142, 113, 127, 114),
    route(123, 124, 132, 126, 138, 133, 138, 165), route(293, 179, 293, 203, 228, 186, 228, 214)
  ]
  var body: some View {
    let motion = GalaxySSIHealthAtlasUptakeMotion(chapter: story.chapter(phase), fraction: story.fraction(phase))
    Canvas { context, size in
      var drawing = context
      let scale = min(size.width, size.height) / 344
      drawing.translateBy(x: (size.width - 344 * scale) / 2, y: (size.height - 344 * scale) / 2)
      drawing.scaleBy(x: scale, y: scale)
      drawing.fill(rounded(0, 0, 344, 344, 8), with: .linearGradient(Gradient(stops: [
        .init(color: Self.color(0xDCEEF7), location: 0), .init(color: Self.color(0xFFF8E8), location: 0.54),
        .init(color: Self.color(0xE4F1F7), location: 1)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 344)))
      bilayer(in: drawing, y: 71)
      bilayer(in: drawing, y: 275, motion: motion)
      if motion.flatten == 0 { vesicle(in: drawing, x: motion.vesicleX, y: motion.vesicleY) }
      receptor(in: drawing, active: motion.bound)
      let insulinPoint = Self.point(on: Self.routes[0], fraction: motion.chapter == 0 ? min(1, motion.fraction / 0.95) : 1,
        start: CGPoint(x: 87, y: 40))
      insulin(in: drawing, point: insulinPoint)
      label(in: drawing, text: t("insulin"), x: 14, y: 48, strong: true)
      label(in: drawing, text: t("receptor"), x: 217, y: 62, strong: true)
      for index in 1...3 {
        signal(in: drawing, path: Self.routes[index], progress: motion.signalProgress(index),
          moving: motion.chapter == index && motion.signalProgress(index) < 1)
      }
      node(in: drawing, text: "IRS", x: 73, y: 103, active: motion.irsActive, accent: 0xB9CCE9)
      if motion.irsActive { dot(in: drawing, x: 124, y: 105, radius: 4, color: 0xDB9F31) }
      transfer(in: drawing, from: 80, to: 160, relay: motion.relay, start: 0.29, finish: 0.57)
      transfer(in: drawing, from: 222, to: 262, relay: motion.relay, start: 0.57, finish: 0.90)
      node(in: drawing, text: "PI3K", x: 111, y: 132, active: motion.relay >= 0.26, accent: 0xB9CCE9)
      node(in: drawing, text: "PIP2", x: 23, y: 157, active: motion.relay >= 0.29, accent: 0xC6CDE9)
      node(in: drawing, text: "PIP3", x: 164, y: 157, active: motion.relay >= 0.57, accent: 0xA9DBE0)
      node(in: drawing, text: "AKT", x: 266, y: 157, active: motion.relay >= 0.90, accent: 0xB8DEC1)
      transporter(in: drawing, motion: motion)
      label(in: drawing, text: "GLUT4", x: motion.transporterX - 54, y: motion.transporterY - 17, strong: true)
      for index in 0...2 {
        let y = 314 - motion.glucoseTravel(index) * 88
        let spread = min(1, max(0, abs(y - 275) / 34)) * 18
        glucose(in: drawing, x: 268 + Double(index - 1) * spread, y: y)
      }
      label(in: drawing, text: t("outside"), x: 14, y: 25)
      label(in: drawing, text: t("inside"), x: 14, y: 92)
      label(in: drawing, text: t("glucose"), x: 14, y: 317)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-uptake-art")
  }
  private func bilayer(in context: GraphicsContext, y: Double, motion: GalaxySSIHealthAtlasUptakeMotion? = nil) {
    var path = Path(); path.move(to: CGPoint(x: 5, y: y))
    if let motion, motion.flatten > 0, motion.radiusY > 0.1 {
      let opening = max(0.5, motion.opening)
      let cy = y - motion.radiusY * cos(opening * 0.017453293)
      let transform = CGAffineTransform(a: 23, b: 0, c: 0, d: motion.radiusY, tx: motion.vesicleX, ty: cy)
      path.addArc(center: .zero, radius: 1, startAngle: .degrees(90 + opening), endAngle: .degrees(450 - opening), clockwise: false, transform: transform)
    }
    path.addLine(to: CGPoint(x: 339, y: y))
    membrane(in: context, path: path)
  }
  private func membrane(in context: GraphicsContext, path: Path) {
    let layers: [(UInt32, Double)] = [(0xB98545,9),(0xF7D589,6.5),(0xFFEDBD,2)]
    for (color, width) in layers { stroke(in: context, path: path, color: color, width: width) }
  }
  private func vesicle(in context: GraphicsContext, x: Double, y: Double) { membrane(in: context, path: circle(x, y, 23)) }
  private func receptor(in context: GraphicsContext, active: Bool) {
    for index in 0...1 {
      let x = 160 + Double(index) * 18
      context.fill(rounded(x - 5, 55, 10, 41, 5), with: .color(Self.color(0x31887F)))
      dot(in: context, x: x, y: 99, radius: 4, color: active ? 0xEBAC43 : 0x568C92)
    }
    let path = Self.route(141, 38, 150, 64, 188, 64, 197, 38)
    context.stroke(path, with: .linearGradient(Gradient(colors: [Self.color(0x9C91D6), Self.color(0x52488A)]),
      startPoint: CGPoint(x: 0, y: 35), endPoint: CGPoint(x: 0, y: 74)), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
  }
  private func insulin(in context: GraphicsContext, point: CGPoint) {
    for index in 0...5 {
      let angle = Double(index) * 1.05, dx = cos(angle) * 7, dy = sin(angle) * 6
      dot(in: context, x: point.x + dx, y: point.y + dy, radius: 4.5, color: 0x357BA9)
      dot(in: context, x: point.x + dx - 1, y: point.y + dy - 1.5, radius: 2.6, color: 0xABD7EA)
    }
  }
  private func transporter(in context: GraphicsContext, motion: GalaxySSIHealthAtlasUptakeMotion) {
    var drawing = context
    drawing.translateBy(x: motion.transporterX, y: motion.transporterY)
    drawing.rotate(by: .degrees(motion.transporterRotation))
    let scale = 0.79 + 0.11 * motion.flatten
    drawing.scaleBy(x: scale, y: scale)
    // Mirror the one-unit overhang outside the source -16...16 gradient interval.
    let gradient = Gradient(stops: [.init(color: Self.mix(1.0 / 32), location: 0),
      .init(color: Self.color(0x237084), location: 1.0 / 34), .init(color: Self.color(0x74C5CB), location: 33.0 / 34),
      .init(color: Self.mix(31.0 / 32), location: 1)])
    drawing.fill(rounded(-17, -13, 34, 29, 8), with: .linearGradient(gradient, startPoint: CGPoint(x: -17, y: 0), endPoint: CGPoint(x: 17, y: 0)))
    drawing.fill(rounded(-4, -15, 8, 32, 3), with: .color(Self.color(0xDFF2EB)))
  }
  private func glucose(in context: GraphicsContext, x: Double, y: Double) {
    var path = Path()
    for index in 0..<6 {
      let angle = (Double(index) + 0.5) * 1.0472, point = CGPoint(x: x + cos(angle) * 7, y: y + sin(angle) * 7)
      if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath(); context.fill(path, with: .color(Self.color(0xFAF2D1)))
    stroke(in: context, path: path, color: 0x996019, width: 1.8)
  }
  private func signal(in context: GraphicsContext, path: Path, progress: Double, moving: Bool) {
    stroke(in: context, path: path, color: 0xA0B4BB, width: 1.3)
    if progress > 0 { stroke(in: context, path: path.trimmedPath(from: 0, to: progress), color: 0x007973, width: 2.5) }
    if moving, progress > 0 {
      let point = path.trimmedPath(from: 0, to: progress).cgPath.currentPoint
      dot(in: context, x: point.x, y: point.y, radius: 7, color: 0xD8FAF0)
      dot(in: context, x: point.x, y: point.y, radius: 4, color: 0x007973)
    }
  }
  private func transfer(in context: GraphicsContext, from: Double, to: Double, relay: Double, start: Double, finish: Double) {
    var path = Path(); path.move(to: CGPoint(x: from, y: 168)); path.addLine(to: CGPoint(x: to, y: 168))
    path.addLine(to: CGPoint(x: to - 4, y: 165)); path.move(to: CGPoint(x: to, y: 168)); path.addLine(to: CGPoint(x: to - 4, y: 171))
    stroke(in: context, path: path, color: relay >= finish ? 0x007973 : 0x728D92, width: 1.5)
    let travel = min(1, max(0, (relay - start) / (finish - start)))
    if travel > 0, travel < 1 { dot(in: context, x: from + (to - from) * travel, y: 168, radius: 3, color: 0x007973) }
  }
  private func node(in context: GraphicsContext, text: String, x: Double, y: Double, active: Bool, accent: UInt32) {
    context.fill(rounded(x, y, 54, 22, 7), with: .color(Self.color(active ? accent : 0xE1E7E9)))
    label(in: context, text: text, x: x + 13, y: y + 15, strong: true)
  }
  private func label(in context: GraphicsContext, text: String, x: Double, y: Double, strong: Bool = false) {
    let size: Double = strong ? 12 : 11
    context.draw(Text(verbatim: text).font(.system(size: size, weight: strong ? .bold : .regular)).foregroundColor(Self.color(0x21474D)),
      at: CGPoint(x: x, y: y - UIFont.systemFont(ofSize: size).ascender), anchor: .topLeading)
  }
  private static func point(on path: Path, fraction: Double, start: CGPoint) -> CGPoint {
    fraction <= 0 ? start : path.trimmedPath(from: 0, to: fraction).cgPath.currentPoint
  }
  private static func route(_ x: Double, _ y: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ endX: Double, _ endY: Double) -> Path {
    var path = Path(); path.move(to: CGPoint(x: x, y: y))
    path.addCurve(to: CGPoint(x: endX, y: endY), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
    return path
  }
  private func circle(_ x: Double, _ y: Double, _ radius: Double) -> Path {
    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
  }
  private func rounded(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ radius: Double) -> Path {
    Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: radius)
  }
  private func stroke(in context: GraphicsContext, path: Path, color: UInt32, width: Double) {
    context.stroke(path, with: .color(Self.color(color)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
  }
  private func dot(in context: GraphicsContext, x: Double, y: Double, radius: Double, color: UInt32) {
    context.fill(circle(x, y, radius), with: .color(Self.color(color)))
  }
  private static func color(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
  }
  private static func mix(_ amount: Double) -> Color {
    Color(red: (35 + 81 * amount) / 255, green: (112 + 85 * amount) / 255, blue: (132 + 71 * amount) / 255)
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasFunctionText.get("health_atlas_uptake_" + key, language) }
}
