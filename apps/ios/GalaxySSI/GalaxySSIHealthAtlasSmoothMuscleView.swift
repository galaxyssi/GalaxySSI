import SwiftUI

struct GalaxySSIHealthAtlasSmoothMuscleView: View {
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
      let step = story.chapter(phase), t = story.fraction(phase), frame = GalaxySSIHealthAtlasSmoothMuscleMotion(step: step, fraction: t)
      art.smoothMuscleScene(frame, step: step, t: t)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-smooth-muscle-wave-art")
  }
}

enum GalaxySSIHealthAtlasSmoothMuscleShapes {
  static let squeeze: UInt32 = 0xA1475C, open: UInt32 = 0x397A70
  static let bolus = Path { p in
    p.move(to: CGPoint(x: -31, y: 1))
    p.addCurve(to: CGPoint(x: -9, y: -17), control1: CGPoint(x: -34, y: -8), control2: CGPoint(x: -19, y: -19))
    p.addCurve(to: CGPoint(x: 17, y: -14), control1: CGPoint(x: 1, y: -23), control2: CGPoint(x: 12, y: -17))
    p.addCurve(to: CGPoint(x: 32, y: 2), control1: CGPoint(x: 28, y: -15), control2: CGPoint(x: 34, y: -7))
    p.addCurve(to: CGPoint(x: 12, y: 17), control1: CGPoint(x: 33, y: 10), control2: CGPoint(x: 22, y: 19))
    p.addCurve(to: CGPoint(x: -14, y: 17), control1: CGPoint(x: 2, y: 22), control2: CGPoint(x: -7, y: 16))
    p.addCurve(to: CGPoint(x: -31, y: 1), control1: CGPoint(x: -23, y: 17), control2: CGPoint(x: -32, y: 11)); p.closeSubpath()
  }
}
