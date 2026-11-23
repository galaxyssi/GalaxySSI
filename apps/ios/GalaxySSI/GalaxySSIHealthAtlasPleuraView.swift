import SwiftUI

struct GalaxySSIHealthAtlasPleuraView: View {
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
      art.pleuraScene(GalaxySSIHealthAtlasPleuraMotion(step: step, fraction: t), step: step)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-pleural-coupling-art")
  }
}

enum GalaxySSIHealthAtlasPleuraInk {
  static let parietal: UInt32 = 0x527F79, visceral: UInt32 = 0x95576B, fluid: UInt32 = 0xA6DBE3, guide: UInt32 = 0x516B72
  static let airway = Path { p in
    p.move(to: CGPoint(x: 180, y: 40)); p.addLine(to: CGPoint(x: 180, y: 97))
    p.addQuadCurve(to: CGPoint(x: 151, y: 123), control: CGPoint(x: 179, y: 108))
    p.move(to: CGPoint(x: 180, y: 97)); p.addQuadCurve(to: CGPoint(x: 210, y: 120), control: CGPoint(x: 185, y: 106))
  }
}
