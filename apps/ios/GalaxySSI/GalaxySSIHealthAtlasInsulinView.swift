import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasInsulinView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    let motion = GalaxySSIHealthAtlasInsulinMotion(chapter: story.chapter(phase), fraction: story.fraction(phase))
    Canvas { context, size in
      let scale = min(size.width, size.height) / 360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 360 * scale) / 2); local.scaleBy(x: scale, y: scale)
      let art = GalaxySSIHealthAtlasInsulinDrawing(context: local, language: language)
      art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), 0, 360, 0xE6F3F6, 0xFBF0DE)
      art.scene(motion)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-insulin-secretion-art")
  }
}

struct GalaxySSIHealthAtlasInsulinDrawing {
  typealias Motion = GalaxySSIHealthAtlasInsulinMotion
  let context: GraphicsContext
  let language: String
  static let membrane: UInt32 = 0x9E7662, cream: UInt32 = 0xF9EFDC, glucose: UInt32 = 0xB07A25
  static let energy: UInt32 = 0x91653A, potassium: UInt32 = 0x875387, calcium: UInt32 = 0x287C72
  static let insulin: UInt32 = 0x397EAA, ink: UInt32 = 0x25474F
  func copy(_ context: GraphicsContext) -> Self { Self(context: context, language: language) }
  func fill(_ path: Path, _ value: UInt32) { context.fill(path, with: .color(Self.color(value))) }
  func stroke(_ path: Path, _ value: UInt32, _ width: Double) {
    context.stroke(path, with: .color(Self.color(value)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
  }
  func gradient(_ path: Path, _ y0: Double, _ y1: Double, _ from: UInt32, _ to: UInt32) {
    context.fill(path, with: .linearGradient(Gradient(colors: [Self.color(from), Self.color(to)]),
      startPoint: CGPoint(x: 0, y: y0), endPoint: CGPoint(x: 0, y: y1)))
  }
  func circlePath(_ x: Double, _ y: Double, _ r: Double) -> Path {
    Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
  }
  func circle(_ x: Double, _ y: Double, _ r: Double, _ value: UInt32) { fill(circlePath(x, y, r), value) }
  func line(_ x: Double, _ y: Double, _ tx: Double, _ ty: Double, _ value: UInt32, _ width: Double) {
    var path = Path(); path.move(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: tx, y: ty)); stroke(path, value, width)
  }
  func particle(_ x: Double, _ y: Double, _ value: UInt32, _ radius: Double) {
    circle(x, y, radius + 0.7, Self.cream); circle(x, y, radius, value)
  }
  func label(_ x: Double, _ y: Double, _ key: String) {
    let text = GalaxySSIHealthAtlasFunctionText.get("health_atlas_insulin_art_" + key, language)
    let measured = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 13, weight: .medium)]).width
    let available = 2 * min(x - 8, 352 - x), size = measured > available ? 13 * available / measured : 13
    let font = UIFont.systemFont(ofSize: size, weight: .medium), width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: .medium)]).width
    context.draw(Text(verbatim: text).font(.system(size: size, weight: .medium)).foregroundColor(Self.color(Self.ink)),
      at: CGPoint(x: x - width / 2, y: y - font.ascender), anchor: .topLeading)
  }
  func leader(_ x: Double, _ y: Double, _ tx: Double, _ ty: Double, _ key: String, _ value: UInt32) {
    line(x, ty < y ? y - 16 : y + 6, tx, ty, value, 1.2); particle(tx, ty, value, 2.4); label(x, y, key)
  }
  func cellCutaway(_ y: Double, pore: Double = 0, gate: Double? = nil) {
    var membrane = Path(); membrane.move(to: CGPoint(x: 23, y: y)); membrane.addLine(to: CGPoint(x: 145, y: y))
    if pore > 0 {
      let width = 5 + 20 * pore
      membrane.addLine(to: CGPoint(x: 180 - width, y: y))
      membrane.addCurve(to: CGPoint(x: 180, y: y + 55), control1: CGPoint(x: 178 - width, y: y + 12), control2: CGPoint(x: 147, y: y + 44))
      membrane.addCurve(to: CGPoint(x: 180 + width, y: y), control1: CGPoint(x: 213, y: y + 44), control2: CGPoint(x: 182 + width, y: y + 12))
    }
    membrane.addLine(to: CGPoint(x: 337, y: y))
    var body = membrane; body.addLine(to: CGPoint(x: 337, y: 323))
    body.addQuadCurve(to: CGPoint(x: 315, y: 343), control: CGPoint(x: 336, y: 343)); body.addLine(to: CGPoint(x: 45, y: 343))
    body.addQuadCurve(to: CGPoint(x: 23, y: 323), control: CGPoint(x: 24, y: 343)); body.closeSubpath()
    gradient(body, 123, 354, 0xF5E6DD, 0xEED7C7)
    var local = context
    if let gate {
      // Even-odd clipping leaves the channel opening clear, matching Android clipOutRect.
      var clip = Path(CGRect(x: 0, y: 0, width: 360, height: 360))
      clip.addRect(CGRect(x: gate - 18, y: y - 8, width: 36, height: 16)); local.clip(to: clip, style: FillStyle(eoFill: true))
    }
    let drawing = copy(local); drawing.stroke(membrane, Self.membrane, 8); drawing.stroke(membrane, 0xECC6A0, 5.5)
    for x in stride(from: 28, through: 330, by: 11) where pore == 0 || !(147...216).contains(x) {
      drawing.circle(Double(x), y - 3, 1.2, Self.cream); drawing.circle(Double(x), y + 3, 1.2, 0xC39776)
    }
    label(75, 28, "outside"); label(79, 321, "inside")
  }
  func channel(_ x: Double, _ y: Double, _ value: UInt32, _ open: Double) {
    let spread = 4 + 8 * open
    for direction in [-1.0, 1.0] {
      let cx = x + direction * (8 + spread)
      fill(Path(roundedRect: CGRect(x: cx - 8, y: y - 20, width: 16, height: 39), cornerRadius: 7), value)
      line(cx - 2, y - 11, cx - 2, y + 10, Self.cream, 1.4)
    }
    if open < 0.40 { line(x - spread, y, x + spread, y, value, 4) }
  }
  func mitochondrion() {
    var path = Path(); path.move(to: CGPoint(x: 142, y: 211))
    path.addCurve(to: CGPoint(x: 193, y: 179), control1: CGPoint(x: 136, y: 187), control2: CGPoint(x: 171, y: 175))
    path.addCurve(to: CGPoint(x: 206, y: 224), control1: CGPoint(x: 225, y: 184), control2: CGPoint(x: 221, y: 206))
    path.addCurve(to: CGPoint(x: 142, y: 211), control1: CGPoint(x: 192, y: 243), control2: CGPoint(x: 151, y: 239)); path.closeSubpath()
    gradient(path, 162, 243, 0xF2BCB1, 0xB97583); stroke(path, 0x96576C, 1.8)
    var cristae = Path(); cristae.move(to: CGPoint(x: 148, y: 210))
    cristae.addCurve(to: CGPoint(x: 169, y: 192), control1: CGPoint(x: 173, y: 207), control2: CGPoint(x: 154, y: 189))
    cristae.addCurve(to: CGPoint(x: 181, y: 225), control1: CGPoint(x: 185, y: 195), control2: CGPoint(x: 168, y: 223))
    cristae.addCurve(to: CGPoint(x: 199, y: 193), control1: CGPoint(x: 193, y: 225), control2: CGPoint(x: 186, y: 188))
    cristae.addQuadCurve(to: CGPoint(x: 204, y: 209), control: CGPoint(x: 205, y: 196)); stroke(cristae, 0xF3D0CC, 2.8)
  }
  func sugar(_ x: Double, _ y: Double) {
    var path = Path()
    for i in 0...5 {
      let angle = Double(i) * .pi / 3, point = CGPoint(x: x + 5.7 * cos(angle), y: y + 5.7 * sin(angle))
      if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath(); fill(path, 0xF0CA7F); stroke(path, Self.glucose, 1.1)
  }
  func insulinMolecule(_ x: Double, _ y: Double, _ scale: Double) {
    for i in 0...4 {
      let a = Double(i) * 2 * .pi / 5, cx = x + 7 * scale * cos(a), cy = y + 6 * scale * sin(a)
      circle(cx, cy, 4.4 * scale, Self.insulin); circle(cx - scale, cy - scale, 2 * scale, 0xB3DCEB)
    }
  }
  static func color(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
      blue: Double(value & 255) / 255, opacity: value > 0xFFFFFF ? Double(value >> 24) / 255 : 1)
  }
}
