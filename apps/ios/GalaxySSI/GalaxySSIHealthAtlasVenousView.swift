import SwiftUI

struct GalaxySSIHealthAtlasVenousView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height) / 360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 360 * scale) / 2); local.scaleBy(x: scale, y: scale)
      let art = GalaxySSIHealthAtlasIllustratedDrawing(context: local, language: language)
      art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), 0, 360, 0xE8F4F3, 0xFBF0DF)
      let step = story.chapter(phase), t = story.fraction(phase)
      art.venousScene(GalaxySSIHealthAtlasVenousMotion(step: step, fraction: t), step: step, t: t)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-venous-return-art")
  }
}

enum GalaxySSIHealthAtlasVenousShapes {
  static let wall: UInt32 = 0x487588, flow: UInt32 = 0x226780, leader: UInt32 = 0x71818A
  static let leg = Path { p in
    p.move(to: CGPoint(x: 46, y: 75))
    p.addCurve(to: CGPoint(x: 98, y: 75), control1: CGPoint(x: 57, y: 70), control2: CGPoint(x: 87, y: 70))
    p.addCurve(to: CGPoint(x: 113, y: 162), control1: CGPoint(x: 94, y: 105), control2: CGPoint(x: 119, y: 123))
    p.addCurve(to: CGPoint(x: 86, y: 255), control1: CGPoint(x: 109, y: 198), control2: CGPoint(x: 91, y: 221))
    p.addCurve(to: CGPoint(x: 94, y: 289), control1: CGPoint(x: 84, y: 268), control2: CGPoint(x: 97, y: 278))
    p.addCurve(to: CGPoint(x: 57, y: 287), control1: CGPoint(x: 90, y: 299), control2: CGPoint(x: 60, y: 299))
    p.addCurve(to: CGPoint(x: 60, y: 252), control1: CGPoint(x: 54, y: 276), control2: CGPoint(x: 64, y: 267))
    p.addCurve(to: CGPoint(x: 37, y: 162), control1: CGPoint(x: 55, y: 214), control2: CGPoint(x: 43, y: 191))
    p.addCurve(to: CGPoint(x: 46, y: 75), control1: CGPoint(x: 29, y: 122), control2: CGPoint(x: 50, y: 104)); p.closeSubpath()
  }
  static let soleus = Path { p in
    p.move(to: CGPoint(x: 47, y: 120))
    p.addCurve(to: CGPoint(x: 63, y: 226), control1: CGPoint(x: 34, y: 155), control2: CGPoint(x: 49, y: 195))
    p.addQuadCurve(to: CGPoint(x: 72, y: 257), control: CGPoint(x: 70, y: 243))
    p.addCurve(to: CGPoint(x: 89, y: 213), control1: CGPoint(x: 78, y: 244), control2: CGPoint(x: 79, y: 232))
    p.addCurve(to: CGPoint(x: 98, y: 120), control1: CGPoint(x: 104, y: 186), control2: CGPoint(x: 113, y: 146)); p.closeSubpath()
  }
  static let gastro = Path { p in
    p.move(to: CGPoint(x: 72, y: 101))
    p.addCurve(to: CGPoint(x: 44, y: 115), control1: CGPoint(x: 64, y: 80), control2: CGPoint(x: 48, y: 89))
    p.addCurve(to: CGPoint(x: 71, y: 206), control1: CGPoint(x: 33, y: 152), control2: CGPoint(x: 49, y: 181))
    p.addCurve(to: CGPoint(x: 102, y: 119), control1: CGPoint(x: 89, y: 184), control2: CGPoint(x: 108, y: 152))
    p.addCurve(to: CGPoint(x: 72, y: 101), control1: CGPoint(x: 98, y: 92), control2: CGPoint(x: 82, y: 84)); p.closeSubpath()
  }
  static let vein = Path { p in
    p.move(to: CGPoint(x: 80, y: 82))
    p.addCurve(to: CGPoint(x: 85, y: 170), control1: CGPoint(x: 78, y: 113), control2: CGPoint(x: 90, y: 140))
    p.addCurve(to: CGPoint(x: 75, y: 254), control1: CGPoint(x: 83, y: 205), control2: CGPoint(x: 72, y: 221))
  }
  static func lumen(_ squeeze: Double) -> Path {
    var path = Path(); path.move(to: CGPoint(x: 249, y: 78))
    trace(&path, side: 1, direction: 1, first: 116, last: 246, end: 315, squeeze: squeeze)
    path.addLine(to: CGPoint(x: 211, y: 315))
    trace(&path, side: -1, direction: -1, first: 246, last: 116, end: 78, squeeze: squeeze)
    path.closeSubpath(); return path
  }
  private static func trace(_ path: inout Path, side: Double, direction: Double, first: Double, last: Double, end: Double, squeeze: Double) {
    let rim = 230 + side * 19, sinus = 230 + side * 27, waist = 230 + side * (19 - 8 * squeeze)
    path.addLine(to: CGPoint(x: rim, y: first - 28 * direction))
    path.addCurve(to: CGPoint(x: sinus, y: first), control1: CGPoint(x: rim, y: first - 17 * direction), control2: CGPoint(x: sinus, y: first - 13 * direction))
    path.addCurve(to: CGPoint(x: waist, y: 181), control1: CGPoint(x: sinus, y: first + 17 * direction), control2: CGPoint(x: waist, y: 181 - 24 * direction))
    path.addCurve(to: CGPoint(x: sinus, y: last), control1: CGPoint(x: waist, y: 181 + 24 * direction), control2: CGPoint(x: sinus, y: last - 17 * direction))
    path.addCurve(to: CGPoint(x: rim, y: last + 28 * direction), control1: CGPoint(x: sinus, y: last + 13 * direction), control2: CGPoint(x: rim, y: last + 17 * direction))
    path.addLine(to: CGPoint(x: rim, y: end))
  }
}
