import SwiftUI

struct GalaxySSIHealthAtlasMesangialView: View {
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
      let stage = GalaxySSIHealthAtlasMesangialMotion.Stage(rawValue: story.chapter(phase)) ?? .locate
      let f = stage.progress(story.fraction(phase)), tension = stage == .tension ? f : 0
      art.mesangialOverview(stage == .locate ? f : nil)
      art.mesangialSection(tension)
      if stage == .support {
        for (i, fiber) in GalaxySSIHealthAtlasMesangialRoutes.fibers.enumerated() {
          let reach = GalaxySSIHealthAtlasMesangialMotion.fiberReach(f, i)
          art.mesangialSweep(fiber, reach - 0.25, reach, 0xA37435, 3.4)
        }
      }
      art.mesangialCell(tension)
      switch stage {
      case .boundary: art.mesangialBoundary(f)
      case .uptake: art.mesangialUptake(f)
      default: break
      }
      art.mesangialLabels()
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-mesangial-support-art")
  }
}
