import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasLymphImmuneView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    let motion = GalaxySSIHealthAtlasLymphImmuneMotion(courseID: story.id, chapter: story.chapter(phase), fraction: story.fraction(phase))
    Canvas { context, size in
      let scale = min(size.width, size.height) / 360
      guard scale > 0 else { return }
      var drawing = context
      drawing.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 360 * scale) / 2); drawing.scaleBy(x: scale, y: scale)
      let art = GalaxySSIHealthAtlasLymphImmuneDrawing(context: drawing, language: language)
      art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), top: 0, bottom: 360, from: 0xEAF6F5, to: 0xFCF5E9)
      if motion.lymph { art.lymphScene(motion) } else { art.antibodyScene(motion) }
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier(story.id == "LYMPH_RETURN" ? "atlas-function-lymph-return-art" : "atlas-function-antibody-response-art")
  }
}

struct GalaxySSIHealthAtlasLymphImmuneDrawing {
  typealias Motion = GalaxySSIHealthAtlasLymphImmuneMotion
  let context: GraphicsContext
  let language: String
  static let rose: UInt32 = 0xA85363, teal: UInt32 = 0x236D69, blue: UInt32 = 0x2F6F95
  static let gold: UInt32 = 0xA77532, cream: UInt32 = 0xFCFBEF, text: UInt32 = 0x23444B
  func copy(_ context: GraphicsContext) -> Self { Self(context: context, language: language) }
  func fill(_ path: Path, _ value: UInt32) { context.fill(path, with: .color(Self.color(value))) }
  func stroke(_ path: Path, _ value: UInt32, _ width: Double) {
    context.stroke(path, with: .color(Self.color(value)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
  }
  func gradient(_ path: Path, top: Double, bottom: Double, from: UInt32, to: UInt32) {
    context.fill(path, with: .linearGradient(Gradient(colors: [Self.color(from), Self.color(to)]),
      startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
  }
  func shaded(_ path: Path, top: Double, bottom: Double, from: UInt32, to: UInt32, edge: UInt32, width: Double = 1.5) {
    gradient(path, top: top, bottom: bottom, from: from, to: to); stroke(path, edge, width)
  }
  func oval(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ value: UInt32) {
    fill(Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2)), value)
  }
  func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ value: UInt32, _ width: Double) {
    var path = Path(); path.move(to: CGPoint(x: x1, y: y1)); path.addLine(to: CGPoint(x: x2, y: y2)); stroke(path, value, width)
  }
  func tracer(_ x: Double, _ y: Double, _ value: UInt32, _ r: Double) {
    oval(x, y, r + 0.8, r + 0.8, Self.cream); oval(x, y, r, r, value)
  }
  func label(_ x: Double, _ y: Double, _ key: String) {
    let text = GalaxySSIHealthAtlasFunctionText.get("health_atlas_" + key, language)
    let measured = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 13, weight: .medium)]).width
    let available = 2 * min(x - 8, 352 - x), size = measured > available ? 13 * available / measured : 13
    let font = UIFont.systemFont(ofSize: size, weight: .medium), width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: .medium)]).width
    context.draw(Text(verbatim: text).font(.system(size: size, weight: .medium)).foregroundColor(Self.color(Self.text)),
      at: CGPoint(x: x - width / 2, y: y - font.ascender), anchor: .topLeading)
  }
  func leader(_ x: Double, _ y: Double, _ tx: Double, _ ty: Double, _ key: String, _ value: UInt32) {
    let labelEdge = ty < y ? y - 16 : y + 6
    line(x, labelEdge, tx, ty, value, 1.1); tracer(tx, ty, value, 2.9); label(x, y, key)
  }
  func cell(_ asset: String, _ x: Double, _ y: Double, _ diameter: Double) {
    guard let rect = Motion.cellBounds(x: x, y: y, diameter: diameter) else { return }
    context.draw(context.resolve(Image(asset)), in: rect)
  }
  static func color(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
  }
}
