import SwiftUI

struct GalaxySSIHealthAtlasSurfactantView: View {
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
      let step = story.chapter(phase), t = story.fraction(phase), width = GalaxySSIHealthAtlasSurfactantMotion.width(step: step, fraction: t)
      art.surfactantOverview(step: step, width: width); art.surfactantCutaway(step: step, t: t, width: width)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-alveolar-surfactant-art")
  }
}

enum GalaxySSIHealthAtlasSurfactantShapes {
  static let lining: UInt32 = 0xC5E4EA, air: UInt32 = 0xEDF7F7, tissue: UInt32 = 0xF5DDD2, rose: UInt32 = 0x995769, guide: UInt32 = 0x547079
  static let sac = Path { p in
    p.move(to: CGPoint(x: 82, y: 28))
    p.addCurve(to: CGPoint(x: 55, y: 69), control1: CGPoint(x: 86, y: 49), control2: CGPoint(x: 67, y: 51))
    p.addCurve(to: CGPoint(x: 91, y: 136), control1: CGPoint(x: 33, y: 99), control2: CGPoint(x: 53, y: 132))
    p.addCurve(to: CGPoint(x: 140, y: 79), control1: CGPoint(x: 133, y: 141), control2: CGPoint(x: 155, y: 107))
    p.addCurve(to: CGPoint(x: 111, y: 28), control1: CGPoint(x: 130, y: 57), control2: CGPoint(x: 107, y: 51))
  }
  static func surface(_ y: Double) -> Path {
    GalaxySSIHealthAtlasSectionLessonView.path(GalaxySSIHealthAtlasSurfactantMotion.surfaceRoute(y), width: 360, height: 360)
  }
  static func section(_ y: Double) -> Path {
    var path = surface(y); path.addLine(to: CGPoint(x: 332, y: 303)); path.addLine(to: CGPoint(x: 28, y: 303)); path.closeSubpath(); return path
  }
  static let typeTwo = Path { p in
    p.move(to: CGPoint(x: 87, y: 246))
    p.addCurve(to: CGPoint(x: 125, y: 212), control1: CGPoint(x: 99, y: 239), control2: CGPoint(x: 96, y: 212))
    p.addCurve(to: CGPoint(x: 170, y: 242), control1: CGPoint(x: 150, y: 212), control2: CGPoint(x: 150, y: 235))
    p.addCurve(to: CGPoint(x: 129, y: 288), control1: CGPoint(x: 170, y: 264), control2: CGPoint(x: 154, y: 284))
    p.addCurve(to: CGPoint(x: 87, y: 246), control1: CGPoint(x: 104, y: 292), control2: CGPoint(x: 85, y: 269)); p.closeSubpath()
  }
}
