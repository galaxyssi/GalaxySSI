import SwiftUI

struct GalaxySSIHealthAtlasEndothelialView: View {
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
      art.endothelialScene(step: story.chapter(phase), t: story.fraction(phase))
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-endothelial-exchange-art")
  }
}

enum GalaxySSIHealthAtlasEndothelialShapes {
  static let field = Path(roundedRect: CGRect(x: 18, y: 24, width: 324, height: 290), cornerRadius: 12)
  static let tileSeam = Path { p in
    p.move(to: CGPoint(x: -3, y: 0))
    p.addCurve(to: CGPoint(x: 4, y: 24), control1: CGPoint(x: 3, y: 6), control2: CGPoint(x: -2, y: 17))
  }
  static let lymph = Path { p in
    p.move(to: CGPoint(x: 352, y: 267))
    p.addCurve(to: CGPoint(x: 153, y: 267), control1: CGPoint(x: 260, y: 258), control2: CGPoint(x: 204, y: 263))
    p.addCurve(to: CGPoint(x: 54, y: 281), control1: CGPoint(x: 113, y: 270), control2: CGPoint(x: 64, y: 259))
    p.addCurve(to: CGPoint(x: 121, y: 304), control1: CGPoint(x: 48, y: 299), control2: CGPoint(x: 85, y: 306))
    p.addCurve(to: CGPoint(x: 352, y: 299), control1: CGPoint(x: 192, y: 304), control2: CGPoint(x: 243, y: 286)); p.closeSubpath()
  }
  static let tissueCell = Path { p in
    p.move(to: CGPoint(x: -24, y: 1))
    p.addCurve(to: CGPoint(x: 3, y: -8), control1: CGPoint(x: -12, y: -3), control2: CGPoint(x: -8, y: -11))
    p.addCurve(to: CGPoint(x: 25, y: 1), control1: CGPoint(x: 13, y: -7), control2: CGPoint(x: 15, y: -1))
    p.addCurve(to: CGPoint(x: 0, y: 8), control1: CGPoint(x: 14, y: 2), control2: CGPoint(x: 9, y: 9))
    p.addCurve(to: CGPoint(x: -24, y: 1), control1: CGPoint(x: -10, y: 9), control2: CGPoint(x: -14, y: 3)); p.closeSubpath()
  }
  static let soluteShape = Path { p in
    p.move(to: CGPoint(x: 0, y: -4.5)); p.addLine(to: CGPoint(x: 4.5, y: 0))
    p.addLine(to: CGPoint(x: 0, y: 4.5)); p.addLine(to: CGPoint(x: -4.5, y: 0)); p.closeSubpath()
  }
  static let proteinShape = Path { p in
    p.move(to: CGPoint(x: -8, y: 0))
    p.addCurve(to: CGPoint(x: 0, y: -6), control1: CGPoint(x: -10, y: -5), control2: CGPoint(x: -5, y: -9))
    p.addCurve(to: CGPoint(x: 7, y: 0), control1: CGPoint(x: 4, y: -9), control2: CGPoint(x: 10, y: -5))
    p.addCurve(to: CGPoint(x: 0, y: 6), control1: CGPoint(x: 11, y: 4), control2: CGPoint(x: 4, y: 9))
    p.addCurve(to: CGPoint(x: -8, y: 0), control1: CGPoint(x: -4, y: 9), control2: CGPoint(x: -10, y: 4)); p.closeSubpath()
  }
}
