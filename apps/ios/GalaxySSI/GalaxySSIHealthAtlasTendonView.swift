import SwiftUI

struct GalaxySSIHealthAtlasTendonView: View {
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
      let step = story.chapter(phase), t = story.fraction(phase), frame = GalaxySSIHealthAtlasTendonMotion(step: step, fraction: t)
      art.tendonScene(frame, step: step, t: t)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-tendon-force-transfer-art")
  }
}

enum GalaxySSIHealthAtlasTendonShapes {
  static let boneInk: UInt32 = 0x96754E, leader: UInt32 = 0x65817B
  static let bone = Path { p in
    p.move(to: CGPoint(x: 264, y: 95))
    p.addCurve(to: CGPoint(x: 305, y: 97), control1: CGPoint(x: 278, y: 79), control2: CGPoint(x: 294, y: 81))
    p.addCurve(to: CGPoint(x: 337, y: 108), control1: CGPoint(x: 314, y: 107), control2: CGPoint(x: 325, y: 107))
    p.addLine(to: CGPoint(x: 337, y: 139))
    p.addCurve(to: CGPoint(x: 307, y: 142), control1: CGPoint(x: 324, y: 139), control2: CGPoint(x: 317, y: 137))
    p.addCurve(to: CGPoint(x: 268, y: 152), control1: CGPoint(x: 293, y: 152), control2: CGPoint(x: 282, y: 159))
    p.addCurve(to: CGPoint(x: 264, y: 95), control1: CGPoint(x: 250, y: 144), control2: CGPoint(x: 248, y: 112)); p.closeSubpath()
  }
  static let corticalEdge = Path { p in
    p.move(to: CGPoint(x: 275, y: 99))
    p.addCurve(to: CGPoint(x: 301, y: 106), control1: CGPoint(x: 286, y: 91), control2: CGPoint(x: 293, y: 97))
    p.addCurve(to: CGPoint(x: 330, y: 115), control1: CGPoint(x: 310, y: 115), control2: CGPoint(x: 323, y: 115))
    p.move(to: CGPoint(x: 272, y: 143))
    p.addCurve(to: CGPoint(x: 304, y: 137), control1: CGPoint(x: 284, y: 151), control2: CGPoint(x: 295, y: 141))
    p.addCurve(to: CGPoint(x: 330, y: 132), control1: CGPoint(x: 313, y: 131), control2: CGPoint(x: 322, y: 132))
  }
}
