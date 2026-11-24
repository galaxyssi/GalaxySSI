import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasVisionView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  private typealias Motion = GalaxySSIHealthAtlasVisionMotion
  static let gold = color(0xA5651B), neural = color(0x137568), rod = color(0x675393), cone = color(0xA84759), textInk = color(0x23434C)
  private static let spectral: [UInt32] = [0x565CBB, 0x118575, 0xBF5661]
  var body: some View {
    let motion = Motion(courseID: story.id, chapter: story.chapter(phase), fraction: story.fraction(phase))
    Canvas { context, size in
      let scale = min(size.width, size.height) / 344
      guard scale > 0 else { return }
      var drawing = context
      drawing.translateBy(x: (size.width - 344 * scale) / 2, y: (size.height - 344 * scale) / 2)
      drawing.scaleBy(x: scale, y: scale)
      drawing.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 344, height: 344), cornerRadius: 8),
        with: .linearGradient(Gradient(colors: [Self.color(0xE9F4F7), Self.color(0xFAF0E3)]),
          startPoint: .zero, endPoint: CGPoint(x: 0, y: 344)))
      if motion.adaptation { compareLight(in: drawing, motion: motion) }
      else {
        switch motion.stage {
        case .entry, .focus: optics(in: drawing, motion: motion)
        case .capture: capture(in: drawing, motion: motion)
        case .relay: relay(in: drawing, motion: motion)
        case .output: axons(in: drawing, motion: motion)
        default: break
        }
      }
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier(story.id == "LIGHT_ADAPTATION" ? "atlas-function-light-adaptation-art" : "atlas-function-vision-art")
  }
  private func optics(in context: GraphicsContext, motion: Motion) {
    picture(in: context, asset: "HealthAtlasEyeSection", l: 6, t: 54, r: 338, b: 275)
    let t = motion.fraction
    for ray in Motion.rays {
      let path = GalaxySSIHealthAtlasSectionLessonView.path(ray, width: 344, height: 344)
        .trimmedPath(from: 0, to: CGFloat(motion.opticsDrawn))
      outlined(in: context, path: path, color: Self.gold, outer: 3.5, inner: 1.7)
      for i in 0..<2 {
        let fraction = Motion.loop(t * 1.28 + Double(i) * 0.5)
        pulse(in: context, route: ray, position: fraction * motion.opticsDrawn, color: Self.gold, radius: 2.7)
      }
    }
    if motion.stage == .focus {
      context.stroke(circle(x: 255, y: 149, radius: 6 + sin(.pi * t) * 3), with: .color(Self.gold), lineWidth: 2)
      leader(in: context, x: 255, y: 149, lx: 279, ly: 46, key: "retina", color: Self.gold)
    } else {
      leader(in: context, x: 54, y: 174, lx: 55, ly: 293, key: "cornea", color: Self.gold)
      leader(in: context, x: 87, y: 165, lx: 119, ly: 309, key: "pupil", color: Self.gold)
      leader(in: context, x: 115, y: 157, lx: 155, ly: 49, key: "lens", color: Self.gold)
    }
    key(in: context, center: 251, y: 301, key: "light", color: Self.gold)
  }
  private func capture(in context: GraphicsContext, motion: Motion) {
    rodCapture(in: context, time: motion.fraction, count: motion.captureCount)
  }
  private func relay(in context: GraphicsContext, motion: Motion) {
    picture(in: context, asset: "HealthAtlasSensoryRetinaSection", l: 5, t: 16, r: 339, b: 278)
    let t = motion.fraction
    for i in 0..<4 {
      pulse(in: context, route: Motion.lightInRetina, position: Motion.loop(t * 1.4 + Double(i) * 0.25), color: Self.gold, radius: 3.5)
      pulse(in: context, route: Motion.coneRelay, position: Motion.loop(t * 1.4 - 0.12 + Double(i) * 0.25 + 1), color: Self.neural, radius: 3.5)
    }
    key(in: context, center: 97, y: 293, key: "light_down", color: Self.gold)
    key(in: context, center: 254, y: 293, key: "relay_up", color: Self.neural)
    label(in: context, x: 172, y: 321, key: "cone_route", size: 11)
  }
  private func axons(in context: GraphicsContext, motion: Motion) {
    picture(in: context, asset: "HealthAtlasBrain", l: 61, t: 12, r: 282, b: 233)
    context.stroke(GalaxySSIHealthAtlasSectionLessonView.path(Motion.nerve, width: 344, height: 344),
      with: .color(Self.neural), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    for i in 0..<5 {
      pulse(in: context, route: Motion.nerve, position: Motion.loop(motion.fraction * 1.6 + Double(i) * 0.2), color: Self.neural, radius: 3.8)
    }
    for point in [CGPoint(x: 48, y: 244), CGPoint(x: 153, y: 231), CGPoint(x: 291, y: 229)] {
      dot(in: context, x: point.x, y: point.y, radius: 5, color: Self.neural)
    }
    label(in: context, x: 55, y: 270, key: "nerve", size: 11.5)
    label(in: context, x: 156, y: 270, key: "thalamus", size: 11.5)
    label(in: context, x: 286, y: 270, key: "cortex", size: 11.5)
    key(in: context, center: 172, y: 311, key: "spikes", color: Self.neural)
  }
  private func compareLight(in context: GraphicsContext, motion: Motion) {
    context.fill(Path(roundedRect: CGRect(x: 24, y: 19, width: 296, height: 73), cornerRadius: 8),
      with: .color(Self.color(Motion.blend(0x29404A, 0xF1E9D4, fraction: motion.light))))
    for (i, spectral) in Self.spectral.enumerated() {
      let x = Double(92 + i * 80)
      let shade = Self.color(Motion.blend(0x8D9C9D, spectral, fraction: motion.chroma))
      let path: Path
      switch i {
      case 0: path = circle(x: x, y: 54, radius: 16)
      case 1: path = Path(roundedRect: CGRect(x: x - 16, y: 38, width: 32, height: 32), cornerRadius: 4)
      default:
        var triangle = Path(); triangle.move(to: CGPoint(x: x, y: 36))
        triangle.addLine(to: CGPoint(x: x + 18, y: 70)); triangle.addLine(to: CGPoint(x: x - 18, y: 70)); triangle.closeSubpath()
        path = triangle
      }
      context.fill(path, with: .color(shade))
      if motion.stage == .color && motion.emphasis == i {
        context.stroke(Path(roundedRect: CGRect(x: x - 22, y: 32, width: 44, height: 44), cornerRadius: 5), with: .color(.white), lineWidth: 2)
      }
    }
    picture(in: context, asset: "HealthAtlasSensoryRod", l: 34, t: 102, r: 142, b: 264)
    picture(in: context, asset: "HealthAtlasSensoryCone", l: 198, t: 102, r: 306, b: 264)
    response(in: context, x: 87, count: motion.rodCount, time: motion.fraction, color: Self.rod)
    response(in: context, x: 251, count: motion.coneCount, time: motion.fraction, color: Self.cone)
    key(in: context, center: 87, y: 293, key: "rod_label", color: Self.rod)
    key(in: context, center: 251, y: 293, key: "cone_label", color: Self.cone)
    label(in: context, x: 172, y: 321, key: "relative", size: 11)
  }
  private func response(in context: GraphicsContext, x: Double, count: Int, time: Double, color: Color) {
    for i in 0..<count {
      let travel = Motion.loop(time * 2 + Double(i) * 0.24), dx = Double((i % 3 - 1) * 9)
      dot(in: context, x: x + dx, y: 260 + travel * 15, radius: 4 - Double(abs(i - 2)) * 0.25, color: color)
    }
  }
  func picture(in context: GraphicsContext, asset: String, l: Double, t: Double, r: Double, b: Double) {
    context.draw(context.resolve(Image(asset)), in: CGRect(x: l, y: t, width: r - l, height: b - t))
  }
  private func pulse(in context: GraphicsContext, route: Motion.Route, position: Double, color: Color, radius: Double) {
    guard let sample = GalaxySSIHealthAtlasFunctionPath.sample(route, position: position, width: 344, height: 344) else { return }
    dot(in: context, x: sample.point.x, y: sample.point.y, radius: radius + 1.4, color: .white)
    dot(in: context, x: sample.point.x, y: sample.point.y, radius: radius, color: color)
  }
  private func leader(in context: GraphicsContext, x: Double, y: Double, lx: Double, ly: Double, key: String, color: Color) {
    let stop = ly > y ? ly - 14 : ly + 5
    var path = Path(); path.move(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: lx, y: stop))
    outlined(in: context, path: path, color: color, outer: 2.7, inner: 1.25)
    dot(in: context, x: x, y: y, radius: 2.7, color: color)
    label(in: context, x: lx, y: ly, key: key, size: 11.5)
  }
  private func key(in context: GraphicsContext, center: Double, y: Double, key: String, color: Color) {
    let text = t(key), font = UIFont.systemFont(ofSize: 11.5)
    let width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 11.5)]).width
    let x = center - (width + 14) / 2
    dot(in: context, x: x + 4, y: y - 4, radius: 3.6, color: color)
    context.draw(Text(verbatim: text).font(.system(size: 11.5)).foregroundColor(Self.textInk),
      at: CGPoint(x: x + 14, y: y - font.ascender), anchor: .topLeading)
  }
  func label(in context: GraphicsContext, x: Double, y: Double, key: String, size: Double) {
    let text = t(key), font = UIFont.systemFont(ofSize: size)
    let width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size)]).width
    context.draw(Text(verbatim: text).font(.system(size: size)).foregroundColor(Self.textInk),
      at: CGPoint(x: x - width / 2, y: y - font.ascender), anchor: .topLeading)
  }
  private func outlined(in context: GraphicsContext, path: Path, color: Color, outer: Double, inner: Double) {
    context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: outer, lineCap: .round, lineJoin: .round))
    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: inner, lineCap: .round, lineJoin: .round))
  }
  func circle(x: Double, y: Double, radius: Double) -> Path {
    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
  }
  func dot(in context: GraphicsContext, x: Double, y: Double, radius: Double, color: Color) {
    context.fill(circle(x: x, y: y, radius: radius), with: .color(color))
  }
  static func color(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasFunctionText.get("health_atlas_vision_story_" + key, language) }
}
