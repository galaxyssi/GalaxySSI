import SwiftUI

struct GalaxySSIHealthAtlasCranialView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height) / 360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 360 * scale) / 2)
      local.scaleBy(x: scale, y: scale)
      let art = GalaxySSIHealthAtlasIllustratedDrawing(context: local, language: language)
      art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), 0, 360, 0xE8F4F3, 0xFBF0DF)
      let frame = GalaxySSIHealthAtlasCranialMotion.Frame(step: story.chapter(phase), fraction: story.fraction(phase))
      art.cranialMidbrain()
      art.cranialEye(90, direction: 1, frame: frame)
      art.cranialEye(270, direction: -1, frame: frame)
      art.cranialNeural(frame)
      art.cranialLight(frame)
      art.cranialLabels(frame.step)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-cranial-reflex-art")
  }
}
