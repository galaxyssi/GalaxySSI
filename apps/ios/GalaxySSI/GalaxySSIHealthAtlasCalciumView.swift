import SwiftUI

struct GalaxySSIHealthAtlasCalciumView: View {
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
      switch step {
      case 2: art.calciumRenalResponse(t)
      case 3: art.calciumIntestinalResponse(t)
      default: art.calciumParathyroids(GalaxySSIHealthAtlasCalciumMotion.State(step: step, fraction: t), t: t)
      }
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-parathyroid-feedback-art")
  }
}

enum GalaxySSIHealthAtlasCalciumShapes {
  static let clay: UInt32 = 0x915D6A, blood: UInt32 = 0xF3C5C9, guide: UInt32 = 0x64727A, gold: UInt32 = 0x9B661F, glandGold: UInt32 = 0xF1C67D
  static let thyroidLobe = Path { p in
    p.move(to: CGPoint(x: 79, y: 80))
    p.addCurve(to: CGPoint(x: 56, y: 29), control1: CGPoint(x: 78, y: 64), control2: CGPoint(x: 73, y: 29))
    p.addCurve(to: CGPoint(x: 42, y: 88), control1: CGPoint(x: 41, y: 29), control2: CGPoint(x: 35, y: 62))
    p.addCurve(to: CGPoint(x: 70, y: 101), control1: CGPoint(x: 49, y: 119), control2: CGPoint(x: 60, y: 119))
    p.addQuadCurve(to: CGPoint(x: 79, y: 80), control: CGPoint(x: 77, y: 92)); p.closeSubpath()
  }
  static let chiefCell = Path { p in
    p.move(to: CGPoint(x: 43, y: 211))
    p.addCurve(to: CGPoint(x: 108, y: 177), control1: CGPoint(x: 51, y: 180), control2: CGPoint(x: 80, y: 177))
    p.addLine(to: CGPoint(x: 250, y: 177))
    p.addCurve(to: CGPoint(x: 317, y: 210), control1: CGPoint(x: 281, y: 177), control2: CGPoint(x: 309, y: 183))
    p.addCurve(to: CGPoint(x: 181, y: 258), control1: CGPoint(x: 327, y: 246), control2: CGPoint(x: 270, y: 260))
    p.addCurve(to: CGPoint(x: 43, y: 211), control1: CGPoint(x: 100, y: 263), control2: CGPoint(x: 38, y: 247)); p.closeSubpath()
  }
  static let kidney = Path { p in
    p.move(to: CGPoint(x: 119, y: 89))
    p.addCurve(to: CGPoint(x: 143, y: 140), control1: CGPoint(x: 157, y: 89), control2: CGPoint(x: 160, y: 122))
    p.addCurve(to: CGPoint(x: 138, y: 181), control1: CGPoint(x: 128, y: 155), control2: CGPoint(x: 123, y: 167))
    p.addCurve(to: CGPoint(x: 109, y: 247), control1: CGPoint(x: 158, y: 204), control2: CGPoint(x: 142, y: 244))
    p.addCurve(to: CGPoint(x: 30, y: 177), control1: CGPoint(x: 61, y: 255), control2: CGPoint(x: 29, y: 226))
    p.addCurve(to: CGPoint(x: 119, y: 89), control1: CGPoint(x: 28, y: 127), control2: CGPoint(x: 61, y: 88)); p.closeSubpath()
  }
  static let renalCortex = Path { p in
    p.move(to: CGPoint(x: 119, y: 102))
    p.addCurve(to: CGPoint(x: 129, y: 138), control1: CGPoint(x: 145, y: 104), control2: CGPoint(x: 143, y: 126))
    p.addCurve(to: CGPoint(x: 126, y: 187), control1: CGPoint(x: 112, y: 154), control2: CGPoint(x: 109, y: 170))
    p.addCurve(to: CGPoint(x: 107, y: 234), control1: CGPoint(x: 143, y: 209), control2: CGPoint(x: 126, y: 230))
    p.addCurve(to: CGPoint(x: 44, y: 177), control1: CGPoint(x: 68, y: 240), control2: CGPoint(x: 43, y: 217))
    p.addCurve(to: CGPoint(x: 119, y: 102), control1: CGPoint(x: 43, y: 135), control2: CGPoint(x: 75, y: 101)); p.closeSubpath()
  }
  static let villus = GalaxySSIHealthAtlasSectionLessonView.path(GalaxySSIHealthAtlasCalciumMotion.villus, width: 360, height: 360)
  static let intestinalWall: Path = {
    var path = villus; path.addLine(to: CGPoint(x: 330, y: 266)); path.addLine(to: CGPoint(x: 330, y: 291))
    path.addLine(to: CGPoint(x: 30, y: 291)); path.addLine(to: CGPoint(x: 30, y: 266)); path.closeSubpath(); return path
  }()
  static let villusDots: [CGPoint] = (1...40).compactMap {
    GalaxySSIHealthAtlasFunctionPath.sample(GalaxySSIHealthAtlasCalciumMotion.villus, position: Double($0) / 41, width: 360, height: 360)?.point
  }
}
