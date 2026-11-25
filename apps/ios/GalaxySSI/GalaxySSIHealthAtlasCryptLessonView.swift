import SwiftUI

struct GalaxySSIHealthAtlasCryptLessonView: View {
  enum Kind { case endocrine, stem }
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  let kind: Kind
  var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height) / 360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 360 * scale) / 2); local.scaleBy(x: scale, y: scale)
      let wall = GalaxySSIHealthAtlasCryptWallDrawing(context: local, language: language)
      wall.art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), 0, 360, 0xE8F4F3, 0xFBF0DF)
      guard GalaxySSIHealthAtlasCryptWallDrawing.centers.count == 29 else { return }
      let step = story.chapter(phase), t = story.fraction(phase)
      wall.wall(feature: kind == .endocrine ? 21 : 14)
      if kind == .endocrine { wall.endocrineSignal(step, t) } else { wall.stemRenewal(step, t) }
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier(kind == .endocrine ? "atlas-function-enteroendocrine-lumen-signal-art" : "atlas-function-intestinal-stem-renewal-art")
  }
}
