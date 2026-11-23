import SwiftUI

struct GalaxySSIHealthAtlasSalivaView: View {
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
      art.salivaMap(step: step, t: t); art.salivaCutaway(step: step, t: t)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-saliva-secretion-art")
  }
}

enum GalaxySSIHealthAtlasSalivaShapes {
  static let rose: UInt32 = 0x9E6574, guide: UInt32 = 0x62666D, water: UInt32 = 0xB9E1E8, fluid: UInt32 = 0x397F95, protein: UInt32 = 0xE8BB64
  static let head = Path { p in
    p.move(to: CGPoint(x: 103, y: 177))
    p.addCurve(to: CGPoint(x: 101, y: 105), control1: CGPoint(x: 116, y: 151), control2: CGPoint(x: 113, y: 131))
    p.addCurve(to: CGPoint(x: 143, y: 14), control1: CGPoint(x: 80, y: 58), control2: CGPoint(x: 100, y: 19))
    p.addCurve(to: CGPoint(x: 222, y: 44), control1: CGPoint(x: 178, y: 8), control2: CGPoint(x: 211, y: 16))
    p.addCurve(to: CGPoint(x: 228, y: 72), control1: CGPoint(x: 227, y: 56), control2: CGPoint(x: 222, y: 63))
    p.addLine(to: CGPoint(x: 243, y: 91))
    p.addQuadCurve(to: CGPoint(x: 238, y: 99), control: CGPoint(x: 248, y: 97))
    p.addQuadCurve(to: CGPoint(x: 234, y: 108), control: CGPoint(x: 224, y: 99))
    p.addQuadCurve(to: CGPoint(x: 239, y: 119), control: CGPoint(x: 246, y: 113))
    p.addQuadCurve(to: CGPoint(x: 238, y: 130), control: CGPoint(x: 246, y: 124))
    p.addCurve(to: CGPoint(x: 232, y: 151), control1: CGPoint(x: 234, y: 133), control2: CGPoint(x: 240, y: 143))
    p.addCurve(to: CGPoint(x: 165, y: 177), control1: CGPoint(x: 219, y: 163), control2: CGPoint(x: 177, y: 144)); p.closeSubpath()
  }
  static let mouth = Path { p in
    p.move(to: CGPoint(x: 171, y: 126))
    p.addCurve(to: CGPoint(x: 237, y: 117), control1: CGPoint(x: 184, y: 106), control2: CGPoint(x: 216, y: 107))
    p.addCurve(to: CGPoint(x: 205, y: 144), control1: CGPoint(x: 235, y: 131), control2: CGPoint(x: 223, y: 142))
    p.addCurve(to: CGPoint(x: 171, y: 126), control1: CGPoint(x: 186, y: 146), control2: CGPoint(x: 169, y: 140)); p.closeSubpath()
  }
  static let tongue = Path { p in
    p.move(to: CGPoint(x: 172, y: 135))
    p.addCurve(to: CGPoint(x: 218, y: 125), control1: CGPoint(x: 184, y: 126), control2: CGPoint(x: 196, y: 121))
    p.addCurve(to: CGPoint(x: 213, y: 139), control1: CGPoint(x: 235, y: 125), control2: CGPoint(x: 227, y: 137))
    p.addQuadCurve(to: CGPoint(x: 172, y: 137), control: CGPoint(x: 185, y: 142)); p.closeSubpath()
  }
  static let jaw = Path { p in
    p.move(to: CGPoint(x: 144, y: 109))
    p.addCurve(to: CGPoint(x: 177, y: 151), control1: CGPoint(x: 148, y: 132), control2: CGPoint(x: 152, y: 146))
    p.addQuadCurve(to: CGPoint(x: 225, y: 144), control: CGPoint(x: 202, y: 155))
  }
  static let acinarCell = Path { p in
    p.move(to: CGPoint(x: 9, y: -5))
    p.addQuadCurve(to: CGPoint(x: 40, y: -24), control: CGPoint(x: 26, y: -15))
    p.addCurve(to: CGPoint(x: 62, y: 0), control1: CGPoint(x: 53, y: -29), control2: CGPoint(x: 62, y: -15))
    p.addCurve(to: CGPoint(x: 40, y: 24), control1: CGPoint(x: 62, y: 15), control2: CGPoint(x: 53, y: 29))
    p.addQuadCurve(to: CGPoint(x: 9, y: 5), control: CGPoint(x: 26, y: 15))
    p.addQuadCurve(to: CGPoint(x: 9, y: -5), control: CGPoint(x: 7, y: 0)); p.closeSubpath()
  }
  static let lumen = Path { p in
    p.move(to: CGPoint(x: 330, y: 254)); p.addLine(to: CGPoint(x: 171, y: 254))
    p.addCurve(to: CGPoint(x: 117, y: 258), control1: CGPoint(x: 143, y: 254), control2: CGPoint(x: 137, y: 262))
    p.addCurve(to: CGPoint(x: 115, y: 276), control1: CGPoint(x: 101, y: 254), control2: CGPoint(x: 97, y: 277))
    p.addCurve(to: CGPoint(x: 171, y: 278), control1: CGPoint(x: 137, y: 270), control2: CGPoint(x: 146, y: 278))
    p.addLine(to: CGPoint(x: 330, y: 278))
  }
}
