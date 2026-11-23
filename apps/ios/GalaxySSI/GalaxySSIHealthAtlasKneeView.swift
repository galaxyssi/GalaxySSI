import SwiftUI

struct GalaxySSIHealthAtlasKneeView: View {
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
      art.kneeScene(GalaxySSIHealthAtlasKneeMotion.at(step: step, fraction: t), step: step, t: t)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-knee-articulation-art")
  }
}

enum GalaxySSIHealthAtlasKneeShapes {
  static let boneLip: UInt32 = 0xA9815E, quad: UInt32 = 0xB66A45, ham: UInt32 = 0x955572
  static let femur = Path { p in
    p.move(to: CGPoint(x: 160, y: 28))
    p.addCurve(to: CGPoint(x: 157, y: 151), control1: CGPoint(x: 154, y: 64), control2: CGPoint(x: 162, y: 126))
    p.addCurve(to: CGPoint(x: 150, y: 187), control1: CGPoint(x: 152, y: 171), control2: CGPoint(x: 145, y: 178))
    p.addCurve(to: CGPoint(x: 193, y: 193), control1: CGPoint(x: 157, y: 200), control2: CGPoint(x: 179, y: 200))
    p.addCurve(to: CGPoint(x: 196, y: 145), control1: CGPoint(x: 213, y: 182), control2: CGPoint(x: 204, y: 167))
    p.addCurve(to: CGPoint(x: 192, y: 28), control1: CGPoint(x: 192, y: 122), control2: CGPoint(x: 198, y: 60))
    p.addQuadCurve(to: CGPoint(x: 160, y: 28), control: CGPoint(x: 176, y: 22)); p.closeSubpath()
  }
  static let tibia = Path { p in
    p.move(to: CGPoint(x: -23, y: 12))
    p.addCurve(to: CGPoint(x: 22, y: 9), control1: CGPoint(x: -16, y: 5), control2: CGPoint(x: 9, y: 4))
    p.addCurve(to: CGPoint(x: 12, y: 37), control1: CGPoint(x: 27, y: 16), control2: CGPoint(x: 18, y: 26))
    p.addCurve(to: CGPoint(x: 11, y: 121), control1: CGPoint(x: 5, y: 58), control2: CGPoint(x: 12, y: 88))
    p.addQuadCurve(to: CGPoint(x: -13, y: 121), control: CGPoint(x: -1, y: 131))
    p.addCurve(to: CGPoint(x: -19, y: 39), control1: CGPoint(x: -13, y: 99), control2: CGPoint(x: -10, y: 62))
    p.addCurve(to: CGPoint(x: -23, y: 12), control1: CGPoint(x: -28, y: 35), control2: CGPoint(x: -26, y: 20)); p.closeSubpath()
  }
  static let fibula = Path { p in
    p.move(to: CGPoint(x: 24, y: 27))
    p.addCurve(to: CGPoint(x: 29, y: 47), control1: CGPoint(x: 39, y: 21), control2: CGPoint(x: 38, y: 37))
    p.addCurve(to: CGPoint(x: 24, y: 118), control1: CGPoint(x: 26, y: 66), control2: CGPoint(x: 26, y: 98))
    p.addQuadCurve(to: CGPoint(x: 16, y: 117), control: CGPoint(x: 18, y: 123))
    p.addCurve(to: CGPoint(x: 18, y: 43), control1: CGPoint(x: 13, y: 95), control2: CGPoint(x: 19, y: 62))
    p.addQuadCurve(to: CGPoint(x: 24, y: 27), control: CGPoint(x: 17, y: 30)); p.closeSubpath()
  }
}
