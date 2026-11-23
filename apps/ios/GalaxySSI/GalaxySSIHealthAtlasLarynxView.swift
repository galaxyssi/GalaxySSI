import SwiftUI

struct GalaxySSIHealthAtlasLarynxView: View {
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
      art.larynxScene(GalaxySSIHealthAtlasLarynxMotion(step: step, fraction: t), step: step, t: t)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-laryngeal-voice-art")
  }
}

enum GalaxySSIHealthAtlasLarynxShapes {
  static let wallEdge: UInt32 = 0x916872, guide: UInt32 = 0x537178, flow: UInt32 = 0x246E76, pulse: UInt32 = 0xA26032
  static let outline = Path { p in
    p.move(to: CGPoint(x: 180, y: 49))
    p.addCurve(to: CGPoint(x: 103, y: 94), control1: CGPoint(x: 143, y: 44), control2: CGPoint(x: 112, y: 62))
    p.addCurve(to: CGPoint(x: 129, y: 189), control1: CGPoint(x: 86, y: 132), control2: CGPoint(x: 100, y: 171))
    p.addCurve(to: CGPoint(x: 180, y: 191), control1: CGPoint(x: 149, y: 203), control2: CGPoint(x: 170, y: 196))
    p.addCurve(to: CGPoint(x: 231, y: 189), control1: CGPoint(x: 190, y: 196), control2: CGPoint(x: 211, y: 203))
    p.addCurve(to: CGPoint(x: 257, y: 94), control1: CGPoint(x: 260, y: 171), control2: CGPoint(x: 274, y: 132))
    p.addCurve(to: CGPoint(x: 180, y: 49), control1: CGPoint(x: 248, y: 62), control2: CGPoint(x: 217, y: 44)); p.closeSubpath()
  }
  static let vestibule = Path { p in
    p.move(to: CGPoint(x: 180, y: 72))
    p.addCurve(to: CGPoint(x: 115, y: 115), control1: CGPoint(x: 148, y: 66), control2: CGPoint(x: 122, y: 83))
    p.addCurve(to: CGPoint(x: 145, y: 179), control1: CGPoint(x: 105, y: 142), control2: CGPoint(x: 121, y: 169))
    p.addCurve(to: CGPoint(x: 180, y: 180), control1: CGPoint(x: 159, y: 186), control2: CGPoint(x: 172, y: 182))
    p.addCurve(to: CGPoint(x: 215, y: 179), control1: CGPoint(x: 188, y: 182), control2: CGPoint(x: 201, y: 186))
    p.addCurve(to: CGPoint(x: 245, y: 115), control1: CGPoint(x: 239, y: 169), control2: CGPoint(x: 255, y: 142))
    p.addCurve(to: CGPoint(x: 180, y: 72), control1: CGPoint(x: 238, y: 83), control2: CGPoint(x: 212, y: 66)); p.closeSubpath()
  }
  static let anteriorRim = Path { p in
    p.move(to: CGPoint(x: 134, y: 69))
    p.addCurve(to: CGPoint(x: 226, y: 69), control1: CGPoint(x: 154, y: 48), control2: CGPoint(x: 206, y: 48))
    p.addCurve(to: CGPoint(x: 180, y: 86), control1: CGPoint(x: 213, y: 66), control2: CGPoint(x: 196, y: 73))
    p.addCurve(to: CGPoint(x: 134, y: 69), control1: CGPoint(x: 164, y: 73), control2: CGPoint(x: 147, y: 66)); p.closeSubpath()
  }
  static let airwayWall = Path { p in
    p.move(to: CGPoint(x: 124, y: 246))
    p.addCurve(to: CGPoint(x: 141, y: 294), control1: CGPoint(x: 122, y: 261), control2: CGPoint(x: 131, y: 279))
    p.addQuadCurve(to: CGPoint(x: 146, y: 339), control: CGPoint(x: 148, y: 306)); p.addLine(to: CGPoint(x: 158, y: 339))
    p.addCurve(to: CGPoint(x: 152, y: 286), control1: CGPoint(x: 160, y: 311), control2: CGPoint(x: 157, y: 296))
    p.addCurve(to: CGPoint(x: 141, y: 246), control1: CGPoint(x: 146, y: 271), control2: CGPoint(x: 139, y: 262)); p.closeSubpath()
  }
  static let frontalLumen = Path { p in
    p.move(to: CGPoint(x: 141, y: 246))
    p.addCurve(to: CGPoint(x: 152, y: 286), control1: CGPoint(x: 139, y: 262), control2: CGPoint(x: 146, y: 271))
    p.addCurve(to: CGPoint(x: 158, y: 339), control1: CGPoint(x: 157, y: 296), control2: CGPoint(x: 160, y: 311))
    p.addLine(to: CGPoint(x: 202, y: 339))
    p.addCurve(to: CGPoint(x: 208, y: 286), control1: CGPoint(x: 200, y: 311), control2: CGPoint(x: 203, y: 296))
    p.addCurve(to: CGPoint(x: 219, y: 246), control1: CGPoint(x: 214, y: 271), control2: CGPoint(x: 221, y: 262)); p.closeSubpath()
  }
  static func superiorFold(_ gap: Double) -> Path {
    Path { p in
      p.move(to: CGPoint(x: 180, y: 86))
      p.addCurve(to: CGPoint(x: 180 - gap, y: 173), control1: CGPoint(x: 177 - 0.15 * gap, y: 112), control2: CGPoint(x: 178 - 0.55 * gap, y: 146))
      p.addCurve(to: CGPoint(x: 119, y: 132), control1: CGPoint(x: 153 - 0.68 * gap, y: 175), control2: CGPoint(x: 123, y: 158))
      p.addCurve(to: CGPoint(x: 180, y: 86), control1: CGPoint(x: 116, y: 113), control2: CGPoint(x: 144, y: 93)); p.closeSubpath()
    }
  }
  static func foldSection(_ gap: Double) -> Path {
    let lip = 180 - gap * 0.55
    return Path { p in
      p.move(to: CGPoint(x: 142, y: 263))
      p.addCurve(to: CGPoint(x: lip, y: 278), control1: CGPoint(x: 155, y: 263), control2: CGPoint(x: lip - 2, y: 270))
      p.addCurve(to: CGPoint(x: 150, y: 289), control1: CGPoint(x: lip - 2, y: 286), control2: CGPoint(x: 160, y: 288)); p.closeSubpath()
    }
  }
}
