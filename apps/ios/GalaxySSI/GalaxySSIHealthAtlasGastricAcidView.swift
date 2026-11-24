import SwiftUI

struct GalaxySSIHealthAtlasGastricAcidView: View {
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
      let t = story.fraction(phase)
      switch story.chapter(phase) {
      case 0: art.gastricAcidLocate(t)
      case 1: art.gastricAcidCellPlate(); art.gastricAcidSignal(t); art.gastricAcidCellLabels()
      case 2: art.gastricAcidCellPlate(); art.gastricAcidExchange(t); art.gastricAcidCellLabels()
      case 3:
        art.gastricAcidCellPlate(GalaxySSIHealthAtlasGastricAcidMotion.lumen(t)); art.gastricAcidSecrete(t); art.gastricAcidCellLabels()
      case 4: art.gastricAcidFeedback(t)
      default: break
      }
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-parietal-secretion-art")
  }
}
