import SwiftUI

struct GalaxySSIHealthAtlasChemicalSenseView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    let motion = GalaxySSIHealthAtlasChemicalSenseMotion(courseID: story.id, chapter: story.chapter(phase), fraction: story.fraction(phase))
    Canvas { context, size in
      let scale = min(size.width, size.height) / 360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 360 * scale) / 2); local.scaleBy(x: scale, y: scale)
      let art = GalaxySSIHealthAtlasIllustratedDrawing(context: local, language: language)
      art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), 0, 360, 0xE8F4F3, 0xFBF0DF)
      if motion.smell { art.smellScene(step: motion.chapter, t: motion.fraction) }
      else { art.tasteScene(step: motion.chapter, t: motion.fraction) }
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier(story.id == "OLFACTION" ? "atlas-function-olfaction-art" : "atlas-function-taste-signal-art")
  }
}

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func chemicalLeader(_ key: String, _ x: Double, _ y: Double, _ tx: Double, _ ty: Double, _ color: UInt32) {
    let start = y + (ty > y ? 8 : -15)
    line(x, start, tx, ty, color, 1.25); disc(tx, ty, 2.3, color, border: Self.cream)
    label(key, x, y, min(2 * x - 8, min(712 - 2 * x, 145)))
  }
  func chemicalFigure(_ path: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32, _ edge: UInt32) {
    gradient(path, top, bottom, from, to); stroke(path, edge, 1.3)
  }
  func chemicalParticles(_ route: GalaxySSIHealthAtlasChemicalSenseMotion.Route, _ t: Double, _ color: UInt32, _ count: Int) {
    for i in 0..<count {
      at(route, GalaxySSIHealthAtlasChemicalSenseMotion.transfer(t, index: i)) { disc($0, $1, i == 0 ? 4.8 : 3.6, color, border: Self.cream) }
    }
  }
}
