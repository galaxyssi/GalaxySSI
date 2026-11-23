import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasHomeostasisView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    let motion = GalaxySSIHealthAtlasHomeostasisMotion(courseID: story.id, chapter: story.chapter(phase), fraction: story.fraction(phase))
    Canvas { context, size in
      let scale = min(size.width, size.height) / 360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 360 * scale) / 2); local.scaleBy(x: scale, y: scale)
      let art = GalaxySSIHealthAtlasHomeostasisDrawing(context: local, language: language)
      art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), 0, 360, 0xEAF4F5, 0xFCF1DF)
      if motion.cooling { art.sweatScene(motion) } else { art.glucagonScene(motion) }
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier(story.id == "SWEAT_COOLING" ? "atlas-function-sweat-cooling-art" : "atlas-function-glucagon-response-art")
  }
}

struct GalaxySSIHealthAtlasHomeostasisDrawing {
  typealias Motion = GalaxySSIHealthAtlasHomeostasisMotion
  let context: GraphicsContext
  let language: String
  static let cream: UInt32 = 0xFBF7E9, water: UInt32 = 0x3F85A4, salt: UInt32 = 0xA36735, violet: UInt32 = 0x775889
  static let gold: UInt32 = 0xA87329, red: UInt32 = 0xAA657B, teal: UInt32 = 0x397A71, text: UInt32 = 0x22434D
  func copy(_ context: GraphicsContext) -> Self { Self(context: context, language: language) }
  func fill(_ path: Path, _ value: UInt32) { context.fill(path, with: .color(Self.color(value))) }
  func stroke(_ path: Path, _ value: UInt32, _ width: Double) {
    context.stroke(path, with: .color(Self.color(value)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
  }
  func gradient(_ path: Path, _ y0: Double, _ y1: Double, _ from: UInt32, _ to: UInt32) {
    context.fill(path, with: .linearGradient(Gradient(colors: [Self.color(from), Self.color(to)]),
      startPoint: CGPoint(x: 0, y: y0), endPoint: CGPoint(x: 0, y: y1)))
  }
  func line(_ x: Double, _ y: Double, _ tx: Double, _ ty: Double, _ value: UInt32, _ width: Double) {
    var path = Path(); path.move(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: tx, y: ty)); stroke(path, value, width)
  }
  func oval(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ value: UInt32) {
    fill(Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2)), value)
  }
  func dot(_ x: Double, _ y: Double, _ value: UInt32, _ r: Double) {
    oval(x, y, r + 0.6, r + 0.6, Self.cream); oval(x, y, r, r, value)
  }
  func ring(_ x: Double, _ y: Double, _ radius: Double, _ value: UInt32) {
    stroke(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)), value, 1.45)
  }
  func rounded(_ l: Double, _ t: Double, _ r: Double, _ b: Double, _ radius: Double, _ value: UInt32) {
    fill(Path(roundedRect: CGRect(x: l, y: t, width: r - l, height: b - t), cornerRadius: radius), value)
  }
  func box(_ l: Double, _ t: Double, _ r: Double, _ b: Double, _ radius: Double, _ y0: Double, _ y1: Double, _ from: UInt32, _ to: UInt32) {
    gradient(Path(roundedRect: CGRect(x: l, y: t, width: r - l, height: b - t), cornerRadius: radius), y0, y1, from, to)
  }
  func tube(_ l: Double, _ t: Double, _ r: Double, _ b: Double, _ value: UInt32) {
    rounded(l, t, r, b, 6, value); line(l + 3, t + 5, l + 3, b - 5, Self.cream, 1.1)
  }
  func picture(_ asset: String, _ l: Double, _ t: Double, _ r: Double, _ b: Double) {
    context.draw(context.resolve(Image(asset)), in: CGRect(x: l, y: t, width: r - l, height: b - t))
  }
  func marker(_ route: Motion.Route, _ fraction: Double, draw: (Double, Double) -> Void) {
    if let sample = GalaxySSIHealthAtlasFunctionPath.sample(route, position: fraction, width: 360, height: 360) { draw(sample.point.x, sample.point.y) }
  }
  func sugar(_ x: Double, _ y: Double, _ r: Double) {
    var path = Path()
    for i in 0...5 {
      let a = Double(i) * .pi / 3, point = CGPoint(x: x + r * cos(a), y: y + r * sin(a))
      if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath(); fill(path, 0xF1C879); stroke(path, Self.gold, 1.2)
  }
  func hormone(_ x: Double, _ y: Double) {
    oval(x - 3.1, y, 3.8, 3.3, Self.violet); oval(x + 2.5, y - 2.5, 3.4, 3.5, 0x9C79A7)
    oval(x + 3.8, y + 2.5, 3.6, 2.7, Self.violet); oval(x - 1.6, y - 1.1, 1.5, 1.1, 0xDFCBE4)
  }
  func key(_ x: Double, _ y: Double, _ title: String, hormone isHormone: Bool) {
    if isHormone { hormone(x - 63, y - 4) } else { sugar(x - 63, y - 4, 5) }; label(x, y, title)
  }
  func leader(_ x: Double, _ y: Double, _ tx: Double, _ ty: Double, _ title: String, _ value: UInt32) {
    line(x, ty < y ? y - 16 : y + 5, tx, ty, value, 1.05); dot(tx, ty, value, 2.2); label(x, y, title)
  }
  func label(_ x: Double, _ y: Double, _ title: String) {
    let text = GalaxySSIHealthAtlasFunctionText.get("health_atlas_home_" + title, language)
    let measured = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 13, weight: .medium)]).width
    let available = 2 * min(x - 8, 352 - x), size = measured > available ? 13 * available / measured : 13
    let font = UIFont.systemFont(ofSize: size, weight: .medium), width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: .medium)]).width
    context.draw(Text(verbatim: text).font(.system(size: size, weight: .medium)).foregroundColor(Self.color(Self.text)),
      at: CGPoint(x: x - width / 2, y: y - font.ascender), anchor: .topLeading)
  }
  func arrow(_ x: Double, _ y: Double, _ tx: Double, _ ty: Double, _ value: UInt32) {
    let dx = tx - x, dy = ty - y, distance = hypot(dx, dy)
    guard distance > 0 else { return }
    let ux = dx / distance, uy = dy / distance
    line(x, y, tx, ty, value, 1.9)
    line(tx, ty, tx - ux * 6 + uy * 4, ty - uy * 6 - ux * 4, value, 1.9)
    line(tx, ty, tx - ux * 6 - uy * 4, ty - uy * 6 + ux * 4, value, 1.9)
  }
  func drop(_ x: Double, _ baseY: Double, _ r: Double) {
    var path = Path(); path.move(to: CGPoint(x: x, y: baseY - 2.2 * r))
    path.addCurve(to: CGPoint(x: x - 0.87 * r, y: baseY - 0.47 * r), control1: CGPoint(x: x - 0.5 * r, y: baseY - 1.7 * r), control2: CGPoint(x: x - 1.15 * r, y: baseY - 0.8 * r))
    path.addCurve(to: CGPoint(x: x + 0.86 * r, y: baseY - 0.43 * r), control1: CGPoint(x: x - 0.64 * r, y: baseY + 0.15 * r), control2: CGPoint(x: x + 0.61 * r, y: baseY + 0.16 * r))
    path.addCurve(to: CGPoint(x: x, y: baseY - 2.2 * r), control1: CGPoint(x: x + 1.14 * r, y: baseY - 0.91 * r), control2: CGPoint(x: x + 0.41 * r, y: baseY - 1.74 * r)); path.closeSubpath()
    fill(path, 0x93C5D5); stroke(path, Self.water, 1.45); oval(x - r * 0.32, baseY - 0.82 * r, r * 0.15, r * 0.28, 0xD8EAF0)
  }
  static func color(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
  }
}
