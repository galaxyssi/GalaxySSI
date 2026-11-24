import SwiftUI

struct GalaxySSIHealthAtlasArterialView: View {
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
      art.arterialLocator(step: step,t: t)
      art.arterialSection(step: step,t: t,expansion: GalaxySSIHealthAtlasArterialMotion.expansion(step: step,t: t,location: 0.24))
      art.line(19,158,341,158,0xCCDCD5,1); art.label("arterial_longitudinal",180,180,210)
      art.arterialTube(step: step,t: t)
      if let center = GalaxySSIHealthAtlasArterialMotion.front(step: step,t: t) { art.arterialPulse(step: step,t: t,fraction: center) }
      if let distance = GalaxySSIHealthAtlasArterialMotion.flowTravel(step: step,t: t) { art.arterialFlow(distance) }
      art.arterialLegend()
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-arterial-pulse-art")
  }
}
