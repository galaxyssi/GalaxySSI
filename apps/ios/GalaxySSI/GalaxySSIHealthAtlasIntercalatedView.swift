import SwiftUI

struct GalaxySSIHealthAtlasIntercalatedView: View {
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
      let stage = GalaxySSIHealthAtlasIntercalatedMotion.Stage(rawValue: story.chapter(phase)) ?? .orientation
      let f = stage.progress(story.fraction(phase))
      art.intercalatedDuct()
      art.intercalatedCapillary(stage == .acidExcretion ? f : 0)
      switch stage {
      case .orientation: art.intercalatedTubularFlow(f)
      case .protonSecretion: art.intercalatedProtons(f)
      case .bicarbonateReturn: art.intercalatedBaseReturn(f)
      case .luminalBuffers:
        art.intercalatedBuffer(f, phosphate: false)
        art.intercalatedBuffer(GalaxySSIHealthAtlasIntercalatedMotion.phosphateDelay(f), phosphate: true)
      case .acidExcretion:
        art.intercalatedBaseReturn(f)
        art.intercalatedBufferedOutflow(f)
      }
      art.intercalatedLabels()
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-intercalated-balance-art")
  }
}
