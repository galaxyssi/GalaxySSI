import SwiftUI

struct GalaxySSIHealthAtlasHairView: View {
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
      art.hairScene(GalaxySSIHealthAtlasHairMotion(step: step, fraction: t), step: step, t: t)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-hair-follicle-cycle-art")
  }
}

enum GalaxySSIHealthAtlasHairInk {
  static let wallEdge: UInt32 = 0x9E647C, hair: UInt32 = 0x534057, light: UInt32 = 0xBA8E94, leader: UInt32 = 0x6B6376
  static let epidermis = Path { p in
    p.move(to: CGPoint(x: 24, y: 132)); p.addLine(to: CGPoint(x: 336, y: 132)); p.addLine(to: CGPoint(x: 336, y: 149))
    for x in stride(from: 336, through: 48, by: -24) {
      p.addCurve(to: CGPoint(x: Double(x - 15), y: 154), control1: CGPoint(x: Double(x - 8), y: 149), control2: CGPoint(x: Double(x - 10), y: 159))
      p.addQuadCurve(to: CGPoint(x: Double(x - 24), y: 149), control: CGPoint(x: Double(x - 20), y: 149))
    }
    p.closeSubpath()
  }
}
