import SwiftUI
import UIKit

// Native counterpart of the source IllustratedStoryView primitives, shared by its course renderers.
struct GalaxySSIHealthAtlasIllustratedDrawing {
  let context: GraphicsContext
  let language: String
  static let cream: UInt32 = 0xFFF8EB, coral: UInt32 = 0xAC6673, peach: UInt32 = 0xEDB8A5, sand: UInt32 = 0xEBCC9F
  static let sienna: UInt32 = 0x9D6334, violet: UInt32 = 0x795489, teal: UInt32 = 0x337B6D, blue: UInt32 = 0x407C9C, lettering: UInt32 = 0x23444E
  func copy(_ context: GraphicsContext) -> Self { Self(context: context, language: language) }
  func fill(_ path: Path, _ value: UInt32) { context.fill(path, with: .color(Self.color(value))) }
  func stroke(_ path: Path, _ value: UInt32, _ width: Double) {
    context.stroke(path, with: .color(Self.color(value)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
  }
  func gradient(_ path: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32) {
    context.fill(path, with: .linearGradient(Gradient(colors: [Self.color(from), Self.color(to)]),
      startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
  }
  func oval(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, fill: UInt32, border: UInt32) {
    let path = Path(ellipseIn: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1))
    self.fill(path, fill); stroke(path, border, 1.05)
  }
  func oval(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, top: Double, bottom: Double, from: UInt32, to: UInt32, border: UInt32) {
    let path = Path(ellipseIn: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1))
    gradient(path, top, bottom, from, to); stroke(path, border, 1.3)
  }
  func rounded(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ radius: Double, _ fill: UInt32) {
    self.fill(Path(roundedRect: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1), cornerRadius: radius), fill)
  }
  func disc(_ x: Double, _ y: Double, _ radius: Double, _ fill: UInt32, border: UInt32? = nil) {
    let path = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
    self.fill(path, fill); if let border { stroke(path, border, 1.15) }
  }
  func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ value: UInt32, _ width: Double) {
    var path = Path(); path.move(to: CGPoint(x: x1, y: y1)); path.addLine(to: CGPoint(x: x2, y: y2)); stroke(path, value, width)
  }
  func arrow(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ value: UInt32) {
    line(x1, y1, x2, y2, value, 1.8)
    let length = max(1, hypot(x2 - x1, y2 - y1)), dx = (x2 - x1) / length, dy = (y2 - y1) / length
    for side in [-1.0, 1.0] { line(x2, y2, x2 - 7 * dx + side * 4 * dy, y2 - 7 * dy - side * 4 * dx, value, 1.8) }
  }
  func label(_ key: String, _ x: Double, _ baseline: Double, _ maxWidth: Double) {
    let text = GalaxySSIHealthAtlasFunctionText.get("health_atlas_" + key, language)
    let measured = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 13, weight: .medium)]).width
    let size = 13 * min(1, maxWidth / max(measured, 0.0001))
    let font = UIFont.systemFont(ofSize: size, weight: .medium), width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: .medium)]).width
    context.draw(Text(verbatim: text).font(.system(size: size, weight: .medium)).foregroundColor(Self.color(Self.lettering)),
      at: CGPoint(x: x - width / 2, y: baseline - font.ascender), anchor: .topLeading)
  }
  func wave(_ t: Double) -> Double { sin(t * 2 * .pi) }
  static func color(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255,
      opacity: value > 0xFFFFFF ? Double(value >> 24) / 255 : 1)
  }
}
