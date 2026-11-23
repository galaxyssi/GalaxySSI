import SwiftUI

struct GalaxySSIHealthAtlasRedCellView: View {
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
      case 0: art.redCellCloseUp(t)
      case 1: art.redCellLung(t)
      case 2: art.redCellTransport(t)
      default: art.redCellPeripheral(t, diffuse: step == 4)
      }
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-red-cell-oxygen-art")
  }
}

enum GalaxySSIHealthAtlasRedCellShapes {
  static let cellEdge: UInt32 = 0xA35264, wallEdge: UInt32 = 0xB47983, oxygen: UInt32 = 0x1C746D
  static let alveolus = Path { p in
    p.move(to: CGPoint(x: 324, y: 78))
    p.addCurve(to: CGPoint(x: 269, y: 89), control1: CGPoint(x: 291, y: 78), control2: CGPoint(x: 293, y: 91))
    p.addCurve(to: CGPoint(x: 207, y: 69), control1: CGPoint(x: 242, y: 87), control2: CGPoint(x: 241, y: 66))
    p.addCurve(to: CGPoint(x: 144, y: 86), control1: CGPoint(x: 181, y: 70), control2: CGPoint(x: 170, y: 88))
    p.addCurve(to: CGPoint(x: 72, y: 79), control1: CGPoint(x: 119, y: 84), control2: CGPoint(x: 100, y: 64))
    p.addCurve(to: CGPoint(x: 64, y: 143), control1: CGPoint(x: 42, y: 94), control2: CGPoint(x: 44, y: 126))
    p.addCurve(to: CGPoint(x: 110, y: 155), control1: CGPoint(x: 74, y: 151), control2: CGPoint(x: 89, y: 155))
    p.addLine(to: CGPoint(x: 324, y: 155))
  }
}
