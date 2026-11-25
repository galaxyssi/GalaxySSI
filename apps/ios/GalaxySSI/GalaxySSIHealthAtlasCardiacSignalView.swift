import SwiftUI

struct GalaxySSIHealthAtlasCardiacSignalView: View {
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
      art.cardiacSignalHeart(step: step, t: t); art.cardiacSignalCell(step: step, t: t)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-cardiac-excitation-art")
  }
}

enum GalaxySSIHealthAtlasCardiacSignalShapes {
  static let outline: UInt32 = 0x975367, circuit: UInt32 = 0x4F5578, excited: UInt32 = 0xE79B45, myofibril: UInt32 = 0x975E80
  static let wall = Path { p in
    p.move(to: CGPoint(x: 147, y: 46))
    p.addCurve(to: CGPoint(x: 93, y: 76), control1: CGPoint(x: 116, y: 17), control2: CGPoint(x: 91, y: 36))
    p.addCurve(to: CGPoint(x: 146, y: 173), control1: CGPoint(x: 96, y: 123), control2: CGPoint(x: 119, y: 154))
    p.addCurve(to: CGPoint(x: 188, y: 168), control1: CGPoint(x: 159, y: 185), control2: CGPoint(x: 174, y: 181))
    p.addCurve(to: CGPoint(x: 218, y: 79), control1: CGPoint(x: 214, y: 146), control2: CGPoint(x: 220, y: 112))
    p.addCurve(to: CGPoint(x: 174, y: 55), control1: CGPoint(x: 220, y: 46), control2: CGPoint(x: 190, y: 37))
    p.addQuadCurve(to: CGPoint(x: 147, y: 46), control: CGPoint(x: 163, y: 70)); p.closeSubpath()
  }
  static let rightVentricle = Path { p in
    p.move(to: CGPoint(x: 106, y: 99))
    p.addCurve(to: CGPoint(x: 133, y: 111), control1: CGPoint(x: 117, y: 95), control2: CGPoint(x: 124, y: 105))
    p.addQuadCurve(to: CGPoint(x: 142, y: 142), control: CGPoint(x: 141, y: 119))
    p.addCurve(to: CGPoint(x: 106, y: 99), control1: CGPoint(x: 133, y: 144), control2: CGPoint(x: 115, y: 122)); p.closeSubpath()
  }
  static let leftVentricle = Path { p in
    p.move(to: CGPoint(x: 171, y: 105))
    p.addCurve(to: CGPoint(x: 200, y: 103), control1: CGPoint(x: 179, y: 94), control2: CGPoint(x: 196, y: 87))
    p.addCurve(to: CGPoint(x: 168, y: 160), control1: CGPoint(x: 203, y: 126), control2: CGPoint(x: 181, y: 157))
    p.addQuadCurve(to: CGPoint(x: 171, y: 105), control: CGPoint(x: 161, y: 146)); p.closeSubpath()
  }
}
