import SwiftUI

struct GalaxySSIHealthAtlasCerebellumView: View {
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
      art.cerebellumAnatomy(); art.cerebellumReach(step: story.chapter(phase), t: story.fraction(phase))
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-cerebellar-coordination-art")
  }
}

enum GalaxySSIHealthAtlasCerebellumShapes {
  static let guide: UInt32 = 0x657984, prediction: UInt32 = 0x4B7095, earlier: UInt32 = 0x8B657E, folia: UInt32 = 0xA76B83
  static let cerebrum = Path { p in
    p.move(to: CGPoint(x: 27, y: 166))
    p.addCurve(to: CGPoint(x: 45, y: 120), control1: CGPoint(x: 23, y: 152), control2: CGPoint(x: 31, y: 129))
    p.addCurve(to: CGPoint(x: 97, y: 119), control1: CGPoint(x: 62, y: 105), control2: CGPoint(x: 84, y: 108))
    p.addCurve(to: CGPoint(x: 114, y: 156), control1: CGPoint(x: 109, y: 127), control2: CGPoint(x: 117, y: 141))
    p.addCurve(to: CGPoint(x: 95, y: 177), control1: CGPoint(x: 114, y: 167), control2: CGPoint(x: 105, y: 175))
    p.addCurve(to: CGPoint(x: 68, y: 175), control1: CGPoint(x: 84, y: 182), control2: CGPoint(x: 77, y: 168))
    p.addCurve(to: CGPoint(x: 38, y: 181), control1: CGPoint(x: 59, y: 181), control2: CGPoint(x: 48, y: 190))
    p.addQuadCurve(to: CGPoint(x: 27, y: 166), control: CGPoint(x: 26, y: 179)); p.closeSubpath()
  }
  static let gyri = Path { p in
    p.move(to: CGPoint(x: 36, y: 159)); p.addQuadCurve(to: CGPoint(x: 49, y: 139), control: CGPoint(x: 37, y: 145))
    p.move(to: CGPoint(x: 45, y: 172)); p.addCurve(to: CGPoint(x: 61, y: 155), control1: CGPoint(x: 56, y: 168), control2: CGPoint(x: 50, y: 154))
    p.move(to: CGPoint(x: 53, y: 129)); p.addCurve(to: CGPoint(x: 84, y: 129), control1: CGPoint(x: 67, y: 123), control2: CGPoint(x: 75, y: 121))
    p.move(to: CGPoint(x: 76, y: 136)); p.addCurve(to: CGPoint(x: 103, y: 152), control1: CGPoint(x: 83, y: 147), control2: CGPoint(x: 97, y: 139))
    p.move(to: CGPoint(x: 82, y: 160)); p.addQuadCurve(to: CGPoint(x: 102, y: 166), control: CGPoint(x: 95, y: 158))
    p.move(to: CGPoint(x: 56, y: 147)); p.addCurve(to: CGPoint(x: 77, y: 153), control1: CGPoint(x: 64, y: 137), control2: CGPoint(x: 77, y: 144))
  }
  static let brainstem = Path { p in
    p.move(to: CGPoint(x: 62, y: 171)); p.addQuadCurve(to: CGPoint(x: 79, y: 176), control: CGPoint(x: 71, y: 167))
    p.addCurve(to: CGPoint(x: 74, y: 198), control1: CGPoint(x: 82, y: 184), control2: CGPoint(x: 77, y: 191))
    p.addCurve(to: CGPoint(x: 69, y: 237), control1: CGPoint(x: 69, y: 210), control2: CGPoint(x: 66, y: 225))
    p.addLine(to: CGPoint(x: 57, y: 239)); p.addQuadCurve(to: CGPoint(x: 57, y: 209), control: CGPoint(x: 53, y: 226))
    p.addCurve(to: CGPoint(x: 54, y: 187), control1: CGPoint(x: 59, y: 199), control2: CGPoint(x: 49, y: 197))
    p.addQuadCurve(to: CGPoint(x: 62, y: 171), control: CGPoint(x: 58, y: 182)); p.closeSubpath()
  }
  static let cerebellum = Path { p in
    p.move(to: CGPoint(x: 75, y: 184))
    p.addCurve(to: CGPoint(x: 108, y: 179), control1: CGPoint(x: 81, y: 173), control2: CGPoint(x: 98, y: 169))
    p.addCurve(to: CGPoint(x: 112, y: 204), control1: CGPoint(x: 118, y: 185), control2: CGPoint(x: 119, y: 197))
    p.addCurve(to: CGPoint(x: 92, y: 218), control1: CGPoint(x: 112, y: 211), control2: CGPoint(x: 100, y: 220))
    p.addCurve(to: CGPoint(x: 73, y: 207), control1: CGPoint(x: 83, y: 222), control2: CGPoint(x: 72, y: 214))
    p.addCurve(to: CGPoint(x: 75, y: 184), control1: CGPoint(x: 68, y: 201), control2: CGPoint(x: 70, y: 189)); p.closeSubpath()
  }
  static let whiteMatter = Path { p in
    p.move(to: CGPoint(x: 75, y: 200)); p.addQuadCurve(to: CGPoint(x: 99, y: 193), control: CGPoint(x: 87, y: 195))
    p.move(to: CGPoint(x: 86, y: 197)); p.addQuadCurve(to: CGPoint(x: 95, y: 185), control: CGPoint(x: 88, y: 190))
    p.move(to: CGPoint(x: 88, y: 197)); p.addQuadCurve(to: CGPoint(x: 101, y: 202), control: CGPoint(x: 91, y: 201))
    p.move(to: CGPoint(x: 83, y: 198)); p.addQuadCurve(to: CGPoint(x: 90, y: 210), control: CGPoint(x: 89, y: 203))
  }
  static let sleeve = Path { p in
    p.move(to: CGPoint(x: -10, y: -17))
    p.addCurve(to: CGPoint(x: 28, y: -13), control1: CGPoint(x: 1, y: -23), control2: CGPoint(x: 18, y: -18))
    p.addQuadCurve(to: CGPoint(x: 27, y: 15), control: CGPoint(x: 34, y: 0))
    p.addCurve(to: CGPoint(x: -9, y: 19), control1: CGPoint(x: 14, y: 18), control2: CGPoint(x: 3, y: 23))
    p.addQuadCurve(to: CGPoint(x: -10, y: -17), control: CGPoint(x: -20, y: 5)); p.closeSubpath()
  }
  static let forearm = Path { p in
    p.move(to: CGPoint(x: -98, y: -10))
    p.addCurve(to: CGPoint(x: -29, y: -6), control1: CGPoint(x: -81, y: -14), control2: CGPoint(x: -53, y: -10))
    p.addQuadCurve(to: CGPoint(x: -14, y: -7), control: CGPoint(x: -22, y: -10))
    p.addLine(to: CGPoint(x: -2, y: -4)); p.addQuadCurve(to: CGPoint(x: 0, y: 1), control: CGPoint(x: 3, y: -3))
    p.addLine(to: CGPoint(x: -15, y: 1)); p.addQuadCurve(to: CGPoint(x: -13, y: 5), control: CGPoint(x: -16, y: 3))
    p.addQuadCurve(to: CGPoint(x: -14, y: 11), control: CGPoint(x: -9, y: 9))
    p.addQuadCurve(to: CGPoint(x: -25, y: 9), control: CGPoint(x: -19, y: 10))
    p.addCurve(to: CGPoint(x: -98, y: 10), control1: CGPoint(x: -48, y: 11), control2: CGPoint(x: -83, y: 15))
    p.addQuadCurve(to: CGPoint(x: -98, y: -10), control: CGPoint(x: -110, y: 2)); p.closeSubpath()
  }
}
