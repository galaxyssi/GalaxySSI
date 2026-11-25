import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasMovementView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    let motion = GalaxySSIHealthAtlasMovementMotion(courseID: story.id, chapter: story.chapter(phase), fraction: story.fraction(phase))
    Canvas { context, size in
      let scale = min(size.width, size.height) / 340
      guard scale > 0 else { return }
      var drawing = context
      drawing.translateBy(x: (size.width - 340 * scale) / 2, y: (size.height - 340 * scale) / 2)
      drawing.scaleBy(x: scale, y: scale)
      let art = GalaxySSIHealthAtlasMovementDrawing(context: drawing, language: language)
      art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 340, height: 340), cornerRadius: 8),
        top: 0, bottom: 340, from: 0xF0F8F8, to: 0xFBF2E4)
      if motion.bone { art.remodeling(chapter: motion.chapter, t: motion.fraction) }
      else { art.muscleScene(chapter: motion.chapter, t: motion.fraction) }
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier(story.id == "BONE_REMODELING" ? "atlas-function-bone-remodeling-art" : "atlas-function-muscle-motion-art")
  }
}

struct GalaxySSIHealthAtlasMovementDrawing {
  typealias Motion = GalaxySSIHealthAtlasMovementMotion
  let context: GraphicsContext
  let language: String
  static let nerveColor: UInt32 = 0x467A8E, teal: UInt32 = 0x347C78, scarlet: UInt32 = 0xAE5660
  static let purple: UInt32 = 0x81669B, amber: UInt32 = 0xB57735, edge: UInt32 = 0x8A614B
  static let textColor: UInt32 = 0x24464F, white: UInt32 = 0xFAF9F1
  func copy(_ context: GraphicsContext) -> Self { Self(context: context, language: language) }
  func fill(_ path: Path, _ value: UInt32) { context.fill(path, with: .color(Self.color(value))) }
  func stroke(_ path: Path, _ value: UInt32, _ width: Double) {
    context.stroke(path, with: .color(Self.color(value)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
  }
  func gradient(_ path: Path, top: Double, bottom: Double, from: UInt32, to: UInt32) {
    context.fill(path, with: .linearGradient(Gradient(colors: [Self.color(from), Self.color(to)]),
      startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
  }
  func horizontalShade(_ path: Path, _ edge: UInt32, _ light: UInt32, _ shadow: UInt32) {
    context.fill(path, with: .linearGradient(Gradient(stops: [
      .init(color: Self.color(edge), location: 0), .init(color: Self.color(light), location: 0.40), .init(color: Self.color(shadow), location: 1)
    ]), startPoint: CGPoint(x: -13, y: 0), endPoint: CGPoint(x: 13, y: 0)))
  }
  func oval(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ value: UInt32) {
    fill(Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2)), value)
  }
  func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ value: UInt32, _ width: Double) {
    var path = Path(); path.move(to: CGPoint(x: x1, y: y1)); path.addLine(to: CGPoint(x: x2, y: y2)); stroke(path, value, width)
  }
  func label(_ x: Double, _ y: Double, _ key: String) {
    let text = GalaxySSIHealthAtlasFunctionText.get("health_atlas_" + key, language)
    let font = UIFont.systemFont(ofSize: 13, weight: .medium), width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 13, weight: .medium)]).width
    context.draw(Text(verbatim: text).font(.system(size: 13, weight: .medium)).foregroundColor(Self.color(Self.textColor)),
      at: CGPoint(x: x - width / 2, y: y - font.ascender), anchor: .topLeading)
  }
  func leader(_ x: Double, _ y: Double, _ toX: Double, _ toY: Double, _ title: String, _ value: UInt32) {
    line(x, y + 5, toX, toY, value, 1.05)
    oval(toX, toY, 2.75, 2.75, Self.white); oval(toX, toY, 1.7, 1.7, value); label(x, y, title)
  }
  func track(_ route: GalaxySSIHealthAtlasSectionLesson.Route, _ value: UInt32, _ width: Double) {
    stroke(GalaxySSIHealthAtlasSectionLessonView.path(route, width: 340, height: 340), value, width)
  }
  func pulse(_ route: GalaxySSIHealthAtlasSectionLesson.Route, _ fraction: Double, _ value: UInt32, _ radius: Double) {
    guard let sample = GalaxySSIHealthAtlasFunctionPath.sample(route, position: fraction, width: 340, height: 340) else { return }
    oval(sample.point.x, sample.point.y, radius, radius, value)
  }
  static func color(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
      blue: Double(value & 255) / 255, opacity: value > 0xFFFFFF ? Double(value >> 24) / 255 : 1)
  }
}
