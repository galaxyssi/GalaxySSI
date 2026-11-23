import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasSignalView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    let motion = GalaxySSIHealthAtlasSignalMotion(courseID: story.id, chapter: story.chapter(phase), fraction: story.fraction(phase))
    Canvas { context, size in
      let scale = min(size.width, size.height) / 360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 360 * scale) / 2); local.scaleBy(x: scale, y: scale)
      let art = GalaxySSIHealthAtlasSignalDrawing(context: local, language: language)
      art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), 0, 360, 0xE9F4F5, 0xFBF0DF)
      switch motion.course {
      case .synaptic: art.synapticScene(motion)
      case .myelin: art.myelinScene(motion)
      case .thyroid: art.thyroidScene(motion)
      }
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier(story.id == "SYNAPTIC_SIGNAL" ? "atlas-function-synaptic-signal-art" :
        story.id == "MYELIN_SIGNAL" ? "atlas-function-myelin-signal-art" : "atlas-function-thyroid-feedback-art")
  }
}

struct GalaxySSIHealthAtlasSignalDrawing {
  typealias Motion = GalaxySSIHealthAtlasSignalMotion
  let context: GraphicsContext
  let language: String
  static let cream: UInt32 = 0xFBF8ED, text: UInt32 = 0x24444E, gold: UInt32 = 0xA76E29, violet: UInt32 = 0x765789
  static let teal: UInt32 = 0x367970, blue: UInt32 = 0x3D7593, coral: UInt32 = 0xA5636E, feedbackInk: UInt32 = 0xA24D5D
  func copy(_ context: GraphicsContext) -> Self { Self(context: context, language: language) }
  func fill(_ path: Path, _ value: UInt32) { context.fill(path, with: .color(Self.color(value))) }
  func stroke(_ path: Path, _ value: UInt32, _ width: Double) {
    context.stroke(path, with: .color(Self.color(value)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
  }
  func gradient(_ path: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32) {
    context.fill(path, with: .linearGradient(Gradient(colors: [Self.color(from), Self.color(to)]),
      startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
  }
  func box(_ l: Double, _ t: Double, _ r: Double, _ b: Double, _ radius: Double, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32) {
    gradient(Path(roundedRect: CGRect(x: l, y: t, width: r - l, height: b - t), cornerRadius: radius), top, bottom, from, to)
  }
  func oval(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ value: UInt32) {
    fill(Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: 2 * rx, height: 2 * ry)), value)
  }
  func dot(_ x: Double, _ y: Double, _ r: Double, _ value: UInt32) {
    oval(x, y, r + 0.7, r + 0.7, Self.cream); oval(x, y, r, r, value)
  }
  func ring(_ x: Double, _ y: Double, _ r: Double, _ value: UInt32) {
    stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), value, 1.6)
  }
  func line(_ x: Double, _ y: Double, _ tx: Double, _ ty: Double, _ value: UInt32, _ width: Double) {
    var path = Path(); path.move(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: tx, y: ty)); stroke(path, value, width)
  }
  func rounded(_ l: Double, _ t: Double, _ r: Double, _ b: Double, _ radius: Double, _ value: UInt32) {
    fill(Path(roundedRect: CGRect(x: l, y: t, width: r - l, height: b - t), cornerRadius: radius), value)
  }
  func plate(_ asset: String, _ l: Double, _ t: Double, _ r: Double, _ b: Double) {
    context.draw(context.resolve(Image(asset)), in: CGRect(x: l, y: t, width: r - l, height: b - t))
  }
  func marker(_ route: Motion.Route, _ f: Double, draw: (Double, Double) -> Void) {
    if let sample = GalaxySSIHealthAtlasFunctionPath.sample(route, position: f, width: 360, height: 360) { draw(sample.point.x, sample.point.y) }
  }
  func trail(_ route: Motion.Route, _ f: Double, _ value: UInt32, length: Double?) {
    guard let length, let start = Motion.trailStart(f, length: length) else { return }
    if f > 0 {
      let path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
        .trimmedPath(from: CGFloat(start), to: CGFloat(f))
      stroke(path, Self.cream, 6); stroke(path, value, 2.7)
    }
    marker(route, f) { dot($0, $1, 3.3, value) }
  }
  func label(_ x: Double, _ y: Double, _ key: String) {
    let text = GalaxySSIHealthAtlasFunctionText.get("health_atlas_signal_" + key, language)
    let measured = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 13, weight: .medium)]).width
    let available = 2 * min(x - 8, 352 - x), size = measured > available ? 13 * available / measured : 13
    let font = UIFont.systemFont(ofSize: size, weight: .medium), width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: .medium)]).width
    context.draw(Text(verbatim: text).font(.system(size: size, weight: .medium)).foregroundColor(Self.color(Self.text)),
      at: CGPoint(x: x - width / 2, y: y - font.ascender), anchor: .topLeading)
  }
  func leader(_ x: Double, _ y: Double, _ tx: Double, _ ty: Double, _ key: String, _ value: UInt32) {
    line(x, ty < y ? y - 16 : y + 5, tx, ty, value, 1.1); dot(tx, ty, 2.1, value); label(x, y, key)
  }
  func legend(_ x: Double, _ y: Double, _ text: String, _ value: UInt32) {
    dot(x - 26, y - 4, 3.7, value)
    let font = UIFont.systemFont(ofSize: 12, weight: .medium), width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .medium)]).width
    context.draw(Text(verbatim: text).font(.system(size: 12, weight: .medium)).foregroundColor(Self.color(Self.text)),
      at: CGPoint(x: x + 3 - width / 2, y: y - font.ascender), anchor: .topLeading)
  }
  func arrow(_ x: Double, _ y: Double, _ tx: Double, _ ty: Double, _ value: UInt32) {
    let dx = tx - x, dy = ty - y, distance = hypot(dx, dy)
    guard distance > 0 else { return }
    let ux = dx / distance, uy = dy / distance
    line(x, y, tx, ty, value, 1.7)
    line(tx, ty, tx - 6 * ux + 3.2 * uy, ty - 6 * uy - 3.2 * ux, value, 1.7)
    line(tx, ty, tx - 6 * ux - 3.2 * uy, ty - 6 * uy + 3.2 * ux, value, 1.7)
  }
  static func color(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
  }
}
