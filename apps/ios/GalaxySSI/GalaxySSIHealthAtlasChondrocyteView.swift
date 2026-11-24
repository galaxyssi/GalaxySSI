import SwiftUI

struct GalaxySSIHealthAtlasChondrocyteView: View {
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
      let step = story.chapter(phase), frame = GalaxySSIHealthAtlasChondrocyteMotion(step: step,fraction: story.fraction(phase))
      var tissue = local
      tissue.translateBy(x: 180, y: 177); tissue.scaleBy(x: 1, y: frame.scaleY); tissue.translateBy(x: -180, y: -177)
      let inside = art.copy(tissue)
      inside.chondrocyteMatrix(frame); inside.chondrocyteCell()
      switch step {
      case 0: inside.chondrocyteZones(frame.t)
      case 1: inside.chondrocyteCollagen(frame.t)
      case 2: inside.chondrocyteAggrecan(frame.t)
      default: break
      }
      if step > 1 { inside.chondrocyteCollagen(1) }
      if step > 2 { inside.chondrocyteAggrecan(1) }
      if step == 4 { art.chondrocyteCompression(frame) }
      art.chondrocyteLabels(frame.scaleY)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-chondrocyte-matrix-art")
  }
}
