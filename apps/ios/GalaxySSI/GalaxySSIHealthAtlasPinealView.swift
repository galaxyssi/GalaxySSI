import SwiftUI

struct GalaxySSIHealthAtlasPinealView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height)/360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width-360*scale)/2, y: (size.height-360*scale)/2)
      local.scaleBy(x: scale, y: scale)
      let art = GalaxySSIHealthAtlasIllustratedDrawing(context: local, language: language)
      let step = story.chapter(phase), t = GalaxySSIHealthAtlasPinealMotion.phase(story.fraction(phase))
      art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), 0, 360,
        (2...3).contains(step) ? 0xF0F1F9 : 0xF8FBFC, (2...3).contains(step) ? 0xE7F1F3 : 0xE7F1F1)
      switch step {
      case 0: art.pinealOrient(t)
      case 1: art.pinealRetinalInput(t)
      case 2: art.pinealRelay(t)
      case 3: art.pinealProduce(t)
      case 4: art.pinealRhythm(t)
      default: break
      }
      art.pinealLabels(step, t)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-pineal-dark-signal-art")
  }
}
