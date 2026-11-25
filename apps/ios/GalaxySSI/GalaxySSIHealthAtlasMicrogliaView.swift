import SwiftUI

struct GalaxySSIHealthAtlasMicrogliaView: View {
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
      let field = GalaxySSIHealthAtlasMicrogliaGeometry.field
      art.gradient(field, 6, 354, 0xEEF3FA, 0xE2F0EA)
      let step = story.chapter(phase), t = GalaxySSIHealthAtlasMicrogliaMotion.phase(story.fraction(phase))
      let close = step == 3, zoom = close ? 1.55 : 1, offsetX = close ? -138.0 : 0, offsetY = close ? -80.0 : 0
      var clipped = local; clipped.clip(to: field)
      clipped.translateBy(x: offsetX, y: offsetY); clipped.scaleBy(x: zoom, y: zoom)
      let detail = art.copy(clipped)
      detail.microgliaBackground(step,t); detail.microgliaArbor(step,t)
      switch step {
      case 2: detail.microgliaFragments(263, 150, 1)
      case 3:
        detail.microgliaPocket(263, 150, GalaxySSIHealthAtlasMicrogliaMotion.ease(t, 0.24, 0.77))
        detail.microgliaFragments(263, 150, 1)
      case 4: detail.microgliaDigestion(t)
      default: break
      }
      art.microgliaLabels(step, zoom, offsetX, offsetY)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-microglia-surveillance-art")
  }
}
