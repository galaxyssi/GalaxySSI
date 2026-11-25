import SwiftUI

struct GalaxySSIHealthAtlasNailView: View {
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
      let step = story.chapter(phase), fraction = story.fraction(phase)
      let t = fraction.isFinite ? min(1, max(0, fraction)) : 0
      let slide = GalaxySSIHealthAtlasNailMotion.slide(step, t)
      let plate = GalaxySSIHealthAtlasNailGeometry.plate(306 + slide)
      art.nailSection(emphasizeBed: step == 4)
      if step == 1 { art.nailDivision(t) }
      art.nailPlate(plate, tip: 306 + slide)
      switch step {
      case 0: art.nailOrientation(t, plate: plate)
      case 2: art.nailMaturation(t)
      case 3, 4: art.nailLandmarks(slide, step: step, t: t, plate: plate)
      default: break
      }
      art.nailFold()
      art.nailLabels()
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-nail-matrix-art")
  }
}
