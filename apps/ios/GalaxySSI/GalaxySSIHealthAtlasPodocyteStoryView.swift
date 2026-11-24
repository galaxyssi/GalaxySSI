import SwiftUI

struct GalaxySSIHealthAtlasPodocyteStoryView: View {
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
      let step = story.chapter(phase), f = GalaxySSIHealthAtlasPodocyteMotion.progress(step: step,t: story.fraction(phase))
      art.podocyteGlomerulus(step == 0 ? f : nil); art.podocyteSpaces(); art.podocyteWall(); art.podocyteBlood(step == 4 ? f : 0)
      switch step {
      case 1: art.podocyteFenestraFocus(f)
      case 2: art.podocyteBasementFocus(f)
      case 3: art.podocyteSlitFocus(f)
      case 4: art.podocyteFiltrate(f)
      default: break
      }
      art.podocyteLabels()
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-podocyte-barrier-art")
  }
}
