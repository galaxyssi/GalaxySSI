import SwiftUI

struct GalaxySSIHealthAtlasBrainstemView: View {
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
      let step = story.chapter(phase), frame = GalaxySSIHealthAtlasBrainstemMotion(step: step, fraction: story.fraction(phase))
      art.gradient(GalaxySSIHealthAtlasBrainstemShapes.body,26,313,0xF9E9D9,0xF2D8D0)
      art.stroke(GalaxySSIHealthAtlasBrainstemShapes.body,0xC69B94,1.3)
      art.brainstemHead(); art.brainstemChest(frame.expansion,contracting: step == 3); art.brainstemAirway()
      art.brainstemMotor(step: step,t: frame.t)
      if step == 3 { art.brainstemAirflow(frame.t,inward: true) }
      if step == 4 && frame.expiration < 1 { art.brainstemAirflow(frame.expiration,inward: false) }
      if step == 0 { art.brainstemPulse(frame.t) }
      art.brainstemNetwork(frame.burst); art.brainstemLabels(frame.expansion)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-brainstem-rhythm-art")
  }
}
