import SwiftUI

struct GalaxySSIHealthAtlasCartilageView: View {
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
      let step = story.chapter(phase), t = story.fraction(phase), motion = GalaxySSIHealthAtlasCartilageMotion(step: step, fraction: t)
      art.cartilageTrochlea(motion, step: step, t: t); art.cartilagePatella(travel: motion.travel)
      if step == 1 || step == 2 { art.cartilageLoad(travel: motion.travel, t: t, arriving: step == 1) }
      if step == 2 || step == 4 { art.cartilageFlow(depth: motion.depth, t: t, returning: step == 4) }
      art.cartilageLabels(depth: motion.depth, travel: motion.travel)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-cartilage-load-art")
  }
}

enum GalaxySSIHealthAtlasCartilageInk {
  static let boneEdge: UInt32 = 0x9B745C, fluid: UInt32 = 0x346F98, load: UInt32 = 0xA26030, space: UInt32 = 0x739292
}
