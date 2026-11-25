import SwiftUI

struct GalaxySSIHealthAtlasEndometriumView: View {
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
      let step = story.chapter(phase), frame = GalaxySSIHealthAtlasEndometriumMotion.Frame(step: step,fraction: story.fraction(phase))
      let section = GalaxySSIHealthAtlasEndometriumGeometry.section(frame)
      art.endometriumContext(step == 0 ? GalaxySSIHealthAtlasEndometriumMotion.ramp(frame.t,from: 0.06,to: 0.85) : 1)
      art.endometriumSection(frame,section: section)
      if step == 3 { art.endometriumFragments(frame.t,tissue: section.tissue) }
      art.endometriumLabels(step)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-endometrium-renewal-art")
  }
}
